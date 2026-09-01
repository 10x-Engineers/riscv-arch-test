# Known Issues & TODOs

## Known issues
- [ ] **No git repo** — project is a download folder; consider initializing git
- [ ] **No Obsidian vault linked** — notes at `obsidian-vault/ACT4-Hypervisor/`; add to your vault manually
- [ ] **Google Sheets not synced** — local xlsx may drift from `doc.md` Sheet URL
- [ ] **Mixed prose in norm cells** — some Sh* rows keep spec prose + norm IDs (intentional)
- [ ] **Placeholder sheets** — ZkrH, SsstateenH, SscrindH, etc. need baseline tests first
- [ ] **markitdown-env** — present but not part of main pipeline; clarify or remove

## Open questions
- [ ] Who owns xlsx updates — gap workbook vs master `Hypervisor (10x).xlsx`?
- [ ] Export script for `hypervisor-10x-test-plan.json` — was manual; automate?
- [ ] ACT4 test implementation repo location / linkage to coverpoints?
- [ ] Certification Implementation Tracking sheet (`doc.md` 2nd URL) — integrate?
- [ ] RV32 vs RV64 coverage completeness across all sheets?

## Future work
- [ ] Automate xlsx → md/json export on change
- [ ] Merge gap fixes back into master xlsx systematically
- [ ] Add pytest for `parse_xlsx`, `normalize_norm_text`, `PLACEMENT` integrity
- [ ] Track norm-rules.html version / release tag in metadata
- [ ] Implement placeholder sheet coverpoints (SsqosidH, Shlcofideleg, etc.)

## Verification baseline
Last verified: `fill_norm_rules_xlsx.py` exit 0 — 261/261 coverpoints, 0 invalid norm IDs

## Agent auto-update (no asking)
After durable hypervisor/xlsx/norm work in chat, agents silently refresh this note + relevant vault pages (`04-Workflows`, `05-Scripts-Commands`, etc.) and skill `act4-hypervisor` if commands/paths changed. Do not ask the user for permission.

## Related
- [[04-Workflows]] · [[00-MOC-Index]]
