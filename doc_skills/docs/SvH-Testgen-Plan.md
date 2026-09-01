# SvH Testgen Plan — 39-test catalog & flow map

**Document role:** **Phase 1** (planning). Human-readable catalog: how many tests, which coverpoints, clear steps per test.  
**Per-test What/Why/How (approval shape):** `docs/SvH-Implementation-Readme.md` — required default for any new suite Plan.  
**Not this doc:** line-level Python/asm — that is **Phase 3** in `docs/SvH_Testgen_Codebase_Walkthrough.md` (written **after** plan approval + generators exist).

**Workflow:** xlsx/csv testplan → **this Plan** → **user review/approval** → Python (`SvH*.py`) → `make testgen` → **Walkthrough** (optional refresh per test).

**As-of:** 2026-08-25 (synced to live `SvH*.py` + regenerated `tests/priv/SvH/*.S`).  
**Generators:** all seven `SvH*.py` modules now carry **inline end-of-line comments** on imports, helpers, and case tables — read Python for intent; this Plan stays at catalog depth.  
**Companion deep dive (Phase 3):** `docs/SvH_Testgen_Codebase_Walkthrough.md` — **T01–T39** chapters (Python lines → asm spine → why each insn).  
**Output dir:** `tests/priv/SvH/` — **39** `SvH_<stem>-00.S` files.

Python **does not** run the hart. It builds `list[str]` of assembly. Framework writes `.S` → GCC links ELF → Sail runs → `.rvvi` → covergroups (`SvH_cg` in `coverpoints/priv/SvH_coverage.svh`).

---

## 1. How a test is named

| Piece | Example |
|-------|---------|
| Python | `generate_two_stage_rw_VSmode` |
| Stem in `_SCENARIOS` | `two_stage_rw_VSmode` |
| File | `tests/priv/SvH/SvH_two_stage_rw_VSmode-00.S` |

Source of truth for the suite list: `generators/testgen/src/testgen/priv/extensions/SvH.py` → `_SCENARIOS` (lines 72–117) + `make_svh` (lines 120–146).

Each `generate_*` is imported at the top of `SvH.py` with a one-line comment naming the output `.S` file.

---

## 1b. Generator module map (7 files)

| File | Tests | Role |
|------|-------|------|
| `SvH.py` | registry | `_SCENARIOS` order, `make_svh`, `@add_priv_test_generator("SvH", …)` |
| `SvHCommon.py` | — | Shared emitters: twins, VA/GPA symbols, PTE macros, hops, SIGUPD, `.data` |
| `SvH_twostage.py` | 7 | Paging on/off, ifetch, MXR, G-walk of VS PT |
| `SvH_csr.py` | 3 | hgatp / vsatp / satp field walks from HS or VS |
| `SvH_perm.py` | 13 | G/VS permissions, SUM, MXR×SUM, VU RWX, x-only |
| `SvH_fault.py` | 3 | Invalid / non-leaf PTEs (`AccessCase` dataclass) |
| `SvH_misc.py` | 13 | HFENCE, MPRV, TVM, A/D, PTE attrs, GPA width, VSBE (`Body` dataclass) |

Offline reference only: `extensions/_park/svh_seed/` (not read at testgen time).

---

## 2. Glossary

| Term | Meaning |
|------|---------|
| Twin | Sv32 + Sv39 bodies in one `.S`, gated by `#ifdef SV32_SUPPORTED` / `SV39_SUPPORTED` |
| `build_twins` | `SvHCommon.build_twins` — Sv32+Sv39 ifdefs; `SIGUPD_COUNT = max(sv32, sv39)` |
| `CG` | `"SvH_cg"` — covergroup tag on every SIGUPD / testcase string |
| VS-stage | Guest VA → GPA (`vsatp`) |
| G-stage | GPA → SPA (`hgatp`, Sv*x4); leaves need **U=1** |
| SIGUPD | `RVTEST_SIGUPD*` — dump GPR/CSR into signature |
| Coverpoint | Bin/cross under `SvH_cg` |
| Bare | `MODE=0` / satp written zero — identity addressing |
| Seed park | `_park/svh_seed/` — offline reference only |

---

## 3. Pipeline (short)

```text
make testgen EXTENSIONS=SvH EXCLUDE_EXTENSIONS=Sm
  → make_svh → delete_old_asm_files → foreach _SCENARIOS: generate_* → TestChunk
  → tests/priv/SvH/SvH_*-00.S
  → (separate) GCC → ELF → Sail → trace → .rvvi → TB / SvH_cg
```

Full dependency list (env macros, Sail, licensed sim, etc.): see Walkthrough §9.

---

## 4. Shared helper cheat sheet (`SvHCommon.py`)

| Helper / constant | Emits / does |
|-------------------|--------------|
| `delete_old_asm_files` | Unlink `tests/priv/SvH/*.S` before regen |
| `VA_CODE`, `VA_DATA_SV32/SV39`, `GPA_*` | Fixed guest VA/GPA symbols (see file header) |
| `PTE_CODE_G`, `PTE_DATA_G`, `PTE_PT_G`, `PTE_V_ONLY`, `PTE_CODE_VS`, `PTE_DATA_VS` | Canonical PTE flag text for macros |
| `set_va_gpa_symbols` | `.set va_code/va_data/gpa_*` (Sv32 may add `vlvl0`) |
| `build_two_stage_maps` / `_page_table_macros` | `G_PTE_SETUP` / `VS_PTE_SETUP` / save-area |
| `two_stage_setup` | symbols + maps + `enable_two_stage` |
| `enable_two_stage` | vsatp+hgatp + both HFENCEs |
| `enable_vs_and_g` | Write both satps + fences (fault family) |
| `enable_vs_only` | vsatp ON, hgatp Bare |
| `disable_paging` | `csrw vsatp/hgatp, x0` + fences |
| `fence_both_stages` | `hfence.vvma` + `hfence.gvma` |
| `set_g_data_leaf` / `set_vs_data_leaf` | Rewrite one G or VS data leaf (fault/perm) |
| `goto_vs` / `goto_vu` / `goto_hs` / `goto_mmode` | Privilege hops |
| `clear_mprv` | Drop `mstatus.MPRV` before SIGUPD (misc / MPRV tests) |
| `preload_spa` / `load_guest_va` | SPA pattern / `LI(reg, va_data)` |
| `pte_bits` | Build `"(PTE_D \| …)"` from X/W/R/U/V/A/D bools |
| `count_sigupds` / `add_sigupd_count` | Bump chunk `sigupd_count` (+ testcase when needed) |
| `sigupd_labeled` / `sigupd_gpr` / `sigupd_csr` | Signature dumps with coverpoint metadata |
| `mismatch_string` / `data_section` / `twin_data` | `.data` pages + fail strings per twin |
| `build_twins` | Sv32/Sv39 ifdef wrap; header uses **max** twin counters |

**Twin rule:** only one `#ifdef SV32_SUPPORTED` or `SV39_SUPPORTED` body runs per ELF — never sum both twins for `SIGUPD_COUNT`.

---

## 5. Complete catalog (39)

**SIGUPD** = `#define SIGUPD_COUNT` in each `.S` (max twin). **Cases** = `// Test case N:` banners (both ifdefs may appear in one file). See **§5.0** for the full index; subsections below add behavior notes.

### 5.0 Master index

| # | Stem | Module | SIGUPD | Cases | Primary coverpoint(s) |
|---|------|--------|--------|-------|------------------------|
| 1 | `g_walk_vs_pt_VSmode` | twostage | 12 | 0 | G walk of VS PT GPA |
| 2 | `hgatp_bare_trans_VSmode` | twostage | 13 | 0 | VS on, G Bare load/store |
| 3 | `stage_both_bare_VSmode` | twostage | 12 | 0 | `cp_stage_both_bare` |
| 4 | `two_stage_ifetch_VSmode` | twostage | 11 | 0 | `cp_two_stage_ifetch` |
| 5 | `two_stage_mxr_VSmode` | twostage | 12 | 0 | `cp_two_stage_mxr` (VS) |
| 6 | `two_stage_mxr_VUmode` | twostage | 12 | 0 | `cp_two_stage_mxr` (VU) |
| 7 | `two_stage_rw_VSmode` | twostage | 12 | 0 | `cp_two_stage_rw` |
| 8 | `csr_hgatp_fields_HSmode` | csr | 89 | 0 | `cp_hgatp_mode_field`, VMID, PPN |
| 9 | `csr_satp_mode_VSmode` | csr | 45 | 0 | satp.MODE WARL (**RV64/Sv39 ifdef only**) |
| 10 | `csr_vsatp_fields_HSmode` | csr | 90 | 0 | `cp_vsatp_*` MODE/ASID/PPN |
| 11 | `g_perm_VSmode` | perm | 20 | 20 | `cp_hgatp_perm_checks` + HS HLV/HSV |
| 12 | `g_perm_VUmode` | perm | 19 | 18 | `cp_hgatp_perm_checks` |
| 13 | `g_u_bit_HSmode` | perm | 15 | 10 | `cp_hgatp_u_mode_access_rw` |
| 14 | `sum_Upages_VSmode` | perm | 14 | 8 | SUM on U=1 VS pages |
| 15 | `vs_perm_VSmode` | perm | 33 | 46 | VS XWR / U / SUM matrix |
| 16 | `vs_perm_VUmode` | perm | 22 | 24 | VU allow/deny U vs S pages |
| 17 | `vsstatus_mxr_sum_VSmode` | perm | 45 | 69 | VS `vsstatus` MXR×SUM×S/U |
| 18 | `vsstatus_mxr_sum_VUmode` | perm | 47 | 74 | VU MXR×SUM |
| 19 | `vu_rwx_two_stage_VUmode` | perm | 12 | 4 | VU U=1 allow / U=0 deny |
| 20 | `xonly_mxr0_HSmode` | perm | 11 | 2 | HS `hlv.w` x-only MXR=0 |
| 21 | `xonly_mxr0_VSmode` | perm | 12 | 4 | VS x-only MXR=0 |
| 22 | `xonly_mxr0_VUmode` | perm | 11 | 2 | VU x-only MXR=0 |
| 23 | `xonly_mxr0_gstage_HSmode` | perm | 11 | 2 | HS G-stage x-only |
| 24 | `hgatp_fault_VSmode` | fault | 19 | 18 | `cp_hgatp_invalid_pte`, non-leaf |
| 25 | `twostage_invalid_VSmode` | fault | 16 | 12 | `VM_permission_invalid_*` |
| 26 | `vsatp_fault_VSmode` | fault | 18 | 16 | `cp_vsatp_invalid_pte`, non-leaf |
| 27 | `g_adbit_VSmode` | misc | 16 | 12 | G/VS A=D=0 |
| 28 | `g_pte_attr_VSmode` | misc | 30 | 23 | G RSW / reserved / PBMT |
| 29 | `g_struct_HSmode` | misc | 12 | 4 | G superpage misalign |
| 30 | `gpa_width_VSmode` | misc | 13 | 3 | GPA width (**RV64 only**) |
| 31 | `hfence_gvma_mode_HSmode` | misc | 12 | 4 | HFENCE.GVMA mode |
| 32 | `hfence_gvma_ops_HSmode` | misc | 13 | 6 | HFENCE.GVMA ops |
| 33 | `hfence_vvma_HSmode` | misc | 13 | 6 | HFENCE.VVMA |
| 34 | `mprv_hgatp_Mmode` | misc | 17 | 14 | MPRV × hgatp |
| 35 | `mprv_sum_two_stage_Mmode` | misc | 13 | 6 | MPRV × SUM |
| 36 | `mprv_vsatp_Mmode` | misc | 13 | 6 | MPRV × vsatp |
| 37 | `tvm_hgatp_HSmode` | misc | 12 | 4 | TVM × hgatp |
| 38 | `vs_pte_attr_VSmode` | misc | 41 | 38 | VS RSW / reserved / PBMT |
| 39 | `vsbe_endian_VSmode` | misc | 15 | 10 | `hstatus.VSBE` |

### 5.1 Twostage — `SvH_twostage.py` (7)

| # | Stem | `generate_*` | `_asm_*` | SIGUPD | What the hart does |
|---|------|--------------|----------|--------|-------------------|
| 1 | `g_walk_vs_pt_VSmode` | `generate_g_walk_vs_pt_VSmode` | `_asm_g_walk_vs_pt` | 12 | G leaf over VS PT GPA: allow load, then V=0 → guest-page fault |
| 2 | `hgatp_bare_trans_VSmode` | `generate_hgatp_bare_trans_VSmode` | `_asm_hgatp_bare` | 13 | VS paging, G Bare; sw/lw + SPA + hgatp read SIGUPD |
| 3 | `stage_both_bare_VSmode` | `generate_stage_both_bare_VSmode` | `_asm_both_bare` | 12 | Both Bare; identity VS access via T-SBI hop |
| 4 | `two_stage_ifetch_VSmode` | `generate_two_stage_ifetch_VSmode` | `_asm_two_stage_ifetch` | 11 | VS ifetch both stages (code maps only; 1 SIGUPD/twin) |
| 5 | `two_stage_mxr_VSmode` | `generate_two_stage_mxr_VSmode` | `_asm_mxr(vu=False)` | 12 | X-only data; MXR=0 fault then MXR=1 load (VS) |
| 6 | `two_stage_mxr_VUmode` | `generate_two_stage_mxr_VUmode` | `_asm_mxr(vu=True)` | 12 | Same for VU (U=1 leaves) |
| 7 | `two_stage_rw_VSmode` | `generate_two_stage_rw_VSmode` | `_asm_two_stage_rw` | 12 | VS sw/lw both stages + SPA readback |

**Worked path (test 7):**  
`make_svh` → `generate_two_stage_rw_VSmode` → `build_twins` → `_asm_two_stage_rw` →  
`two_stage_setup` → `preload_spa` → `load_guest_va` → `goto_vs` → `sw`/`lw` → `goto_mmode` → 2× SIGUPD → `twin_data`.  
See generated `tests/priv/SvH/SvH_two_stage_rw_VSmode-00.S`.

**CSRs / addresses touched:** `vsatp`, `hgatp`, HFENCEs; VAs `va_code`/`va_data`; SPA `test_region`.

---

### 5.2 CSR — `SvH_csr.py` (3)

Uses `_write_csr_then_sigupd`, `_walk_mode_field`, `_walk_ppn_bits` — each field sample is one SIGUPD. HS entry via `RVTEST_TSBI_GOTO_SMODE`; VS Bare (`csrw vsatp, x0`) isolates hgatp/vsatp bins.

| # | Stem | `generate_*` | SIGUPD | Focus |
|---|------|--------------|--------|-------|
| 8 | `csr_hgatp_fields_HSmode` | `generate_csr_hgatp_fields_HSmode` | 89 | hgatp MODE (Bare + legal + RV64 WARL), VMID, PPN walking-1 |
| 9 | `csr_satp_mode_VSmode` | `generate_csr_satp_mode_VSmode` | 45 | satp.MODE 0–15 from VS (**`#ifdef SV39_SUPPORTED` only**) |
| 10 | `csr_vsatp_fields_HSmode` | `generate_csr_vsatp_fields_HSmode` | 90 | vsatp MODE/ASID/PPN from HS (mirror hgatp pattern) |

---

### 5.3 Perm — `SvH_perm.py` (13)

Case tables live in `_asm_*` bodies as packed tuples → `SigCase` → `_asm_*_seed_case` / `_asm_load_case` / … Each case emits a `// Test case N:` banner + SIGUPD.

| # | Stem | `generate_*` | SIGUPD | Cases | Focus |
|---|------|--------------|--------|-------|-------|
| 11 | `g_perm_VSmode` | `generate_g_perm_VSmode` | 20 | 20 | G XWR×U from VS + HS HLV/HSV cases |
| 12 | `g_perm_VUmode` | `generate_g_perm_VUmode` | 19 | 18 | G perm matrix from VU |
| 13 | `g_u_bit_HSmode` | `generate_g_u_bit_HSmode` | 15 | 10 | G U=0/U=1; HS `hlv`/`hsv` |
| 14 | `sum_Upages_VSmode` | `generate_sum_Upages_VSmode` | 14 | 8 | SUM 0/1 on U=1 VS pages |
| 15 | `vs_perm_VSmode` | `generate_vs_perm_VSmode` | 33 | 46 | VS XWR / U / SUM directed matrix |
| 16 | `vs_perm_VUmode` | `generate_vs_perm_VUmode` | 22 | 24 | VU on U vs S pages |
| 17 | `vsstatus_mxr_sum_VSmode` | `generate_vsstatus_mxr_sum_VSmode` | 45 | 69 | `vsstatus` MXR×SUM (VS) |
| 18 | `vsstatus_mxr_sum_VUmode` | `generate_vsstatus_mxr_sum_VUmode` | 47 | 74 | MXR×SUM (VU) |
| 19 | `vu_rwx_two_stage_VUmode` | `generate_vu_rwx_two_stage_VUmode` | 12 | 4 | U=1 allow / U=0 deny two-stage |
| 20 | `xonly_mxr0_HSmode` | `generate_xonly_mxr0_HSmode` | 11 | 2 | HS `hlv.w` x-only MXR=0 |
| 21 | `xonly_mxr0_VSmode` | `generate_xonly_mxr0_VSmode` | 12 | 4 | VS x-only MXR=0 |
| 22 | `xonly_mxr0_VUmode` | `generate_xonly_mxr0_VUmode` | 11 | 2 | VU x-only MXR=0 |
| 23 | `xonly_mxr0_gstage_HSmode` | `generate_xonly_mxr0_gstage_HSmode` | 11 | 2 | G-stage x-only; HS `hlv.w` |

**Typical conditions:** rewrite leaf with `pte_bits(x=,w=,r=,u=,v=)`; set/clear SUM/MXR in `sstatus`/`vsstatus`; hop; access; SIGUPD success or fault sentinel.

**VU RWX addresses (from `_asm_vu_rwx`):** e.g. `va_data=0x008001000`, `va_deny=0x008002000`, matching GPAs `0x00C002000` / `0x00C003000`, code `va_code=0x90000000` (Sv32) — see `SvH_perm.py` around the `_asm_vu_rwx` body.

---

### 5.4 Fault — `SvH_fault.py` (3)

`AccessCase` dataclass + `_asm_for_cases` emit numbered banners. **`twostage_invalid`** clears `medeleg`/`hedeleg` so faults stay at M.

| # | Stem | `generate_*` | SIGUPD | Cases/twin | Focus |
|---|------|--------------|--------|------------|-------|
| 24 | `hgatp_fault_VSmode` | `generate_hgatp_fault_VSmode` | 19 | 9 | G V=0, L0 non-leaf, HS HLV/HSV, restore, ifetch, sw+SPA |
| 25 | `twostage_invalid_VSmode` | `generate_twostage_invalid_VSmode` | 16 | 6 | VS or G V=0 × lw/sw/jalr matrix |
| 26 | `vsatp_fault_VSmode` | `generate_vsatp_fault_VSmode` | 18 | 8 | VS invalid/non-leaf + HS SPVP HLV/HSV + valid lw + jalr |

---

### 5.5 Misc — `SvH_misc.py` (13)

`Body(lines, sigs, cases)` per twin; `_finish_twin_test` / `_finish_single_test` set chunk counters to **max** twin. `RV64_PTE_DEFS` injected for Sv39 RSW/PBMT tests.

| # | Stem | `generate_*` | SIGUPD | Cases | Focus |
|---|------|--------------|--------|-------|-------|
| 27 | `g_adbit_VSmode` | `generate_g_adbit_VSmode` | 16 | 12 | G/VS A=D=0 then restore |
| 28 | `g_pte_attr_VSmode` | `generate_g_pte_attr_VSmode` | 30 | 23 | G RSW/reserved/PBMT (4 Sv32 + 20 Sv39) |
| 29 | `g_struct_HSmode` | `generate_g_struct_HSmode` | 12 | 4 | Misaligned G superpage → valid 4KiB |
| 30 | `gpa_width_VSmode` | `generate_gpa_width_VSmode` | 13 | 3 | Canonical vs non-canonical GPA (**RV64 only**) |
| 31 | `hfence_gvma_mode_HSmode` | `generate_hfence_gvma_mode_HSmode` | 12 | 4 | Bare↔paged hgatp + HFENCE.GVMA |
| 32 | `hfence_gvma_ops_HSmode` | `generate_hfence_gvma_ops_HSmode` | 13 | 6 | HFENCE.GVMA rs1/rs2 forms |
| 33 | `hfence_vvma_HSmode` | `generate_hfence_vvma_HSmode` | 13 | 6 | HFENCE.VVMA variants |
| 34 | `mprv_hgatp_Mmode` | `generate_mprv_hgatp_Mmode` | 17 | 14 | MPRV+MPP+MPV × G maps |
| 35 | `mprv_sum_two_stage_Mmode` | `generate_mprv_sum_two_stage_Mmode` | 13 | 6 | MPRV as VS on U-page SUM 0/1 |
| 36 | `mprv_vsatp_Mmode` | `generate_mprv_vsatp_Mmode` | 13 | 6 | MPRV × vsatp-only maps |
| 37 | `tvm_hgatp_HSmode` | `generate_tvm_hgatp_HSmode` | 12 | 4 | TVM=0 allow / TVM=1 trap on `csrw hgatp` |
| 38 | `vs_pte_attr_VSmode` | `generate_vs_pte_attr_VSmode` | 41 | 38 | VS RSW/reserved/PBMT (8 Sv32 + 31 Sv39) |
| 39 | `vsbe_endian_VSmode` | `generate_vsbe_endian_VSmode` | 15 | 10 | `hstatus.VSBE` LE check |

---

## 6. Per-test mental model (apply to any of the 39)

```text
1. Symbols     .set va_* / gpa_*
2. Maps        G_PTE_SETUP / VS_PTE_SETUP (expand in env headers)
3. Enable      vsatp / hgatp (+ HFENCE)
4. (optional)  Rewrite one leaf for the case (perms/V=0/MXR/…)
5. Hop         VS / VU / HS / MPRV path
6. Stimulus    lw/sw/jalr/CSR/hlv/hfence/…
7. Return      M-mode (goto_mmode / clear MPRV)
8. SIGUPD      dump result or fault sentinel
9. .data       test_region, page tables, mismatch strings
```

**Why each class of asm line exists**

| Asm / directive | Why generated |
|-----------------|---------------|
| `.set va_data, …` | Give macros and `LI` a relocatable guest VA |
| `G_PTE_SETUP` / `VS_PTE_SETUP` | Install PTEs the walk will use |
| `V_SAVE_AREA_SETUP` | Trap save area reachable at guest code VA |
| `VSATP_SETUP` / `HGATP_SETUP` | Program translation CSRs |
| `hfence.vvma` / `hfence.gvma` | Publish PTE/CSR changes to TLBs |
| `RVTEST_GOTO_LOWER_MODE VSmode` | Enter guest with relocate |
| `sw` / `lw` / `jalr` | Create the architectural event coverpoints sample |
| `csrr`/`csrw` of *atp / status | CSR or MXR/SUM/TVM/MPRV stimulus |
| `RVTEST_SIGUPD` | Architectural “print” into signature for TB compare |
| `.pushsection .data` / `.zero 4096` | Backing store for SPA + page tables |

Macro **bodies** are **not** in SvH*.py — see `tests/env/rvtest_macros_hypervisor.h`.

---

## 7. Missing dependencies (plan view)

| Need | Used for | Owned by |
|------|----------|----------|
| Testgen writer + registry | `.S` emission | `generators/testgen` (not SvH*.py) |
| `riscv_arch_test.h` + hypervisor macros | Expand PTE/hop/SIGUPD macros | `tests/env/` |
| GCC + linker scripts | ELF | Toolchain / framework Make |
| Sail hypervisor model | Run ELF | External Sail install |
| `sail_to_rvvi` | Short Tracefile | Framework converter |
| `SvH_coverage.svh` | Coverbins | `coverpoints/priv/` |
| Licensed Questa/VCS | UCDB | Host license (Starter ≠ enough) |

Without these, `.S` may exist while **run/coverage** cannot complete.

---

## 8. Commands

```bash
cd riscv-arch-test
# Force regen after editing SvH*.py (stamp may skip otherwise):
rm -f work/stamps/testgen.stamp && make testgen EXTENSIONS=SvH EXCLUDE_EXTENSIONS=Sm JOBS=1
ls tests/priv/SvH/*.S | wc -l   # expect 39
```

Do **not** hand-edit `tests/priv/SvH/*.S`. Change Python → re-run testgen.

**Sync this Plan after generator edits:** refresh §5.0 SIGUPD column from `#define SIGUPD_COUNT` in each `.S` (or re-run the catalog script in CI).

---

## 9. Doc sync rules

- **Phase order:** Plan (this file) → user approval → Python → Walkthrough. Do not write Walkthrough sections for tests that are not yet in `_SCENARIOS`.
- Suite list: only `_SCENARIOS` in `SvH.py` (39 tuples — order matches §5.0).
- Helper names: only public APIs in `SvHCommon.py` (`build_twins`, `set_g_data_leaf`, … — not legacy `emit_twin`).
- Generators: inline comments in `SvH*.py` are authoritative for case intent; update this Plan’s **SIGUPD/Cases** columns when counters change.
- Line numbers drift — search function names if line refs move.
- Per-test **What/Why/How** at plan level: §5.0 + Walkthrough T* chapters. **Code-level** narrative: `SvH_Testgen_Codebase_Walkthrough.md`.
