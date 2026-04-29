# OpenClaw Grounding Guard 3.1

有效抑制 OpenClaw 幻觉率：自动注入可追溯上下文，并通过独立评估器做出站审计。

## 3.1 升级重点

- Harness 化运行状态：L1 写入 checkpoint，L3 读取并完成审计闭环
- 网络检索熔断：失败计数 + 冷却窗口，避免长运行时持续失败抖动
- 生成与评估分离：L3 作为独立 evaluator 计算审计分数与结论
- 强约束可配置：`requireSource` / `requireConfidence` 仍由配置硬执行
- 无侵入输出：`message:sent` 仅追加告警，不改写主回复

## 两篇基准文章（3.1 设计依据）

- OpenAI Harness Engineering: <https://openai.com/zh-Hans-CN/index/harness-engineering/>
- Anthropic Harness Design: <https://www.anthropic.com/engineering/harness-design-long-running-apps>

## 快速安装

```bash
openclaw hooks install .
openclaw hooks list
cp config/example.json ~/.openclaw/grounding-guard.json
```

可选环境变量（启用网络检索）：

```bash
export TAVILY_API_KEY="your-api-key"
```

## 架构

```text
用户消息
    ↓
[Hook] Pre-Processor (L1)
    ├── extractKeywords
    ├── 调用 [Tools] search_local
    ├── 按需调用 [Tools] search_web（带熔断）
    ├── 注入 Grounding Context
    └── 写入 checkpoint/harness 状态
    ↓
LLM 生成响应
    ↓
[Hook] Post-Processor (L3)
    ├── 解析 [Source] / [Confidence]
    ├── 可选调用 [Tools] verify_fact
    ├── evaluator 评分（score + verdict）
    └── 追加审计告警（不篡改原回复）
    ↓
返回给用户
```

## 3.1 关键配置

```json
{
  "preProcessor": {
    "enabled": true,
    "version": "3.1.0",
    "executionMode": "balanced",
    "searchPaths": ["~/.openclaw/", "~/.openclaw/workspace/"],
    "allowedBasePaths": ["~/.openclaw/", "~/.openclaw/workspace/"],
    "maxResults": 10,
    "maxKeywords": 5,
    "maxContextChars": 6000,
    "enableWebSearch": true,
    "webSearchThreshold": 3,
    "maxWebResults": 5,
    "checkpointEnabled": true,
    "webCircuitBreakerFailureThreshold": 3,
    "webCircuitBreakerCooldownMs": 300000
  },
  "postProcessor": {
    "enabled": true,
    "version": "3.1.0",
    "allowedBasePaths": ["~/.openclaw/", "~/.openclaw/workspace/"],
    "requireSource": true,
    "requireConfidence": true,
    "onMissing": "warn",
    "enableFactVerification": true,
    "factVerificationThreshold": 0.5,
    "emitAuditMessage": true,
    "evaluatorEnabled": true,
    "minAuditScore": 70
  }
}
```

## 文档

- `docs/ARCHITECTURE.md`
- `docs/CONFIGURATION.md`
- `docs/INSTALL.md`
- `docs/EXECUTION_SPEC_3.1.md`
- `docs/HARNESS_MAPPING_3.1.md`

## License

MIT
