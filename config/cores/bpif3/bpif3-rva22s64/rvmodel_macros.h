// rvmodel_macros.h
// DUT-specific macro definitions for SpacemiT K1 / Banana Pi BPI-F3
// SPDX-License-Identifier: BSD-3-Clause
//
// Hardware addresses (SpacemiT K1, from Bianbu DTS / U-Boot logs):
//   DRAM:                        0x0-0x80000000 (2GiB)
//   UART0 (NS16550-compatible): 0xD4017000
//   CLINT base:                 0xE4000000  (spacemit,k1-clint)
//     MSIP  (hart 0):           0xE4000000
//     MTIME:                    0xE400BFF8
//     MTIMECMP (hart 0):        0xE4004000
//   PLIC:                       0xE0000000  (spacemit,k1-plic)
//
// Memory layout for ACT runner:
//   Firmware load+entry: 0x04000000  (BOARD_FW_LOAD_ADDR)
//   tohost:              linked symbol inside each test ELF (see below);
//                        0x04100000 (BOARD_FIXED_TOHOST_ADDR) fallback only
//   Test ELF pack:       0x0C200000  (BOARD_EXT_PACK_ADDR)
//   Test ELF load:       0x50000000  (link.ld RAM_ORIGIN; above the first GiB for the Sv tests)

#ifndef _RVMODEL_MACROS_H
#define _RVMODEL_MACROS_H

#define LOAD_ADDR32(_REG, _ADDR)               \
    li   _REG, _ADDR                          ;\
    slli _REG, _REG, 32                       ;\
    srli _REG, _REG, 32

#define K1_UART0_BASE    0xD4017000
#define K1_UART_THR_OFF  0x00   /* Transmit Holding Register */
#define K1_UART_LSR_OFF  0x14   /* Line Status Register      */
#define K1_UART_LSR_THRE 0x20   /* Bit 5: TX Holding Empty   */

// K1 CLINT
#define K1_MSIP_ADDRESS     0xE4000000
#define K1_MTIME_ADDRESS    0xE400BFF8
// ACT act4 (#2864) requires mtime whenever machine timer interrupts are implemented.
#define RVMODEL_MTIME_ADDRESS K1_MTIME_ADDRESS
#define K1_MTIMECMP_ADDRESS 0xE4004000

#ifndef BOARD_FIXED_TOHOST_ADDR
#define BOARD_FIXED_TOHOST_ADDR 0x04100000
#endif

#define RVMODEL_DATA_SECTION \
    .pushsection .data,"aw",@progbits;  \
    .p2align 3;                          \
    .global tohost;                      \
tohost:                                  \
    .dword 0;                            \
    .popsection

#define STANDARD_SM_SUPPORTED

##### STARTUP #####

//#define RVMODEL_BOOT

//#define RVMODEL_BOOT_TO_MMODE

##### TERMINATION #####

// Write 1 (HTIF PASS) to tohost, then spin in WFI.
// The runner monitor (runner_monitor.c:620) checks: if (v == 1) → PASS.
#define RVMODEL_HALT_PASS                              \
    la   a0, tohost                                   ;\
    li   a1, 1                                        ;\
    sd   a1, 0(a0)                                    ;\
    _rvmodel_halt_pass_loop:                          ;\
    wfi                                               ;\
    j    _rvmodel_halt_pass_loop

#define RVMODEL_HALT_FAIL                              \
    la   a0, tohost                                   ;\
    li   a1, 3                                        ;\
    sd   a1, 0(a0)                                    ;\
    _rvmodel_halt_fail_loop:                          ;\
    wfi                                               ;\
    j    _rvmodel_halt_fail_loop

##### IO #####

#define RVMODEL_IO_INIT(_R1, _R2, _R3)                \
    LOAD_ADDR32(_R1, K1_UART0_BASE)                  ;\
    li   _R2, 0x03                                   ;\
    sb   _R2, 0x0C(_R1)                              ; /* LCR: 8N1 */

#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR) \
1:                                                    ;\
    lbu  _R1, 0(_STR_PTR)                            ;\
    beqz _R1, 3f                                     ;\
2:                                                    ;\
    LOAD_ADDR32(_R2, K1_UART0_BASE)                  ;\
    addi _R2, _R2, K1_UART_LSR_OFF                  ;\
4:                                                    ;\
    lbu  _R3, 0(_R2)                                 ;\
    andi _R3, _R3, K1_UART_LSR_THRE                 ;\
    beqz _R3, 4b                                     ;\
    LOAD_ADDR32(_R2, K1_UART0_BASE)                  ;\
    sb   _R1, K1_UART_THR_OFF(_R2)                  ;\
    addi _STR_PTR, _STR_PTR, 1                       ;\
    j    1b                                          ;\
3:

##### Access Fault #####

// RVMODEL_ACCESS_FAULT_ADDRESS is deliberately not defined, so ACT skips its access-fault
// subtests (tests/env/check_defines.h). The K1 never raises access faults for plain
// addresses: 0x0 is DRAM (memory@0), unmapped 0x80_0000_0000 reads bus garbage, and
// 1 << 40 wraps to 0x0 (csr_probe on the board, 2026-10-05).

// The K1 CLINT is ~3.5 GiB from the test image: ACT must load CLINT addresses absolutely.
#define RVMODEL_CLINT_ABSOLUTE 1
#define RVMODEL_MTIMECMP_ADDRESS K1_MTIMECMP_ADDRESS

##### Machine Interrupts #####

#define RVMODEL_INTERRUPT_LATENCY 50

#define RVMODEL_TIMER_INT_SOON_DELAY 200

#define RVMODEL_MAX_CYCLES_PER_TIMER_TICK 100

#define RVMODEL_MSIP_ADDRESS K1_MSIP_ADDRESS

#define RVMODEL_SET_MEXT_INT(_R1, _R2)
#define RVMODEL_CLR_MEXT_INT(_R1, _R2)

#define RVMODEL_SET_MSW_INT(_R1, _R2)  \
    LOAD_ADDR32(_R2, K1_MSIP_ADDRESS) ;\
    li _R1, 1                         ;\
    sw _R1, 0(_R2);

#define RVMODEL_CLR_MSW_INT(_R1, _R2)  \
    LOAD_ADDR32(_R2, K1_MSIP_ADDRESS) ;\
    sw zero, 0(_R2);

##### Supervisor Interrupts #####

#define RVMODEL_SET_SEXT_INT(_R1, _R2)
#define RVMODEL_CLR_SEXT_INT(_R1, _R2)
#define RVMODEL_SET_SSW_INT(_R1, _R2)
#define RVMODEL_CLR_SSW_INT(_R1, _R2)

##### Sscofpmf #####

// Counter and event for the Sscofpmf tests (required by ACT act4 since the Sscofpmf suites).
// SpacemiT X60 (K1): event 0x06 counts loads; source: the BPI-F3 device tree's riscv,event-to-mhpmevent maps the SBI L1D read-access event (0x10000) to 0x06 on counters 3-18 (artifacts/onboarding/bpif3_20261005_dtb/k1-x_deb1.dts in the runner repo).
// Documented, not yet measured on the board. The Sail reference counts EV_FENCE for the same
// selector (sail.json event_selectors) and the reference build triggers it with a fence.
#define RVMODEL_HPM_COUNTER 3
#define RVMODEL_MHPMEVENT_VAL 0x06
#define RVMODEL_MHPMEVENT_CODE(_R1, _R2) \
    lw _R2, 0(_R1)

#endif // _RVMODEL_MACROS_H
