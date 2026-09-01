# Test-generation lifecycle (detail)

Use this after `SKILL.md`. Each phase has an exit condition. If the exit is already true, skip.

## 0. Plan document (Phase 1 — before Python)

**When:** New or refreshed coverpoint sheet (e.g. `Hypervisor (10x) - Gap Highlighted.xlsx` / `.csv`) drives a new priv suite or major SvH extension.

**Agent flow:**

1. **`explore`** — read csv/xlsx rows, `hypervisor-10x-test-plan.json`, grep existing `generate_*` / coverpoints.
2. **`act4-hypervisor`** — canonical norm IDs; gap vs xlsx.
3. **Main agent** — draft `riscv-arch-test/docs/<Suite>-Testgen-Plan.md` and, for human approval, a short Implementation Readme (SvH pattern: `docs/SvH-Implementation-Readme.md`):
   - One subsection per planned test (stem, `generate_*` name, family file).
   - **Required default shape for every stem** (plain English, not Python line numbers):
     - **What:** one sentence — what this test is
     - **Why:** one sentence — why we run it (coverage / ISA)
     - **How:** ordered plan steps — setup maps → enter mode → stimulus → return → SIGUPD / check
   - Coverpoint id(s) per test; case count; privilege + paging matrix.
   - Map to family module (`*_twostage.py`, `*_csr.py`, …) like SvH split.

**Exit:** Every stem has What/Why/How; **user explicitly approves** (or edits plan in review). Incomplete How steps = plan not done.

**Do not:** write `generators/testgen/.../*.py` or update Walkthrough until plan approved.

## 0b. Codebase walkthrough (Phase 3 — after code)

**When:** Generators registered, `make testgen` produces `.S`, validation run (or best-effort on Starter Questa).

**Write:** `riscv-arch-test/docs/<Suite>_Testgen_Codebase_Walkthrough.md` — per-test chapters with Python line cites, asm spine, SIGUPD timeline, coverpoint map, MISSING DEPENDENCY labels (copy SvH T01–T39 structure).

**Exit:** Every `_SCENARIOS` stem has a walkthrough chapter synced to live code.

## 1. Specification analysis

- Privileged / hypervisor: `riscv-spec.md` (Ch.5 hypervisor), Priv ISA. Quote the clause that the test must make true or false.
- Unpriv: instruction encoding + `testplans/<suite>.csv` column meaning.
- Exit: one-sentence architectural claim + privilege mode + translation stages involved.

## 2. Reading (repo + vault, not memory)

Order:

1. `obsidian-vault/ACT4-riscv-arch-test/07-Known-Facts-Do-Not-Invent.md`
2. `riscv-arch-test/AI_CONTEXT_SUMMARY.md`
3. Matching plan + walkthrough (`docs/<Suite>-Testgen-Plan.md` first; `docs/<Suite>_Testgen_Codebase_Walkthrough.md` if code exists)
4. Live generator + one generated `.S` of the closest test

Exit: list of files that already implement or almost implement the claim.

## 3. Norm-rule mapping

- Canonical IDs only: `norm-rules.html` (`norm:hstatus_sz_acc_op`).
- Coverpoint row: `hypervisor-10x-test-plan.md` / `.json` / xlsx sheet (SvH-US Col A, Normative Rule col as in `act4-hypervisor`).
- If xlsx gap: use `act4-hypervisor` pipeline; do **not** invent norms inside the generator.

Exit: `(coverpoint_id, norm_id, sheet)` or explicit “no xlsx row — directed ISA test”.

## 4. Repository exploration (avoid redundant work)

Search before coding:

```text
generate_<stem>   _SCENARIOS   coverpoint=   cp_<name>
tests/priv/<Suite>/*.S
coverpoints/priv/<Suite>_coverage.svh
```

If an existing ELF already hits the bin, report stem + coverpoint map; do not duplicate.

Exit: “extend `<file>:<fn>`” or “new stem in `_SCENARIOS`” or “already covered”.

## 5. Test-case design

- Directed cases; permission matrices copy existing case counts (do not explode XWR).
- Each case: title, expected (Successful | Expected Fault), coverpoint id, access (`lw`/`sw`/`jalr`/`hlv`/`hsv`/`csrr*`), paging (vsatp/hgatp Bare/ON), hop.
- SIGUPD: one dump per observable; `SIGUPD_COUNT` = exact dumps (twin = **max**, not sum).

Exit: numbered case table that could be pasted as `// Test case N:` banners.

## 6. Generator implementation

**SvH:** add `generate_*` in the matching family (`SvH_twostage|csr|perm|fault|misc.py`), helpers in `SvHCommon.py` if shared, register tuple in `SvH.py` `_SCENARIOS`. Twins via `build_twins`.

**Other priv:** copy the suite’s existing `make_*` + Common module (Zawrs, Exceptions, Sdtrig, Interrupts). Decorator `@add_priv_test_generator("Suite", required_extensions=[...], extra_defines=[...])`.

**Unpriv:** add/adjust CSV row + registered coverpoint generator; never write `tests/rv32*` by hand.

SPDX header on new files. Trailing comments on generated asm if that suite already does.

## 7. Test generation

```bash
cd riscv-arch-test
# Make uses uv run — do not source .localenv unless the user already did
make testgen EXTENSIONS=<Suite> EXCLUDE_EXTENSIONS=Sm JOBS=1
```

Diff the new/changed `tests/priv/<Suite>/*.S`. If stamp hides changes: `make clean-tests` then testgen (this **deletes** generated SvH `.S`).

## 8. Validation

```bash
export PATH=/opt/riscv-gcc-15/bin:$PATH   # GCC ≥15 on this host
make elfs CONFIG_FILES=config/sail/sail-rv32-max/test_config.yaml \
  EXTENSIONS=<Suite> EXCLUDE_EXTENSIONS=Sm JOBS=1 FAST=True
make coverage COVERAGE_CONFIG_FILES=config/sail/sail-rv32-max/test_config.yaml \
  EXTENSIONS=<Suite> EXCLUDE_EXTENSIONS=Sm COVERAGE_SIMULATOR=questa JOBS=1 FAST=True
```

RV64/Sv39: `sail-rv64-max` when the test is Sv39-only.

Pass/fail: `work/<cfg>/coverage/priv/<Suite>/<test>.log` (`TEST FAILED` / `TEST PASSED`). Not `build/*.sig.log`.

Coverage sampling: licensed `vsim`/`vcs` + UCDB. Starter: compile/Sail only.

## 9. Coverage writing + review

- Hand-write bins/crosses in `coverpoints/priv/<Suite>_coverage.svh`.
- Glue: `make covergroupgen` / `make coverage` regenerates `coverpoints/coverage/*` — do not edit those.
- Review checklist: hop vs VA≠PA; SIGUPD mode; PTE leaf vs non-leaf (`R/W/X` vs `PTE_V` only); G-stage U=1; `hfence` after PTE rewrite; coverpoint name in SIGUPD label matches `SvH_cg` / suite cg.

Exit: generator + `.S` + coverpoint ids agree; validation evidence cited; vault updated if facts changed.
