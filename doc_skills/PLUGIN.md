# ACT4 doc_skills — plug-in for anyone

Portable agent stack: skills, rules, vaults, Graphify, SvH docs, offline `norm-rules.html`.

**Works with:** Cursor, Claude Code, Codex, Copilot, Windsurf, or any chat that can read files — no vendor lock-in.

---

## Choose your setup (30 seconds)

| Situation | Do this |
|-----------|---------|
| **Just exploring** | Open this folder; read [`AGENTS.md`](AGENTS.md) or [`TEAM_GUIDE.md`](TEAM_GUIDE.md). No install. |
| **Teammate with ACT4 repo** | `./install.sh link /path/to/ACT4` then open the repo in your IDE. |
| **Cursor user (global)** | `./install.sh cursor` |
| **Cursor + ACT4 project** | `./install.sh repo /path/to/ACT4` |
| **Maintainer refreshing pack** | `./sync-from-repo.sh /path/to/ACT4` |

Verify anytime: `./install.sh verify`

---

## Copy-paste bootstrap (any agent)

Attach this folder (or point at `doc_skills/`) and paste:

```text
You are working on ACT4 RISC-V verification.

1. Read AGENTS.md (or TEAM_GUIDE.md) in the attached doc_skills pack.
2. Pick ONE workstream — do not mix hypervisor xlsx with make coverage:
   • testgen → skills/act4-testgen/SKILL.md + vaults/ACT4-riscv-arch-test/
   • Sail/coverage → skills/act4-riscv-arch-test/SKILL.md + same vault
   • xlsx/norms → skills/act4-hypervisor/SKILL.md + vaults/ACT4-Hypervisor/
3. Read vault …/07-Known-Facts-Do-Not-Invent.md before inventing commands.
4. Hard don’ts: no hand-edit tests/priv/SvH/*.S; TB reads *.rvvi not *.trace;
   canonical norm IDs from references/norm-rules.html only.
5. After durable changes, update vault + handoffs/AI_CONTEXT_SUMMARY.md in the same turn.
```

More prompts: [`prompts/bootstrap.md`](prompts/bootstrap.md)

---

## By tool

### Cursor
```bash
./install.sh repo /path/to/ACT4   # recommended: link + skills + rules + vault copy
```
Rules auto-load from `.cursor/rules/`. Skills appear in the agent skill list.

Legacy one-liner (same as `./install.sh cursor [repo]`):
```bash
./install-into-cursor.sh [/path/to/ACT4]
```

### Claude Code / CLI
1. Copy or symlink pack anywhere (e.g. `~/ACT4-doc_skills/`).
2. In `CLAUDE.md` or project instructions:
   ```markdown
   Before ACT4 work, read ~/ACT4-doc_skills/AGENTS.md and the matching skill under skills/.
   ```
3. Or run with the pack directory as context: `claude --add-dir ~/ACT4-doc_skills`

### Codex / OpenAI
Add to repo `AGENTS.md` (or Codex instructions):
```markdown
Portable ACT4 stack: .cursor/doc_skills/AGENTS.md — read before testgen or coverage work.
```

### GitHub Copilot / generic
1. Put pack at `.cursor/doc_skills/` (symlink OK): `./install.sh link .`
2. Reference `TEAM_GUIDE.md` in PR descriptions or workspace notes.
3. Human reviewers use `HOW_TO_USE.md` skill picker.

### Obsidian (human memory)
Open `vaults/ACT4-riscv-arch-test/` or `vaults/ACT4-Hypervisor/` as a vault folder (optional `.obsidian/` included).

---

## What you still need locally

This pack is **memory + playbooks**, not the full source tree:

| For | Need on disk |
|-----|----------------|
| `make testgen` / `make coverage` | Full `riscv-arch-test/` checkout |
| Hypervisor xlsx pipeline | ACT4 repo root + `pdf-env/` |
| Graphify CLI queries | `graphify` installed (`graphify explain "…"`) |
| UCDB / covergroups | Licensed Questa or VCS (not Starter FPGA) |

---

## Pack layout

| Path | Purpose |
|------|---------|
| [`AGENTS.md`](AGENTS.md) | Standard agent entry (agents.md format) |
| [`TEAM_GUIDE.md`](TEAM_GUIDE.md) | Full team guide |
| [`HOW_TO_USE.md`](HOW_TO_USE.md) | 2-minute skill picker |
| [`PATH_INDEX.md`](PATH_INDEX.md) | Path catalog |
| [`EXTERNAL_LINKS.md`](EXTERNAL_LINKS.md) | Live URLs |
| `skills/` | ACT4 + process playbooks |
| `rules/` | Standing constraints (`.mdc`) |
| `vaults/` | Agent memory (Obsidian) |
| `graphify-out/` | Repo map (~148 MB `graph.json`) |
| `docs/` | SvH Plan / Walkthrough |
| `handoffs/` | `AI_CONTEXT_SUMMARY.md`, AGENTS copies |
| `references/` | Offline norms + sheet exports |

---

## Workstreams (pick one per task)

| Job | Skill | Vault |
|-----|-------|-------|
| Generate / fix tests | `skills/act4-testgen/` | `vaults/ACT4-riscv-arch-test/` |
| Run Sail / coverage | `skills/act4-riscv-arch-test/` | same |
| xlsx / norms | `skills/act4-hypervisor/` | `vaults/ACT4-Hypervisor/` |
| Upstream RVVI | `skills/rvvi/` | `09-RVVI-Clone.md` |

---

## Maintainer

```bash
./sync-from-repo.sh /path/to/ACT4   # refresh pack from live repo
./install.sh verify                 # sanity check
```

Share: zip this folder, git submodule, or internal drive — recipients run `./install.sh link …`.

See also [`README.md`](README.md).
