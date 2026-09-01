# ACT4 — Agent Instructions (root)

**Repo:** `/home/ahsan-10xe/Downloads/ACT4-20260706T103524Z-3-001`

## Superpowers + unlazy (default methodology)

This workspace loads [obra/superpowers](https://github.com/obra/superpowers) by default via `.cursor/hooks.json` + skills under `.cursor/skills/`. Use Superpowers workflows (brainstorm → plan → TDD/subagents → review) for general software work.

**unlazy (default completion discipline):** [Leonxlnx/unlazy](https://github.com/Leonxlnx/unlazy) is installed at `.cursor/skills/unlazy/` (also mirrored under `~/.cursor/skills/unlazy/`). For substantial / multi-part / audit / build work — or when the user says `/unlazy`, `tree N`, `gates`, or “do not stop until it is done” — read that skill first, write a `GATES.md` (or scoped `.unlazy/<scope>/` pipeline) before implementing, and prove outcomes with `node .cursor/skills/unlazy/scripts/gate-check.mjs`. Skip unlazy only for trivial edits or short factual replies. Requires Node 16+ (`mise` tool `node@22` in this workspace).

**Precedence:** this `AGENTS.md`, ACT4 rules, and `act4-*` skills override Superpowers and unlazy whenever they conflict (paths, Make/coverage/xlsx pipelines, vault updates, license constraints). unlazy gates must still use real ACT4 commands from the matching workstream skill.

Workstreams live here. Pick the skill that matches the task; do not invent paths/commands from memory.

**Shareable stack for teammates / any agent:** copy `.cursor/doc_skills/` or run `./.cursor/doc_skills/install.sh link .` — see `PLUGIN.md` + pack `AGENTS.md`. Optional Cursor wiring: `install.sh repo /path/to/ACT4`.

| Workstream | Skill | Vault (agent memory) | When |
|------------|-------|----------------------|------|
| Hypervisor (10x) test-plan / norm gaps / xlsx | `act4-hypervisor` | `obsidian-vault/ACT4-Hypervisor/00-MOC-Index.md` | coverpoints in spreadsheets, `norm-rules.html`, gap pipeline |
| Test generation (SvH + other suites) | `act4-testgen` | `obsidian-vault/ACT4-riscv-arch-test/00-MOC-Index.md` | spec → norms → generator Python → `make testgen` → validate → coverpoints |
| riscv-arch-test run + coverage | `act4-riscv-arch-test` | `obsidian-vault/ACT4-riscv-arch-test/00-MOC-Index.md` | Sail ELFs, Tracefile/`.rvvi`, RVVI TB, Questa coverage, Sm/H tests |
| Upstream RVVI standard (clone) | `rvvi` | vault `09-RVVI-Clone.md` | Understanding TRACE/TEXT/API; **do not wire ACT4 until user says how** |

## Never hallucinate / burn tokens
1. Read the matching **skill + vault MOC** before acting.
2. **Auto-update memory without asking:** after any turn that changes durable facts (commands, env, blockers, suites, license, proven artifacts), update that workstream’s vault + handoff (`AI_CONTEXT_SUMMARY.md` for arch-test; Known-Issues for hypervisor) in the **same turn**. Do not ask permission; do not wait for “please update the vault.”
3. For coverage: TB reads `*.rvvi` (short Tracefile), **not** raw Sail `*.trace`. Details in skill `tracefile-rvvi.md`.
4. Cite/check real files under `riscv-arch-test/framework/src/act/` when unsure.
5. Coverage needs a **verification-licensed** `vsim` (or VCS). This host’s Starter Questa cannot sample covergroups. Do not assist with cracked/pirate Questa.
6. Default Make excludes `Sm` (`EXCLUDE_EXTENSIONS`); clear it when running Sm.
7. Do not hand-edit `coverpoints/coverage/*` (covergroupgen glue).

---

## A) Hypervisor (10x) xlsx / norms

1. Read `PROJECT.md` if context is unclear
2. Use skill `act4-hypervisor` (`.cursor/skills/` or `~/.cursor/skills/act4-hypervisor/`)
3. Golden sources: `Hypervisor (10x).xlsx` → `riscv-spec.md` (Ch.5) → `norm-rules.html`
4. Exports: `hypervisor-10x-test-plan.md` / `.json`

### Regenerate pipeline (order matters)
```bash
pdf-env/bin/python3 generate_hypervisor_norm_gaps.py
pdf-env/bin/python3 generate_consolidated_updates.py
pdf-env/bin/python3 generate_highlighted_xlsx.py
pdf-env/bin/python3 fill_norm_rules_xlsx.py   # exit 0 = verified
```

### Edit conventions
- Norm IDs: canonical from `norm-rules.html` (`norm:hstatus_sz_acc_op`), not `norm:csr:*:reg`
- Gap mappings: update `GOLDEN` + `PLACEMENT` + `CP_NORMS` together
- Sheet quirks: `H - US` header row 2; `SvH-US` has `Normative Rule(10x)` col 11
- Venv: `pdf-env/bin/python3`

### Key scripts
| Script | Output |
|--------|--------|
| `generate_hypervisor_norm_gaps.py` | `hypervisor-norm-rules-missing-from-xlsx.md` |
| `generate_consolidated_updates.py` | `hypervisor-xlsx-consolidated-updates.md` |
| `generate_highlighted_xlsx.py` | `Hypervisor (10x) - Gap Highlighted.xlsx` |
| `fill_norm_rules_xlsx.py` | fills norms + `norm-rules-fill-verification.md` |

### Knowledge base
- Obsidian: `obsidian-vault/ACT4-Hypervisor/00-MOC-Index.md`
- External URLs: `doc.md`

---

## B) riscv-arch-test (run tests + coverage)

**Tree:** `riscv-arch-test/` — `AGENTS.md` + `AI_CONTEXT_SUMMARY.md` + `readme_coverpoint_flow.md`.  
**Vault:** `obsidian-vault/ACT4-riscv-arch-test/` · **Rule:** `.cursor/rules/riscv-arch-test-act4.mdc`

1. Use skill `act4-riscv-arch-test` (project `.cursor/skills/`, `riscv-arch-test/.cursor/skills/`, or `~/.cursor/skills/`)
2. Read vault `00-MOC-Index.md` / `07-Known-Facts-Do-Not-Invent.md` so host facts stay grounded
3. Always: `source riscv-arch-test/.localenv/bin/activate` (+ `source env_questa.sh` for coverage)
4. Pipeline: Sail `--trace` → `*.trace` → `sail_to_rvvi.py` → `*.rvvi` → `testbench.sv` (+traceFileList) → RVVI → covergroups → UCDB/reports
5. Primary config: `config/sail/sail-rv32-max/`
6. Starter Questa on this host compiles TB but **cannot** sample covergroups; need paid Questa/VCS for UCDB

```bash
cd riscv-arch-test && source .localenv/bin/activate && source env_questa.sh
make coverage COVERAGE_CONFIG_FILES=config/sail/sail-rv32-max/test_config.yaml \
  EXTENSIONS=Hact4 EXCLUDE_EXTENSIONS=Sm COVERAGE_SIMULATOR=questa JOBS=1 FAST=True
```
