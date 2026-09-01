# Proposal: AI efficiency stack (named tools)

**Ask:** Adopt the tools below as the default way we use AI on code projects — memory, planning, repo map, and self-explaining code.

---

## Stack (what → why → impact)

| # | Tool | Open source / home | Why | Impact |
|---|------|--------------------|-----|--------|
| 1 | **Obsidian** | [obsidian.md](https://obsidian.md/) | Human-readable vault of facts, MOCs, blockers, handoffs | Knowledge survives chats; onboarding and agent context stay stable |
| 2 | **Agent Skills** (`SKILL.md`) | [agentskills/agentskills](https://github.com/agentskills/agentskills) · [agentskills.io](https://agentskills.io) · examples [anthropics/skills](https://github.com/anthropics/skills) | Open standard playbooks agents load on demand | Repeatable workflows; portable across Cursor / Copilot / other agents |
| 3 | **Superpowers** | [obra/superpowers](https://github.com/obra/superpowers) | Skills pack: brainstorm → plan → TDD → debug → review → worktrees | Complex work stays structured; built-in review discipline |
| 4 | **AGENTS.md** | [agents.md](https://agents.md) | Repo-root instructions for any coding agent | One entry file; agents don’t guess project rules |
| 5 | **Cursor Rules** (`.cursor/rules/*.mdc`) | Cursor native | Always-on constraints | Hard don’ts enforced every session |
| 6 | **Graphify** | [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify) · [graphify.net](https://graphify.net/) | Builds a **queryable knowledge graph** of the whole repo (`graph.html`, `GRAPH_REPORT.md`, `graph.json`) | Fast “how does *project_name* fit together?” before coding; less blind grep |
| 7 | **AI code explainer / auto-comment** | [mwahaj36/devsplain](https://github.com/mwahaj36/devsplain) | Adds JSDoc/inline comments without rewriting logic; CI/hook friendly | New code stays self-explanatory by default; reviews read faster |
| 8 | **Obsidian ↔ Agent memory (MCP)** | [jodfie/Obsidian-Memory](https://github.com/jodfie/Obsidian-Memory) · [sauravkalia/agentvault](https://github.com/sauravkalia/agentvault) · [lbochmann/obsidian-vault-mcp](https://github.com/lbochmann/obsidian-vault-mcp) | Lets the agent **read/write/search** the vault over MCP | Decisions and “what we learned” land in Obsidian automatically |

---

## How we use them together

```text
Graphify          → map the repo (what exists, what connects)
Obsidian + MCP    → remember durable facts across sessions
AGENTS.md + Rules → hard constraints
Skills + Superpowers → how to plan / implement / review
devsplain (or Cursor rule: comment on write) → code explains itself
Cursor agent      → does the work with the above loaded
```

**Review loop:** Graphify/report for scope → Superpowers plan → implement with comments → Skills/Rules check → vault update.

---

## Expected efficiency gains

| Area | Gain |
|------|------|
| **Orientation** | Graphify = whole-project picture in minutes, not days of browsing |
| **Continuity** | Obsidian + MCP = no re-teaching the agent every chat |
| **Execution** | Superpowers + Skills = plan → verify → review, not spaghetti edits |
| **Readability** | Auto-comment / self-explain rule = less “what does this do?” in review |
| **Governance** | AGENTS.md + Rules = consistent behavior across people and agents |

---

## Adopt now (minimum)

1. Obsidian vault open for the project  
2. `AGENTS.md` + Cursor Rules + domain Skills  
3. Superpowers installed for the agent  
4. Graphify run once per major project (`graphify .` → read `GRAPH_REPORT.md`)  
5. Policy: **self-explanatory comments on every agent write** (Cursor rule and/or `devsplain`)

---

## One-line ask

**Approve this named stack so AI work is mapped (Graphify), remembered (Obsidian), guided (Skills/Superpowers), and readable (auto-explain comments) — not ad-hoc chat.**
