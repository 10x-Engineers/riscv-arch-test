---
name: rvvi
description: >-
  RISC-V Verification Interface (cloned upstream). Use when the user mentions
  RVVI, RVVI-TRACE, RVVI-TEXT, RVVI-API, mem_access/PTE/GPTE, or comparing
  ACT4 *.rvvi / forked rvviTrace to the standard. Read this before proposing
  any ACT4 migration. Do not change ACT4 coverage paths until the user says how.
---

# RVVI (upstream clone) — agent memory

**Clone root:** `/home/ahsan-10xe/Downloads/ACT4-20260706T103524Z-3-001/RVVI`  
**Remote:** https://github.com/riscv-verification/RVVI  
**Pinned HEAD when skill written:** `bd1c6b2` (Add net cancel support)  
**Versions in tree:** TRACE **1.7**, TEXT **0.5**, API **1.37**, VVP **0.0** (empty)

## Standing order

1. **Understand from this clone first** — prefer files under `RVVI/` over chat memory or GitHub guesses.
2. ACT4 hypervisor PTE path (2026-08-17): coverpoints sample `ins.current.mem_{i,d}.pte` / `.gpte` (official types). Do not reintroduce `vs_pte_*` fields on `RISCV_trace_data`.
3. ACT4’s flat `*.rvvi` dialect ≠ official RVVI-TEXT yet (converter still emits `VS_PTE_*` keys).
4. Deeper map: [reference.md](reference.md). ACT4 gap map: `act4-riscv-arch-test/RVVI-for-ACT4.md`.

## Mental model (graph)

```
┌──────────────────┐     observes      ┌─────────────────────┐
│ DUT / Sail ISS   │ ────────────────► │ RVVI-TRACE (SV IF)  │
│ retire / trap    │   valid+order+…   │  + mem_access FIFO  │
└──────────────────┘                   └──────────┬──────────┘
                                                  │
           ┌──────────────────────────────────────┼──────────────────────┐
           ▼                                      ▼                      ▼
   ┌───────────────┐                    ┌─────────────────┐     ┌────────────────┐
   │ RVVI-TEXT     │  replay into TRACE │ Coverage / TB   │     │ RVVI-API (C)   │
   │ file format   │ ◄── parser.sv      │ (ACT4 samples)  │     │ lockstep RM    │
   └───────────────┘                    └─────────────────┘     └────────────────┘
           ▲
           │  (optional) NET / CANCEL / MEM before RET|TRAP
```

**Four pieces — never mix jobs:**

| Piece | Job | Clone path |
|-------|-----|------------|
| **TRACE** | SV observation interface | `source/host/rvvi/rvviTrace.sv` + `include/.../rvviTraceTypes.svh` |
| **TEXT** | Text that *drives* TRACE | `RVVI-TEXT/README.md` + `examples/*.rvvi` |
| **API** | Lockstep compare vs reference | `include/host/rvvi/rvviApi.h` + `rvviApiPkg.sv` |
| **VVP** | Virtual peripherals | `RVVI-VVP/` — **WIP empty** |

## TRACE facts (1.7) — memorize

- Event clocked on `clk`; sample when `valid`.
- `trap=1` → exception state update, insn did **not** retire; `trap=0` → normal retire (compare on retire).
- Privilege: `mode` + `mode_virt` (VS=`1,1`, VU=`0,1`, HS=`1,0`, M=`3,0`, U=`0,0`).
- Writes: `x_wdata`/`x_wb`, `f_*`, `v_*`, `csr`/`csr_wb`.
- Extra: `state[hart][string]` (string KV — shadowed CSRs, not paging).
- **Paging is NOT TRACE wires.** Use `rvvi_mem_access_t` via `mem_access_push` / `mem_access_pop` after `client_register(..., recv_memory=1)`.
- Also: `net_push` / `net_pop` / `net_cancel_*` for pins (interrupts, etc.).

### `rvvi_mem_access_t` (the official PTE path)

| Field | Meaning |
|-------|---------|
| `fetch` | 1=I-bus, 0=D-bus |
| `size` | bytes |
| `vaddr` / `paddr` | VA → host PA |
| `gaddr` | guest PA when H on; else 0 |
| `pte` | leaf — **VS-stage when H active** |
| `gpte` | **G-stage** leaf when H active |
| `page_type` / `guest_page_type` | kilo…peta (3-bit) |

Push **before** asserting `valid`. Multiple MEM records per insn OK. Incomplete walks allowed on traps.

## TEXT facts (0.5) — memorize

Mandatory first line: `VERSION <maj> <min>`.

Core verbs (not ACT4’s flat `ORDER PC INSN …`):

```
RET  <pc> <insn>     … optional X/F/V/C/MODE/VIRT/…
TRAP <pc> <insn>     … same sideband
MEM  I|D <bytes> <vaddr> <paddr> <n> [PTE hex] [GPTE hex] [PT K|M|…] [GPT …] [GPADDR hex]
C    <csr_addr> <value>     # NOT "CSR"
VIRT <0|1>                  # NOT "MODE_VIRT"
```

Parser demo: `source/host/rvvi/rvviTextParser.sv` (`+traceFile=`). Checker: `rvviTextChecker.py`.  
Examples under `RVVI-TEXT/examples/` (traps/dhrystones/vectors) — **no MEM/PTE samples in those examples** yet.

## API facts — memorize

Use for **DUT ↔ reference lockstep**, not for Sail→covergroup alone.

Phases: config → `rvviRefInit(elf)` → mark volatile CSRs/mem → loop (`EventStep` / compares) → `rvviRefShutdown`.

Can be driven by DPI from TB **or** by a TRACE→API bridge (Imperas `trace2api` — not in this clone).

## ACT4 contrast (do not invent)

| | Upstream RVVI | ACT4 today |
|--|---------------|------------|
| TRACE file | `RVVI/.../rvviTrace.sv` **1.7** | `riscv-arch-test/.../fcov/rvviTrace.sv` **1.6 fork** |
| PTE delivery | `mem_access` / TEXT `MEM PTE/GPTE` | Flat keys `PTE_*` / `VS_PTE_*` / `G_PTE_*` → **extra wires** |
| Short log | Official TEXT (`RET`/`TRAP`/`MEM`) | Custom KEY/VALUE line (`ORDER`/`PC`/`INSN`/`CSR`) named `*.rvvi` |
| Producer | DUT tracer or TEXT replay | `sail_to_rvvi.py` from Sail `*.trace` |
| Consumer | Coverage / API bridge | `testbench.sv` → covergroups |

## When user later says “use it”

Only then propose a design. Default options (pick when asked):

1. **TEXT path** — converter emits official TEXT; TB uses/ adapts `rvviTextParser` → stock TRACE.
2. **Struct path** — keep Sail→converter, fill `rvvi_mem_access_t` + stock TRACE 1.7; shim covergroups.
3. **Hybrid** — TEXT for new suites; keep ACT4 dialect until SvH covergroups migrate.

Never silently replace forked wires mid-coverage without a plan.

## Quick open list

```
RVVI/README.md
RVVI/RVVI-TRACE/README.md
RVVI/RVVI-TEXT/README.md
RVVI/RVVI-API/README.md
RVVI/include/host/rvvi/rvviTraceTypes.svh
RVVI/source/host/rvvi/rvviTrace.sv
RVVI/source/host/rvvi/rvviTextParser.sv
RVVI/RVVI-TEXT/examples/traps.rvvi
```
