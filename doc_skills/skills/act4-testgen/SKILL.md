---
name: act4-testgen
description: >-
  Use when generating, extending, or repairing ACT4 architectural tests
  (SvH, ExceptionsH, Hact4, Zawrs*, Interrupts*, Sm/S/U priv suites, unpriv
  CSV testplans), writing coverpoints, mapping xlsx/norm-rules to generators,
  implementing testgen Python, regenerating tests/priv/*.S, or running
  make testgen. Use for new test cases, generator bugs, and covergroup bins
  that need a matching ELF.
---

# ACT4 test generation (agentic lifecycle)

Autonomous end-to-end: spec → read → norms → repo reuse → case design → generator → `make testgen` → validate → coverpoints + review. Ask the user **only** when a decision cannot be reasonably inferred from files, vault, and prior tests.

**Do not hand-edit generated `.S`.** SoT is Python (priv) or CSV+coverpoint generators (unpriv).

## Skills to load with this one

| Need | Skill |
|------|--------|
| Sail / `.rvvi` / Questa / UCDB | `act4-riscv-arch-test` |
| xlsx / `norm-rules.html` / gap scripts | `act4-hypervisor` |
| Substantial work | `unlazy` (gates before claiming done) |

ACT4 paths/commands in those skills **win** over Superpowers.

## Infer vs ask

**Infer (do not ask):** suite name from path/`EXTENSIONS`; copy nearest family helper; hop macros from existing SvH/Zawrs; `SIGUPD_COUNT` = exact dump count; RV32 vs RV64 from existing twins / `#ifdef SV32_SUPPORTED`; coverpoint id from `*_coverage.svh` + xlsx Col A; skip work already covered by an existing `generate_*` or live `.S`.

**Ask (blocking):** new suite name vs stuffing into an existing suite; WARL/illegal encodings with no spec/xlsx rule; changing trap handler / `riscv_arch_test.h`; claiming licensed coverage on Starter Questa; deleting parked tests; wiring upstream RVVI into ACT4.

## Lifecycle (do in order; skip a phase only with evidence)

Read [lifecycle.md](lifecycle.md) + [reuse-map.md](reuse-map.md). Short form:

**Documentation phases (priv suites from xlsx/csv):**

0. **Plan doc** — write `docs/<Suite>-Testgen-Plan.md` (and/or `<Suite>-Implementation-Readme.md` for review). **Required per test before any Python:** **What** (what it is) · **Why** (why we need it) · **How** (ordered plan steps: setup → mode → stimulus → check → SIGUPD). Also: stem, coverpoint map, family file, case count. Template: `docs/SvH-Implementation-Readme.md`. **Wait for user approval.**
0b. **Walkthrough doc** — write `docs/<Suite>_Testgen_Codebase_Walkthrough.md` **after** code + testgen validate (SvH: T01–T39 style).

1. **Spec** — Privileged ISA + hypervisor Ch.5 (`riscv-spec.md`). Cite the rule, not a guess.
2. **Read** — vault `07-Known-Facts-Do-Not-Invent.md`, `AI_CONTEXT_SUMMARY.md`, `<Suite>-Testgen-Plan.md`, nearest existing generator + `.S`.
3. **Norms** — canonical `norm:...` from `norm-rules.html` / `hypervisor-10x-test-plan.md`. Map coverpoint ↔ norm. Never invent `norm:csr:*:reg`.
4. **Explore** — search `generate_*`, `_SCENARIOS`, `coverpoints/priv/<Suite>_coverage.svh`. If a test already proves the bin, **stop** and report the stem.
5. **Design** — directed cases (not full XWR explosion). One observable per case: allow vs fault vs WARL readback. Privilege + paging explicit (VS/VU/HS/M, vsatp/hgatp Bare/ON).
6. **Implement** — extend existing family file; register in `_SCENARIOS` (SvH) or `make_*` loop. Reuse `*Common.py`. Match `.S` style of that suite (banners, SIGUPD, hops).
7. **Generate** — from `riscv-arch-test/`:
   ```bash
   make testgen EXTENSIONS=<Suite> EXCLUDE_EXTENSIONS=Sm JOBS=1
   ```
   Confirm `tests/priv/<Suite>/` output. `make clean` / `clean-tests` drops generated SvH `.S`.
8. **Validate** — `make elfs` then `make coverage` with the suite (see `act4-riscv-arch-test`). Grep `work/<cfg>/coverage/priv/<Suite>/<test>.log` for `TEST FAILED`. `*.sig.log` is **not** self-check. Starter Questa: ELF/Sail OK; **no** UCDB claim.
9. **Coverage + review** — edit `coverpoints/priv/<Suite>_coverage.svh` only. **Never** `coverpoints/coverage/*`. Ids in generator SIGUPD metadata must match `cp_*` / coverpoint names. Self-review: unused bins, wrong hop, SIGUPD under MPRV, VA≠PA return via `RVTEST_GOTO_MMODE`.

## Hard rules

- Priv: `generators/testgen/src/testgen/priv/extensions/` + `@add_priv_test_generator("Suite", ...)`. Discovery skips `_*.py`.
- Unpriv: `testplans/<suite>.csv` + coverpoint generators — not priv Python.
- Suite dir name → `+define+<SUITE>_COVERAGE` (`SvH` → `SVH_COVERAGE`).
- VS paging ON: stimulus in guest, SIGUPD from M. Clear MPRV before SIGUPD if signature is not mapped.
- Do not patch `tests/env/rvtest_trap_handler.h`.
- No cracked Questa. Update vault + `AI_CONTEXT_SUMMARY.md` when durable facts change.
