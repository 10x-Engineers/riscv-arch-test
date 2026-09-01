# Architecture

## System diagram
```
┌─────────────────┐   ┌──────────────────┐   ┌─────────────────┐
│ norm-rules.html │   │ Hypervisor(10x)  │   │  riscv-spec.md  │
│  (2920 norms)   │   │     .xlsx        │   │  (golden Ch.5)  │
└────────┬────────┘   └────────┬─────────┘   └────────┬────────┘
         │                     │                      │
         └──────────┬──────────┴──────────┬───────────┘
                    ▼                     ▼
         generate_hypervisor_norm_gaps.py
                    │
                    ▼
    hypervisor-norm-rules-missing-from-xlsx.md
                    │
         generate_consolidated_updates.py (PLACEMENT)
                    ▼
    hypervisor-xlsx-consolidated-updates.md
                    │
         generate_highlighted_xlsx.py
                    ▼
    Hypervisor (10x) - Gap Highlighted.xlsx
                    │
         fill_norm_rules_xlsx.py (CP_NORMS + NORM_ALIASES)
                    ▼
    norm-rules-fill-verification.md
```

## Modules

| Script | Role |
|--------|------|
| `generate_hypervisor_norm_gaps.py` | Parse norms + xlsx; `GOLDEN` curated mappings; gap report |
| `generate_consolidated_updates.py` | `PLACEMENT` dict → section-wise update list |
| `generate_highlighted_xlsx.py` | Copy xlsx, yellow/green highlights, `_Legend` |
| `fill_norm_rules_xlsx.py` | Fill norm columns; canonicalize legacy IDs |
| `generate_hypervisor_study_guide.py` | PDF/HTML study guide from spec |

## Data flow rules
- **PLACEMENT** is authoritative for gap highlights (not fuzzy match)
- **GOLDEN** maps norm → spec quote + nearest test + gap reason
- **CP_NORMS** maps coverpoint → norm IDs for fill script
- Exports: `hypervisor-10x-test-plan.{md,json}` for agent memory

## Privilege model (verification)
```
M → HS → VS → U/VU
     ↑ guest OS thinks it's S-mode when V=1
```
See `ACT4/diagram.md` for teaching notes.

## Related
- [[06-Domain-RISC-V-Hypervisor]] · [[05-Scripts-Commands]]
