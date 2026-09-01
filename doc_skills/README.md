# ACT4 `doc_skills` — plug-in pack for anyone

One folder you can **copy, zip, submodule, or symlink** so any teammate or coding agent gets the same ACT4 stack: skills, rules, vaults, Graphify, SvH docs, offline norms.

**Plug-in guide:** [`PLUGIN.md`](PLUGIN.md) · **Agent entry:** [`AGENTS.md`](AGENTS.md) · **Team guide:** [`TEAM_GUIDE.md`](TEAM_GUIDE.md)

---

## 30-second start

```bash
# Option A — no install (any agent)
# Open this folder; read AGENTS.md; attach to chat.

# Option B — link into ACT4 repo (recommended for teams)
./install.sh link /path/to/ACT4

# Option C — Cursor IDE full setup
./install.sh repo /path/to/ACT4

# Sanity check
./install.sh verify
```

Copy-paste prompts: [`prompts/bootstrap.md`](prompts/bootstrap.md)

---

## Who it’s for

| User | How |
|------|-----|
| DV teammate | `./install.sh link …` → read `TEAM_GUIDE.md` |
| Cursor | `./install.sh repo …` (skills + rules auto-load) |
| Claude Code / Codex / Copilot | Read pack in place; add `AGENTS.md` to project instructions |
| Maintainer | `./sync-from-repo.sh /path/to/ACT4` |

**Size:** ~160 MB (mostly `graphify-out/graph.json`). No Graphify cache included.

---

## What’s inside

| Path | Contents |
|------|----------|
| [`PLUGIN.md`](PLUGIN.md) | Install per IDE / agent |
| [`AGENTS.md`](AGENTS.md) | Standard agent bootstrap |
| [`HOW_TO_USE.md`](HOW_TO_USE.md) | 2-minute skill picker |
| [`TEAM_GUIDE.md`](TEAM_GUIDE.md) | Full team guide |
| [`PATH_INDEX.md`](PATH_INDEX.md) | Path catalog |
| [`EXTERNAL_LINKS.md`](EXTERNAL_LINKS.md) | Live URLs |
| `install.sh` | Universal installer |
| `sync-from-repo.sh` | Maintainer refresh |
| `install-into-cursor.sh` | Legacy wrapper → `install.sh cursor` |
| `skills/` | ACT4 + process + unlazy playbooks |
| `rules/` | Standing constraints |
| `vaults/` | Obsidian agent memory |
| `graphify-out/` | Repo map |
| `docs/` | SvH Plan, Walkthrough, Implementation Readme |
| `handoffs/` | Living facts + AGENTS copies |
| `references/` | `norm-rules.html`, sheet exports |
| `prompts/` | Copy-paste bootstrap text |

---

## Workstreams (pick one)

| Job | Skill | Vault |
|-----|-------|-------|
| Generate / fix tests | `skills/act4-testgen/` | `vaults/ACT4-riscv-arch-test/` |
| Run Sail / coverage | `skills/act4-riscv-arch-test/` | same |
| xlsx / norms | `skills/act4-hypervisor/` | `vaults/ACT4-Hypervisor/` |
| RVVI (read-only) | `skills/rvvi/` | `09-RVVI-Clone.md` |

Do **not** mix hypervisor xlsx scripts with `make coverage` in one task.

---

## Still need a full checkout for

- `make testgen` / `make coverage` → `riscv-arch-test/` tree
- Hypervisor scripts → ACT4 repo root + `pdf-env/`
- Editing generators → `generators/testgen/.../extensions/`

This pack teaches **how**; the repo holds **code and Make**.

---

## Maintainer refresh

```bash
./sync-from-repo.sh /path/to/ACT4
./install.sh verify
```

Pack version: see [`.pack-version`](.pack-version)
