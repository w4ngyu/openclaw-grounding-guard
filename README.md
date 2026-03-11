# OpenClaw Grounding Guard

有效抑制 OpenClaw 幻觉率：自动注入可追溯上下文，并对出站标注做审计告警。

> Anti-Hallucination add-on for OpenClaw - 自动注入可追溯上下文，并对出站标注做审计告警

## 核心特性

- **三层架构**: L1 Pre-Processor（注入上下文）→ L2 Tools（搜索/校验）→ L3 Post-Processor（出站审计/告警）
- **四级置信度**: high (本地) / medium (网络) / low (LLM) / unknown
- **中文支持**: 完整的中文关键词提取和搜索（CJK 字符）
- **自动降级**: ripgrep 不可用时自动使用 grep
- **标注审计**: 检查 [Source] / [Confidence]，缺失时追加告警（不篡改已发送内容）
- **深度验证（可选）**: 基于本地来源做关键词一致性校验（verify_fact）
- **智能补充**: 本地结果 < 3 时自动触发网络搜索

## 快速安装

```bash
# 1. 安装 Hook Pack（推荐：符合 OpenClaw 官方 hooks install 规范）
# 在 dist 目录执行：
openclaw hooks install .

# 2. （可选）确认已启用
openclaw hooks list

# 3. 复制配置文件（可选）
cp config/example.json ~/.openclaw/grounding-guard.json

# 4. 安装依赖（可选）
# macOS: brew install ripgrep
# Windows: 建议安装 ripgrep（choco/scoop），否则只会返回空结果

# 5. 如未生效再重启 Gateway（不同部署方式命令可能不同）
# openclaw gateway restart

# 6. 验证安装
# macOS/Linux 示例（你的日志路径可能不同）
grep -i "grounding" /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log | tail -20
# 预期输出:
# Registered hook: grounding-post-processor -> message:sent
# Registered hook: grounding-pre-processor -> message:preprocessed
```

## 重要：Hook 格式要求

本项目使用 **ES Module** 格式，这是 OpenClaw 正确加载的关键。

**handler.js 必须使用以下格式**:
```javascript
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const { extractKeywords } = require('../../utils/security.cjs');

export default async function handler(event) {
  // Hook 逻辑
}
```

**不要**使用 CommonJS 格式 (`require`/`module.exports`)，否则会出现 `Handler 'default' is not a function` 错误。

## 架构

```
用户消息
    ↓
[Hook] Pre-Processor (L1)
    ├── extractKeywords (支持中文 CJK)
    ├── safeRipgrepSearch (rg/grep 自动降级)
    ├── searchWeb (Tavily API，本地<3结果时触发)
    └── 合并注入 Grounding Context
    ↓
LLM 生成响应
    ↓
[Hook] Post-Processor (L3)
    ├── 解析 [Source] 和 [Confidence]
    ├── 验证本地文件存在性
    └── 出站审计：发送后追加告警（不篡改原回复）
    ↓
返回给用户（建议带 [Source] 和 [Confidence]）
```

## 配置

编辑 `~/.openclaw/grounding-guard.json`:

```json
{
  "preProcessor": {
    "enabled": true,
    "searchPaths": ["~/.openclaw/", "~/.openclaw/workspace/"],
    "maxResults": 10,
    "relevanceThreshold": 0.6,
    "enableWebSearch": true,
    "webSearchThreshold": 3,
    "maxWebResults": 5
  },
  "postProcessor": {
    "enabled": true,
    "requireSource": true,
    "requireConfidence": true,
    "onMissing": "auto-fix",
    "enableFactVerification": true,
    "factVerificationThreshold": 0.5
  }
}
```

## 环境变量

```bash
export TAVILY_API_KEY="your-api-key"  # 用于网络搜索
```

## 信源优先级

| 优先级 | 信源类型 | 置信度标签 | 检索方式 |
|--------|----------|------------|----------|
| 1 | 本地配置文件 | `[Confidence: high]` | ripgrep/grep |
| 2 | 本地工作区文件 | `[Confidence: high]` | ripgrep/grep |
| 3 | 网络搜索 (Tavily) | `[Confidence: medium]` | API 调用 |
| 4 | LLM 内部知识 | `[Confidence: low]` | 标注为推测 |
| 5 | 无法验证 | `[Confidence: unknown]` | 必须承认不确定 |

## 文件结构

```
src/
├── hooks/
│   ├── grounding-pre-processor/
│   │   ├── HOOK.md
│   │   └── handler.js      # L1: 输入预处理 (ES Module)
│   └── grounding-post-processor/
│       ├── HOOK.md
│       └── handler.js      # L3: 出站审计/告警 (ES Module)
├── tools/
│   └── grounding-tools.cjs  # L2: 工具函数封装（search_local/search_web/verify_fact）
├── utils/
│   └── security.cjs        # 安全工具模块 (CommonJS)

config/
└── example.json            # 配置示例
```

**注意**: handler.js 使用 ES Module 格式（`import`/`export`），而 utils/security.cjs 保持 CommonJS 格式（`require`/`exports`）。

## 测试

```bash
# 测试中文关键词提取
cd ~/.openclaw/hooks && node -e "
const { extractKeywords } = require('./utils/security.cjs');
console.log(extractKeywords('不死鸟 V3 版本'));
// 输出: ['不死鸟', '版本']
"

# 测试本地搜索
cd ~/.openclaw/hooks && node -e "
const { safeRipgrepSearch } = require('./utils/security.cjs');
async function test() {
  const results = await safeRipgrepSearch('不死鸟', '~/.openclaw/workspace/doc', 5);
  console.log('Found:', results.length);
}
test();
"
```

## 故障排除

### 问题: Hook 加载失败 - `Handler 'default' is not a function`
**原因**: handler.js 使用了 CommonJS 格式，OpenClaw 需要 ES Module 格式
**解决**: 确保 handler.js 使用 ES Module 语法：
```javascript
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
export default async function handler(event) { ... }
```

### 问题: Hook 加载失败 - `Cannot find module`
**原因**: OpenClaw 尝试加载 `.ts` 文件而不是 `.js`
**解决**: 
1. 确保 `.ts` 文件已重命名或删除
2. 确保 `handler.js` 存在且为 ES Module 格式
3. 确保 HOOK.md 中指定了 `entry: handler.js`

### 问题: 中文搜索无结果
**解决**: 检查 `utils/security.cjs` 是否包含 CJK 正则；Windows 需要安装 ripgrep（rg）

### 问题: 本地搜索报错
**解决**: 检查系统是否有 `grep`，或安装 `ripgrep`:
```bash
brew install ripgrep
```

### 问题: 网络搜索不触发
**解决**: 检查 `TAVILY_API_KEY` 是否设置
```bash
echo $TAVILY_API_KEY
```

## License

MIT
