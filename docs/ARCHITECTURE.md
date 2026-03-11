# Grounding Guard 架构文档

## 系统概述

Grounding Guard 是一组 OpenClaw Hooks + 一组“工具函数（L2）”，主目标是为每次对话自动注入「可追溯的本地/网络上下文」并强化来源标注习惯。

## 三层架构

### Layer 1: Pre-Processor（输入预处理层）

**触发时机**: `message:preprocessed` - OpenClaw 完成消息预处理后（此时可安全修改 `bodyForAgent`）

**功能**:
1. 提取关键词（支持 CJK 中文/日文/韩文）
2. 本地文件搜索（ripgrep/grep 自动降级）
3. 网络搜索补充（本地结果 < 3 时触发 Tavily）
4. 构建 Grounding Context 注入 `bodyForAgent`

**文件**: `src/hooks/grounding-pre-processor/handler.js`

### Layer 2: Tool Integration（工具集成层）

L2 是“可复用工具函数层”，用于把本地搜索 / 网络搜索 / 事实校验从 Hook 逻辑中抽离，便于复用、测试与演进。

**工具列表**:
- `search_local`：本地文件搜索（rg 优先、grep 降级）
- `search_web`：Tavily 网络搜索（需要 `TAVILY_API_KEY`）
- `verify_fact`：对本地来源做关键词一致性校验（轻量校验）

**文件**: `src/tools/grounding-tools.cjs`

### Layer 3: Post-Processor（出站审计/告警层）

**触发时机**: `message:sent` - 出站消息已发送后

**功能**:
1. 解析 `[Source: ...]` 标注
2. 解析 `[Confidence: ...]` 标注
3. 验证本地来源文件存在性
4. 追加一条告警消息（不篡改已发送内容）

**文件**: `src/hooks/grounding-post-processor/handler.js`

## 数据流

```
用户消息
    ↓
Pre-Processor
    ├── extractKeywords
    ├── searchLocalFiles
    ├── searchWeb (if local < 3)
    └── buildGroundingContext
    ↓
注入 Grounding Context 到 bodyForAgent
    ↓
LLM 生成响应并发送
    ↓
Post-Processor（sent 审计）
    ├── parseSourceAnnotations
    ├── parseConfidenceAnnotations
    ├── validateLocalSources（可选）
    └── warn message
```

## 关键技术点

### CJK 支持
```typescript
// 保留 CJK Unified Ideographs + Hiragana + Katakana
.replace(/[^\w\s\u4e00-\u9fa5\u3040-\u309f\u30a0-\u30ff]/g, ' ')
```

### 自动降级
```typescript
try {
  await execAsync('which rg', { timeout: 1000 });
  // 使用 ripgrep
} catch {
  // 降级为 grep
}
```

### 信源优先级
- 本地文件 → `[Confidence: high]`
- 网络搜索 → `[Confidence: medium]`
- LLM 知识 → `[Confidence: low]`
- 无法验证 → `[Confidence: unknown]`
