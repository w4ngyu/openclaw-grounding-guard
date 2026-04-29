# Grounding Guard 3.1 执行规范

版本：3.1.0

## 0. 依据

- OpenAI Harness Engineering（2026-02-11）
- Anthropic Harness Design for long-running apps（2026-03-24）

## 1. 生命周期与职责分离

- L1 必须运行在 `message:preprocessed`
- L3 必须运行在 `message:sent`
- L3 仅审计，不得改写已发送主回复

## 2. 长运行稳定性约束

- 必须具备 checkpoint/handoff 字段，跨阶段可追踪
- 网络检索必须支持熔断（失败阈值 + 冷却时间）
- 降级路径必须可用：L2 不可用时不阻断主流程

## 3. 评估器规范（Generator/Evaluator 分离）

- 生成由 L1/L2 负责，评估由 L3 负责
- L3 产出结构化结果：`grades/score/verdict/issues`
- 评估阈值由 `minAuditScore` 配置驱动

## 4. 预算与边界

- 输入预算：`maxInputSize`
- 检索预算：`maxKeywords` + `maxResults`
- 注入预算：`maxContextChars`
- 路径边界：全部本地读取必须通过 `allowedBasePaths`

## 5. 策略执行要求

- `requireSource` 与 `requireConfidence` 必须由代码执行
- 缺失时按 `onMissing` 行为：
  - `warn`: 输出告警
  - `silent`: 仅记录审计

## 6. 可观测性

- L1 输出 `groundingDiagnostics` 与 `groundingCheckpoint`
- L3 输出 `groundingAudit`（含评分与问题码）
