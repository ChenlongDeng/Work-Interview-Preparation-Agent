# 项目内 Vibe Coding 统一配置（Codex + Claude）

这套配置的目标是：
- 只维护项目内的一份源配置；
- 一条脚本同步到 Codex / Claude 的原生读取位置；
- 敏感信息不入库。

## 设计逻辑

系统分成两层：
1. 源配置层（可维护）：`.vibe-coding-config/**`
2. 运行时层（工具实际读取）：`.mcp.json`、`.codex/config.toml`、`.codex/agents/profiles`、`.claude/agents`

同步脚本负责把“源配置层”投影到“运行时层”。

## 目录结构

- `mcp/mcp.template.json`：MCP 唯一源模板（可提交，推荐只放 `${VAR}` 占位）
- `mcp/mcp-add-history.sh`：`mcp add` 命令账本（默认不执行）
- `memory/AGENTS.md`：统一记忆主文件
- `skills/<skill_id>/SKILL.md`：技能源文件
- `agents.toml`：Agents 唯一源（Codex 原生 TOML）
- `agent-profiles/**`：Codex profiles 唯一源（会镜像同步到 `.codex/agents/profiles`）
- `scripts/sync-configs.sh`：唯一同步入口
- `.env.mcp.local`：MCP 敏感变量（不提交）

## 唯一同步脚本

```bash
./.vibe-coding-config/scripts/sync-configs.sh mcp
./.vibe-coding-config/scripts/sync-configs.sh memory
./.vibe-coding-config/scripts/sync-configs.sh skills
./.vibe-coding-config/scripts/sync-configs.sh agents
./.vibe-coding-config/scripts/sync-configs.sh all
./.vibe-coding-config/scripts/sync-configs.sh dry-run

# 仅显式导入账本（默认不会执行账本）
./.vibe-coding-config/scripts/sync-configs.sh --import-history mcp
```

## 每个命令做什么

- `mcp`
  - 读取 `mcp.template.json`
  - 解析 `${VAR}`（来自 `.env.mcp.local`）
  - 可选导入 `mcp-add-history.sh` 中 `# @mcp-add {...}`
  - 写入项目根 `.mcp.json`（Claude project MCP）
  - 写入项目内 `.codex/config.toml` 的 MCP managed block

- `memory`
  - 维护根目录软链接：`AGENTS.md`、`CLAUDE.md`
  - 二者都指向 `.vibe-coding-config/memory/AGENTS.md`

- `skills`
  - Codex：`.agents/skills -> .vibe-coding-config/skills`（软链接）
  - 不再导出到 Claude slash commands

- `agents`
  - 只读 `agents.toml`（单一源）
  - 同步 `agent-profiles/**` 到 `.codex/agents/profiles/**`
  - 写入 `.codex/config.toml` 的 agents managed block
  - 自动生成 `.claude/agents/<agent_name>.md`

- `all`
  - 依次执行：`mcp` + `memory` + `skills` + `agents`

- `dry-run`
  - 不改文件，只打印源与目标、可解析的 MCP 服务列表

## 关于 Slash Commands 与 Skills

- `slash commands`：给你用的触发入口（例如在 Claude 里输入 `/xxx`）。
- `skills`：给模型用的能力说明与执行规范。
- 这两者可以桥接，也可以分离。当前配置已关闭桥接，只保留 skills 本体。

## Claude 同名导出与覆盖规则

- 不使用前缀，直接导出同名文件。
- 脚本通过文件首行标记 `<!-- managed-by: vibe-coding-config -->` 识别自己生成的文件。
- 如果目标文件同名但不是脚本管理文件，脚本会跳过并告警，不会覆盖你的手写文件。

## Codex Agents 源写法（推荐）

在 `agents.toml` 里使用：

```toml
[agents.reviewer]
description = "Review code changes and call out concrete risks."
model = "gpt-5"
tools = ["Read", "Grep", "Bash"]
prompt = """
You are a strict code reviewer.
Focus on correctness and regression risk.
"""
```

目前脚本会从每个 `[agents.<name>]` 解析这些字段：
- `description`（可选）
- `model`（可选）
- `tools`（可选，字符串数组）
- `prompt`（可选，支持 `"""..."""` 多行）

## MCP 更新方式

1. 修改模板：`mcp/mcp.template.json`
2. 本地敏感值写入：`.env.mcp.local`
3. 预览：
```bash
./.vibe-coding-config/scripts/sync-configs.sh dry-run
```
4. 同步：
```bash
./.vibe-coding-config/scripts/sync-configs.sh mcp
```
5. 重新打开 Codex / Claude 会话。

## 安全与 Git

建议忽略：
- `.vibe-coding-config/.env.mcp.local`
- `.mcp.json`
- `.codex/config.toml`
- `.claude/settings.local.json`

建议提交前执行：
```bash
git status
```
确认没有敏感信息。

## 注意事项

- `mcp-add-history.sh` 默认只是账本，不自动执行。
- Codex 要读取项目内 `.codex/config.toml`，该项目需要在 Codex 中处于 trusted 状态。
