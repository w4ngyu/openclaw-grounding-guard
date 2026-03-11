// Grounding Guard security/utilities (CommonJS so it can be loaded from ESM hooks via createRequire)
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFile } = require('child_process');
const { promisify } = require('util');

const execFileAsync = promisify(execFile);

const DEFAULT_MAX_RESULTS = 10;
const DEFAULT_RELEVANCE_THRESHOLD = 0.6;
const DEFAULT_MAX_INPUT_SIZE = 10000;
const DEFAULT_MAX_KEYWORDS = 5;
const CONCURRENCY_LIMIT = 3;
const CONTENT_TRUNCATE_LENGTH = 500;
const DEFAULT_WEB_TIMEOUT = 15000;
const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB
const MAX_FILE_READ_CHARS = 100 * 1024; // 100KB

function expandHome(inputPath) {
  if (!inputPath || typeof inputPath !== 'string') return inputPath;
  if (!inputPath.startsWith('~')) return inputPath;
  return path.join(os.homedir(), inputPath.slice(1));
}

function escapeRegex(str) {
  return String(str).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function deepMerge(target, source) {
  const result = { ...(target || {}) };
  for (const key of Object.keys(source || {})) {
    const value = source[key];
    if (value === undefined) continue;
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      result[key] = deepMerge(result[key] || {}, value);
      continue;
    }
    result[key] = value;
  }
  return result;
}

function validatePath(inputPath, allowedBasePaths) {
  try {
    const resolvedPath = path.resolve(expandHome(inputPath));
    const allowed = (allowedBasePaths || []).some((basePath) => {
      const resolvedBase = path.resolve(expandHome(basePath));
      const relative = path.relative(resolvedBase, resolvedPath);
      return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
    });
    if (!allowed) {
      return { isValid: false, error: `Path ${resolvedPath} is not within allowed base paths` };
    }
    return { isValid: true, resolvedPath };
  } catch (error) {
    return { isValid: false, error: `Path validation error: ${error}` };
  }
}

async function tryExecFile(bin, args, options) {
  try {
    const { stdout = '' } = await execFileAsync(bin, args, options);
    return { ok: true, stdout };
  } catch (err) {
    const stdout = err && typeof err.stdout === 'string' ? err.stdout : '';
    const code = err && typeof err.code === 'number' ? err.code : undefined;
    if (code === 1) return { ok: true, stdout }; // "no matches" for rg/grep
    return { ok: false, stdout, error: err };
  }
}

async function canRun(bin, args = ['--version']) {
  const probe = await tryExecFile(bin, args, { timeout: 1000, maxBuffer: 1024 * 1024 });
  return probe.ok;
}

function parseGrepLikeOutput(stdout) {
  if (!stdout) return [];
  const lines = String(stdout).split('\n').filter((line) => line.trim());
  const results = [];
  for (const line of lines) {
    const match = line.match(/^(.+?):(\d+):(.*)$/);
    if (!match) continue;
    results.push({
      filePath: match[1],
      lineNumber: Number.parseInt(match[2], 10),
      content: match[3].trim(),
    });
  }
  return results;
}

async function safeRipgrepSearch(keyword, searchPath, maxResults, timeoutMs = 10000) {
  const results = [];
  try {
    const expandedPath = expandHome(searchPath);
    if (!expandedPath || !fs.existsSync(expandedPath)) return results;

    const maxBuffer = 8 * 1024 * 1024;

    if (await canRun('rg')) {
      const run = await tryExecFile(
        'rg',
        ['-F', '-i', '-n', '--max-count', String(maxResults), String(keyword), String(expandedPath)],
        { timeout: timeoutMs, maxBuffer }
      );
      if (!run.ok) {
        console.warn('[safeRipgrepSearch] rg failed:', run.error && run.error.message ? run.error.message : run.error);
        return results;
      }
      return parseGrepLikeOutput(run.stdout);
    }

    if (process.platform === 'win32') {
      console.warn('[safeRipgrepSearch] Windows: ripgrep (rg) is required (grep is not assumed to exist).');
      return results;
    }

    const grepHelpOk = await canRun('grep', ['--help']);
    if (!grepHelpOk) {
      console.warn('[safeRipgrepSearch] grep not found; install ripgrep (rg) for best compatibility.');
      return results;
    }

    const run = await tryExecFile(
      'grep',
      ['-R', '-i', '-n', '-m', String(maxResults), String(keyword), String(expandedPath)],
      { timeout: timeoutMs, maxBuffer }
    );
    if (!run.ok) {
      console.warn('[safeRipgrepSearch] grep failed:', run.error && run.error.message ? run.error.message : run.error);
      return results;
    }
    return parseGrepLikeOutput(run.stdout);
  } catch (error) {
    console.warn(`[safeRipgrepSearch] Search failed for "${keyword}":`, error && error.message ? error.message : error);
    return results;
  }
}

function calculateRelevance(content, keyword) {
  const lowerContent = String(content || '').toLowerCase();
  const lowerKeyword = String(keyword || '').toLowerCase();
  if (!lowerKeyword) return 0;

  if (lowerContent.includes(lowerKeyword)) {
    let score = 0.8;
    const wordBoundaryRegex = new RegExp(`\\b${escapeRegex(lowerKeyword)}\\b`, 'i');
    if (wordBoundaryRegex.test(lowerContent)) score += 0.1;
    const occurrences = (lowerContent.match(new RegExp(escapeRegex(lowerKeyword), 'gi')) || []).length;
    if (occurrences > 1) score += Math.min(0.1 * (occurrences - 1), 0.1);
    return Math.min(score, 1.0);
  }

  if (lowerKeyword.length >= 3 && lowerContent.includes(lowerKeyword.slice(0, -1))) return 0.5;
  return 0.3;
}

async function searchWeb(query, maxResults = 5) {
  if (!query || String(query).length > 1000) {
    throw new Error('Invalid query: must be non-empty and less than 1000 characters');
  }

  const apiKey = process.env.TAVILY_API_KEY;
  if (!apiKey) {
    return { results: [], query: String(query) };
  }

  if (typeof fetch !== 'function') {
    console.warn('[searchWeb] Global fetch is unavailable; requires Node.js >= 18.');
    return { results: [], query: String(query) };
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), DEFAULT_WEB_TIMEOUT);
  try {
    const response = await fetch('https://api.tavily.com/search', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        api_key: apiKey,
        query: String(query),
        max_results: maxResults,
        include_answer: false,
        search_depth: 'basic',
      }),
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`Tavily API error: ${response.status}`);
    const data = await response.json();
    const results = (data && data.results ? data.results : []).map((r) => {
      let source = 'unknown';
      try {
        if (r.url && typeof r.url === 'string') source = new URL(r.url).hostname;
      } catch {
        source = r.url ? String(r.url).split('/')[2] || 'unknown' : 'unknown';
      }
      return {
        title: String(r.title || ''),
        url: String(r.url || ''),
        snippet: String(r.content || ''),
        source,
      };
    });
    return { results, query: String(query) };
  } catch (error) {
    const msg = error && error.name === 'AbortError' ? 'timeout' : (error && error.message ? error.message : String(error));
    console.warn('[searchWeb] Failed:', msg);
    return { results: [], query: String(query) };
  } finally {
    clearTimeout(timeoutId);
  }
}

function extractKeywords(text, options = {}) {
  const maxInputSize = Number.isFinite(options.maxInputSize) ? options.maxInputSize : DEFAULT_MAX_INPUT_SIZE;
  const maxKeywords = Number.isFinite(options.maxKeywords) ? options.maxKeywords : DEFAULT_MAX_KEYWORDS;
  const truncatedText = String(text || '').length > maxInputSize ? String(text).slice(0, maxInputSize) : String(text || '');

  const stopWords = new Set([
    'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
    'should', 'may', 'might', 'must', 'shall', 'can', 'need', 'dare',
    'ought', 'used', 'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by',
    'from', 'as', 'into', 'through', 'during', 'before', 'after', 'above',
    'below', 'between', 'under', 'and', 'but', 'or', 'yet', 'so', 'if',
    'because', 'although', 'though', 'while', 'where', 'when', 'that',
    'which', 'who', 'whom', 'whose', 'what', 'this', 'these', 'those',
    'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her',
    'us', 'them', 'my', 'your', 'his', 'its', 'our', 'their', 'mine',
    'yours', 'hers', 'ours', 'theirs', 'myself', 'yourself', 'himself',
    'herself', 'itself', 'ourselves', 'yourselves', 'themselves',
  ]);

  const words = truncatedText
    .toLowerCase()
    .replace(/[^\w\s\u4e00-\u9fa5\u3040-\u309f\u30a0-\u30ff]/g, ' ')
    .split(/[\s]+/)
    .filter((word) => {
      const isCJK = /[\u4e00-\u9fa5\u3040-\u309f\u30a0-\u30ff]/.test(word);
      const minLength = isCJK ? 2 : 3;
      return word.length >= minLength && !stopWords.has(word);
    });

  const frequency = Object.create(null);
  for (const word of words) frequency[word] = (frequency[word] || 0) + 1;

  return Object.entries(frequency)
    .sort((a, b) => b[1] - a[1])
    .slice(0, maxKeywords)
    .map(([word]) => word);
}

async function verifyFact(statement, sources) {
  if (!statement || String(statement).length > 5000) {
    throw new Error('Invalid statement: must be non-empty and less than 5000 characters');
  }
  if (!Array.isArray(sources) || sources.length === 0) {
    return {
      isVerified: false,
      confidence: 0,
      reasoning: 'No sources provided for verification',
      limitations: ['Cannot verify without sources'],
    };
  }

  const limitedSources = sources.slice(0, 10);
  const statementKeywords = extractKeywords(statement, { maxInputSize: 5000, maxKeywords: 15 });
  if (statementKeywords.length === 0) {
    return {
      isVerified: false,
      confidence: 0,
      reasoning: 'Could not extract meaningful keywords from statement',
      limitations: ['Statement too vague or contains only stop words'],
    };
  }

  let verifiedCount = 0;
  let totalChecked = 0;
  const conflictingInfo = [];
  const limitations = [
    'Using simple keyword matching, not semantic understanding',
    'May produce false positives/negatives',
  ];

  for (const source of limitedSources) {
    totalChecked++;
    try {
      if (String(source).startsWith('http')) {
        limitations.push(`Cannot fetch content from web source: ${source}`);
        continue;
      }

      const expandedPath = expandHome(String(source));
      const validation = validatePath(expandedPath, ['~/.openclaw', '~/.openclaw/workspace', './', os.homedir()]);
      if (!validation.isValid) {
        conflictingInfo.push(`Path not allowed: ${source}`);
        continue;
      }

      if (!fs.existsSync(expandedPath)) {
        conflictingInfo.push(`Source file not found: ${source}`);
        continue;
      }

      const stats = fs.statSync(expandedPath);
      let sourceContent = '';
      if (stats.size > MAX_FILE_SIZE) {
        sourceContent = fs.readFileSync(expandedPath, 'utf-8').slice(0, MAX_FILE_READ_CHARS);
        limitations.push(`Large file truncated: ${source}`);
      } else {
        sourceContent = fs.readFileSync(expandedPath, 'utf-8');
      }

      const sourceLower = sourceContent.toLowerCase();
      const matchingKeywords = statementKeywords.filter((kw) => sourceLower.includes(String(kw).toLowerCase()));
      if (matchingKeywords.length / statementKeywords.length >= 0.7) {
        verifiedCount++;
      } else {
        const matchRate = Math.round((matchingKeywords.length / statementKeywords.length) * 100);
        conflictingInfo.push(`Source ${source} only matches ${matchRate}% of keywords (${matchingKeywords.length}/${statementKeywords.length})`);
      }
    } catch (e) {
      conflictingInfo.push(`Error reading source ${source}: ${e && e.message ? e.message : String(e)}`);
    }
  }

  const confidence = totalChecked > 0 ? verifiedCount / totalChecked : 0;
  return {
    isVerified: confidence >= 0.5,
    confidence,
    reasoning: `Verified against ${verifiedCount}/${totalChecked} sources using keyword matching`,
    conflictingInfo: conflictingInfo.length > 0 ? conflictingInfo : undefined,
    limitations,
  };
}

module.exports = {
  DEFAULT_MAX_RESULTS,
  DEFAULT_RELEVANCE_THRESHOLD,
  DEFAULT_MAX_INPUT_SIZE,
  DEFAULT_MAX_KEYWORDS,
  CONCURRENCY_LIMIT,
  CONTENT_TRUNCATE_LENGTH,
  DEFAULT_WEB_TIMEOUT,
  MAX_FILE_SIZE,
  MAX_FILE_READ_CHARS,
  escapeRegex,
  deepMerge,
  validatePath,
  safeRipgrepSearch,
  calculateRelevance,
  searchWeb,
  verifyFact,
  extractKeywords,
};

