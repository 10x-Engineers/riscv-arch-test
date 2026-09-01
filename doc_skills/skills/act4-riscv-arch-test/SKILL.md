---
name: act4-riscv-arch-test
description: >-
  ACT4 riscv-arch-test run/coverage workflow — Sail ELF build, short-trace (.rvvi)
  Tracefile→RVVI sampling, Questa/VCS covergroups, Sm/hypervisor priv tests.
  Use when running make elfs/coverage, debugging Sail traces, RVVI testbench,
  coverpoint hits, sail-rv32-max, coverpoints/coverage glue, or tests under
  riscv-arch-test/. Read vault ACT4-riscv-arch-test before inventing facts.
---

# ACT4 riscv-arch-test (run + coverage)

**Root:** `/home/ahsan-10xe/Downloads/ACT4-20260706T103524Z-3-001/riscv-arch-test`

## Memory stack (read in order — anti-hallucination)
1. Vault MOC: `../obsidian-vault/ACT4-riscv-arch-test/00-MOC-Index.md`
2. Vault facts: `…/07-Known-Facts-Do-Not-Invent.md` + `08-Agent-Memory-Protocol.md`
3. Handoff: `AI_CONTEXT_SUMMARY.md`
4. This skill (+ `tracefile-rvvi.md`, `RVVI-for-ACT4.md`, `env-and-commands.md`)
5. Source: `framework/src/act/sail_to_rvvi.py`, `fcov/testbench.sv`

**When durable facts change:** update vault + `AI_CONTEXT_SUMMARY.md` (+ this skill if commands/paths change), then mirror skill to `riscv-arch-test/.cursor/skills/` and `~/.cursor/skills/`.

### Auto-update standing order (no asking)
Do **not** ask the user to update memory. If this chat turn changed durable state (env, suite, blocker, command, license, artifact proof), write the vault/`AI_CONTEXT_SUMMARY.md`/skill updates in the **same turn** before finishing. Protocol: vault `08-Agent-Memory-Protocol.md`.

## Anti-hallucination rules (always)
1. Prefer vault/files over chat memory.
2. Do **not** invent Tracefile keys — only keys in `testbench.sv` `case(key)`.
3. Do **not** claim coverage without verification-licensed `vsim`/`vcs` **and** UCDB/report artifacts.
4. This host’s Questa Starter **cannot** sample covergroups (`svverification`) — TB may still compile.
5. Do **not** hand-edit generated `tests/rv32*`, `coverpoints/unpriv`, `coverpoints/coverage/*`.
6. `EXCLUDE_EXTENSIONS` defaults to `Sm` — clear it when running Sm: `EXCLUDE_EXTENSIONS=`.
7. Suite dir name drives covergroup define (`ExceptionsH` → `EXCEPTIONSH_COVERAGE`). Hand tests in `tests/priv/Sm/` do **not** auto-enable `ExceptionsH` / `SvH`.
8. Refuse cracked/pirate Questa.

## Env (no activate)
New terminals: `~/.bashrc` → `setup_act4.sh` (cd project + Questa + `~/.local/bin/uv`).
Make uses `uv run` — **do not** `source .localenv/bin/activate`.

## Goal pipeline
```
.S → ELF (GCC) → Sail run (--trace) → *.trace
  → sailLog2Trace() → *.rvvi   ← THIS is what TB reads as Tracefile
  → +traceFileList=*.tracelist → testbench.sv → rvviTrace
  → coverage.sample() → *.ucdb → coverreport → work/<cfg>/reports/
```

## Commands (copy exactly)
```bash
# Smoke / Hact4 coverage path (current working suite)
make coverage \
  COVERAGE_CONFIG_FILES=config/sail/sail-rv32-max/test_config.yaml \
  EXTENSIONS=Hact4 EXCLUDE_EXTENSIONS=Sm \
  COVERAGE_SIMULATOR=questa JOBS=1 FAST=True

# Functional ELFs
make elfs \
  CONFIG_FILES=config/sail/sail-rv32-max/test_config.yaml \
  EXTENSIONS=Hact4 EXCLUDE_EXTENSIONS=Sm JOBS=1

# Hypervisor covergroups (suite-level)
make coverage \
  COVERAGE_CONFIG_FILES=config/sail/sail-rv32-max/test_config.yaml \
  EXTENSIONS=ExceptionsH EXCLUDE_EXTENSIONS=Sm JOBS=1
```

## Tracefile what-TB-gets (critical)
- TB plusarg: `+traceFileList=<suite>.tracelist` (paths to `*.rvvi`, **not** raw Sail `*.trace`).
- Format: one retired insn per line, space-separated `KEY VALUE` (X/F/V/CSR take 3 tokens).
- Converter today emits only: `ORDER PC INSN MODE` + optional `X`/`F`/`V`/`CSR`.
- TB also accepts: `TRAP DEBUG_MODE` + interrupt/VM keys — see [tracefile-rvvi.md](tracefile-rvvi.md).
- `sail_to_rvvi.py` emits `MODE_VIRT` + SvH PTE/access keys + **`TRAP`** (fetch-fault → `*_PTE_I`). Still TODO: interrupts, `PHYS_ADR_*` / `PPN_*`.

## Coverpoints layout
| Path | Edit? |
|------|-------|
| `coverpoints/priv/` | Yes — real suite covergroups |
| `coverpoints/unpriv/` | No — regenerate |
| `coverpoints/coverage/` | **No** — covergroupgen switchboard |

## SvH directed tests (`tests/priv/SvH/`)
Every new/edited SvH `.S` header — coverpoint ids only, no sheet/xlsx text:
```
// Coverpoints mapped (SvH_cg):
//   two_stage_write — …
//   two_stage_read  — …
```
Ids match SvH Col A / `SvH_coverage.svh` (`cp_*` or `two_stage_*`).

## Artifact locations
| Kind | Path |
|------|------|
| ELFs | `work/<cfg>/elfs/...` |
| Sail verbose | `work/<cfg>/coverage/.../<test>.trace` |
| Short trace | `work/<cfg>/coverage/.../<test>.rvvi` |
| UCDB | `work/<cfg>/coverage/priv/<Suite>/<Suite>.ucdb` |
| Reports | `work/<cfg>/reports/<Suite>_*.txt`, `_overall_summary.txt` |

## Current Hact4 / env
| Item | Status |
|------|--------|
| `tests/priv/Hact4/cp_smoke.S` | Smoke OK path (no VS paging) |
| `tests/priv/Hact4/_park/` | VS hangers parked |
| `riscv_arch_test.h` `#undef H_SUPPORTED` | Must stay **commented** |

## Tooling checklist
| Tool | Notes |
|------|-------|
| `uv` | `~/.local/bin/uv` — Make uses `uv run` (no `.localenv` activate) |
| `sail_riscv_sim` | **v0.13** `~/.local/bin` — [nadime15/sail-riscv `hypervisor`](https://github.com/nadime15/sail-riscv/tree/hypervisor) |
| `vsim` | Mentor 2021.2_1 via `env_questa.sh`; license only `$QUESTA_HOME/license.dat` — never questa-starter-official |

## Deep refs
- Vault: `obsidian-vault/ACT4-riscv-arch-test/`
- [tracefile-rvvi.md](tracefile-rvvi.md) · [env-and-commands.md](env-and-commands.md)
- `AGENTS.md`, `AI_CONTEXT_SUMMARY.md`, `readme_coverpoint_flow.md`
