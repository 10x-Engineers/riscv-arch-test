# Workflows & Commands

## Always first
```bash
# New terminal only — ~/.bashrc → setup_act4.sh (cd + Questa + uv).
# No cd / activate / source needed. Make uses: uv run act …
```

## Coverage (suite-level only)
```bash
make coverage \
  COVERAGE_CONFIG_FILES=config/sail/sail-rv32-max/test_config.yaml \
  EXTENSIONS=Hact4 EXCLUDE_EXTENSIONS=Sm \
  COVERAGE_SIMULATOR=questa JOBS=1 FAST=True
```

| Knob | Fact |
|------|------|
| `EXTENSIONS=` | Suite dir name under `tests/priv/` or unpriv suite |
| `EXCLUDE_EXTENSIONS=` | **Defaults include `Sm`** — use empty to run Sm |
| Cannot | Select a single coverpoint bin (e.g. only `cp_hedeleg`) via Make |

## ELFs only
```bash
make elfs \
  CONFIG_FILES=config/sail/sail-rv32-max/test_config.yaml \
  EXTENSIONS=Hact4 EXCLUDE_EXTENSIONS=Sm JOBS=1
```

## Regenerate generated tests/cover glue
```bash
make clean-tests tests
# or covergroupgen via Make targets — do not hand-patch coverpoints/coverage/
```

## After a good licensed run
```bash
less work/sail-rv32-max/reports/<Suite>_summary.txt
less work/sail-rv32-max/reports/<Suite>_uncovered.txt
vsim -viewcov work/sail-rv32-max/coverage/priv/<Suite>/<Suite>.ucdb
```

## Triage order
1. Env: `which act sail_riscv_sim riscv64-unknown-elf-gcc vsim`
2. Assemble/link under `work/<cfg>/build/`
3. Sail hang / huge `.trace` → `JOBS=1`, park VS-paging tests, consider inst-limit hacks only if documented
4. Empty/short `.rvvi` / missing `MODE_VIRT` before blaming bins
5. Wrong `EXTENSIONS` → wrong `*_COVERAGE` define
6. Starter Questa: TB may compile but **covergroup sample fails** — see [[06-Host-Env-Questa]]

## Related
- [[02-Architecture-Pipeline]] · [[07-Known-Facts-Do-Not-Invent]]
