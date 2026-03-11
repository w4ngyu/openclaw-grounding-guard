---
name: grounding-post-processor
version: "1.3.0"
description: 出站审计：检查来源/置信度标注并追加告警
entry: handler.js
metadata:
  openclaw:
    emoji: 🛡️
    events:
      - message:sent
---

# Grounding Post-Processor

验证 LLM 响应是否包含必要的来源标注和置信度标注。

## 触发时机

- `message:sent` - 出站消息已发送后（Hook 层做审计/告警）

## 功能

1. 解析 [Source: ...] 标注
2. 解析 [Confidence: ...] 标注
3. 验证本地来源文件存在性
4. 检查置信度与来源类型匹配
5. 追加一条告警消息（不篡改已发送内容）

## 说明

OpenClaw 的 Hooks 机制在通用情况下更适合“补充上下文/记录/告警”。如需“硬拦截/强制重写回复”，通常需要更深的运行时集成（非纯 Hook）。

## 配置

在 `~/.openclaw/grounding-guard.json` 中配置（可选）：

```json
{
  "postProcessor": {
    "enabled": true,
    "requireSource": true,
    "requireConfidence": true,
    "enableFactVerification": true,
    "factVerificationThreshold": 0.5
  }
}
```
