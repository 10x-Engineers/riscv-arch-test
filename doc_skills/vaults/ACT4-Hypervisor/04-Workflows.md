# Workflows

## Norm gap pipeline
```bash
cd /home/ahsan-10xe/Downloads/ACT4-20260706T103524Z-3-001
pdf-env/bin/python3 generate_hypervisor_norm_gaps.py
pdf-env/bin/python3 generate_consolidated_updates.py
pdf-env/bin/python3 generate_highlighted_xlsx.py
pdf-env/bin/python3 fill_norm_rules_xlsx.py   # exit 0 = verified
```

## After editing Hypervisor (10x).xlsx
1. Re-export `hypervisor-10x-test-plan.md/json` if structure changed materially
2. Re-run full pipeline above
3. Update `PLACEMENT` / `GOLDEN` / `CP_NORMS` for new coverpoints
4. Update `.cursor/rules/hypervisor-10x-act4.mdc` if CSR inventory changes

## Adding a missing norm
1. Confirm norm exists in `norm-rules.html`
2. Add to `GOLDEN` in `generate_hypervisor_norm_gaps.py` (spec quote, related CPs)
3. Add to `PLACEMENT` in `generate_consolidated_updates.py` (sheet, action, targets)
4. Add to `CP_NORMS` in `fill_norm_rules_xlsx.py` if filling norm column
5. Regenerate all outputs

## Debugging gap false positives
- Check `covered()` alias logic in `generate_hypervisor_norm_gaps.py`
- Prefer curated `PLACEMENT` over fuzzy matching
- Verify xlsx header row (H-US row 2, SvH-US dual norm columns)

## Study guide regen
```bash
pdf-env/bin/python3 generate_hypervisor_study_guide.py
```

## Agent session bootstrap
1. Read `.cursor/skills/act4-hypervisor/SKILL.md`
2. Read `hypervisor-10x-test-plan.md` for sheet context
3. Check `norm-rules-fill-verification.md` for norm fill status

## Related
- [[05-Scripts-Commands]] · [[07-Known-Issues-TODOs]]
