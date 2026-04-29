# Grounding Guard 3.1 安装指南

## 前置条件

- OpenClaw CLI 可用
- Node.js >= 18
- 推荐安装 `rg`（ripgrep）

## 安装步骤

### 1. 安装 Hook Pack

在 `source/` 目录执行：

```bash
openclaw hooks install .
openclaw hooks list
```

### 2. 写入配置

```bash
cp config/example.json ~/.openclaw/grounding-guard.json
```

### 3. 可选配置网络检索

```bash
export TAVILY_API_KEY="your-api-key"
```

### 4. 生效验证

```bash
openclaw hooks info grounding-pre-processor
openclaw hooks info grounding-post-processor
```

## 快速自检

```bash
node -e "import('./src/hooks/grounding-pre-processor/handler.js').then(()=>console.log('pre ok'))"
node -e "import('./src/hooks/grounding-post-processor/handler.js').then(()=>console.log('post ok'))"
node -e "const t=require('./src/tools/grounding-tools.cjs'); console.log(Object.keys(t))"
```

预期：
- `pre ok`
- `post ok`
- `search_local,search_web,verify_fact`

## 常见问题

### `L2 tools unavailable`

原因：仅复制了 hooks，未复制 `src/tools`。

解决：确保按包安装（`openclaw hooks install .`），不要只手工拷贝单个 hook 目录。

### Windows 本地检索无结果

原因：未安装 `rg`。

解决：安装 ripgrep（`scoop install ripgrep` 或 `choco install ripgrep`）。
