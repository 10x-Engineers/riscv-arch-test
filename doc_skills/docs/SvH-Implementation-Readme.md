# SvH tests — implementation plan (What / Why / How)

**For:**  reviewer / anyone approving testgen work
**As-of:** 2026-08-25
**Rule:** Every planned test **must** have **What / Why / How** before Python is written. Same shape for any future suite Plan doc.

| Field | Meaning |
|-------|---------|
| **What** | What this test is (one sentence) |
| **Why** | Why we run it (coverage / ISA rule) |
| **How** | Plan steps the hart / generator will do (plain English) |

**Related docs:**
- Catalog + coverpoints: `docs/SvH-Testgen-Plan.md`
- Code-level (after generators): `docs/SvH_Testgen_Codebase_Walkthrough.md`
- Default for agents: skill `act4-testgen` → Plan phase requires What/Why/How per stem

---

## Approach (short)

- **Python writes assembly** (`make testgen EXTENSIONS=SvH`) — do not hand-edit `.S`.
- **39** scenarios → five family files + `SvHCommon.py` + `SvH.py` registry.
- Sv32 + Sv39 live **in the same file** (twins).
- Success: regenerate → Sail pass → coverage ~**99.7%** (VSBE bin = Sail limit).

| File | Count | Plain words |
|------|-------|-------------|
| `SvH_twostage.py` | 7 | Guest + hypervisor paging on/off |
| `SvH_csr.py` | 3 | Hypervisor/guest satp field walks |
| `SvH_perm.py` | 13 | What guest/hypervisor may R/W/X |
| `SvH_fault.py` | 3 | Bad PTEs must fault |
| `SvH_misc.py` | 13 | Fences, MPRV, TVM, A/D, PTE attrs, VSBE |

---

## Default plan template (use for every new test / suite)

Copy this block once per stem in any `<Suite>-Testgen-Plan.md` or Implementation Readme:

```text
### N. <stem> → <Suite>_<stem>-00.S
- Module: <family>.py · Coverpoint(s): <cp_*>
- What: …
- Why: …
- How: …
```

**How** should list ordered steps (setup → mode → stimulus → check → SIGUPD), not Python line numbers.

---

## Twostage (`SvH_twostage.py`) — 7 tests

### 1. `g_walk_vs_pt_VSmode` → `SvH_g_walk_vs_pt_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks G-stage translation of VS page-table pages in VS-mode (first allow, then deny).
- **Why:** To verify that the processor walks VS page tables through G-stage and faults when that G-stage mapping is invalid, for coverage.
- **How:** It sets up two-stage paging, does a VS-mode load that succeeds, then makes the G-stage PTE of the VS page table invalid, retries the load, checks the results through the signature mechanism, and records coverage.

### 2. `hgatp_bare_trans_VSmode` → `SvH_hgatp_bare_trans_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks VS-stage load/store when `hgatp` is Bare (G-stage off).
- **Why:** To verify that VS-mode paging works on its own when `hgatp` is zero, and that `hgatp` stays zero, for coverage.
- **How:** It maps VS pages to physical addresses, clears `hgatp`, enters VS-mode, stores then loads, reads `hgatp` back, checks the results through the signature mechanism, and records coverage.

### 3. `stage_both_bare_VSmode` → `SvH_stage_both_bare_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks identity addressing in VS-mode when both `vsatp` and `hgatp` are Bare.
- **Why:** To verify that VS-mode can load and store physical addresses with paging off at both stages, for coverage.
- **How:** It clears both `vsatp` and `hgatp`, enters VS-mode, stores then loads at the physical test region, checks the results through the signature mechanism, and records coverage.

### 4. `two_stage_ifetch_VSmode` → `SvH_two_stage_ifetch_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks instruction fetch through two-stage translation in VS-mode.
- **Why:** To verify that VS-mode can fetch and execute instructions after both VS-stage and G-stage walks, for coverage.
- **How:** It maps the code page through both stages, enters VS-mode, runs a simple instruction, returns to M-mode, checks the result through the signature mechanism, and records coverage.

### 5. `two_stage_mxr_VSmode` → `SvH_two_stage_mxr_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks execute-only page loads in VS-mode with MXR off, then on.
- **Why:** To verify that VS-mode cannot read execute-only pages when MXR=0, and can when MXR=1, for coverage.
- **How:** It maps data as execute-only through both stages, tries a VS-mode load with MXR=0 (fault), sets MXR=1, retries the load, checks the results through the signature mechanism, and records coverage.

### 6. `two_stage_mxr_VUmode` → `SvH_two_stage_mxr_VUmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks execute-only page loads in VU-mode with MXR off, then on.
- **Why:** To verify that VU-mode cannot read execute-only U-pages when MXR=0, and can when MXR=1, for coverage.
- **How:** It maps U=1 execute-only pages through both stages, tries a VU-mode load with MXR=0 (fault), sets MXR=1, retries the load, checks the results through the signature mechanism, and records coverage.

### 7. `two_stage_rw_VSmode` → `SvH_two_stage_rw_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks two-stage load and store in VS-mode.
- **Why:** To verify that a VS-mode store and load walk both VS-stage and G-stage and land in real physical memory, for coverage.
- **How:** It sets up two-stage paging, enters VS-mode, stores then loads a known value, reads the physical page back from M-mode, checks the results through the signature mechanism, and records coverage.

---

## CSR (`SvH_csr.py`) — 3 tests

### 8. `csr_hgatp_fields_HSmode` → `SvH_csr_hgatp_fields_HSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks the `hgatp` MODE, VMID, and PPN fields in HS-mode, including MODE values `0–15`.
- **Why:** To verify that the processor correctly legalizes `hgatp` encodings and reports the expected results for coverage.
- **How:** It enters HS-mode, writes MODE values `0–15`, VMID all-ones, and walking-1 PPN bits into `hgatp`, reads them back, checks the results through the signature mechanism, and records coverage.

### 9. `csr_satp_mode_VSmode` → `SvH_csr_satp_mode_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks the `satp.MODE` field in VS-mode, including `satp`/`vsatp` behavior and MODE values `0–15`.
- **Why:** To verify that the processor correctly handles all possible `satp.MODE` encodings and reports the expected results for coverage.
- **How:** It sets up VS-mode with Sv39, reads `satp`/`vsatp`, writes MODE values `0–15` into `satp`, reads them back, checks the results through the signature mechanism, and records coverage.

### 10. `csr_vsatp_fields_HSmode` → `SvH_csr_vsatp_fields_HSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks the `vsatp` MODE, ASID, and PPN fields in HS-mode, including MODE values `0–15`.
- **Why:** To verify that the processor correctly legalizes `vsatp` encodings and reports the expected results for coverage.
- **How:** It enters HS-mode, writes MODE values `0–15`, ASID all-ones, and walking-1 PPN bits into `vsatp`, reads them back, checks the results through the signature mechanism, and records coverage.

---

## Perm (`SvH_perm.py`) — 13 tests

### 11. `g_perm_VSmode` → `SvH_g_perm_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks G-stage page permissions from VS-mode, plus HS-mode HLV/HSV.
- **Why:** To verify that G-stage U/XWR/V bits allow or deny VS-mode accesses, and that HS hypervisor loads/stores follow G-stage rules, for coverage.
- **How:** It turns on G-stage only, rewrites the G-stage PTE for each case, enters VS or HS, does load/store or HLV/HSV, checks the results through the signature mechanism, and records coverage.

### 12. `g_perm_VUmode` → `SvH_g_perm_VUmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks G-stage page permissions from VU-mode.
- **Why:** To verify that VU-mode accesses follow G-stage U/XWR/V bits (U=1 required), for coverage.
- **How:** It turns on G-stage only, rewrites the G-stage PTE for each case, enters VU-mode, does load/store, checks the results through the signature mechanism, and records coverage.

### 13. `g_u_bit_HSmode` → `SvH_g_u_bit_HSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks the G-stage U bit for HS-mode HLV and HSV.
- **Why:** To verify that hypervisor load/store of a guest GPA succeeds when U=1 and faults when U=0, for coverage.
- **How:** It turns on G-stage, sets the G-stage U bit, enters HS-mode, does HLV/HSV, repeats with U=0, checks the results through the signature mechanism, and records coverage.

### 14. `sum_Upages_VSmode` → `SvH_sum_Upages_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks VS-mode access to U-mode pages with SUM off, then on.
- **Why:** To verify that `vsstatus.SUM=0` blocks VS access to U pages and `SUM=1` allows it, for coverage.
- **How:** It maps a U=1 page, enters VS-mode with SUM=0 (load/store fault), sets SUM=1, retries, checks the results through the signature mechanism, and records coverage.

### 15. `vs_perm_VSmode` → `SvH_vs_perm_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks VS-stage page permissions from VS-mode.
- **Why:** To verify that VS-mode load, store, and fetch follow VS-stage XWR/U/SUM bits, for coverage.
- **How:** It maps VS-stage pages, rewrites the VS PTE for each case, enters VS-mode, does the access, checks the results through the signature mechanism, and records coverage.

### 16. `vs_perm_VUmode` → `SvH_vs_perm_VUmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks VS-stage page permissions from VU-mode.
- **Why:** To verify that VU-mode can use U=1 pages and is denied on supervisor pages, for coverage.
- **How:** It maps VS-stage pages, rewrites the VS PTE for each case, enters VU-mode, does the access, checks the results through the signature mechanism, and records coverage.

### 17. `vsstatus_mxr_sum_VSmode` → `SvH_vsstatus_mxr_sum_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks `vsstatus` MXR and SUM together from VS-mode.
- **Why:** To verify that MXR and SUM correctly allow or deny VS loads, stores, and jumps on S-pages and U-pages, for coverage.
- **How:** It sets MXR/SUM, maps S-page and U-page combinations, enters VS-mode for each access, checks the results through the signature mechanism, and records coverage.

### 18. `vsstatus_mxr_sum_VUmode` → `SvH_vsstatus_mxr_sum_VUmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks `vsstatus` MXR and SUM together from VU-mode.
- **Why:** To verify that VU-mode still cannot use supervisor pages even with SUM=1, while MXR still affects U-pages, for coverage.
- **How:** It sets MXR/SUM, maps S-page and U-page combinations, enters VU-mode for each access, checks the results through the signature mechanism, and records coverage.

### 19. `vu_rwx_two_stage_VUmode` → `SvH_vu_rwx_two_stage_VUmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks VU-mode load/store through two-stage paging with U=1, then U=0.
- **Why:** To verify that VU-mode succeeds on U=1 pages at both stages and faults when the VS-stage U bit is 0, for coverage.
- **How:** It sets up two-stage maps, enters VU-mode, stores/loads with U=1, then retries with VS-stage U=0, checks the results through the signature mechanism, and records coverage.

### 20. `xonly_mxr0_HSmode` → `SvH_xonly_mxr0_HSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks HS-mode HLV of a VS-stage execute-only page with MXR=0.
- **Why:** To verify that HS hypervisor load cannot read execute-only guest data when MXR is off, for coverage.
- **How:** It maps an execute-only VS-stage page, enters HS-mode with SPVP=1, does `hlv.w`, checks the result through the signature mechanism, and records coverage.

### 21. `xonly_mxr0_VSmode` → `SvH_xonly_mxr0_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks VS-mode load of an execute-only page with MXR=0.
- **Why:** To verify that VS-mode cannot read execute-only data when MXR is off, while instruction fetch of execute-only code still works, for coverage.
- **How:** It maps an execute-only data page, enters VS-mode, tries a load (fault), runs a simple add to show fetch still works, checks the results through the signature mechanism, and records coverage.

### 22. `xonly_mxr0_VUmode` → `SvH_xonly_mxr0_VUmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks VU-mode load of an execute-only U-page with MXR=0.
- **Why:** To verify that VU-mode cannot read execute-only data when MXR is off, for coverage.
- **How:** It maps a U=1 execute-only page, enters VU-mode, tries a load, checks the result through the signature mechanism, and records coverage.

### 23. `xonly_mxr0_gstage_HSmode` → `SvH_xonly_mxr0_gstage_HSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks HS-mode HLV of a G-stage execute-only GPA with MXR=0.
- **Why:** To verify that G-stage execute-only pages cannot be read by HLV when MXR is off, for coverage.
- **How:** It turns on G-stage only, maps an execute-only G-stage page, enters HS-mode, does `hlv.w`, checks the result through the signature mechanism, and records coverage.

---

## Fault (`SvH_fault.py`) — 3 tests

### 24. `hgatp_fault_VSmode` → `SvH_hgatp_fault_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks G-stage invalid and non-leaf PTEs from VS-mode and HS-mode.
- **Why:** To verify that a bad G-stage PTE causes a guest-page fault on load, store, fetch, HLV, and HSV, for coverage.
- **How:** It turns on G-stage, rewrites the G-stage PTE to invalid or non-leaf, does each access, then restores a valid PTE, checks the results through the signature mechanism, and records coverage.

### 25. `twostage_invalid_VSmode` → `SvH_twostage_invalid_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks invalid VS-stage or G-stage PTEs during two-stage translation in VS-mode.
- **Why:** To verify that V=0 at either stage faults load, store, and jump independently, for coverage.
- **How:** It sets up two-stage paging, invalidates either the VS-stage or G-stage leaf, does `lw`/`sw`/`jalr`, checks the results through the signature mechanism, and records coverage.

### 26. `vsatp_fault_VSmode` → `SvH_vsatp_fault_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks VS-stage invalid and non-leaf PTEs from VS-mode and HS-mode.
- **Why:** To verify that a bad VS-stage PTE faults load, store, fetch, and HS HLV/HSV, for coverage.
- **How:** It turns on VS-stage only, uses valid, invalid, and non-leaf mappings, does each access, checks the results through the signature mechanism, and records coverage.

---

## Misc (`SvH_misc.py`) — 13 tests

### 27. `g_adbit_VSmode` → `SvH_g_adbit_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks G-stage and VS-stage A/D bits in VS-mode.
- **Why:** To verify that A=D=0 on a G-stage page-table mapping or a VS data page causes a fault, for coverage.
- **How:** It maps pages with A=D=0, enters VS-mode, does load/store/jump, then restores A=D=1, checks the results through the signature mechanism, and records coverage.

### 28. `g_pte_attr_VSmode` → `SvH_g_pte_attr_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks G-stage PTE RSW, reserved, and PBMT bits using HS-mode HLV/HSV.
- **Why:** To verify that G-stage RSW is ignored, reserved bits fault, and PBMT follows `menvcfg.PBMTE`, for coverage.
- **How:** It rewrites G-stage PTE attribute bits, enters HS-mode, does HLV/HSV, checks the results through the signature mechanism, and records coverage.

### 29. `g_struct_HSmode` → `SvH_g_struct_HSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks a misaligned G-stage superpage from HS-mode.
- **Why:** To verify that a misaligned G superpage faults, and that a later valid 4KiB leaf plus HFENCE.GVMA succeeds, for coverage.
- **How:** It installs a misaligned G superpage, does HS HLV (fault), replaces it with a valid 4KiB leaf, fences, retries HLV, checks the results through the signature mechanism, and records coverage.

### 30. `gpa_width_VSmode` → `SvH_gpa_width_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks GPA width in VS-mode (RV64).
- **Why:** To verify that GPAs wider than Sv39x4 or non-canonical GPAs fault, while a legal GPA succeeds, for coverage.
- **How:** It enters VS-mode with identity addressing, does `ld`/`sd` at out-of-range and legal GPAs, checks the results through the signature mechanism, and records coverage.

### 31. `hfence_gvma_mode_HSmode` → `SvH_hfence_gvma_mode_HSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks HFENCE.GVMA when `hgatp` switches between Bare and paged.
- **Why:** To verify that HFENCE.GVMA flushes G-stage TLB entries after an `hgatp` mode change, for coverage.
- **How:** It switches `hgatp` Bare↔paged, issues HFENCE.GVMA, does HS HLV, checks the results through the signature mechanism, and records coverage.

### 32. `hfence_gvma_ops_HSmode` → `SvH_hfence_gvma_ops_HSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks HFENCE.GVMA operand encodings in HS-mode.
- **Why:** To verify that all rs1/rs2 forms of HFENCE.GVMA are accepted and G-stage translation still works, for coverage.
- **How:** It issues HFENCE.GVMA with different register operands, does HS HLV after each, checks the results through the signature mechanism, and records coverage.

### 33. `hfence_vvma_HSmode` → `SvH_hfence_vvma_HSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks HFENCE.VVMA operand encodings.
- **Why:** To verify that all HFENCE.VVMA forms are accepted and VS-stage translation still works, for coverage.
- **How:** It issues HFENCE.VVMA from HS-mode with different operands, then does a VS-mode load, checks the results through the signature mechanism, and records coverage.

### 34. `mprv_hgatp_Mmode` → `SvH_mprv_hgatp_Mmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks M-mode MPRV with G-stage translation (`MPP` and `MPV`).
- **Why:** To verify that MPRV+MPP+MPV routes M-mode loads through G-stage when required, and that HLV ignores MPRV, for coverage.
- **How:** It stays in M-mode, sets MPRV/MPP/MPV, does loads of a G-stage GPA, also tries HLV, checks the results through the signature mechanism, and records coverage.

### 35. `mprv_sum_two_stage_Mmode` → `SvH_mprv_sum_two_stage_Mmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks M-mode MPRV as VS on a U-page with SUM off, then on.
- **Why:** To verify that MPRV+MPP=S+MPV=1 follows `vsstatus.SUM` for U-page access through two-stage paging, for coverage.
- **How:** It maps a U=1 page through both stages, does M-mode MPRV loads/stores with SUM=0 then SUM=1, checks the results through the signature mechanism, and records coverage.

### 36. `mprv_vsatp_Mmode` → `SvH_mprv_vsatp_Mmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks M-mode MPRV with VS-stage only (`hgatp` Bare).
- **Why:** To verify that MPRV can walk `vsatp` for MPP=S and MPP=U, and that a raw load of a VA without MPRV faults, for coverage.
- **How:** It maps VS-stage S-page and U-page VAs, does M-mode loads with MPRV off and on, checks the results through the signature mechanism, and records coverage.

### 37. `tvm_hgatp_HSmode` → `SvH_tvm_hgatp_HSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks HS writes to `hgatp` with TVM off, then on.
- **Why:** To verify that TVM=0 allows HS `csrw hgatp` and TVM=1 traps that write, for coverage.
- **How:** It clears TVM, enters HS, writes `hgatp` successfully, then sets TVM=1, retries the write (trap), returns to M, checks the results through the signature mechanism, and records coverage.

### 38. `vs_pte_attr_VSmode` → `SvH_vs_pte_attr_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks VS-stage PTE RSW, reserved, and PBMT bits from VS-mode.
- **Why:** To verify that VS-stage RSW is ignored, reserved bits fault, and PBMT follows envcfg rules, for coverage.
- **How:** It rewrites VS-stage PTE attribute bits, enters VS-mode for each access, checks the results through the signature mechanism, and records coverage.

### 39. `vsbe_endian_VSmode` → `SvH_vsbe_endian_VSmode-00.S`
- **What:** A generated RISC-V Hypervisor test that checks guest endianness via `hstatus.VSBE` in VS-mode.
- **Why:** To verify little-endian guest loads/stores under VSBE (Sail may not implement big-endian VSBE), for coverage.
- **How:** It programs `hstatus.VSBE`, enters VS-mode, does endian-sensitive load/store, checks the results through the signature mechanism, and records coverage.

---

## How we know it worked

1. `make testgen EXTENSIONS=SvH EXCLUDE_EXTENSIONS=Sm` regenerates all 39 `.S` files.
2. All 39 **pass** on Sail (RV32 + RV64).
3. Coverage stays ~**99.7%**; only open hole is Sail **VSBE**.

## Out of scope

- Full XWR permission explosion
- Fixing Sail VSBE
- Changing the coverage testbench

## Ask / approval gate

Approve when: **every stem has What / Why / How**, then Python may be written. Code-level Walkthrough comes **after** generators exist.
