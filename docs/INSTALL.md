# Grounding Guard 安装指南

## 快速安装（推荐）

### 1. 安装 Hook Pack

在本项目的 `dist/` 目录中执行：

```bash
openclaw hooks install .
openclaw hooks list
```

### 2. 配置（可选）

```bash
# 复制配置文件
cp config/example.json ~/.openclaw/grounding-guard.json

# 编辑配置（可选）
nano ~/.openclaw/grounding-guard.json
```

### 3. 环境变量（可选：网络搜索）

```bash
# 添加到 ~/.zshrc 或 ~/.bashrc
export TAVILY_API_KEY="your-tavily-api-key"

# 重新加载配置
source ~/.zshrc
```

### 4. 生效方式

多数情况下安装后立即生效；如未生效再重启 Gateway（不同部署方式命令可能不同）。

## 验证安装

```bash
# 查看 hooks 列表
openclaw hooks list

# 测试中文关键词提取
cd ~/.openclaw/hooks && node -e "
const { extractKeywords } = require('./utils/security.cjs');
console.log(extractKeywords('不死鸟 V3 版本'));
"
# 预期输出: ['不死鸟', '版本']
```

## 故障排除

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
