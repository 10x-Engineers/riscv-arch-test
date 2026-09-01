# Path index — pack + full ACT4 repo

**Legend:** **R** = read · **W** = write · Paths under **Pack** are relative to this `doc_skills/` folder.  
**Repo** paths are relative to an ACT4 checkout root (when you work in the full tree).

---

## Pack layout (self-contained)

| Pack path | R/W | Description |
|-----------|-----|-------------|
| `README.md` | **R** | Plug-in hub — start here |
| `PLUGIN.md` | **R** | Install for any IDE / agent |
| `AGENTS.md` | **R** | Standard agent entry ([agents.md](https://agents.md)) |
| `install.sh` | optional | Universal installer (`verify`, `cursor`, `link`, `repo`) |
| `sync-from-repo.sh` | maintainer | Refresh pack from live ACT4 checkout |
| `prompts/bootstrap.md` | **R** | Copy-paste prompts for any agent |
| `HOW_TO_USE.md` | **R** | 2-minute skill/vault picker |
| `TEAM_GUIDE.md` | **R+W** | Full team guide (canonical shareable copy) |
| `EXTERNAL_LINKS.md` | **R** | Live URLs for norms, sheets, tools |
| `PATH_INDEX.md` | **R** | This file |
| `install-into-cursor.sh` | optional | Legacy wrapper → `install.sh cursor` |
| `skills/<name>/SKILL.md` | **R** | Agent playbooks (any coding agent) |
| `rules/*.mdc` | **R** | Standing constraints (readable by any agent; auto-loaded in Cursor) |
| `vaults/ACT4-riscv-arch-test/` | **R+W** | Arch-test / testgen memory |
| `vaults/ACT4-Hypervisor/` | **R+W** | Hypervisor xlsx memory |
| `graphify-out/GRAPH_REPORT.md` | **R** | Human repo map |
| `graphify-out/graph.json` | **R** | Queryable graph (`graphify explain`) |
| `docs/SvH-*.md` | **R+W** | Plan, Implementation What/Why/How, Walkthrough |
| `handoffs/AI_CONTEXT_SUMMARY.md` | **R+W** | Living arch-test handoff |
| `handoffs/ROOT-AGENTS.md` | **R** | Root agent contract |
| `handoffs/riscv-arch-test-AGENTS.md` | **R** | Framework Make/testgen contract |
| `references/norm-rules.html` | **R** | Canonical norm IDs (offline) |
| `references/riscv-spec.md` | **R** | Spec text (offline) |
| `references/hypervisor-10x-test-plan.*` | **R** | Full sheet export |
| `cursor-config/` | **R** | hooks/settings snapshot |

---

## Skills (pack `skills/` ↔ repo `.cursor/skills/`)

### ACT4 domain

| Skill | Pack | Repo |
|-------|------|------|
| `act4-testgen` | `skills/act4-testgen/` | `.cursor/skills/act4-testgen/` |
| `act4-riscv-arch-test` | `skills/act4-riscv-arch-test/` | `.cursor/skills/act4-riscv-arch-test/` |
| `act4-hypervisor` | `skills/act4-hypervisor/` | `.cursor/skills/act4-hypervisor/` |
| `rvvi` | `skills/rvvi/` | `.cursor/skills/rvvi/` |
| `unlazy` | `skills/unlazy/` | `.cursor/skills/unlazy/` |

### Process (Superpowers — real copies in pack)

`brainstorming`, `writing-plans`, `executing-plans`, `test-driven-development`, `systematic-debugging`, `subagent-driven-development`, `dispatching-parallel-agents`, `verification-before-completion`, `requesting-code-review`, `receiving-code-review`, `finishing-a-development-branch`, `using-git-worktrees`, `using-superpowers`, `writing-skills`

---

## Rules (pack `rules/` ↔ repo `.cursor/rules/`)

| File | Role |
|------|------|
| `act4-project-bootstrap.mdc` | Pick one workstream; skill + vault table |
| `riscv-arch-test-act4.mdc` | Sail → `.rvvi` → coverage; auto-update vault |
| `hypervisor-10x-act4.mdc` | Hypervisor sheets, CSR lists, norms |
| `svh-code-explainer.mdc` | Plain-English SvH `.S` explanations |
| `unlazy-default.mdc` | Gates before claiming done |
| `ponytail-act4-riscv-arch-test.mdc` | Minimal-diff guidance |

---

## Vaults

| Pack | Repo |
|------|------|
| `vaults/ACT4-riscv-arch-test/` | `obsidian-vault/ACT4-riscv-arch-test/` |
| `vaults/ACT4-Hypervisor/` | `obsidian-vault/ACT4-Hypervisor/` |

Start: `00-MOC-Index.md`. Hard facts: arch-test `07-Known-Facts-Do-Not-Invent.md`.

---

## Live code (not in pack — needs full `riscv-arch-test/` tree)

| Path | Notes |
|------|-------|
| `riscv-arch-test/generators/testgen/.../SvH*.py` | Edit these — not `.S` |
| `riscv-arch-test/tests/priv/SvH/*.S` | Generated output |
| `riscv-arch-test/coverpoints/priv/SvH_coverage.svh` | Hand covergroup |
| `riscv-arch-test/coverpoints/coverage/*` | **Never hand-edit** |
| `generate_*_xlsx.py` / `fill_norm_rules_xlsx.py` | Repo-root hypervisor pipeline |

The pack teaches **how**; the ACT4 checkout holds **generators and Make**.

---

## Graphify

| Pack | Repo |
|------|------|
| `graphify-out/` | `graphify-out/` (repo root) |

Rebuild (exclude huge cache): `graphify update . --force` from repo root.  
CLI: `~/.local/bin/graphify` (install separately from [Graphify](https://graphify.net/)).

---

## Focused helpers / parallel work (optional)

Some IDEs spawn child sessions; others do the same roles in one chat. Pattern: read → implement → run. See `TEAM_GUIDE.md` §3.3.

---

## Maintainer: refresh pack

From this pack directory:

```bash
./sync-from-repo.sh /path/to/ACT4
./install.sh verify
```

Or manually from ACT4 repo root:

```bash
PACK=.cursor/doc_skills
"$PACK/sync-from-repo.sh" .
```
