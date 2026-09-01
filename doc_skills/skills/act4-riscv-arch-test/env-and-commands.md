# Where things live + how to run tests

Work in the `riscv-arch-test/` folder.

## Folders (what each one is for)

| Folder | What it is |
|--------|------------|
| `config/sail/sail-rv32-max/` | Main settings for 32-bit Sail runs (has Hypervisor) |
| `tests/priv/` | Test source files (`.S`) |
| `tests/env/` | Shared macros (setup, traps) |
| `coverpoints/priv/` | Coverage checks we write by hand |
| `framework/` | Build tools, Sail→short trace, coverage testbench |
| `generators/` | Tools that build tests and covergroup glue |
| `work/` | All outputs (ELFs, logs, coverage reports) |

You do **not** need to activate `.localenv`. Make already uses `uv run`.

## Config folder must have

These files live under each Sail config (example: `config/sail/sail-rv32-max/`):

- `test_config.yaml`
- UDB yaml
- `rvmodel_macros.h`
- `link.ld`
- `sail.json`
- `rvtest_config.h`
- `rvtest_config.svh`
- optional `run_cmd.txt`

How Sail is started for `sail-rv32-max`:

```
sail_riscv_sim {debug:--trace --trace-output __TRACEFILE__} --config config/sail/sail-rv32-max/sail.json
```

## Make options (copy what you need)

| Option | Plain meaning |
|--------|----------------|
| `CONFIG_FILES=` | Which config builds the ELFs |
| `COVERAGE_CONFIG_FILES=` | Which config runs coverage |
| `EXTENSIONS=` | Which test suite to run (example: `SvH`) |
| `EXCLUDE_EXTENSIONS=` | Suites to skip. Default skips `Sm`. To run Sm, set this empty. |
| `COVERAGE_SIMULATOR=` | `questa` (usual) or `vcs` |
| `DEBUG=True` | Extra debug logs |
| `FAST=True` | Skip objdump (faster) |
| `JOBS=1` | Run one job at a time (use if it hangs or traces get huge) |

### Example commands

```bash
# Build ELFs
make elfs \
  CONFIG_FILES=config/sail/sail-rv32-max/test_config.yaml \
  EXTENSIONS=SvH EXCLUDE_EXTENSIONS=Sm JOBS=1

# Run coverage
make coverage \
  COVERAGE_CONFIG_FILES=config/sail/sail-rv32-max/test_config.yaml \
  EXTENSIONS=SvH EXCLUDE_EXTENSIONS=Sm \
  COVERAGE_SIMULATOR=questa JOBS=1 FAST=True
```

## Did the test pass?

Look in the log under `work/.../coverage/...`:

- Pass: `RVCP-SUMMARY: TEST PASSED - Test File "<name.S>"`
- Fail: `TEST FAILED`
- `SIGRUN`: only making a signature (not a full self-check)

## If something is wrong — check in this order

1. Tools on PATH? `which uv sail_riscv_sim riscv64-unknown-elf-gcc`
2. Coverage needs a real Questa: `which vsim` and a valid license
3. Build errors? Look in `work/<config>/build/`
4. Sail hangs or `.trace` files are huge? Use `JOBS=1`
5. Empty or bad `.rvvi`? Fix the Sail→short-trace step before blaming coverpoints
6. Wrong `EXTENSIONS=`? Wrong suite = wrong coverage group turned on

## Questa on this machine

```bash
# Usually set by setup_act4.sh, or:
#   source env_questa.sh
# QUESTA_HOME → ~/questasim/questasim
# LM_LICENSE_FILE → ~/questasim/questasim/license.dat
# Do NOT use the Intel FPGA starter license under Downloads.
which vsim && vsim -version
```

More host notes: vault `06-Host-Env-Questa.md`.

## Other work in this repo (different skill)

- Spreadsheet / norm work → skill `act4-hypervisor`
- This run/coverage work → vault `obsidian-vault/ACT4-riscv-arch-test/00-MOC-Index.md`
