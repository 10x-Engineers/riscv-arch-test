# File Index

## Authoritative inputs
| File | Role |
|------|------|
| `Hypervisor (10x).xlsx` | Master test plan (31 sheets) |
| `norm-rules.html` | Norm catalog (~2.9k IDs) |
| `riscv-spec.md` | ISA spec markdown (Ch.5 = hypervisor) |
| `riscv-spec.html` | HTML spec variant |
| `doc.md` | External URLs (Sheets, GitHub releases) |

## Generated outputs
| File | Generator |
|------|-----------|
| `hypervisor-10x-test-plan.md/json` | Manual export / prior session |
| `hypervisor-norm-rules-missing-from-xlsx.md` | `generate_hypervisor_norm_gaps.py` |
| `hypervisor-xlsx-consolidated-updates.md` | `generate_consolidated_updates.py` |
| `Hypervisor (10x) - Gap Highlighted.xlsx` | `generate_highlighted_xlsx.py` |
| `norm-rules-fill-verification.md` | `fill_norm_rules_xlsx.py` |
| `riscv-hypervisor-study-guide.html` | `generate_hypervisor_study_guide.py` |

## Config / agent memory
| Path | Purpose |
|------|---------|
| `.cursor/rules/hypervisor-10x-act4.mdc` | Always-on CSR/sheet reference |
| `.cursor/skills/act4-hypervisor/SKILL.md` | Agent skill for this project |
| `ACT4/diagram.md` | Privilege mode teaching notes |

## Environments
| Path | Packages |
|------|----------|
| `pdf-env/` | openpyxl, weasyprint, reportlab |
| `markitdown-env/` | (secondary; not primary pipeline) |

## Backups
- `Hypervisor (10x) - Gap Highlighted.backup.xlsx`

## Related
- [[05-Scripts-Commands]] · [[00-MOC-Index]]
