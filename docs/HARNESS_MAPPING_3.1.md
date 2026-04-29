# Harness 原则到 Guard 3.1 的映射

## 参考

- OpenAI: <https://openai.com/zh-Hans-CN/index/harness-engineering/>
- Anthropic: <https://www.anthropic.com/engineering/harness-design-long-running-apps>

## 映射关系

### A. “地图而非百科全书” -> 最小入口 + 渐进披露

- 使用简洁主配置，细节下沉到分文档
- 运行时只注入预算内关键信息，不一次性灌入全部上下文

### B. 代码仓库作为记录系统 -> 结构化 checkpoint/audit

- L1 写 `groundingCheckpoint`
- L3 写 `groundingAudit`
- 支持按运行阶段追踪与回溯

### C. 反馈回路与角色分离 -> 生成/评估分离

- L1/L2 负责生成上下文
- L3 作为独立 evaluator 打分与判定

### D. 长运行应用稳定性 -> 熔断与降级

- web search 失败达到阈值后进入冷却期
- L2 缺失或外部检索失败时保持 fail-open，不阻断主链路

### E. 控制熵 -> 明确预算 + 问题码

- `maxContextChars` 控制上下文膨胀
- 审计问题标准化编码（`GG-*`）便于治理
