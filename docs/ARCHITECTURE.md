# Grounding Guard 3.1 架构文档

## 设计目标

- 降低幻觉率，而不是追求不现实的绝对拦截
- 把检索、校验、审计拆成独立层，减少耦合
- 让策略由配置驱动，可回退、可演进
- 对齐 harness 原则：结构化状态、角色分离、长运行稳定

## 三层架构

### L1: Pre-Processor (`message:preprocessed`)

职责：
- 关键词提取（CJK）
- 调用 L2 本地检索（必要时调用 L2 网络检索）
- 将 Grounding Context 注入 `event.context.bodyForAgent`
- 写入 `groundingCheckpoint`

边界：
- 受 `maxInputSize/maxKeywords/maxContextChars` 预算约束
- 受 `searchPaths/allowedBasePaths` 路径白名单约束
- 网络检索受熔断器约束（阈值 + 冷却）

### L2: Tool Integration（可复用工具层）

职责：
- `search_local`：本地检索与相关性评分
- `search_web`：外部检索（可选）
- `verify_fact`：来源一致性轻校验

边界：
- 执行超时与并发限制
- 不做消息改写，仅提供工具结果

### L3: Post-Processor (`message:sent`)

职责：
- 检查 `[Source]` / `[Confidence]`
- 校验本地来源可达性
- 可选调用 L2 的 `verify_fact`
- evaluator 评分（`grades/score/verdict`）
- 追加审计告警（不篡改原回复）

边界：
- `requireSource/requireConfidence` 按配置生效
- `emitAuditMessage` 与 `onMissing` 控制告警行为
- `minAuditScore` 决定审计通过阈值

## 数据流

用户消息 -> L1 注入上下文 + checkpoint -> LLM 生成 -> L3 审计评分 + 告警 -> 返回用户

## Harness 对齐点

- **System of Record**：规范与状态全部落在仓库与结构化字段
- **Generator/Evaluator 分离**：L1/L2 与 L3 职责清晰分离
- **Long-running 稳定**：熔断 + 预算 + fail-open + 审计追踪
