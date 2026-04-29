// Grounding Pre-Processor Hook
// Layer 1: 自动检索本地内容并注入上下文
// OpenClaw 官方格式: handler(event)

import { createRequire } from 'module';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

// 动态导入 CommonJS 模块
const require = createRequire(import.meta.url);
const utils = (() => {
  try {
    return require('../../utils/security.cjs');
  } catch {
    // 兼容手动复制到 ~/.openclaw/hooks/<hook>/ 的布局
    return require('../utils/security.cjs');
  }
})();
const {
  extractKeywords,
  deepMerge,
  DEFAULT_MAX_RESULTS,
  DEFAULT_RELEVANCE_THRESHOLD,
  DEFAULT_MAX_INPUT_SIZE,
  DEFAULT_MAX_KEYWORDS,
  CONTENT_TRUNCATE_LENGTH,
} = utils;

const tools = (() => {
  try {
    return require('../../tools/grounding-tools.cjs');
  } catch {
    return null;
  }
})();

// 配置接口
const DEFAULT_CONFIG = {
  enabled: true,
  version: '3.1.0',
  executionMode: 'balanced',
  configPath: '~/.openclaw/grounding-guard.json',
  allowedBasePaths: [
    '~/.openclaw/',
    '~/.openclaw/workspace/'
  ],
  searchPaths: [
    '~/.openclaw/',
    '~/.openclaw/workspace/'
  ],
  maxResults: DEFAULT_MAX_RESULTS,
  relevanceThreshold: DEFAULT_RELEVANCE_THRESHOLD,
  enableVectorSearch: false,
  maxInputSize: DEFAULT_MAX_INPUT_SIZE,
  maxKeywords: DEFAULT_MAX_KEYWORDS,
  maxContextChars: 6000,
  enableWebSearch: true,
  webSearchThreshold: 3,
  maxWebResults: 5,
  emitDiagnostics: true,
  checkpointEnabled: true,
  webCircuitBreakerFailureThreshold: 3,
  webCircuitBreakerCooldownMs: 300000
};

const webCircuitState = {
  failures: 0,
  openedAtMs: 0,
};

function expandHome(p) {
  if (!p || typeof p !== 'string') return p;
  if (!p.startsWith('~')) return p;
  return path.join(os.homedir(), p.slice(1));
}

function loadUserConfig(configPath) {
  try {
    const expanded = expandHome(configPath);
    if (!expanded || !fs.existsSync(expanded)) return {};
    const raw = fs.readFileSync(expanded, 'utf-8');
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch (e) {
    console.warn('[grounding-pre-processor] Failed to load config:', e && e.message ? e.message : e);
    return {};
  }
}

function getConfig() {
  const user = loadUserConfig(DEFAULT_CONFIG.configPath);
  return applyExecutionMode(deepMerge(DEFAULT_CONFIG, user.preProcessor || user || {}));
}

function applyExecutionMode(config) {
  const mode = String(config.executionMode || 'balanced').toLowerCase();
  if (mode === 'strict') {
    return {
      ...config,
      maxResults: Math.min(config.maxResults, 8),
      maxKeywords: Math.min(config.maxKeywords, 4),
      maxContextChars: Math.min(config.maxContextChars, 5000),
      enableWebSearch: Boolean(config.enableWebSearchStrictMode),
      maxWebResults: Math.min(config.maxWebResults, 3),
    };
  }

  if (mode === 'performance') {
    return {
      ...config,
      maxResults: Math.min(config.maxResults, 6),
      maxKeywords: Math.min(config.maxKeywords, 3),
      maxContextChars: Math.min(config.maxContextChars, 3500),
      webSearchThreshold: Math.min(config.webSearchThreshold, 2),
      maxWebResults: Math.min(config.maxWebResults, 3),
    };
  }

  return config;
}

function quickHash(input) {
  let hash = 0;
  const text = String(input || '');
  for (let index = 0; index < text.length; index += 1) {
    hash = ((hash << 5) - hash) + text.charCodeAt(index);
    hash |= 0;
  }
  return Math.abs(hash).toString(16);
}

function getRunId(event, message) {
  const seed = `${event?.context?.turnId || ''}:${event?.context?.sessionId || ''}:${message.slice(0, 256)}`;
  return `gg-${quickHash(seed)}`;
}

function isWebSearchAllowed(config) {
  if (!config.enableWebSearch) return false;
  if (webCircuitState.failures < config.webCircuitBreakerFailureThreshold) return true;
  const now = Date.now();
  if (now - webCircuitState.openedAtMs >= config.webCircuitBreakerCooldownMs) {
    webCircuitState.failures = 0;
    webCircuitState.openedAtMs = 0;
    return true;
  }
  return false;
}

function markWebSearchResult(ok, config) {
  if (ok) {
    webCircuitState.failures = 0;
    webCircuitState.openedAtMs = 0;
    return;
  }
  webCircuitState.failures += 1;
  if (webCircuitState.failures >= config.webCircuitBreakerFailureThreshold) {
    webCircuitState.openedAtMs = Date.now();
  }
}

async function searchLocalFiles(keywords, config) {
  if (!tools || typeof tools.search_local !== 'function') {
    console.warn('[grounding-pre-processor] L2 tools unavailable, skip local search.');
    return [];
  }

  return tools.search_local({
    keywords,
    searchPaths: config.searchPaths,
    allowedBasePaths: config.allowedBasePaths || DEFAULT_CONFIG.allowedBasePaths,
    maxResults: config.maxResults,
    timeoutMs: 10000,
    relevanceThreshold: config.relevanceThreshold,
  });
}

// 构建 Grounding Context
function buildGroundingContext(results, maxContextChars) {
  if (results.length === 0) {
    return '';
  }

  let remaining = Number.isFinite(maxContextChars) ? Math.max(maxContextChars, 0) : 6000;
  const sections = results.map(r => {
    if (remaining <= 0) return null;
    const content = r.content.substring(0, Math.min(CONTENT_TRUNCATE_LENGTH, Math.max(remaining - 180, 80)));
    const section = `### 来源: ${r.filePath} (相关度: ${(r.relevanceScore * 100).toFixed(0)}%)\n` +
      `第 ${r.lineNumber} 行:\n` +
      '```\n' +
      content +
      (r.content.length > content.length ? '\n... (truncated)' : '') +
      '\n```';
    remaining -= section.length;
    return section;
  }).filter(Boolean);

  return `\n### 📁 本地来源（高置信度）\n\n` +
         `${sections.join('\n\n')}`;
}

// 构建网络搜索 Grounding Context
function buildWebGroundingContext(results, maxContextChars) {
  if (results.length === 0) {
    return '';
  }

  let remaining = Number.isFinite(maxContextChars) ? Math.max(maxContextChars, 0) : 2500;
  const sections = results.map(r => {
    if (remaining <= 0) return null;
    const snippet = r.snippet.substring(0, Math.min(CONTENT_TRUNCATE_LENGTH, Math.max(remaining - 220, 80)));
    const section = `### 来源: ${r.title} (${r.source})\n` +
      `URL: ${r.url}\n` +
      '```\n' +
      snippet +
      (r.snippet.length > snippet.length ? '\n... (truncated)' : '') +
      '\n```';
    remaining -= section.length;
    return section;
  }).filter(Boolean);

  return `\n### 🌐 网络来源（中置信度）\n\n` +
         `${sections.join('\n\n')}`;
}

// 注入 Grounding Prompt
function injectGroundingPrompt(originalPrompt, groundingContext) {
  const groundingSection = `\n## 🔍 Grounding Context（系统自动检索到的相关内容）\n\n` +
    `${groundingContext}\n\n` +
    `---\n\n` +
    `## 回答规则\n\n` +
    `1. **优先使用上述 Grounding Context 中的信息**\n` +
    `2. **如果 Grounding Context 不足**，你可以：\n` +
    `   - 使用 search_web 工具搜索网络\n` +
    `   - 基于你的知识回答，但必须标注 [Confidence: low]\n` +
    `3. **每条回答必须包含**：\n` +
    `   - [Source: <来源>] - 文件路径、URL 或 "LLM knowledge"\n` +
    `   - [Confidence: high/medium/low/unknown] - 基于信源类型\n` +
    `4. **如果不确定**，必须说："我不确定，让我搜索一下" 或 "基于现有信息，我认为..."\n`;

  if (originalPrompt.includes('## 🔍 Grounding Context')) {
    return originalPrompt.replace(/## 🔍 Grounding Context[\s\S]*?(?=\n## |$)/, groundingSection);
  }

  return originalPrompt + '\n' + groundingSection;
}

// OpenClaw 官方 handler 格式
export default async function handler(event) {
  try {
    // OpenClaw 官方事件模型：event.type + event.action（兼容旧版 "message:xxx"）
    const isLegacyMessageKey = typeof event.type === 'string' && event.type.startsWith('message:');
    const legacyAction = isLegacyMessageKey ? event.type.split(':')[1] : null;
    const messageTypeOk = event.type === 'message' || isLegacyMessageKey;
    const action = event.action || legacyAction;

    // 推荐在 message:preprocessed 时注入（此时可安全修改 bodyForAgent）
    if (!messageTypeOk || action !== 'preprocessed') return;

    // 获取配置
    const config = getConfig();

    // 如果禁用，直接返回
    if (!config.enabled) {
      return;
    }

    // 获取用户消息
    const message =
      (event.context && (event.context.content || event.context.bodyForAgent)) ||
      (event.data && event.data.message) ||
      '';
    const runId = getRunId(event, message);

    // 如果消息为空或太长，跳过
    if (!message || message.length > config.maxInputSize) {
      return;
    }

    // 1. 提取关键词
    const keywords = extractKeywords(message, {
      maxInputSize: config.maxInputSize,
      maxKeywords: config.maxKeywords
    });

    if (keywords.length === 0) {
      return;
    }

    // 2. 搜索本地文件
    const results = await searchLocalFiles(keywords, config);

    // 3. 构建本地上下文
    let groundingContext = buildGroundingContext(results, config.maxContextChars);

    // 4. 如果本地结果不足且启用了网络搜索，自动触发网络搜索
    if (isWebSearchAllowed(config) && results.length < config.webSearchThreshold) {
      const webQuery = message.slice(0, 200);
      if (tools && typeof tools.search_web === 'function') {
        try {
          const webResults = await tools.search_web({ query: webQuery, maxResults: config.maxWebResults });
          if (webResults.results.length > 0) {
            const webContext = buildWebGroundingContext(webResults.results, Math.floor(config.maxContextChars * 0.45));
            groundingContext += webContext;
            markWebSearchResult(true, config);
          } else {
            markWebSearchResult(false, config);
          }
        } catch {
          markWebSearchResult(false, config);
        }
      }
    }

    // 5. 如果没有找到任何内容，添加提示
    if (!groundingContext) {
      groundingContext = '\n## 🔍 Grounding Context\n\n未在本地或网络找到相关内容。\n';
    }

    // 6. 修改 event.context 来影响后续处理
    if (!event.context) {
      event.context = {};
    }

    const originalBody = event.context.bodyForAgent || event.context.content || '';
    event.context.bodyForAgent = injectGroundingPrompt(originalBody, groundingContext);

    // 添加标记表示已处理
    event.context.groundingContextInjected = true;
    event.context.groundingSourcesCount = results.length;
    if (config.emitDiagnostics) {
      event.context.groundingDiagnostics = {
        version: config.version,
        executionMode: config.executionMode,
        runId,
        phase: 'preprocessed',
        maxResults: config.maxResults,
        maxKeywords: config.maxKeywords,
        webSearchEnabled: config.enableWebSearch,
        webCircuitOpen: webCircuitState.failures >= config.webCircuitBreakerFailureThreshold,
      };
    }
    if (config.checkpointEnabled) {
      event.context.groundingCheckpoint = {
        runId,
        phase: 'L1_COMPLETE',
        sourceHits: results.length,
        contextChars: groundingContext.length,
        timestamp: new Date().toISOString(),
      };
    }
  }
  catch (error) {
    console.error('[Grounding Pre-Processor] Error:', error);
    // 出错时不阻断
  }
}
