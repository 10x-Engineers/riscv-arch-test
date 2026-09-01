# Reuse map — look here first

Do not invent new helpers when these exist.

## SvH (hypervisor two-stage)

| Piece | Path |
|-------|------|
| Orchestrator / `_SCENARIOS` | `generators/testgen/src/testgen/priv/extensions/SvH.py` |
| Twins, hops, PTE/ATP, SIGUPD | `…/SvHCommon.py` (`build_twins`, `goto_vs`/`vu`/`hs`, `two_stage_setup`, `enable_vs_only`, `disable_paging`) |
| Paging on/off, ifetch, MXR | `SvH_twostage.py` |
| hgatp / vsatp / satp WARL | `SvH_csr.py` |
| Perms, SUM, MXR×SUM, x-only | `SvH_perm.py` |
| Invalid / non-leaf PTE | `SvH_fault.py` (`PTE_V` only = non-leaf; R/W/X set = leaf) |
| HFENCE, MPRV, TVM, attrs, VSBE | `SvH_misc.py` |
| Generated ELFs | `tests/priv/SvH/SvH_<stem>-00.S` |
| Covergroup | `coverpoints/priv/SvH_coverage.svh` (`SvH_cg`) |
| Teaching docs | `docs/SvH_Testgen_Codebase_Walkthrough.md`, `docs/SvH-Testgen-Plan.md` |
| Parked seeds (offline) | `generators/testgen/src/testgen/priv/extensions/_park/svh_seed/` |

## Other priv suites (same registry)

| Pattern | Copy from |
|---------|-----------|
| Exceptions + Common | `ExceptionsSm.py` + `ExceptionsCommon.py` |
| Zawrs family | `ZawrsS.py` / `ZawrsU.py` / `ZawrsSm.py` + `ZawrsCommon.py` |
| Interrupts | `InterruptsS.py`, `InterruptsSm.py`, `InterruptsU.py`, `InterruptsSstc.py` |
| Sdtrig | `SdtrigS.py` + `SdtrigCommon.py` |
| Registry | `@add_priv_test_generator` in `priv/registry.py` |

Suite name = directory under `tests/priv/` = `EXTENSIONS=` = covergroup define prefix.

## Unpriv

| Piece | Path |
|-------|------|
| Plans | `testplans/<suite>.csv` |
| Coverpoint gens | `generators/testgen/src/testgen/coverpoints/` (`@add_coverpoint_generator`) |
| Output (do not edit) | `tests/rv32*`, `tests/rv64*`, `coverpoints/unpriv/` |

## Env macros (missing from Python)

PTE/ATP/hops/SIGUPD expand in `tests/env/` (`G_PTE_SETUP`, `VSATP_SETUP`, `RVTEST_GOTO_LOWER_MODE`, `RVTEST_TSBI_GOTO_VSMODE`, `RVTEST_GOTO_MMODE`, `RVTEST_SIGUPD`). Python only chooses arguments.

## Norm / xlsx (hypervisor plan)

`Hypervisor (10x).xlsx` → `hypervisor-10x-test-plan.md` / `.json` → `norm-rules.html`. Scripts: skill `act4-hypervisor`.
