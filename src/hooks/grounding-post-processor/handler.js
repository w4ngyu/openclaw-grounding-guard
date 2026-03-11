// Grounding Post-Processor Hook
// Layer 3: 输出后处理，强制验证来源标注
// OpenClaw 官方格式: handler(event)

import { createRequire } from 'module';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

// 动态导入 CommonJS 模块
const require = createRequire(import.meta.url);
const utils = (() => {
  try {
    return require('../../utils/security.cjs');
  } catch {
    return require('../utils/security.cjs');
  }
})();
const {
  escapeRegex,
  deepMerge,
  verifyFact,
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
  configPath: '~/.openclaw/grounding-guard.json',
  requireSource: true,
  requireConfidence: true,
  onMissing: 'auto-fix',
  maxContentSize: 100000,
  enableFactVerification: true,
  factVerificationThreshold: 0.5
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
    console.warn('[grounding-post-processor] Failed to load config:', e && e.message ? e.message : e);
    return {};
  }
}

function getConfig() {
  const user = loadUserConfig(DEFAULT_CONFIG.configPath);
  return deepMerge(DEFAULT_CONFIG, user.postProcessor || user || {});
}

// 解析来源标注
function parseSourceAnnotations(content) {
  const sources = [];
  const regex = /\[Source:\s*(.+?)\]/g;
  let match;

  while ((match = regex.exec(content)) !== null) {
    const value = match[1].trim();
    let type = 'unknown';

    if (value.startsWith('/') || value.startsWith('~')) {
      type = 'local';
    } else if (value.startsWith('http')) {
      type = 'web';
    } else if (value.toLowerCase().includes('llm') || value.toLowerCase().includes('knowledge')) {
      type = 'llm';
    }

    sources.push({ type, value, isValid: true });
  }

  return sources;
}

// 解析置信度标注
function parseConfidenceAnnotation(content) {
  const regex = /\[Confidence:\s*(high|medium|low|unknown)\]/i;
  const match = content.match(regex);

  if (match) {
    const level = match[1].toLowerCase();
    return { level, isValid: true };
  }

  return null;
}

// 验证本地文件是否存在
async function validateLocalSource(sourcePath) {
  try {
    const expandedPath = sourcePath.startsWith('~')
      ? path.join(os.homedir(), sourcePath.slice(1))
      : sourcePath;

    await fs.promises.access(expandedPath, fs.constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

// 验证响应
async function validateResponse(content) {
  const sources = parseSourceAnnotations(content);
  const confidence = parseConfidenceAnnotation(content);
  const issues = [];

  // 验证来源
  if (sources.length === 0) {
    issues.push('Missing [Source: ...] annotation');
  } else {
    for (const source of sources) {
      if (source.type === 'local') {
        source.isValid = await validateLocalSource(source.value);
        if (!source.isValid) {
          issues.push(`Source file does not exist: ${source.value}`);
        }
      }
    }
  }

  // 验证置信度
  if (!confidence) {
    issues.push('Missing [Confidence: high/medium/low/unknown] annotation');
  }

  // 检查置信度与来源是否匹配
  if (confidence && sources.length > 0) {
    const hasLocalSource = sources.some(s => s.type === 'local' && s.isValid);
    const hasWebSource = sources.some(s => s.type === 'web');

    if (hasLocalSource && confidence.level !== 'high') {
      issues.push('Local sources should have [Confidence: high]');
    } else if (hasWebSource && confidence.level === 'high') {
      issues.push('Web sources should have [Confidence: medium] or lower');
    } else if (!hasLocalSource && !hasWebSource && confidence.level !== 'low' && confidence.level !== 'unknown') {
      issues.push('LLM-only knowledge should have [Confidence: low] or [Confidence: unknown]');
    }
  }

  return {
    hasSource: sources.length > 0,
    hasConfidence: confidence !== null,
    sources,
    confidence,
    issues
  };
}

// 深度事实验证
async function performFactVerification(content, sources, threshold) {
  const localSources = sources.filter(s => s.type === 'local' && s.isValid);
  
  if (localSources.length === 0) {
    return { verified: true, details: ['No local sources to verify'] };
  }

  const sourcePaths = localSources.map(s => s.value);
  const verification = tools && typeof tools.verify_fact === 'function'
    ? await tools.verify_fact({ statement: content, sources: sourcePaths })
    : await verifyFact(content, sourcePaths);

  const details = [
    `Fact verification: ${verification.isVerified ? 'PASSED' : 'FAILED'}`,
    `Confidence: ${(verification.confidence * 100).toFixed(0)}%`,
    `Reasoning: ${verification.reasoning}`
  ];

  if (verification.limitations.length > 0) {
    details.push(`Limitations: ${verification.limitations.join(', ')}`);
  }

  if (verification.conflictingInfo && verification.conflictingInfo.length > 0) {
    details.push(`Conflicts: ${verification.conflictingInfo.slice(0, 3).join('; ')}`);
  }

  return {
    verified: verification.isVerified && verification.confidence >= threshold,
    details
  };
}

// 生成拦截消息
function generateRejectionMessage(issues) {
  return `⚠️ **Grounding Guard 拦截**\n\n` +
         `响应未通过来源验证：\n\n` +
         issues.map(i => `- ${i}`).join('\n') +
         `\n\n**请补充来源标注后重新生成。**\n\n` +
         `规则：\n` +
         `- 本地文件来源 → [Source: /path/to/file] [Confidence: high]\n` +
         `- 网络搜索来源 → [Source: https://...] [Confidence: medium]\n` +
         `- LLM 知识 → [Source: LLM knowledge] [Confidence: low]\n` +
         `- 不确定 → [Source: unknown] [Confidence: unknown]`;
}

// 生成警告消息
function generateWarningMessage(issues) {
  return `\n\n---\n` +
         `⚠️ **Grounding Warning**: ${issues.join(', ')}\n` +
         `*此响应未完全通过来源验证*`;
}

// OpenClaw 官方 handler 格式
export default async function handler(event) {
  // OpenClaw 官方事件模型：event.type + event.action（兼容旧版 "message:xxx"）
  const isLegacyMessageKey = typeof event.type === 'string' && event.type.startsWith('message:');
  const legacyAction = isLegacyMessageKey ? event.type.split(':')[1] : null;
  const messageTypeOk = event.type === 'message' || isLegacyMessageKey;
  const action = event.action || legacyAction;

  // 用 message:sent 做“出站审计/告警”（Hook 层无法可靠拦截已生成但未发送的回复）
  if (!messageTypeOk || action !== 'sent') return;

  // 深合并配置
  const config = getConfig();

  // 如果禁用，直接返回
  if (!config.enabled) {
    return;
  }

  let content = (event.context && event.context.content) ? String(event.context.content) : '';
  if (!content) return;

  // 内容大小限制
  if (content.length > config.maxContentSize) {
    content = content.substring(0, config.maxContentSize);
  }

  // 验证响应
  const validation = await validateResponse(content);

  // 深度事实验证（如果启用且有本地来源）
  if (config.enableFactVerification && validation.sources.some(s => s.type === 'local')) {
    const factCheck = await performFactVerification(content, validation.sources, config.factVerificationThreshold);
    
    if (!factCheck.verified) {
      validation.issues.push(`Fact verification failed: ${factCheck.details.join('; ')}`);
    }
  }

  // 如果没有问题，直接返回
  if (validation.issues.length === 0) {
    return;
  }

  // Hook 层的通用做法：追加一条告警消息（不篡改已发送内容）
  const warning = generateWarningMessage(validation.issues);
  if (!Array.isArray(event.messages)) event.messages = [];
  event.messages.push(warning);
}
