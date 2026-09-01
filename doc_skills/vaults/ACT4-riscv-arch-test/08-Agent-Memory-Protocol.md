# Agent memory protocol

How AI agents must use this vault so they do not hallucinate or drift.

## Standing order — auto-update (no asking)
**Do not ask the user** whether to update memory. After any chat turn that changes durable project state, **silently update** the stores below in the same session before ending the turn.

Triggers (any of these → write memory):
- New/changed commands, configs, paths, env scripts
- Tool/version/license findings (Sail, GCC, Questa, VCS)
- Test added/moved/parked/unparked; suite renamed
- Pipeline facts (Tracefile keys, converter gaps, coverpoint glue)
- Blockers resolved or newly discovered
- Proven artifact paths (what worked / what failed and why)
- User corrections that reverse a prior “fact”

Non-triggers (skip): pure Q&A with no new durable fact; failed speculative tries that teach nothing reusable.

## On every `riscv-arch-test/` task
1. Read [[00-MOC-Index]] (or this note + [[07-Known-Facts-Do-Not-Invent]]).
2. Load skill **`act4-riscv-arch-test`** (project + `~/.cursor/skills`).
3. Skim `riscv-arch-test/AI_CONTEXT_SUMMARY.md` for session-fresh facts.
4. Prefer **file reads** over memory for converter keys, Make knobs, license status.
5. If Hypervisor xlsx/norms: switch to vault `ACT4-Hypervisor` + skill `act4-hypervisor` — do not blend pipelines.
6. **Before finishing the turn:** if anything durable changed, run the update checklist below (no prompt).

## Update checklist (same turn)
| Store | What to update |
|-------|----------------|
| `AI_CONTEXT_SUMMARY.md` | **Always** bump date + facts/blockers/commands when anything durable changed |
| This vault `07-Known-Facts-Do-Not-Invent.md` | Bullet facts / open items / wrong directions |
| This vault `06-Host-Env-Questa.md` | Tool paths/versions/license |
| This vault `03` / `04` / `05` | Paths, workflows, coverpoint layout if those shifted |
| Skill `SKILL.md` or `env-and-commands.md` | Command/path contract changes — then **mirror** to `riscv-arch-test/.cursor/skills/` and `~/.cursor/skills/` |
| Cursor rule `riscv-arch-test-act4.mdc` | Only if bootstrap hard truths changed |
| `readme_coverpoint_flow.md` | **Append** user-facing clarifications (never strip history) |

Keep updates short and factual. Do not narrate “I updated the vault” unless the user asks; just do it.

## What not to trust from chat alone
- “Coverage works now” without UCDB/report paths
- Suite ↔ covergroup mapping without checking `coverpoints/priv/` and defines
- That Starter Questa gained verification features (verify `vsim` error / license)
- That parked tests were unparked

## Sources of truth ranking
1. Source code under `framework/`, `coverpoints/priv/`, configs
2. This vault + `AI_CONTEXT_SUMMARY.md` (must stay current via auto-update)
3. Skill docs
4. Chat history (lowest — may be stale; memory files beat transcript)

## Related
- [[00-MOC-Index]] · Cursor rule `riscv-arch-test-act4.mdc`
