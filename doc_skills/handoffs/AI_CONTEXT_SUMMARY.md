# AI context summary — riscv-arch-test

> Living handoff for agents. Prefer this + vault over chat memory.
> Vault: `../obsidian-vault/ACT4-riscv-arch-test/00-MOC-Index.md`
> Skills: `act4-riscv-arch-test` (run/coverage), `act4-testgen` (generate/extend tests)
> Human flow: `readme_coverpoint_flow.md`
> Updated: **2026-08-31** (doc_skills plug-in: install.sh / PLUGIN.md / AGENTS.md)

## Auto-update policy
Agents **must** refresh this file + vault facts in the same turn when durable work lands. Never ask the user for permission. Protocol: vault `08-Agent-Memory-Protocol.md`.

## Mission
Run ACT4 Sail→RVVI→covergroup coverage for priv/hypervisor-related suites on this checkout.

## Hard facts
| Fact | Detail |
|------|--------|
| TB input | `*.rvvi` from `sail_to_rvvi.py`, **not** `*.trace` |
| Primary config | `config/sail/sail-rv32-max/` (+ `sail-rv64-max/` for Sv39) |
| Sail | `~/.local/bin/sail_riscv_sim` v0.13, nadime15 `hypervisor` branch |
| Sail config | ACT4 max + Sail 0.13 H schema fields; **do not** wholesale-replace `sail-rv64-max/sail.json` with Sail defaults |
| Questa | Mentor/Siemens **2021.2_1** at `~/questasim/questasim` via `env_questa.sh` / `setup_act4.sh`; license **only** `$QUESTA_HOME/license.dat`. Never use `questa-starter-official` / Intel FPGA. If `vsim: No such file` → scripts missing or not sourced. |
| Glue | Never edit `coverpoints/coverage/*` |
| H enable | Keep `#undef H_SUPPORTED` commented in `tests/env/riscv_arch_test.h` |
| Trap handler | **Do not edit** `tests/env/rvtest_trap_handler.h` (reverted to git HEAD 2026-08-12). `actual_tramp_sz` is HEAD `+9+5`. |
| HS EPC advance | When `hstatus.SPV=1`, use `hlvx.hu` to read guest sepc halfword |
| `sv32` define | `#define sv32 0x10` in `tests/env/rvtest_macros.h` (≠ `sv39` which is `0`) |
| Permissions | Never `sudo make` / `sudo make clean` — leaves `work/` and generated trees root-owned |
| Compiler | This tree needs **GCC ≥15** (`/opt/riscv-gcc-15`, 16.1.0). Host 13.2 fails `check_compiler_version`. `export PATH=/opt/riscv-gcc-15/bin:$PATH` (or `gcc15`) before Make |
| SvH on disk | **39** generated chunks: `tests/priv/SvH/SvH_<stem>-00.S` (one file per explicit `_emit(...)` in `SvH.py`; Sv32+Sv39 under `#ifdef` in each file) |
| SvH SoT | Python emitters: `SvH.py` (39× `_emit(...)`) + `SvHCommon.py` + `SvH_{twostage,csr,perm,fault,misc}.py`. Regenerate: `make testgen EXTENSIONS=SvH EXCLUDE_EXTENSIONS=Sm`. Do **not** hand-edit output. |
| SvH testgen docs (3 phases) | **Phase 1:** `docs/SvH-Testgen-Plan.md` + `docs/SvH-Implementation-Readme.md` (**What/Why/How required per test** before Python). **Phase 2:** edit `SvH*.py` + `make testgen`. **Phase 3:** `docs/SvH_Testgen_Codebase_Walkthrough.md`. Team demo: `../docs/DV-Monthly-AI-Agent-Stack-and-Testgen-Demo-Plan.md` §4. |
| SvH `.S` header style | `Coverpoints mapped (SvH_cg):` + ids; `// What this proves (one line):`; numbered case list when applicable; in-body `// Test case N:` banners for numbered cases; trailing `//` on active lines; `#define` `\` continuations use `/* */` not `//`. Legacy human review notes: `SvH_REVIEW_WALKTHROUGH.md` (pre-Python layout). |
| SvH SIGUPD | Dump **side-by-side with each case**. HS/Bare may dump in lower mode. **VS with paging ON:** stimulus in VS → return to M → SIGUPD (signature not guest-mapped). CSR walks may dump each iter from HS. `SIGUPD_COUNT` = exact dump count (incl. walk iters). |
| SvH T-SBI | **Return from VA≠PA guest:** `RVTEST_GOTO_MMODE` (a0=0 → `rtn2mmode` VA→PA). Stock `RVTEST_TSBI_GOTO_MMODE` (a0=1) breaks at GVA in M — **do not patch trap handler**. Enter: T-SBI VS/S if PA/identity; `GOTO_LOWER_MODE` if `V_SAVE_AREA_SETUP`. |
| SvH MPRV + SIGUPD | **Clear `MPRV` before any SIGUPD** whose effective mode would translate the signature address (e.g. `vsatp` maps only `va_s`/`va_u`). Re-set MPRV at the start of the next case. `mprv_hgatp_*` is unaffected — G-stage map still reaches the signature. |
| Verifying a test really passes | `*.sig.log` under `build/` is only the **signature-generation** run (stores, never compares) — it says SUCCESS even when self-check would fail. The real self-check runs are `work/<cfg>/coverage/priv/<Suite>/<test>.log`; grep for `TEST FAILED`, or just run `make coverage`. |
| Graphify | Repo-root `graphify-out/` (`GRAPH_REPORT.md`, `graph.json`). Built **2026-08-25** via `graphify update . --force` (~123k nodes / 162k edges; HTML skipped — too large). Query: `graphify explain "…"`. |
| Shareable agent pack | `.cursor/doc_skills/` — plug-in for anyone: `PLUGIN.md`, pack `AGENTS.md`, `./install.sh link /path/to/ACT4`, `prompts/bootstrap.md` |

## Hact4 suite (Sail-tuned, all PASS)
| Test | Role |
|------|------|
| `cp_smoke.S` | M/H CSR smoke |
| `hsv_instrs_HSmode.S` | Legal HSV.W/H/B in HS (no deliberate faults) |
| `vsatp_sv32_invalid_pte_VSmode.S` | VS invalid leaf V=0 → page faults skipped |
| `sv32x4_pte_perms_VSmode.S` | G-stage no-U faults + U=1 success |

## SvH status (directed FC + Python testgen)
| Item | Detail |
|------|--------|
| Verdict | **P0 + directed P1 FC Cleared** on licensed Questa (2026-08-11 write_acc pad; 2026-08-17 emitter gate). Not full theoretical `SvH_cg` cross product — **VSBE=1** remains Sail Partial only. |
| Coverage (emitter gate) | RV32 **99.66%** (574/575); RV64 **99.71%** (888/889). Only miss: `vsbe_hstatus.set` — Sail `legalize_hstatus`. Reports: `work/sail-rv{32,64}-max/reports/SvH_uncovered.txt`. |
| ELFs | **39** `SvH_*-00.S` on disk; each may contain both `#ifdef SV32_SUPPORTED` and `#ifdef SV39_SUPPORTED` twins. |
| Sheet map | Gap Highlighted `SvH` tab = coverpoint SoT; implementation tracker: `SvH_Coverage_Implementation_Plan.md`; repo-root status xlsx (**39** rows 1:1 with Python stems — legacy **76**-row twin-split inventory is historical only). |
| Gap Highlighted audit (2026-08-11) | **54** Col-A CPs + **7** `***` notes. Waive: `cp_vsatp_speculative_a_bit`. Residual hole: VSBE Sail only. |

### Key historical closes (still true for bins; filenames were pre-Python `svh_*`)
- **VM_permission write_acc (2026-08-11):** `twostage_invalid` cases 3–4 VS `sw` cleared write_acc holes.
- **OUR-side pad (2026-08-07):** mxr_sum / spages / reserved fields largely cleared RV32+RV64; adbit rewritten 2026-08-10 (VS implicit G A/D, not HS HLV).
- **RV64 twin pass (2026-08-07):** hfence*, g_perm, faults, mprv_sum, xonly, vu_rwx, etc. — now folded into **39** Python twins via `build_twins`.
- **Sail-only remain:** VSBE (`legalize_hstatus`); do not fake.

`Hact4_cg` historically **80%** — miss was `cp_hsv` hsv_w/h/b on Hact4 path (HSV often omitted in `.rvvi`).

## sail.json notes
| Config | Keep |
|--------|------|
| `sail-rv32-max` | H + schema adds OK; MainMemory `supports_pte_*=true`; `physaddr_bits` 34 |
| `sail-rv64-max` | Keep ACT4 values (`vlen_exp` 10, bitmanip/AMO on, PMP 64); **surgical** H/schema only — never Sail-default replace |

## Commands
Open a **new** terminal — `~/.bashrc` → `setup_act4.sh` (cd + Questa + `uv` on PATH). **No** `.localenv` activate; Make uses `uv run act`.

```bash
export PATH=/opt/riscv-gcc-15/bin:$PATH   # required — GCC ≥15
source setup_act4.sh                      # Questa on PATH

# Regenerate SvH assembly (after editing SvH*.py)
make testgen EXTENSIONS=SvH EXCLUDE_EXTENSIONS=Sm JOBS=1

# RV64 SvH coverage
make coverage COVERAGE_CONFIG_FILES=config/sail/sail-rv64-max/test_config.yaml \
  EXTENSIONS=SvH EXCLUDE_EXTENSIONS=Sm COVERAGE_SIMULATOR=questa JOBS=1 FAST=True

# RV32 SvH coverage
make coverage COVERAGE_CONFIG_FILES=config/sail/sail-rv32-max/test_config.yaml \
  EXTENSIONS=SvH EXCLUDE_EXTENSIONS=Sm COVERAGE_SIMULATOR=questa JOBS=1 FAST=True

# Hact4 smoke path
make coverage COVERAGE_CONFIG_FILES=config/sail/sail-rv32-max/test_config.yaml \
  EXTENSIONS=Hact4 EXCLUDE_EXTENSIONS=Sm COVERAGE_SIMULATOR=questa JOBS=1 FAST=True
```

## Blockers
1. Prefer a legal Siemens license for ongoing use; crack/`pubkey_verify` is out of scope for agents
2. Full SvH_cg needs many more PTE/mode crosses than current bring-up tests hit
3. If `Permission denied` on `work/` or `tests/rv32i/*`: tree was root-owned — `sudo chown -R "$USER:$USER" .` (never leave `sudo make` artifacts)
4. ~~2026-08-05 SvH MPRV/SIGUPD failure~~ — **fixed** (see MPRV rule in Hard facts)

## Do not
- Crack/pirate licenses
- Claim bin hits without UCDB/reports
- Hand-edit `coverpoints/coverage/` or generated `tests/priv/SvH/*.S`
- Re-park Hact4 tests (they PASS on this Sail now)
- Confuse with `act4-hypervisor` xlsx pipeline (different workstream)
- Replace `sail-rv64-max/sail.json` wholesale with Sail defaults
- Assume **76** `.S` files on disk — count is **39** Python-generated chunks
