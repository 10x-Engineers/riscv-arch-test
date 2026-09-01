# Host environment — Sail & Questa (this machine)

> Update this note when tools/licenses change. Agents must verify with `which` / version, not assume.

## Sail
| Item | Value |
|------|-------|
| Binary | `~/.local/bin/sail_riscv_sim` |
| Version | **v0.13** |
| Source branch | [nadime15/sail-riscv `hypervisor`](https://github.com/nadime15/sail-riscv/tree/hypervisor) |
| Config | `config/sail/sail-rv32-max/sail.json` (H-enabled for Sail 0.13) |

## Toolchain
- `riscv64-unknown-elf-gcc` present on this host
- Python via `~/.local/bin/uv` → Make `uv run act` (no `.localenv` activate)
- New terminals: `~/.bashrc` → `setup_act4.sh` → cd + Questa + uv PATH

## Questa — Mentor/Siemens 2021.2_1 ONLY
| Item | Value |
|------|-------|
| Install | `~/questasim/questasim/` |
| vsim | `…/bin/vsim` or `…/linux_x86_64/vsim` |
| Project env | `riscv-arch-test/env_questa.sh` |
| License | **only** `~/questasim/questasim/license.dat` |

### Do not use (FPGA / Starter — out of scope)
- `~/Downloads/questa-starter-official/` (installer + its `lic/license.dat`)
- `~/intelFPGA_pro/` / `questa_fse`
- Any `LM_LICENSE_FILE` pointing at Starter/FPGA licenses

### Verify before coverage
```bash
source env_questa.sh
echo $LM_LICENSE_FILE   # must be .../questasim/questasim/license.dat
which vsim && vsim -version
vsim -c -do "quit -f"
```

**Never** assist with cracked/pirate Questa or license bypass.

## Related
- [[07-Known-Facts-Do-Not-Invent]] · [[04-Workflows-Commands]]
