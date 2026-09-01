# RVVI and ACT4 — plain map

**Rule:** Prefer official `pte`/`gpte` (`rvvi_mem_access_t`) for new H work. Keep the `ins.current.vs_pte_*` shim until coverpoints are explicitly renamed. Do not claim full RVVI-TEXT compliance yet.

| Thing | Where |
|-------|--------|
| Official RVVI (clone) | `RVVI/` in this repo |
| Deeper RVVI notes | skill `rvvi` |
| ACT4 short-trace notes | [tracefile-rvvi.md](tracefile-rvvi.md) |

---

## What is RVVI?

RVVI is a shared way for RISC-V tools to talk about “what the CPU did.”

It has **4 parts**. Do not mix them up:

| Part | Simple job | Do we use it in ACT4? |
|------|------------|------------------------|
| **TRACE** | Live signals in the simulator (one event per instruction or trap) | Yes — but our copy is **old / changed** |
| **TEXT** | A text file that can replay those events | **No** — our `.rvvi` file is our own format |
| **API** | Compare a design against a golden model | **No** — we use Sail separately |
| **VVP** | Fake UART / timer / etc. | **No** (not ready upstream) |

RVVI is **not** Sail’s long log. Sail still writes `*.trace`. We convert that into something the coverage TB can read.

---

## The big difference (page tables)

### Official RVVI

Page-table info does **not** live on wires named `pte_i` / `VS_PTE_*` / `G_PTE_*`.

It lives in a **memory-access record**:

| Field | Meaning |
|-------|---------|
| `fetch` | 1 = instruction, 0 = data |
| `vaddr` / `paddr` | virtual address / physical address |
| `gaddr` | guest physical address (when Hypervisor is on) |
| `pte` | page-table entry (VS-stage when Hypervisor is on) |
| `gpte` | G-stage page-table entry |

In the official text file that looks like:

```text
MEM D 4 <vaddr> <paddr> 2 PTE <hex> GPTE <hex>
RET <pc> <insn>
```

or `TRAP` instead of `RET` when it trapped.

### ACT4 today

We put page-table values on **our own keys and wires**:

```text
ORDER … PC … INSN … MODE … MODE_VIRT … VS_PTE_D … G_PTE_D …
```

Our `rvviTrace.sv` has extra ports for those. Upstream RVVI 1.7 does **not**.

So: our `.rvvi` file is **inspired by** RVVI names, but it is **not** official RVVI-TEXT.

---

## How ACT4 works today

```
Sail long log (*.trace)
  → sail_to_rvvi.py          (still emits VS_PTE_* / G_PTE_* keys)
  → short file (*.rvvi)
  → testbench.sv             (pushes rvvi_mem_access_t.pte / .gpte)
  → rvviTrace mem_i / mem_d  (no vs_pte_* TRACE wires)
  → save_rvvi_data shim      (ins.current.vs_pte_* / g_pte_*)
  → SvH_coverage.svh
```

Single-stage `PTE_I` / `PTE_D` still use legacy TRACE wires `pte_i` / `pte_d`.

---

## Name cheat sheet

| Our key | Official idea |
|---------|----------------|
| `ORDER` | same idea (`order`) |
| `PC` + `INSN` | retire = `RET`, trap = `TRAP` |
| `TRAP 0/1` | `trap` bit (or TEXT `TRAP` line) |
| `MODE` + `MODE_VIRT` | `MODE` + `VIRT` |
| `CSR` | official text uses `C` |
| `VS_PTE_*` | official: `pte` |
| `G_PTE_*` | official: `gpte` |
| `PTE_I` / `PTE_D` | same `pte`, but on I vs D memory access |
| `VIRT_ADR_*` / `PHYS_ADR_*` | `vaddr` / `paddr` |

---

## Status (2026-08-17 — first ACT4 wiring)

| Done | Detail |
|------|--------|
| Types in fcov | `framework/src/act/fcov/rvviTraceTypes.svh` (copy of official) |
| TRACE fork | Removed `vs_pte_*` / `g_pte_*` **wires**; added `mem_i`/`mem_d` holders + `mem_access_push/pop/clear` |
| TB | Still accepts flat keys `VS_PTE_*` / `G_PTE_*`; pushes `rvvi_mem_access_t` (`pte`/`gpte`, `fetch` = I/D) |
| Cover shim | `save_rvvi_data` maps `mem_*.pte` → `ins.current.vs_pte_*`, `mem_*.gpte` → `g_pte_*` so **SvH_coverage.svh unchanged** |
| Converter | Still emits `VS_PTE_*`/`G_PTE_*` (not full official TEXT yet) |
| Not done | Full RVVI-TEXT `MEM`/`RET` dialect; TRACE 1.7 multi-client; rename coverpoints |

---

## Later

Goal: emit official TEXT `MEM` + `RET`/`TRAP` from the converter (or a generator), then optionally point coverpoints at `pte`/`gpte` directly.

Skip for now: RVVI-API, VVP, multi-issue fancy cases.

---

## Easy mistakes to avoid

1. Our `*.rvvi` ≠ official RVVI-TEXT (name alone does not make it standard).
2. Upstream has **no** `vs_pte_*` ports — coverpoint names `vs_pte_*` on `ins.current` are an ACT4 shim over `pte`/`gpte`.
3. Official names: `pte` ≈ our VS PTE, `gpte` ≈ our G PTE.
4. For SvH coverage we **need** page-table info somehow (official = MEM records).
5. A trapping load may only show part of a page walk — we already handle that in `sail_to_rvvi.py`.

---

## Where to look

| Need | Open |
|------|------|
| Official TRACE | `RVVI/RVVI-TRACE/README.md`, `RVVI/source/host/rvvi/rvviTrace.sv` |
| Official page fields | `RVVI/include/host/rvvi/rvviTraceTypes.svh` (+ ACT4 copy under `fcov/`) |
| Official text format | `RVVI/RVVI-TEXT/README.md` |
| Our TB keys | `framework/src/act/fcov/testbench.sv` |
| Our TRACE fork | `framework/src/act/fcov/rvviTrace.sv` |
| Our converter | `framework/src/act/sail_to_rvvi.py` |
| Our key list | [tracefile-rvvi.md](tracefile-rvvi.md) |
| Full RVVI skill | `.cursor/skills/rvvi/` |
