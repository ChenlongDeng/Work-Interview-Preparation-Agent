# Skills 源目录

每个技能一个目录，目录内至少包含 `SKILL.md`。

示例：
- `skills/reviewer/SKILL.md`
- `skills/research/SKILL.md`

同步后：
- Codex 使用 `.agents/skills` 软链接直接读取。
- Claude 生成同名命令文件到 `.claude/commands/<skill_id>.md`。
