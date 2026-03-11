# Grounding Guard（dist）GitHub 发布审计报告

更新时间：2026-03-12

## 结论（是否达到发 GitHub 标准）

**结论：基本达到。** `dist/` 已具备「可公开仓库发布」的最小闭环：明确的安装方式、MIT License、变更记录、可被 OpenClaw 官方 `hooks install` 识别的 Hook Pack 结构、默认配置与安全边界。

推荐把 `dist/` 作为 GitHub 仓库根目录发布（或把本项目根目录发布，但在 README 明确 `dist/` 才是可安装产物）。

## 打分（10 分制）

- **OpenClaw 兼容性**：8/10  
  - Hook 事件与 `event.type + event.action` 模型对齐（并保留一定的兼容分支）。
  - Pre-Processor 使用 `message:preprocessed`，通过修改 `event.context.bodyForAgent` 注入上下文，符合 Hooks 的通用能力边界。
  - Post-Processor 调整为 `message:sent` 的“审计/告警”模式（Hook 层无法稳定做到“拦截并重写已生成但未发送的回复”）。
- **通用性/可移植性**：7/10  
  - Node.js `>=18`（依赖全局 `fetch`）。
  - macOS/Linux：优先 `rg`，缺失时降级 `grep`；Windows 默认要求 `rg`（未安装则返回空结果并告警）。
- **稳定性/安全性**：8/10  
  - 本地搜索使用 `execFile` 传参（避免 shell 注入与跨平台重定向问题）。
  - 搜索路径有 allowlist（默认仅 `~/.openclaw/` 与 `~/.openclaw/workspace/`）。
  - 事实校验读取文件有体积上限与截断。
- **发布完整度（文档/授权/结构）**：8/10  
  - `README.md`、`docs/`、`LICENSE`、`CHANGELOG.md`、示例配置齐全。
  - `package.json` 含 `openclaw.hooks`，满足 Hook Pack 安装路径。

综合：**7.8/10（可公开发布）**

## 关键检查项（通过/风险）

### 1) 必备发布文件

- 通过：`README.md`、`LICENSE`（MIT）、`CHANGELOG.md`
- 通过：`docs/INSTALL.md`、`docs/ARCHITECTURE.md`
- 通过：`config/example.json`
- 通过：`package.json`（含 `openclaw.hooks`，可用于 `openclaw hooks install .`）

### 2) OpenClaw Hooks 语法与事件模型

- 通过：`HOOK.md` 采用 frontmatter + `entry: handler.js`
- 通过：Pre-Processor 事件：`message:preprocessed`
- 通过：Post-Processor 事件：`message:sent`
- 风险（已在文档中声明）：Hook 机制更适合“注入/记录/告警”，不适合作为“硬拦截回复”的通用实现方式

### 3) 依赖与运行环境

- 通过：不再依赖 `node-fetch`（改用 Node 18+ 的全局 `fetch`）
- 风险：Windows 原生缺省不保证 `grep`，因此未安装 `rg` 时本地搜索会空结果（已告警 + 文档说明）

### 4) 脱敏/泄露检查（dist 内）

- 通过：未发现真实 API Key / Token / 私钥等敏感内容（仅示例 `TAVILY_API_KEY`）
- 建议：如果要长期公开维护，建议再补一层 CI 检查（例如简单的 secret scan）

## 已做的“GitHub 发布就绪”修正（本次审计内补齐）

- 新增 `dist/package.json`，使其成为符合 OpenClaw `hooks install` 的 Hook Pack
- 修正 Hook 事件模型：从旧式 `message:xxx` 判断改为对齐 `event.type + event.action`（并保留一定兼容）
- 修正注入点：Pre-Processor 改为写入 `event.context.bodyForAgent`
- 修正工具模块：`security.js` → `security.cjs`（配合 `type: module` 的 ESM Hooks），并移除 `node-fetch` 依赖
- 修正文档：安装方式、配置路径、事件名、能力边界（post 仅审计/告警）
- 收紧默认搜索路径：默认不再包含 `./`（避免 Gateway 工作目录不确定导致误扫全盘）

## 后续可选增强（不影响发布但提升体验）

- 增加“安装后自检”脚本（例如输出 hooks list + 一次 dry-run 搜索）
- 增加 Windows 指南（`scoop install ripgrep` / `choco install ripgrep`）到 `docs/INSTALL.md`
- 如果未来 OpenClaw 提供“出站可拦截/可重写”的官方事件或插件生命周期钩子，可把 Post-Processor 升级为真正的强制策略

