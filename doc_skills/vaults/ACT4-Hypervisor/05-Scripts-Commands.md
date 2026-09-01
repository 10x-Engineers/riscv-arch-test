# Scripts & Commands

## Python (use pdf-env)
```bash
VENV=pdf-env/bin/python3
$VENV generate_hypervisor_norm_gaps.py
$VENV generate_consolidated_updates.py
$VENV generate_highlighted_xlsx.py
$VENV fill_norm_rules_xlsx.py
$VENV generate_hypervisor_study_guide.py
```

## Quick checks
```bash
# Count coverpoints missing norms
$VENV -c "
import openpyxl, re
from fill_norm_rules_xlsx import load_valid_norms, find_header, is_coverpoint
valid=load_valid_norms(); wb=openpyxl.load_workbook('Hypervisor (10x) - Gap Highlighted.xlsx', data_only=True)
miss=0
for sn in wb.sheetnames:
    if sn.startswith('_'): continue
    ws=wb[sn]; hr,cols=find_header(ws)
    if not hr: continue
    cp_col=cols.get('coverpoint',1); ncol=cols.get('normative rule')
    for r in range(hr+1,ws.max_row+1):
        cp=ws.cell(r,cp_col).value
        if cp and is_coverpoint(str(cp).strip()) and not (ws.cell(r,ncol).value or '').strip():
            miss+=1
print('missing', miss)
"

# Grep norm in catalog
rg 'norm:H_pmp' norm-rules.html
```

## Key functions
| Script | Functions |
|--------|-----------|
| `generate_hypervisor_norm_gaps.py` | `parse_norm_rules`, `parse_xlsx`, `covered`, `GOLDEN` |
| `generate_consolidated_updates.py` | `PLACEMENT`, `build_rows` |
| `generate_highlighted_xlsx.py` | `build_update_maps_from_placement`, `apply_sheet_updates` |
| `fill_norm_rules_xlsx.py` | `CP_NORMS`, `NORM_ALIASES`, `normalize_norm_text` |

## No formal test suite
Verification = script exit codes + `norm-rules-fill-verification.md`

## Related
- [[04-Workflows]] · [[03-File-Index]]
