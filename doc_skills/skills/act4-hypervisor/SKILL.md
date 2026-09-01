---
name: act4-hypervisor
description: ACT4 RISC-V Hypervisor (10x) test-plan tooling — xlsx coverpoints, norm-rules gap analysis, spec golden reference, highlighted workbook updates. Use for Hypervisor extension verification, norm ID mapping, test plan edits, or ACT4 coverpoint work.
---

# ACT4 Hypervisor (10x)

## Quick start
```bash
cd /home/ahsan-10xe/Downloads/ACT4-20260706T103524Z-3-001
pdf-env/bin/python3 generate_hypervisor_norm_gaps.py      # gap .md
pdf-env/bin/python3 generate_consolidated_updates.py      # merged updates .md
pdf-env/bin/python3 generate_highlighted_xlsx.py            # highlighted xlsx
pdf-env/bin/python3 fill_norm_rules_xlsx.py               # fill/verify norm IDs
```

## Golden sources (read order)
1. `Hypervisor (10x).xlsx` — authoritative test plan (31 sheets)
2. `riscv-spec.md` — spec golden (~Ch.5 hypervisor L29288+)
3. `norm-rules.html` — 2920 norm IDs (canonical `norm:...` names)
4. `hypervisor-10x-test-plan.md` / `.json` — exported coverpoints
5. `.cursor/rules/hypervisor-10x-act4.mdc` — CSR inventory, sheet summary

## Pipeline
```
norm-rules.html + xlsx + riscv-spec.md
  → generate_hypervisor_norm_gaps.py → hypervisor-norm-rules-missing-from-xlsx.md
  → generate_consolidated_updates.py (PLACEMENT dict) → hypervisor-xlsx-consolidated-updates.md
  → generate_highlighted_xlsx.py → Hypervisor (10x) - Gap Highlighted.xlsx
  → fill_norm_rules_xlsx.py → canonical norm IDs + norm-rules-fill-verification.md
```

## Key conventions
- **Norm IDs**: use `norm-rules.html` canonical IDs (`norm:hstatus_sz_acc_op`), not legacy `norm:csr:hstatus:reg`
- **Gap analysis**: scope H + Sh* chapters; use curated `GOLDEN` + `PLACEMENT`, not fuzzy `covered()` alone
- **Sheet layouts vary**: `H - US` header row 2; `SvH-US` has `Normative Rule(10x)` col 11
- **Highlight colors**: yellow=append norm, green=new row, blue=new sheet (`_Legend` tab)
- **Venv**: `pdf-env/` (openpyxl, weasyprint, reportlab)

## When editing xlsx
1. Update source `Hypervisor (10x).xlsx` OR gap workbook intentionally
2. Re-run generators in pipeline order
3. Verify with `fill_norm_rules_xlsx.py` (exit 0 = all coverpoints have valid norms)
4. Update `PLACEMENT` in `generate_consolidated_updates.py` for new gaps

## Domain essentials
- Priv modes: M, HS, VS, U, VU | `V=1` = guest context
- Two-stage VM: VS-stage (vsatp) + G-stage (hgatp)
- Delegation: medeleg/hedeleg (exceptions), mideleg/hideleg (interrupts)
- Trap logging: M/HS/VS each have distinct CSR sets (see cursor rule)

## External links
See `doc.md` — Google Sheets test plan, norm-rules release, ACT4 req.adoc

## Full reference
Obsidian: `obsidian-vault/ACT4-Hypervisor/00-MOC-Index.md`
