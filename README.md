# codex-skills

用于收集与 Codex 相关的 skills、MCP 服务与 agents 的仓库。内容以可复用的技能说明、可执行脚本与提示词模板为主，便于在本地或 CI 环境中快速复用。

## 目录结构

```text
.
├── skills/     # 技能集合（每个技能包含 SKILL.md 与相关脚本/模板）
├── mcp/        # MCP 服务相关配置或说明
├── agents/     # Agent 角色或系统提示词
├── prompts/    # 通用提示词与模板
├── .specify/   # 项目规范或元信息
├── AGEMT.md    # 角色/系统提示词（中文）
└── LICENSE
```

## 已收录技能

### autonomous-skill

长时任务自动化执行技能。核心能力：
- 多会话执行（Initializer + Executor 模式）
- 任务拆解与进度追踪（`task_list.md` / `progress.md`）
- 自动续跑与会话恢复（`session.id`）
- 任务隔离（`.autonomous/<task-name>/`）

入口脚本：
- Linux/macOS：`skills/autonomous-skill/scripts/run-session.sh`
- Windows：`skills/autonomous-skill/scripts/run-session.ps1`

完整说明见：`skills/autonomous-skill/SKILL.md`

### ask-questions-if-underspecified

当需求不明确时，强制先澄清关键问题再开始实现，避免误工。强调最小问题集、明确默认假设与可快速回复的选项格式。

完整说明见：`skills/ask-questions-if-underspecified/SKILL.md`

## 使用方式

1. 进入 `skills/<skill-name>/` 查看 `SKILL.md`
2. 按技能说明执行脚本或套用模板
3. 需要扩展时，可在 `skills/` 新增技能目录并补充说明与脚本

## 适用场景

- 需要可复用的 Codex 工作流（如长时任务、需求澄清）
- 本地/团队沉淀通用能力与提示词模板
- 将 Codex 与 MCP 服务集成到项目流程中

