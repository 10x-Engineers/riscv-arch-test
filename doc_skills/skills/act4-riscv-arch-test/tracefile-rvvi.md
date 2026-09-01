# Tracefile → RVVI (ACT4 coverage)

## Two files (do not confuse)

| File | Producer | Consumer | Role |
|------|----------|----------|------|
| `*.trace` | `sail_riscv_sim --trace --trace-output` | `sailLog2Trace()` | Verbose Sail log |
| `*.rvvi` | `framework/src/act/sail_to_rvvi.py` | `fcov/testbench.sv` | **Short Tracefile** for RVVI |

Coverage TB never reads Sail `*.trace` directly. `build_plan.gen_rvvi_tasks()` converts then groups paths into `<Suite>.tracelist`. Questa: `vsim ... +traceFileList=...`.

## Sail verbose example
```
[0] [M]: 0x80000000 (0x0000C097) auipc x1, 0xc
x1 <- 0x8000C000
CSR mip (0x344) <- 0x00000080
```

## Short-trace (`.rvvi`) example (what TB gets)
```
ORDER 0 PC 80000000 INSN 0000C097 MODE 3 X 1 8000C000
ORDER 1 PC 80000004 INSN 1B808093 MODE 3 X 1 8000C1B8 CSR 344 00000080
```

Parser: `splitLine` → pop key, pop value; for `X`/`F`/`V`/`CSR` pop a third token (reg/addr then hex data). Non-empty line → `valid=1`. Unknown key → `$finish`.

## Keys accepted by `testbench.sv` → `rvvi.*[0][0]`

| Trace key | Format | RVVI signal |
|-----------|--------|-------------|
| `ORDER` | decimal | `order` |
| `INSN` | hex | `insn` |
| `TRAP` | binary | `trap` |
| `DEBUG_MODE` | binary | `debug_mode` |
| `PC` | hex | `pc_rdata` |
| `MODE` | 3=M,1=S,0=U | `mode` |
| `MODE_VIRT` | decimal (V bit) | `mode_virt` |
| `M_EXT_INTR` / `S_EXT_INTR` / `M_TIMER_INTR` / `M_SOFT_INTR` | binary | matching `*_intr` |
| `VIRT_ADR_I` / `VIRT_ADR_D` | hex | `virt_adr_*` |
| `PHYS_ADR_I` / `PHYS_ADR_D` | hex | `phys_adr_*` |
| `PTE_I` / `PTE_D` | hex | `pte_*` |
| `VS_PTE_I` / `VS_PTE_D` | hex | `vs_pte_*` |
| `G_PTE_I` / `G_PTE_D` | hex | `g_pte_*` |
| `PPN_I` / `PPN_D` | hex | `ppn_*` |
| `PAGE_TYPE_I` / `PAGE_TYPE_D` | binary | `page_type_*` |
| `READ_ACCESS` / `WRITE_ACCESS` / `EXECUTE_ACCESS` | binary | `*_access` |
| `X` / `F` / `V` | `n hexval` | `*_wdata[n]`, bit in `*_wb` |
| `CSR` | `addr hexval` (hex CSR#) | `csr[addr]`, `csr_wb[addr]` |

## What converter emits today (`sail_to_rvvi.py`)
Emits: `ORDER`, `PC`, `INSN`, `MODE`, `MODE_VIRT` (VS/VU), `X`/`F`/`V`/`CSR`,
`READ/WRITE/EXECUTE_ACCESS`, and from Sail `mem[R]` walks: `PTE_*` / `VS_PTE_*` /
`G_PTE_*`. Tracks **vsatp CSR 0x280** and **hgatp 0x680** MODE (bit 31): Bare-vsatp
guest → `G_PTE_*`; Bare-hgatp VS → `VS_PTE_*`; two-stage → leaves[-2]=VS, [-1]=G.
Invalid V=0 leaves accepted when A/D and R/W/X are set.

Emits `TRAP 1` when Sail logs `trapping from …` after an insn; fetch-*-fault walks after a redirect are promoted to `VS_PTE_I`/`G_PTE_I`. Still TODO: interrupts, `PHYS_ADR_*` / `PPN_*`.

MODE quirk: Sail logs mode at insn **start**; converter writes previous insn’s MODE from the **next** insn’s start mode (RVVI end-of-insn mode). Last insn falls back to its own start mode.

## Sample path after RVVI drive
```
rvvi.valid → riscv_arch_test → disassemble → coverage.sample()
  → save_rvvi_data → sample_extensions → suite_*_sample → covergroup.sample(ins)
```

Define gate: suite stem uppercased + `_COVERAGE` (e.g. `EXCEPTIONSH_COVERAGE`).

## Source paths
- `framework/src/act/sail_to_rvvi.py`
- `framework/src/act/fcov/testbench.sv`
- `framework/src/act/fcov/rvviTrace.sv`
- `framework/src/act/fcov/riscv_arch_test.sv`
- `framework/src/act/fcov/coverage/RISCV_coverage_rvvi.svh`
- `framework/src/act/riscv-arch-test.do`
- Sample: `work/tmp/sample.rvvi`
