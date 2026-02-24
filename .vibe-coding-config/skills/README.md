# Skills

每个 skill 一个目录，目录内包含 `SKILL.md`。

## 设计原则

- Skill 只放**可复用的操作流程**，不放文档或 agent 提示词
- Agent 行为定义在 `agents.toml`，主流程在 `memory/AGENTS.md`
- 不和 agent prompt 重复

## 当前 Skills

- `feishu-init`：飞书多维表格初始化（按路径发现/创建文件夹和 Base）

## 同步

- Codex：`.agents/skills` 软链接到此目录
- Claude/Kimi：当前不生成 slash commands
