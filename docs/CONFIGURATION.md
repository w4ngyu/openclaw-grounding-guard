# Grounding Guard 3.1 配置指南

## 配置文件位置

`~/.openclaw/grounding-guard.json`

## `preProcessor`

- `enabled`: 是否启用 L1
- `version`: 配置版本（建议 `3.1.0`）
- `executionMode`: `strict` | `balanced` | `performance`
- `searchPaths`: 检索路径
- `allowedBasePaths`: 路径白名单
- `maxResults`: 本地命中上限
- `maxKeywords`: 关键词上限
- `maxContextChars`: 注入上下文字符预算
- `enableWebSearch`: 是否允许网络检索
- `webSearchThreshold`: 本地命中低于该值触发网络检索
- `maxWebResults`: 网络命中上限
- `checkpointEnabled`: 是否输出 `groundingCheckpoint`
- `webCircuitBreakerFailureThreshold`: 熔断失败阈值
- `webCircuitBreakerCooldownMs`: 熔断冷却时长（毫秒）
- `emitDiagnostics`: 是否输出 `groundingDiagnostics`

## `postProcessor`

- `enabled`: 是否启用 L3
- `version`: 配置版本（建议 `3.1.0`）
- `allowedBasePaths`: 来源路径白名单
- `requireSource`: 强制要求 `[Source]`
- `requireConfidence`: 强制要求 `[Confidence]`
- `onMissing`: `warn` | `silent`
- `enableFactVerification`: 启用轻量一致性校验
- `factVerificationThreshold`: 校验置信阈值
- `emitAuditMessage`: 是否向对话追加审计告警
- `evaluatorEnabled`: 是否启用独立评估器
- `minAuditScore`: 审计通过阈值（0~100）

## 模式建议

- `strict`: 稳定优先，预算更紧，默认关闭网络检索
- `balanced`: 默认推荐，效果与开销平衡
- `performance`: 低延迟优先，命中与上下文预算更小

## 故障排查

### 配置无效

- 用 `python3 -m json.tool ~/.openclaw/grounding-guard.json` 验证 JSON
- 重新执行 `openclaw hooks list` / `openclaw hooks info <name>`

### 无 checkpoint/audit 输出

- 检查 `preProcessor.checkpointEnabled`
- 检查 `postProcessor.evaluatorEnabled`
- 检查 `preProcessor.enabled` / `postProcessor.enabled`

### 误报过多

- 调低 `requireSource/requireConfidence`
- 设置 `onMissing: "silent"` 或 `emitAuditMessage: false`
- 适当下调 `minAuditScore`

### 网络检索频繁失败

- 检查 `TAVILY_API_KEY`
- 调整熔断参数，观察 `groundingDiagnostics.webCircuitOpen`
