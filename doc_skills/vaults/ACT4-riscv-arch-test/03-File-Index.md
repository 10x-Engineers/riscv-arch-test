# File Index (ground truth paths)

All paths relative to `riscv-arch-test/` unless noted.

## Must-read before inventing
| Path | Why |
|------|-----|
| `AGENTS.md` | Repo conventions + Make |
| `AI_CONTEXT_SUMMARY.md` | Living host/session facts |
| `readme_coverpoint_flow.md` | Human + agent coverpoint narrative |
| `framework/src/act/sail_to_rvvi.py` | Trace → RVVI converter |
| `framework/src/act/fcov/testbench.sv` | Tracefile key parser |
| `framework/src/act/fcov/riscv_arch_test.sv` | sample hook |
| `config/sail/sail-rv32-max/` | Primary Sail/H config |
| `setup_act4.sh` | Auto-sourced from `~/.bashrc` — cd + Questa + `uv` on PATH (no activate) |
| `env_questa.sh` | Mentor 2021.2_1 PATH + `~/questasim/questasim/license.dat` |

## Tests
| Path | Notes |
|------|-------|
| `tests/priv/<Suite>/` | Priv hand + generated `.S` (many `**/*.S` gitignored pattern) |
| `tests/priv/Hact4/cp_smoke.S` | Smoke (M-mode, no VS paging) |
| `tests/priv/Hact4/_park/` | Hung VS-paging hand tests |
| `tests/env/riscv_arch_test.h` | **Keep `#undef H_SUPPORTED` commented** or guest PTs missing |
| `tests/env/rvtest_setup.h`, `rvtest_trap_handler.h` | Macros |
| `tests/rv32*` / `rv64*` | **Generated — do not hand-edit** |

## Coverpoints
| Path | Edit? |
|------|-------|
| `coverpoints/priv/*_coverage.svh` | Yes (hand) |
| `coverpoints/unpriv/` | No — regenerate via covergroupgen/CSV |
| `coverpoints/coverage/` | **No** — glue only (`RISCV_coverage_{config,base_init,base_sample}.svh`, `RISCV_instruction_sample.svh`) |
| `coverpoints/general/` | Shared helpers / standard CPs |

## Work artifacts
| Kind | Path |
|------|------|
| ELFs | `work/<cfg>/elfs/…` |
| Coverage suite dir | `work/sail-rv32-max/coverage/priv/<Suite>/` |
| Reports | `work/<cfg>/reports/` |
| Logs | `work/<cfg>/summary.log`, `logs/` |

## Generators
| Path | Role |
|------|------|
| `generators/coverage/` | `covergroupgen` |
| `generators/testgen/` | unpriv CSV + priv generators |
| `testplans/*.csv` | Unpriv coverpoint plans |

## Parent-repo status tracker
| Path | Notes |
|------|-------|
| `../SvH Sail Testing Status.xlsx` | Human-readable sheets: **Start here** / **Every test** / **Words we use**. **2026-08-11** sync: **76** `.S` 1:1 disk; licensed Questa RV32 **99.29%** (552/555) / RV64 **99.39%** (817/820). Partial = VSBE only (both endian ELFs). |
| `/home/ahsan-10xe/Downloads/SvH Sail Testing Status latest.xlsx` | P0–P4 tracker (Summary / Status Detail / Legend). **2026-08-11:** de-duped/twin-adjacent + JK symmetry; **76** `.S` 1:1 disk; Latest **99.29% / 99.39%**; Partial = VSBE only. **Both** status xlsx files are current at these %. |

## Related
- [[03-File-Index]] is this note · [[05-Coverpoints-Layout]]
