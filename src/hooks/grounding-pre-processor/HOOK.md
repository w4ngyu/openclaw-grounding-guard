---
name: grounding-pre-processor
version: "1.3.0"
description: 自动搜索本地内容并注入 Grounding Context
entry: handler.js
metadata:
  openclaw:
    emoji: 🔍
    events:
      - message:preprocessed
---

# Grounding Pre-Processor

自动检索本地配置文件和工作区文档，将相关内容注入到系统提示中。

## 触发时机

- `message:preprocessed` - OpenClaw 完成消息预处理后（此时可修改 `bodyForAgent`）

## 功能

1. 从用户消息中提取关键词
2. 使用 ripgrep 搜索本地文件
3. 计算内容相关性
4. 构建 Grounding Context
5. 注入到 `bodyForAgent`（让后续 Agent/LLM 可直接使用）

## 依赖

- macOS/Linux：`rg`（可选，未安装会尝试降级到 `grep`）
- Windows：建议安装 `rg`（否则默认返回空结果）

## 配置

在 `~/.openclaw/grounding-guard.json` 中配置（可选）：

```json
{
  "preProcessor": {
    "enabled": true,
    "searchPaths": ["~/.openclaw/", "~/.openclaw/workspace/"],
    "maxResults": 10,
    "maxInputSize": 10000,
    "maxKeywords": 5,
    "relevanceThreshold": 0.6,
    "enableWebSearch": true
  }
}
```
