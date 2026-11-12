# Milk-V Megrez (ESWIN EIC7700X, SiFive P550) ACT configuration

DUT name `milkv-megrez-p550`. Tests run on hart 1 through the minimal UART
runner (`milkv_megrez_eic7700x` board in the runner repository); Sail runs
the same tests on hart 0.

ISA: `rv64imafdch_zicntr_zicsr_zifencei_zihpm_zba_zbb_sscofpmf` (Linux on the
board), `RV64GC_Zba_Zbb_Sscofpmf` + H (TRM), Sv48 (TRM, DTB).
`sail_riscv_sim --print-isa-string` with this `sail.json` reports
`rv64imafdch_zicntr_zicsr_zifencei_zihpm_zmmul_..._zba_zbb_..._sscofpmf_...`.

| File | Purpose |
|---|---|
| `milkv-megrez-p550.yaml` | UDB architecture configuration (test selection and expected behavior) |
| `sail.json` | Sail 0.14.1 reference-model configuration |
| `link.ld` | Places tests in the runner payload window `0x90000000`-`0xB0000000` |
| `rvmodel_macros.h` | Halt, console, CLINT and PLIC/UART interrupt macros for hart 1 |
| `test_config.yaml`, `test_config.local.yaml` | ACT entry points (CI path / tools on `$PATH`) |

## Sources

- **TRM**: EIC7700X SoC Technical Reference Manual v1.0.0-20250103, Part 1
  (github.com/eswincomputing/EIC7700X-SoC-Technical-Reference-Manual), CPU
  chapter 3.4.
- **DTB**: `eic7700-milkv-megrez-no-npu.dtb` from Milk-V release `2025-0219`
  (sha256 `92ce561b...`).
- **OpenSBI log**: official bootloader 2025-0224 booted on the board
  (OpenSBI v1.5 hart feature detection).
- **Linux log**: RockOS 6.6.87 boot on the board.

## Values and evidence

| Parameter | Value | Status | Source |
|---|---|---|---|
| Privileged ISA | 1.11 | confirmed | TRM Table 3-5; OpenSBI "Priv Version v1.11" |
| H | implemented, **draft 0.6** | confirmed | TRM Table 3-5; misa `rv64imafdchx` |
| misa.X (non-standard) | set | confirmed | OpenSBI misa decode |
| PMP | 8 regions, 4 KiB, pmpcfg2 hardwired 0 | confirmed | TRM 3.4 PMP; OpenSBI; DTB |
| Physical address width | 41 | derived | OpenSBI "PMP Address Bits 39" (pmpaddr holds PA[N-1:2]) |
| ASID width | 0 | confirmed | Linux "ASID allocator disabled (0 bits)" |
| Address translation | Sv39, Sv48; hgatp Sv39x4, Sv48x4 | confirmed | TRM satp/hgatp tables; DTB `mmu-type` |
| mtvec alignment | Direct 4 B, Vectored 256 B | confirmed | TRM Table 3-46 |
| stvec alignment | Vectored 128 B | confirmed | TRM Table 3-58 |
| medeleg writable | `0xF0B55D` | confirmed | csr_probe 2026-10-05 (`medeleg <- ~0`); TRM Table 3-52 lists `0xF0B7FF`, but access faults 1/5/7 are not delegatable on the board |
| mideleg writable | `0x2222` in Sail | partial | the board reads `0x2666` after writing all ones (TRM Table 3-51 lists `0x3666`; no SGEI bit, GEILEN 0); Sail fixes the VS bits itself |
| HPM counters | mhpmcounter3-6 | confirmed | OpenSBI "MHPM Info 4 (0x00000078)" |
| Misaligned load/store | traps (software emulation) | confirmed | TRM 3.4 mcause note |
| Cache block | 64 B | confirmed | DTB `d-cache-block-size` |
| CLINT | `0x02000000`, mtime 1 MHz | confirmed | OpenSBI aclint; runner measurement |
| PLIC | `0x0C000000`, 520 sources, hart1 M ctx 2, S ctx 3 | confirmed | DTB `interrupts-extended`; TRM |
| UART0 | `0x50900000`, shift 2, 32-bit access, PLIC source 100 | confirmed | DTB (U-Boot's DTS says 16-bit; both work for TX) |
| Cycles per timer tick | 2048 bound | derived | 1.8 GHz max (Milk-V) / 1 MHz mtime |
| mvendorid / marchid / mimpid | `0x489` / `0x8000000000000008` / `0x6220425` | confirmed | csr_probe 2026-10-05 |
| HPM counter width | 48 | confirmed | csr_probe 2026-10-05 (`mhpmcounter3 <- ~0`) |
| time CSR implemented | false | confirmed | csr_probe 2026-10-05: `rdtime` raises illegal instruction |
| LR/SC reservation, misaligned fault priority, xtval reporting, WFI | U74 values | **UNVERIFIED** | probe on hardware |
| VMID width | 0 | confirmed | csr_probe 2026-10-05: no writable hgatp.VMID bits |
| Sscounterenw, Sstvecd | enabled | **UNVERIFIED** (Sstvecd consistent with TRM) | |
| RVMODEL_ACCESS_FAULT_ADDRESS | `0x0` | confirmed | csr_probe 2026-10-05: load from `0x0` raises load access fault |

## Hypervisor

The hardware implements the draft Hypervisor extension 0.6 (TRM). ACT and UDB
model ratified H 1.0, so H is **not** listed in `milkv-megrez-p550.yaml` and no
H tests are generated. `sail.json` keeps H enabled so `misa.H` and the
H-related `mstatus` fields match the hardware. Enabling H tests needs the
ACT `hypervisor` branch and a decision on 0.6-vs-1.0 differences.

## Validation (offline)

- UDB validation: pass.
- `sail_riscv_sim --validate-config`: pass.
- Build with Sail 0.14.1: committed `Zba,Zbb,Zihpm,PMPSm,SvSm` (400 steps) and
  generated `InterruptsSm,InterruptsS,ExceptionsSm,Sm,S,U,ZicntrSm,Sstvecd,Sscounterenw`
  (410 steps) all succeeded; 162 hardware ELFs load and enter inside
  `0x90000000`-`0xB0000000`.
- Hardware: Jenkins megrez-uart-sanity #3 (2026-10-05) failed 6/8 on access-fault delegation with medeleg `0xF0B7FF`; csr_probe measured `0xF0B55D`, applied here.
