# ACT4 agent instructions (portable pack)

This file lives in the **doc_skills** plug-in. Paths below are **relative to this pack folder** unless you also have a full ACT4 checkout open.

**Human start:** [`TEAM_GUIDE.md`](TEAM_GUIDE.md) · **Install:** [`PLUGIN.md`](PLUGIN.md) · **Quick pick:** [`HOW_TO_USE.md`](HOW_TO_USE.md)

## Bootstrap (every session)

1. Read this file + the matching **skill** under `skills/` + vault **MOC**.
2. Read `vaults/ACT4-riscv-arch-test/07-Known-Facts-Do-Not-Invent.md` (arch-test) or `vaults/ACT4-Hypervisor/00-MOC-Index.md` (hypervisor).
3. Pick **one** workstream — do not mix xlsx scripts with `make coverage`.
4. After durable work, update the vault + `handoffs/AI_CONTEXT_SUMMARY.md` in the same turn (no asking).

## Workstreams

| Workstream | Skill | Vault | When |
|------------|-------|-------|------|
| Test generation (SvH, etc.) | `skills/act4-testgen/SKILL.md` | `vaults/ACT4-riscv-arch-test/00-MOC-Index.md` | Python → `make testgen` |
| Sail / RVVI / coverage | `skills/act4-riscv-arch-test/SKILL.md` | same vault | ELF, `.rvvi`, Questa UCDB |
| Hypervisor xlsx / norms | `skills/act4-hypervisor/SKILL.md` | `vaults/ACT4-Hypervisor/00-MOC-Index.md` | gap scripts, norm-rules |
| Upstream RVVI | `skills/rvvi/SKILL.md` | vault `09-RVVI-Clone.md` | read-only until wired |

Full repo contracts (when checkout present): `handoffs/ROOT-AGENTS.md`, `handoffs/riscv-arch-test-AGENTS.md`.

## Methodology

- **Process:** skills under `skills/` (brainstorm → plan → implement → verify). See `skills/using-superpowers/SKILL.md`.
- **Completion discipline:** `skills/unlazy/SKILL.md` — write `GATES.md` + run `node skills/unlazy/scripts/gate-check.mjs` for substantial work.
- **Precedence:** ACT4 `act4-*` skills and `handoffs/*AGENTS*` win over generic process skills on paths, Make commands, vault updates, license rules.

## Never invent

- TB reads **`*.rvvi`**, not Sail `*.trace`.
- Do not hand-edit `tests/priv/SvH/*.S` or `coverpoints/coverage/*`.
- Norm IDs: canonical from `references/norm-rules.html` (e.g. `norm:hstatus_sz_acc_op`), not `norm:csr:*:reg`.
- Do not claim covergroup UCDB on Starter Questa; refuse cracked/pirate licenses.
- SvH today: **39** generated files via explicit `_emit(...)` in `SvH.py` (7 Python modules); regenerate with `make testgen EXTENSIONS=SvH`.

## If you have a full ACT4 checkout

| Pack path | Live repo path |
|-----------|----------------|
| `vaults/ACT4-riscv-arch-test/` | `obsidian-vault/ACT4-riscv-arch-test/` |
| `skills/act4-*` | `.cursor/skills/act4-*` |
| `rules/` | `.cursor/rules/` |
| Generators | `riscv-arch-test/generators/testgen/.../extensions/SvH*.py` |

Install pack into repo: `./install.sh repo /path/to/ACT4`

## External links

[`EXTERNAL_LINKS.md`](EXTERNAL_LINKS.md) — norm-rules download, spreadsheets, tooling.
