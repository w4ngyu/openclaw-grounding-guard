'use strict';

const {
  safeRipgrepSearch,
  calculateRelevance,
  searchWeb,
  verifyFact,
  extractKeywords,
  validatePath,
} = require('../utils/security.cjs');

async function searchLocal({ query, keywords, searchPaths, allowedBasePaths, maxResults, timeoutMs, relevanceThreshold }) {
  const kw = Array.isArray(keywords) ? keywords : extractKeywords(String(query || ''), { maxKeywords: 5 });
  const paths = Array.isArray(searchPaths) ? searchPaths : [];
  const concurrency = 3;
  const tasks = [];
  const results = [];

  for (const searchPath of paths) {
    const validation = validatePath(searchPath, allowedBasePaths || []);
    if (!validation.isValid) continue;
    const resolvedSearchPath = validation.resolvedPath;

    for (const keyword of kw) {
      tasks.push({ keyword, resolvedSearchPath });
    }
  }

  for (let index = 0; index < tasks.length; index += concurrency) {
    const batch = tasks.slice(index, index + concurrency);
    const batchResults = await Promise.all(batch.map(async ({ keyword, resolvedSearchPath }) => {
      const raw = await safeRipgrepSearch(keyword, resolvedSearchPath, maxResults || 10, timeoutMs || 10000);
      return raw.map((r) => ({
        ...r,
        keyword,
        relevanceScore: calculateRelevance(r.content, keyword),
      }));
    }));
    results.push(...batchResults.flat());
  }

  const unique = new Map();
  for (const r of results) {
    const key = `${r.filePath}:${r.lineNumber}`;
    const existing = unique.get(key);
    if (!existing || existing.relevanceScore < r.relevanceScore) unique.set(key, r);
  }

  return Array.from(unique.values())
    .filter((r) => typeof relevanceThreshold === 'number' ? r.relevanceScore >= relevanceThreshold : true)
    .sort((a, b) => b.relevanceScore - a.relevanceScore)
    .slice(0, maxResults || 10);
}

async function searchWebTool({ query, maxResults }) {
  return searchWeb(String(query || ''), maxResults || 5);
}

async function verifyFactTool({ statement, sources, allowedBasePaths }) {
  return verifyFact(
    String(statement || ''),
    Array.isArray(sources) ? sources : [],
    { allowedBasePaths: Array.isArray(allowedBasePaths) ? allowedBasePaths : undefined }
  );
}

module.exports = {
  search_local: searchLocal,
  search_web: searchWebTool,
  verify_fact: verifyFactTool,
};
