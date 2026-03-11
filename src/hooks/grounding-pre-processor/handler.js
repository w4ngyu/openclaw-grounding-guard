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
  safeRipgrepSearch,
  calculateRelevance,
  extractKeywords,
  searchWeb,
  validatePath,
  deepMerge,
  DEFAULT_MAX_RESULTS,
  DEFAULT_RELEVANCE_THRESHOLD,
  DEFAULT_MAX_INPUT_SIZE,
  DEFAULT_MAX_KEYWORDS,
  CONCURRENCY_LIMIT,
  CONTENT_TRUNCATE_LENGTH,
} = utils;

// 配置接口
const DEFAULT_CONFIG = {
  enabled: true,
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
  enableWebSearch: true,
  webSearchThreshold: 3,
  maxWebResults: 5
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
  return deepMerge(DEFAULT_CONFIG, user.preProcessor || user || {});
}

// 搜索本地文件
async function searchLocalFiles(keywords, config) {
  const allResults = [];

  for (const searchPath of config.searchPaths) {
    const validation = validatePath(searchPath, config.allowedBasePaths || DEFAULT_CONFIG.allowedBasePaths);
    if (!validation.isValid) continue;
    const resolvedSearchPath = validation.resolvedPath;

    const batchPromises = keywords.map(async (keyword) => {
      const raw = await safeRipgrepSearch(keyword, resolvedSearchPath, config.maxResults, 10000);
      return raw.map((r) => ({ ...r, relevanceScore: calculateRelevance(r.content, keyword) }));
    });

    const batchResults = await Promise.all(batchPromises);
    allResults.push(...batchResults.flat());
  }

  // 去重、排序、截断
  const uniqueResults = new Map();
  for (const result of allResults) {
    const key = `${result.filePath}:${result.lineNumber}`;
    const existing = uniqueResults.get(key);
    if (!existing || existing.relevanceScore < result.relevanceScore) {
      uniqueResults.set(key, result);
    }
  }

  return Array.from(uniqueResults.values())
    .filter(r => r.relevanceScore >= config.relevanceThreshold)
    .sort((a, b) => b.relevanceScore - a.relevanceScore)
    .slice(0, config.maxResults);
}

// 构建 Grounding Context
function buildGroundingContext(results) {
  if (results.length === 0) {
    return '';
  }

  const sections = results.map(r => {
    return `### 来源: ${r.filePath} (相关度: ${(r.relevanceScore * 100).toFixed(0)}%)\n` +
           `第 ${r.lineNumber} 行:\n` +
           '```\n' +
           r.content.substring(0, CONTENT_TRUNCATE_LENGTH) +
           (r.content.length > CONTENT_TRUNCATE_LENGTH ? '\n... (truncated)' : '') +
           '\n```';
  });

  return `\n### 📁 本地来源（高置信度）\n\n` +
         `${sections.join('\n\n')}`;
}

// 构建网络搜索 Grounding Context
function buildWebGroundingContext(results) {
  if (results.length === 0) {
    return '';
  }

  const sections = results.map(r => {
    return `### 来源: ${r.title} (${r.source})\n` +
           `URL: ${r.url}\n` +
           '```\n' +
           r.snippet.substring(0, CONTENT_TRUNCATE_LENGTH) +
           (r.snippet.length > CONTENT_TRUNCATE_LENGTH ? '\n... (truncated)' : '') +
           '\n```';
  });

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
    let groundingContext = buildGroundingContext(results);

    // 4. 如果本地结果不足且启用了网络搜索，自动触发网络搜索
    if (config.enableWebSearch && results.length < config.webSearchThreshold) {
      const webQuery = message.slice(0, 200);
      const webResults = await searchWeb(webQuery, config.maxWebResults);

      if (webResults.results.length > 0) {
        const webContext = buildWebGroundingContext(webResults.results);
        groundingContext += webContext;
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
  }
  catch (error) {
    console.error('[Grounding Pre-Processor] Error:', error);
    // 出错时不阻断
  }
}
