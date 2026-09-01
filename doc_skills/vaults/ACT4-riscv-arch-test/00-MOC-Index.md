# ACT4 riscv-arch-test — Map of Content

> **Agent memory vault.** Read this index first on any `riscv-arch-test/` task.
> Path: `obsidian-vault/ACT4-riscv-arch-test/` (Open as vault folder in Obsidian if needed).

## Core notes
- [[01-Project-Overview]]
- [[02-Architecture-Pipeline]]
- [[03-File-Index]]
- [[04-Workflows-Commands]]
- [[05-Coverpoints-Layout]]
- [[06-Host-Env-Questa]]
- [[07-Known-Facts-Do-Not-Invent]]
- [[08-Agent-Memory-Protocol]]
- [[09-RVVI-Clone]]

## Sibling workstream (different skill)
- Hypervisor xlsx / norms: `../ACT4-Hypervisor/00-MOC-Index.md` → skill `act4-hypervisor`
- **RVVI upstream clone:** `../../RVVI/` → skill `rvvi` (do not wire ACT4 until user says how)

## Cursor wiring
| Kind | Path |
|------|------|
| Skill | `.cursor/skills/act4-riscv-arch-test/SKILL.md` (+ `tracefile-rvvi.md`, **`RVVI-for-ACT4.md`**, `~/.cursor/skills/…`) |
| Testgen skill | `.cursor/skills/act4-testgen/SKILL.md` — spec/norms/reuse/generator/`make testgen`/validate/coverpoints; mirrored `riscv-arch-test/.cursor/skills/` + `~/.cursor/skills/` |
| Rule | `.cursor/rules/riscv-arch-test-act4.mdc` |
| Tree AGENTS | `riscv-arch-test/AGENTS.md` |
| Living handoff | `riscv-arch-test/AI_CONTEXT_SUMMARY.md` |
| Human flow doc | `riscv-arch-test/readme_coverpoint_flow.md` |
| SvH generation | SoT = Python emitters (`SvH.py` + families); `make testgen EXTENSIONS=SvH` → **39** `tests/priv/SvH/SvH_*-00.S`. **Phase 1:** `docs/SvH-Testgen-Plan.md` + `docs/SvH-Implementation-Readme.md` (**What/Why/How per test**). **Phase 3:** `docs/SvH_Testgen_Codebase_Walkthrough.md` (T01–T39 mapping rules). Gate **2026-08-17:** RV32 **99.66%** / RV64 **99.71%** (VSBE only). |
| SvH status (human) | Repo-root `SvH Sail Testing Status.xlsx` — **Start here** / **Every test** / **Words we use** (keep this format; not P0 columns). **2026-08-11** sync: **76** `.S`; **99.29%** / **99.39%**; Partial = VSBE only. (Inventory may lag 39-chunk rename.) |
| SvH status tracker | Repo-root `SvH Sail Testing Status latest up to date.xlsx` — sheets **Summary** / **Status Detail** / **Legend**. **2026-08-20:** synced to **39** Python testgen chunks (`SvH_<stem>-00.S`); merged old 76 twin-split rows; added Family/module/generator/twin-layout cols. Coverage **99.29%** RV32 / **99.39%** RV64; Partial = VSBE only. |
| SvH `.S` comments | Active suite public-reader commented; **2026-08-11** Sv-section restructure (all 76) — see `riscv-arch-test/SvH_REVIEW_WALKTHROUGH.md` |
| SvH review walkthrough | `riscv-arch-test/SvH_REVIEW_WALKTHROUGH.md` — section map + reviewer checklist |
| SvH covergroup comments | `SvH_coverage.svh` P3/P4 crosses + TRAP notes; empty-bin Sail cites kept |
| AI tooling proposal | `../AI_TOOLING.md` (repo root) |
| Graphify (repo map) | Repo-root `graphify-out/` — `GRAPH_REPORT.md` + `graph.json` (built **2026-08-25**, ~123k nodes; no `graph.html` — too large). Rebuild: `graphify update . --force`. Query: `graphify explain "SvH"`. |
| **Team guide (full path catalog §11)** | `docs/DV-Monthly-AI-Agent-Stack-and-Testgen-Demo-Plan.md` — vaults, skills, rules, agents, unlazy gates, sub-agents, read/write roles |
| **Shareable stack pack** | `.cursor/doc_skills/` — copy this folder to another PC (`README.md` + `install-into-cursor.sh`); includes skills, rules, vaults, Graphify report/graph, SvH docs, `norm-rules.html`, `TEAM_GUIDE.md` |

## Repo roots
- Parent: `/home/ahsan-10xe/Downloads/ACT4-20260706T103524Z-3-001`
- Arch-test: `…/riscv-arch-test`

## Hard truths (never invent opposite)
1. Coverage TB reads **`*.rvvi`**, not Sail `*.trace`.
2. Starter Questa on this host **cannot sample covergroups** (`svverification`).
3. Do **not** hand-edit `coverpoints/coverage/*` (covergroupgen glue).
4. Suite name = tests dir = `+define+SUITE_COVERAGE` — cannot select a single bin via Make.
5. Refuse cracked/pirate Questa.
6. **Agents auto-update this vault + `AI_CONTEXT_SUMMARY.md` after durable chat work — no asking** ([[08-Agent-Memory-Protocol]]).
