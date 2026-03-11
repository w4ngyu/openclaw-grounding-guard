# Changelog

## [1.3.0] - 2026-03-11

### Added
- 中文关键词提取支持（CJK Unified Ideographs）
- ripgrep/grep 自动降级机制
- verify_fact 工具实现
- **Post-Processor 深度事实验证**（performFactVerification）
- 网络搜索配置参数（enableWebSearch, webSearchThreshold, maxWebResults）
- 事实验证配置参数（enableFactVerification, factVerificationThreshold）

### Fixed
- 修复中文查询无法提取关键词的问题
- 修复 ripgrep 未安装时本地搜索失效的问题
- 修复 grounding-guard.json 配置不完整的问题
- **修复 verify_fact 未集成到 Post-Processor 的问题**
- **修复 Hook 格式问题 - 从 CommonJS 转为 ES Module**
  - 解决 `Handler 'default' is not a function` 错误
  - 解决 `Cannot find module` 错误
  - 22:05:33 两个 hooks 均成功注册

### Changed
- extractKeywords 支持 CJK 字符（最小长度 2）
- safeRipgrepSearch 自动检测 ripgrep，不可用时降级为 grep
- Post-Processor 新增深度事实验证逻辑
- **handler.js 改为 ES Module 格式**（使用 `import`/`export`）
- **移除 HOOK.md 中的 `export: default` 配置**

## [1.2.0] - 2026-03-10

### Added
- Grounding Guard 基础架构（L1/L2/L3）
- search_local 工具
- search_web 工具（Tavily API）
- Post-Processor 来源/置信度验证

## [1.0.0] - 2026-03-05

### Added
- 项目初始化
- 设计规格书
