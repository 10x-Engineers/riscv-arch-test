# SvH directed-test review walkthrough

**Audience:** teammates reviewing `tests/priv/SvH/*.S`  
**Date:** 2026-08-11  
**Scope:** clarity / structure only — **same cases, same coverpoints, same Sv framework**

---

## What stayed the same (Sv framework)

SvH still mirrors `tests/priv/Sv/`:

| Piece | Same as Sv |
|-------|------------|
| Header | Numbered case list + expected outcomes |
| Config | `START_TEST_CONFIG` / `MARCH` / `REQUIRED_EXTENSIONS` |
| Body | `RVTEST_BEGIN` → `main:` → PTE setup → cases → `RVTEST_CODE_END` |
| Checks | Per-case `RVTEST_SIGUPD` + mismatch `.string`s |
| Mode hops | `GOTO_LOWER_MODE` / T-SBI enter; **return always** `RVTEST_TSBI_GOTO_MMODE` |
| Paging SIGUPD | VS with paging ON → return to M before SIGUPD |
| Line comments | Trailing `//` on insn/macro/`.set`/data lines; `#define \` bodies use `/* */` |

**Do not invent a new test architecture.** H/T-SBI and two-stage PTE macros are the only SvH-specific adaptations.

---

## What we simplified (before → after intent)

| Before (pain) | After (intent) |
|---------------|----------------|
| Flat `main:` — addresses, PTEs, fences, cases mixed | **Sv-style section banners** in fixed order (below) |
| Same long T-SBI essay on every GOTO/SIGUPD line | **One Mode-hops blurb** at top; short `// M→VS` / `// →M (T-SBI)` on hops |
| Bare `//-----` with no case title (e.g. twostage_invalid) | **`// Test case N: … \| Expected: …`** matching the header list |
| Nested “bin: urwx…” noise under every case | Optional short `// Coverpoints: cp_…` only where useful; **header case list is SoT for review** |
| “sheet rule” / xlsx jargon in comments | Removed — coverpoint ids + one-line prove statement only |
| DATA region unlabeled | Banners: **physical region / page-table storage / mismatch strings** |

**Not changed:** instruction sequences, PTE bit choices, SIGUPD counts, privilege paths, coverpoint mapping.

---

## How to read one SvH test (section map)

Open any file (gold: `svh_two_stage_rw_VSmode.S` or dense: `svh_hgatp_fault_VSmode.S`) and skim in this order:

```text
1. Header
   - Coverpoints mapped (SvH_cg):   ← what coverage this ELF feeds
   - What this proves (one line):    ← pass/fail story
   - Numbered case list             ← reviewer checklist

2. START_TEST_CONFIG + SIGUPD_COUNT / TRAP_SIGUPD_COUNT

3. Mode hops note (once)

4. main:
   - Virtual addresses / GPA definitions   (.set …)
   - Page-table setup (G and/or VS)
   - Enable translation / TLB fences / preloads
   - Test Cases Start from here
       //----- Test case N: … | Expected: …
       hop → stimulus → hop → SIGUPD

5. DATA
   - PHYSICAL ADDRESS REGION
   - Page-table storage
   - Mismatch strings (SIGUPD)
```

**Case body rhythm (typical):**

```text
(optional PTE rewrite + hfence from M/HS)
sentinel / pointer setup
enter VS/VU/HS
lw|sw|jalr|hlv|hsv + nop pad
return to M (T-SBI)
SIGUPD (expect value or fault sentinel / SPA unchanged)
```

---

## What reviewers should check

Focus here — **not** every `hfence` / `nop`:

1. **Header case list ↔ body case banners** — same N, same allow/fault story  
2. **Coverpoints mapped ↔ cases** — each listed CP id has at least one case that exercises it  
3. **Privilege path** — VS vs VU vs HS vs M-only MPRV matches the CP axis  
4. **SIGUPD meaning** — success value, fault sentinel (0), or SPA unchanged after store-fault  
5. **Paging + SIGUPD** — no SIGUPD while VS paging maps away from `begin_signature`  
6. **G fences** — `hfence.gvma` only from M/HS (never VS/VU)

Skip unless debugging a FAIL: repeated trap-pad `nop`s, identical T-SBI comments, page-table storage `.zero(4096)`.

---

## Intentionally denser files

These stay long because **coverage needs many cases**, not because structure is wrong:

| Files | Why denser |
|-------|------------|
| `svh_vsstatus_mxr_sum_{,sv39_}{VS,VU}mode.S` | ~30+ MXR×SUM×page-type axes — case banners already list each; collapsing would drop bins |
| `svh_vs_perm_{,sv39_}{VS,VU}mode.S` | Large XWR / SUM matrix; kept expanded (Sv-like runner macros would hide PTEs) |
| `svh_vs_pte_attr_RV64_VSmode.S` / `svh_g_pte_attr_RV64_VSmode.S` | RV64 attribute walks — many leaf shapes |

Review those via the **header case list** first, then spot-check 2–3 cases.

---

## Sail smoke (this restructure)

Representative dense set, `PATH=/opt/riscv-gcc-15/bin:$PATH`, `sail-rv32-max`, self-check logs:

| Test | Result |
|------|--------|
| `svh_hgatp_fault_VSmode.S` | TEST PASSED |
| `svh_two_stage_mxr_VSmode.S` | TEST PASSED |
| `svh_two_stage_mxr_VUmode.S` | TEST PASSED |
| `svh_g_perm_VSmode.S` | TEST PASSED |
| `svh_csr_hgatp_fields_HSmode.S` | TEST PASSED |
| `svh_csr_vsatp_fields_HSmode.S` | TEST PASSED |
| `svh_twostage_invalid_VSmode.S` | TEST PASSED |
| `svh_two_stage_rw_VSmode.S` | TEST PASSED |

Full 76-ELF suite not re-run in this pass; structure-only edits + smoke above.

---

## Gold files to compare while reviewing

| Role | File |
|------|------|
| Sv style reference | `tests/priv/Sv/sv32_mstatus_mxr_Smode.S`, `sv32_invalid_pte_Smode.S` |
| SvH simple gold | `tests/priv/SvH/svh_two_stage_rw_VSmode.S` |
| SvH dense gold | `tests/priv/SvH/svh_hgatp_fault_VSmode.S` |
