# Architecture — End-to-end pipeline

## One diagram
```
.S (tests/priv|unpriv|…)
  → GCC → ELF / sig.elf
  → sail_riscv_sim --trace → *.trace          (verbose Sail log)
  → sail_to_rvvi.sailLog2Trace() → *.rvvi     (short Tracefile)
  → <Suite>.tracelist (list of .rvvi paths)
  → vsim +testbench.sv +traceFileList=…
       → rvviTrace → coverage.sample()
       → *.ucdb → work/<cfg>/reports/
```

**Questa does not execute the RISC-V ELF.** Sail does. TB only replays `.rvvi`.

## Who produces what
| Artifact | Producer | Consumer |
|----------|----------|----------|
| `*.trace` | `sail_riscv_sim --trace-output` | `sail_to_rvvi.py` only |
| `*.rvvi` | `framework/src/act/sail_to_rvvi.py` | `fcov/testbench.sv` |
| `*.tracelist` | ACT `build_plan` | `+traceFileList=` |
| `*.ucdb` | licensed `vsim` covergroup sample | coverreport / GUI |

## Converter limits (do not claim otherwise)
`sail_to_rvvi.py` today emits: `ORDER PC INSN MODE` + optional `X`/`F`/`V`/`CSR`.
**TODO / often missing:** traps, interrupts, `MODE_VIRT`, VM keys.
TB `case(key)` accepts more keys than converter emits — empty ≠ unsupported forever.

## Covergroup enable
`EXTENSIONS=<Suite>` → compile define `<SUITE>_COVERAGE` (uppercased suite name) → includes from `coverpoints/coverage/RISCV_coverage_config.svh` → real bins in `coverpoints/priv|unpriv/<Suite>_coverage.svh`.

## Related
- [[05-Coverpoints-Layout]] · [[04-Workflows-Commands]] · skill `tracefile-rvvi.md`
