# Project Overview

## What this is
**ACT4 riscv-arch-test** — build/run RISC-V architectural tests (Sail reference) and sample **functional coverpoints** via RVVI + Questa/VCS.

Orthogonal to parent **Hypervisor (10x) xlsx / norm gap** work (`act4-hypervisor`). Same parent download folder; different skill and vault.

## Goals we care about here
- Compile priv/unpriv `.S` → ELF
- Run on Sail (`sail_riscv_sim` v0.13, hypervisor branch) with `--trace`
- Convert Sail log → short Tracefile `*.rvvi`
- Replay in fcov TB → hit covergroup bins → UCDB + reports

## Primary config (this host)
`config/sail/sail-rv32-max/` — RV32 + H in `sail.json`.

## Python packages (`uv` workspace)
| Package | CLI |
|---------|-----|
| `framework/` | `act` |
| `generators/testgen/` | `testgen` |
| `generators/coverage/` | `covergroupgen` |

## Local venv
Python via **`uv run`** (`~/.local/bin/uv`); no `.localenv` activate. `setup_act4.sh` from `~/.bashrc` sets PATH + Questa.

## Related
- [[02-Architecture-Pipeline]] · [[00-MOC-Index]]
