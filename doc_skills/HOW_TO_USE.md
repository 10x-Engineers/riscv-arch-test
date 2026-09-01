# How to use this pack (2 minutes)

Works with **any** coding agent — no IDE install required.

## 0. Plug in (pick one)
| Setup | Command |
|-------|---------|
| Read-only | Open folder → [`AGENTS.md`](AGENTS.md) |
| ACT4 repo | `./install.sh link /path/to/ACT4` |
| Cursor | `./install.sh repo /path/to/ACT4` |
| Copy-paste prompt | [`prompts/bootstrap.md`](prompts/bootstrap.md) |

Full options: [`PLUGIN.md`](PLUGIN.md)

## 1. Open the guide
Read [`TEAM_GUIDE.md`](TEAM_GUIDE.md) or [`AGENTS.md`](AGENTS.md).

## 2. Pick the job → open one skill

| I need to… | Open |
|------------|------|
| Add / fix a test suite | `skills/act4-testgen/SKILL.md` (+ `lifecycle.md`, `reuse-map.md`) |
| Run Sail / `.rvvi` / coverage | `skills/act4-riscv-arch-test/SKILL.md` |
| Map norms ↔ xlsx | `skills/act4-hypervisor/SKILL.md` |
| Prove a big task is done | `skills/unlazy/SKILL.md` |
| Lost in the repo | `graphify-out/GRAPH_REPORT.md` or `graphify explain "SvH"` |

## 3. Read memory before coding
- Arch-test / testgen: `vaults/ACT4-riscv-arch-test/07-Known-Facts-Do-Not-Invent.md` + `handoffs/AI_CONTEXT_SUMMARY.md`
- Hypervisor xlsx: `vaults/ACT4-Hypervisor/00-MOC-Index.md`

## 4. Testgen document order (never skip)
1. **Plan** — What / Why / How per test → user approves (`docs/SvH-Implementation-Readme.md` is the template)
2. **Python** — then `make testgen`
3. **Walkthrough** — after generators exist (`docs/SvH_Testgen_Codebase_Walkthrough.md`)

## 5. Hard don’ts
- Do not hand-edit `tests/priv/SvH/*.S` or `coverpoints/coverage/*`
- Do not invent `norm:csr:*:reg` IDs — use `references/norm-rules.html`
- Do not claim covergroup UCDB on Starter Questa

## 6. External links
See [`EXTERNAL_LINKS.md`](EXTERNAL_LINKS.md).
