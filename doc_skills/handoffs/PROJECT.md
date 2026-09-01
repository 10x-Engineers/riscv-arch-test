# ACT4 Hypervisor (10x)

**Path:** `/home/ahsan-10xe/Downloads/ACT4-20260706T103524Z-3-001`

## Auto-integrated (no manual setup)
| Component | Location | Loads when |
|-----------|----------|------------|
| Cursor rules (×2) | `.cursor/rules/*.mdc` | Every chat in this workspace |
| Cursor skill (project) | `.cursor/skills/act4-hypervisor/` | Hypervisor-related tasks |
| Cursor skill (global) | `~/.cursor/skills/act4-hypervisor/` | Any workspace |
| Agent instructions | `AGENTS.md` | Cursor agent reads on task start |
| Obsidian vault | `obsidian-vault/ACT4-Hypervisor/` | Open in Obsidian (symlink below) |
| Obsidian symlink | `~/Documents/Obsidian/ACT4-Hypervisor` | Points to vault above |

## Regenerate
```bash
pdf-env/bin/python3 generate_hypervisor_norm_gaps.py
pdf-env/bin/python3 generate_consolidated_updates.py
pdf-env/bin/python3 generate_highlighted_xlsx.py
pdf-env/bin/python3 fill_norm_rules_xlsx.py
```

## Docs
- `AGENTS.md` — agent workflow
- `doc.md` — external URLs
- `obsidian-vault/ACT4-Hypervisor/00-MOC-Index.md` — full knowledge base
