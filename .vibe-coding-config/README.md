# Vibe Coding 配置说明

这个目录用于统一管理三家工具的 MCP 与记忆文件同步：
- Codex
- Claude Code
- Gemini CLI

## 这个系统到底怎么工作
- 你只维护两份“源文件”：
  - MCP 源：`mcp/mcp.json`
  - 记忆源：`memory/AGENTS.md`
- 脚本 `scripts/sync-configs.sh` 做的事情是“分发”：
  - 把 `mcp.json` 写到三家工具的原生配置文件
  - 把根目录 `AGENTS.md / CLAUDE.md / GEMINI.md` 指向同一份记忆源（软链接）
- 所以核心原则是：
  - 单一事实源（避免三份配置漂移）
  - 工具端只读原生位置（不改工具默认行为）
  - 仓库内可审计，用户目录是生成结果

## 目录结构
- `mcp/mcp.example.json`：MCP 模板文件（可提交到 Git）。
- `mcp/mcp.json`：本地 MCP 实际配置（包含密钥，默认不进 Git）。
- `mcp/mcp-add-history.sh`：MCP 命令账本脚本（手工记录/回放参考，不参与默认同步）。
- `memory/AGENTS.md`：统一记忆主文件。
- `scripts/sync-configs.sh`：主同步脚本（真正执行同步动作）。
- `.env.mcp.local`：本地环境变量（可选，默认不进 Git）。

## 两个 Shell 文件的区别（重点）
- `scripts/sync-configs.sh`：
  - 这是主程序。
  - 你日常只需要运行这个脚本。
  - 负责把 `mcp/mcp.json` 同步到目标配置，并处理记忆软链接。
- `mcp/mcp-add-history.sh`：
  - 这是命令账本（记录历史 `mcp add ...`）。
  - 默认不会被 `sync-configs.sh` 调用。
  - 主要用于留痕、回看、人工参考，不是必跑脚本。

## 主同步脚本用法
```bash
# 默认 scope=project（推荐）
./.vibe-coding-config/scripts/sync-configs.sh mcp
./.vibe-coding-config/scripts/sync-configs.sh memory
./.vibe-coding-config/scripts/sync-configs.sh all
./.vibe-coding-config/scripts/sync-configs.sh dry-run

# 显式使用全局 scope（会写入 ~）
./.vibe-coding-config/scripts/sync-configs.sh --scope global mcp
```

## 更新 MCP 内容（新增/修改/删除）
1. 编辑 `mcp/mcp.json` 的 `mcpServers`：
   - 新增：新增一个 server 节点（名字、`command`、`args`）
   - 修改：直接改已有 server 的 `command/args/env`
   - 删除：删除该 server 节点
2. 先预览：
```bash
./.vibe-coding-config/scripts/sync-configs.sh dry-run
```
3. 执行同步：
```bash
./.vibe-coding-config/scripts/sync-configs.sh mcp
```
4. 重启对应 CLI（Codex / Claude / Gemini）或新开会话，让新 MCP 配置生效。

## 新安装与依赖
- 必需依赖：
  - `jq`（脚本解析 JSON）
  - `node` + `npm/npx`（多数 MCP 用 `npx` 启动）
- 建议检查：
```bash
jq --version
node --version
npx --version
```
- 关于“是否需要手动安装 MCP 包”：
  - 如果 `command` 是 `npx ...`（当前配置就是），通常不需要手动全局安装，首次运行会自动拉取。
  - 如果网络受限或代理有问题，首次拉取可能失败，需要先处理 npm 网络或手动安装。
  - 如果 `command` 是本地二进制路径（不是 `npx`），需要你先在本机安装对应可执行文件。

### 每个命令具体做什么
- `mcp`（仅 MCP 同步，默认项目作用域）：
  - 读取 `mcp/mcp.json` 的 `mcpServers`
  - 更新项目内 `./.mcp.json`（Claude 项目配置）
  - 更新项目内 `./.gemini/settings.json`（Gemini 工作区配置）
  - `codex` 项目作用域下目前不做持久写入（会给提示）
- `memory`（仅记忆入口同步）：
  - 确保 `memory/AGENTS.md` 存在
  - 创建/更新根目录软链接：
    - `AGENTS.md`
    - `CLAUDE.md`
    - `GEMINI.md`
- `all`：
  - 先执行 `mcp`，再执行 `memory`
- `dry-run`：
  - 不写任何文件
  - 只打印源文件、目标文件、当前 MCP server 列表

### 成功/失败判断
- 成功时会输出：`ok: updated ...` 或 `ok: linked ...`
- 典型失败场景：
  - 没有 `jq`：会报 `jq is required`
  - `mcp.json` 缺少 `mcpServers`：会报 `missing mcpServers in mcp.json`
  - 使用 `${VAR}` 占位但变量没定义：会报 `Missing env var: ...`
  - 运行环境限制写入 `~`：需要提权执行 `mcp` 或 `all`
  - `npx` 首次拉取失败：通常是网络/代理问题，不是同步脚本逻辑错误

## 作用域说明（project vs global）
- `project`（默认）：
  - 只写当前仓库内文件（推荐）
  - 目标：`./.mcp.json`、`./.gemini/settings.json`
  - 不写 `~`，避免影响其他项目
- `global`：
  - 写用户全局配置（会影响其他项目）
  - 目标：`~/.codex/config.toml`、`~/.claude.json`、`~/.gemini/settings.json`
  - 需要时手动显式传 `--scope global`

## 首次配置步骤
1. 从模板创建本地 MCP 文件：
```bash
cp ./.vibe-coding-config/mcp/mcp.example.json ./.vibe-coding-config/mcp/mcp.json
```
2. 编辑 `mcp/mcp.json`：
可以直接写明文，或使用 `${VAR}` 占位。
3. 如果用了 `${VAR}`，在 `./.vibe-coding-config/.env.mcp.local` 填变量值。
4. 执行：
```bash
./.vibe-coding-config/scripts/sync-configs.sh all
```

## 安全建议（重要）
- 不要把真实密钥写进 `mcp.example.json`。
- `mcp/mcp.json`、`.env.mcp.local`、`./.mcp.json`、`./.gemini/settings.json` 默认已加入 `.gitignore`，避免误提交。
- 提交前建议执行：
```bash
git status
```
确认没有把密钥文件带入版本库。
