# Coverpoints layout (simple)

## Three layers
| Folder | Who writes | What |
|--------|------------|------|
| `coverpoints/priv/` | Humans | Suite covergroups e.g. `ExceptionsH_coverage.svh` |
| `coverpoints/unpriv/` | Generator from CSV | I, M, Zaamo, … |
| `coverpoints/coverage/` | **covergroupgen only** | Switchboard — `#ifdef SUITE_COVERAGE` includes / init / sample |

## Glue files (`coverpoints/coverage/` — do not edit)
| File | Role |
|------|------|
| `RISCV_coverage_config.svh` | Include suite `_coverage.svh` when define set |
| `RISCV_coverage_base_init.svh` | `new()` covergroup objects |
| `RISCV_coverage_base_sample.svh` | Call `suite_sample(hart, issue, ins)` each retire |
| `RISCV_instruction_sample.svh` | Shared insn decode → `ins_t` |

## Suite naming
`EXTENSIONS=ExceptionsH` → `+define+EXCEPTIONSH_COVERAGE` → priv `ExceptionsH_coverage.svh`.
`EXTENSIONS=Hact4` → `HACT4_COVERAGE`. Hand tests in `tests/priv/Sm/` do **not** enable `ExceptionsH` / `SvH`.

## Where to add a new priv suite
1. `tests/priv/<Suite>/*.S`
2. `coverpoints/priv/<Suite>_coverage.svh` (+ `_init.svh` as required by existing pattern)
3. Re-run covergroupgen / `make coverage` so glue regenerates
4. Never paste bins into `coverpoints/coverage/`

## Hact4 bring-up (current)
| Coverpoint | From tests |
|------------|------------|
| `cp_smoke_alu` | `cp_smoke.S` ADDI/XOR/OR |
| `cp_smoke_csr` | `cp_smoke.S` mstatus/misa/hstatus/hedeleg |
| `cp_hsv` | `hsv_instrs_HSmode.S` HSV.W/H/B |
| `cp_paging_csr` | vsatp/hgatp/satp setup in paging tests |
| `cp_mem` | LW/SW used by HSV verify + guests |

## SvH ↔ SvH sheet (2026-08-11 alignment)
Source: `Hypervisor (10x) - Gap Highlighted.xlsx` → **`SvH`**.
Covergroup: `coverpoints/priv/SvH_coverage.svh`.
**Comments in that `.svh`:** front-facing only (plain English + empty-bin reasons). Sheet jargon stays in vault/plan/xlsx — **not** in the covergroup file.
**Plan:** `riscv-arch-test/SvH_Coverage_Implementation_Plan.md` (may lag; prefer this note + status xlsx).

| Class | Count | Notes |
|-------|------:|-------|
| Named sheet CPs | **54** | Col A (excl. `***`) |
| IMPL in `SvH_cg` | **53** | All sheet intents except waived speculative A |
| SUB | **1** | `vsatp_sum_set` → `cp_vsatp_sum_effects` |
| WAIVE | **1** | `cp_vsatp_speculative_a_bit` (squash not in `.rvvi`) |
| `***` notes | **7** | Not CPs |
| Arch rules | — | **RV64-only:** `cp_vsatp_mode_field`, `cp_satp_mode_field`, `cp_hgatp_gpa_width_checks`, PBMT/reserved. **BOTH:** most others (RV32 + Sv39 twins). `cp_hgatp_mode_field`: RV64 0..15 walk + RV32 Bare/Sv32x4 |

**2026-08-11 fixes:** restored `svh_csr_vsatp_fields_HSmode.S`; RV32 `cp_hgatp_mode_field` + Bare case. Rows 47–57 were already covered (not missing).

**2026-08-12 sheet-bin pass:** Gap Highlighted `Bins` column vs `SvH_cg` — added starting-MODE axis on CSR MODE walks, HFENCE rs1/rs2 `{x0,nz}`, `cp_two_stage_mxr` uses `sstatus.MXR` + G x-only (was vsstatus-only), exec `_x` where sheet lists fetch. Unobservable in `.rvvi` (page size, TLB cached, GPA bit walk, squash) still omitted. New `_x` / M-mode hfence bins need ELFs before FC % returns to 99%.

**Header rule (all future SvH `.S`):** `Coverpoints mapped (SvH_cg):` + exact coverpoint ids only — no sheet/xlsx/column mentions in the test file.



## Related
- `readme_coverpoint_flow.md` section “What is coverpoints/coverage/?”
- [[02-Architecture-Pipeline]]
