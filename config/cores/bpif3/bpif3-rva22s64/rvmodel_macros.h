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
    .global rvmodel_last_plic_claim;     \
rvmodel_last_plic_claim:                 \
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

// ACT prints from any mode (a failure seen by the S-mode trap handler is reported from S-mode),
// but the UART is mapped only in M-mode: under the Sv tests' page tables an S-mode print takes a
// load page fault on the LSR poll, which re-enters the trap handler until the trap signature
// overflows and hides the original failure (bpif3-uart-weekly #14: 10 Sv/Svpbmt/Zicbo tests). So
// switch to M-mode first, as on the K3 (printing ends in a halt, so the mode is never restored),
// and clear mstatus.MPRV so an M-mode print in the *_mprv_* tests is not translated either.
// Skip the switch when ACT already records M-mode: the "TEST PASSED" print runs after the M trap
// handler is torn down, so its ecall reaches the runner instead and every passing test hung
// (bpif3/loop #18: 81 timeouts, 0 passes).
#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR) \
    mv   _R3, _STR_PTR                               ;\
    LA(_R1, rvtest_current_mode)                     ;\
    LREG _R1, 0(_R1)                                 ;\
    beqz _R1, 5f                                     ;\
    RVTEST_TSBI_GOTO_MMODE                           ;\
5:                                                    ;\
    mv   _STR_PTR, _R3                               ;\
    li   _R1, 0x20000 /* mstatus.MPRV */             ;\
    csrc mstatus, _R1                                ;\
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

// External interrupts use the real UART0 -> PLIC path, as on the VF2 and Megrez: UART0 THRE is PLIC
// source 42; hart 0 (the runner's payload hart) is PLIC context 0 (M) and 1 (S). Source, contexts and
// the runner's PLIC cleanup between tests: ACT-Runner cert_harness/boards/bpif3_k1.env. Sail builds
// replace these macros with its interrupt generator (tests/env/sail_macros.h).
// UART0 is the K1's PXA-type UART: IER bit 6 (UUE) enables the unit, so IER is only read-modify-written.
#define K1_UART_IER_OFF     0x04
#define K1_UART_IER_THRI    0x02   /* Bit 1: THR empty interrupt */
#define K1_UART_MCR_OFF     0x10
#define K1_UART_MCR_OUT2    0x08   /* Bit 3: gates the UART interrupt output to the PLIC */
#define K1_PLIC_PRIO_U0     0xE00000A8   /* priority, source 42 */
#define K1_PLIC_PEND_U0     0xE0001004   /* pending word 1 (sources 32..63) */
#define K1_PLIC_U0_BIT      0x400        /* source 42 in words 1 */
#define K1_PLIC_EN_M_U0     0xE0002004   /* hart 0 M (ctx 0) enable word 1 */
#define K1_PLIC_EN_S_U0     0xE0002084   /* hart 0 S (ctx 1) enable word 1 */
#define K1_PLIC_THR_M       0xE0200000   /* ctx 0 threshold */
#define K1_PLIC_CLAIM_M     0xE0200004   /* ctx 0 claim/complete */
#define K1_PLIC_THR_S       0xE0201000   /* ctx 1 threshold */
#define K1_PLIC_CLAIM_S     0xE0201004   /* ctx 1 claim/complete */

// Real UART/PLIC delivery is asynchronous (VF2 and Megrez use the same value).
#define RVMODEL_INTERRUPT_LATENCY 6000

#define RVMODEL_TIMER_INT_SOON_DELAY 200

#define RVMODEL_MAX_CYCLES_PER_TIMER_TICK 100

#define RVMODEL_MSIP_ADDRESS K1_MSIP_ADDRESS

// Route source 42 to one PLIC context, raise UART0 THRE, then wait until the PLIC shows it pending.
// The PXA UART drives its interrupt line only while MCR.OUT2 is set (probe irq_path_probe2, single-ELF
// #256: OUT2 = 0 leaves source 42 idle while IIR shows THRE; OUT2 = 1 pends 42 and sets MEIP or SEIP),
// so SET turns OUT2 on and CLR turns it off again.
// These helpers can run after entry to S/U mode, so they poll the PLIC pending MMIO word, not mip.
#define K1_SET_UART_EXT_INT(_R1, _R2, _EN, _THR)                    \
  LOAD_ADDR32(_R2, K1_PLIC_PRIO_U0);                                \
  li _R1, 1;                                                        \
  sw _R1, 0(_R2);                                                   \
  LOAD_ADDR32(_R2, _EN);                                            \
  lw _R1, 0(_R2);                                                   \
  ori _R1, _R1, K1_PLIC_U0_BIT;                                     \
  sw _R1, 0(_R2);                                                   \
  LOAD_ADDR32(_R2, _THR);                                           \
  sw zero, 0(_R2);                                                  \
  LOAD_ADDR32(_R2, K1_UART0_BASE + K1_UART_MCR_OFF);                \
  lw _R1, 0(_R2);                                                   \
  ori _R1, _R1, K1_UART_MCR_OUT2;                                   \
  sw _R1, 0(_R2);                                                   \
  LOAD_ADDR32(_R2, K1_UART0_BASE + K1_UART_IER_OFF);                \
  lbu _R1, 0(_R2);                                                  \
  ori _R1, _R1, K1_UART_IER_THRI;                                   \
  sb _R1, 0(_R2);                                                   \
  fence iorw, iorw;                                                 \
  li _R1, 100000;                                                   \
1:                                                                  \
  LOAD_ADDR32(_R2, K1_PLIC_PEND_U0);                                \
  lw _R2, 0(_R2);                                                   \
  srli _R2, _R2, 10;                                                \
  andi _R2, _R2, 1;                                                 \
  bnez _R2, 2f;                                                     \
  addi _R1, _R1, -1;                                                \
  bnez _R1, 1b;                                                     \
2:

// Drop UART0 THRE, claim/complete the context, unroute source 42, then wait until it is no longer
// pending so the next SET sees a fresh edge through the PLIC gateway.
#define K1_CLR_UART_EXT_INT(_R1, _R2, _EN, _CLAIM)                  \
  LOAD_ADDR32(_R2, K1_UART0_BASE + K1_UART_IER_OFF);                \
  lbu _R1, 0(_R2);                                                  \
  andi _R1, _R1, ~K1_UART_IER_THRI;                                 \
  sb _R1, 0(_R2);                                                   \
  LOAD_ADDR32(_R2, K1_UART0_BASE + K1_UART_MCR_OFF);                \
  lw _R1, 0(_R2);                                                   \
  andi _R1, _R1, ~K1_UART_MCR_OUT2;                                 \
  sw _R1, 0(_R2);                                                   \
  fence iorw, iorw;                                                 \
  LOAD_ADDR32(_R2, _CLAIM);                                         \
  lw _R1, 0(_R2);                                                   \
  beqz _R1, 3f;                                                     \
  la _R2, rvmodel_last_plic_claim;                                  \
  sd _R1, 0(_R2);                                                   \
  LOAD_ADDR32(_R2, _CLAIM);                                         \
  sw _R1, 0(_R2);                                                   \
3:                                                                  \
  LOAD_ADDR32(_R2, _EN);                                            \
  lw _R1, 0(_R2);                                                   \
  andi _R1, _R1, ~K1_PLIC_U0_BIT;                                   \
  sw _R1, 0(_R2);                                                   \
  LOAD_ADDR32(_R2, K1_PLIC_PRIO_U0);                                \
  sw zero, 0(_R2);                                                  \
  fence iorw, iorw;                                                 \
  li _R1, 100000;                                                   \
4:                                                                  \
  LOAD_ADDR32(_R2, K1_PLIC_PEND_U0);                                \
  lw _R2, 0(_R2);                                                   \
  srli _R2, _R2, 10;                                                \
  andi _R2, _R2, 1;                                                 \
  beqz _R2, 5f;                                                     \
  addi _R1, _R1, -1;                                                \
  bnez _R1, 4b;                                                     \
5:                                                                  \
  fence iorw, iorw

#define RVMODEL_SET_MEXT_INT(_R1, _R2) \
  K1_SET_UART_EXT_INT(_R1, _R2, K1_PLIC_EN_M_U0, K1_PLIC_THR_M)

#define RVMODEL_CLR_MEXT_INT(_R1, _R2) \
  K1_CLR_UART_EXT_INT(_R1, _R2, K1_PLIC_EN_M_U0, K1_PLIC_CLAIM_M)

#define RVMODEL_SET_MSW_INT(_R1, _R2)  \
    LOAD_ADDR32(_R2, K1_MSIP_ADDRESS) ;\
    li _R1, 1                         ;\
    sw _R1, 0(_R2);

#define RVMODEL_CLR_MSW_INT(_R1, _R2)  \
    LOAD_ADDR32(_R2, K1_MSIP_ADDRESS) ;\
    sw zero, 0(_R2);

##### Supervisor Interrupts #####

// RVMODEL_SET/CLR_SEXT_INT are left undefined, as on the K3: ACT then raises and clears the S external
// interrupt through mip.SEIP from M-mode (tests/env/check_defines.h, rvtest_setup.h). ACT runs these
// macros in S/U-mode for S/U tests, and the PLIC path did not deliver SEI there: in bpif3/loop #17 the
// U tests never saw SEIP and three S tests hung, although the same PLIC ctx 1 path raises SEIP from
// M-mode and S-mode can read and write the PLIC (probes irq_path_probe2 and irq_smode_probe3, single-ELF
// #256 and #257). The M external interrupt keeps the UART THRE -> PLIC ctx 0 path.

// No RVMODEL_SET/CLR_SSW_INT: the K1 has no supervisor software-interrupt device in its memory map, so
// ACT sets mip.SSIP itself, directly or through T-SBI (as on the VF2 and Megrez). The empty definitions
// used before made the board skip the interrupt while Sail raised it.

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
