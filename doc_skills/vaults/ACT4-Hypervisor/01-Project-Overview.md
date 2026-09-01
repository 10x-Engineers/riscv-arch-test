# Project Overview

## Purpose
ACT4 RISC-V **Hypervisor Extension** conformance test planning and **normative-rule coverage** analysis for the **Hypervisor (10x)** spreadsheet.

## Goals
1. Maintain coverpoint/test plan in `Hypervisor (10x).xlsx` (31 sheets)
2. Map coverpoints → `norm:...` IDs from `norm-rules.html`
3. Find gaps vs spec (`riscv-spec.md` Ch.5 golden)
4. Produce actionable update lists + highlighted workbooks

## Stakeholders / upstream
- **10x** test plan (Google Sheet → local xlsx)
- **RISC-V ISA manual** norm-rules release (`doc.md` links)
- **ACT4** arch-test requirements (`riscv-arch-test` act4 branch)

## Not in scope (yet)
- Actual RISC-V test assembly / simulation execution
- CI/CD for arch tests
- Automated xlsx ↔ Google Sheets sync

## Status (Jul 2026)
- 261 coverpoints, all have valid norm IDs in gap workbook
- 43 missing norms identified (curated); highlighted xlsx generated
- Study guide PDF/HTML from spec Ch.5

## Related
- [[02-Architecture]] · [[04-Workflows]] · [[03-File-Index]]
