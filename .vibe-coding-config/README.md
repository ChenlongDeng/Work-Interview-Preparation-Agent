# Vibe Coding 统一配置（Codex + Claude + Kimi）

一份源配置，一条脚本同步到 Codex / Claude / Kimi 运行时位置。

## 目录结构

```
.vibe-coding-config/
├── agents.toml              # Worker agents 定义（不含主 Agent）
├── agent-model-matrix.json  # Worker 在各平台的模型映射
├── mcp/
│   └── mcp.template.json    # MCP 模板（占位符，可提交 git）
├── .env.mcp.local           # 密钥（gitignore）
├── memory/
│   └── AGENTS.md            # 主 Agent 指令源
├── skills/
│   └── feishu-init/         # 飞书初始化 skill
├── agent-profiles/          # Codex profiles 源
└── scripts/
    └── sync-configs.sh      # 同步入口
```

## 同步命令

```bash
./.vibe-coding-config/scripts/sync-configs.sh mcp        # MCP 配置
./.vibe-coding-config/scripts/sync-configs.sh memory      # 主 Agent 指令 → AGENTS.md / CLAUDE.md
./.vibe-coding-config/scripts/sync-configs.sh skills      # Skills 软链接
./.vibe-coding-config/scripts/sync-configs.sh agents      # Workers → Codex + Claude + Kimi
./.vibe-coding-config/scripts/sync-configs.sh all-core    # mcp + skills + agents（推荐开发期）
./.vibe-coding-config/scripts/sync-configs.sh all         # 全部（含 memory）
./.vibe-coding-config/scripts/sync-configs.sh dry-run     # 预览
```

## 同步目标

| 命令 | 生成文件 |
|------|----------|
| `mcp` | `.mcp.json`（Claude）、`.codex/config.toml` MCP 块 |
| `memory` | `AGENTS.md`、`CLAUDE.md`（从 `memory/AGENTS.md` 复制）|
| `skills` | `.agents/skills` 软链接 |
| `agents` | `.claude/agents/*.md`、`.kimi/agents/*.md`、`.codex/config.toml` agents 块 |

## 模型映射

`agent-model-matrix.json` 控制各 worker 在不同平台使用的模型：

```json
{
  "strict": true,
  "agents": {
    "worker_collector": {
      "codex": "gpt-5.3-codex",
      "claude": "claude-sonnet-4-6",
      "kimi": "kimi-k2.5"
    }
  }
}
```

- `strict=true`：每个 worker 必须有 codex + claude 映射
- `kimi` 字段可选

## Agent 架构

- **主 Agent**：定义在 `memory/AGENTS.md`，负责编排流程
- **worker_collector**：从小红书帖子提取问答（并行）
- **worker_qa_processor**：单题标准化、去重、写回飞书（串行）

## 环境变量

飞书配置通过 `.env.mcp.local` 注入：

```bash
LARK_MCP_APP_ID=cli_xxx
LARK_MCP_APP_SECRET=xxx
FEISHU_BASE_PATH="云盘/AI/八股复习"
FEISHU_BASE_NAME="面试题知识库"
FEISHU_APP_TOKEN="xxx"
FEISHU_POSTS_TABLE_ID="tblXxx"
FEISHU_KNOWLEDGE_TABLE_ID="tblYyy"
```
