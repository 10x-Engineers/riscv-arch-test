// rvmodel_macros.h
// DUT-specific macro definitions for the SpacemiT K3 Pico-ITX (X100 cores)
// SPDX-License-Identifier: BSD-3-Clause
//
// Hardware addresses, measured on the board (runner repo
// artifacts/onboarding/spacemit_k3_20261019/):
//   DRAM:                        0x1_0000_0000 - 0x8_FFFF_FFFF (32 GiB); 0x0 is TCM
//   UART0 (8250, xscale):        0xD4017000, reg-shift 2, already configured by SPL
//   M-mode CLINT (riscv,clint0): 0xF1810000 (DTB the boot chain hands to OpenSBI)
//     MSIP  (hart 0):            0xF1810000
//     MTIMECMP (hart 0):         0xF1814000
//     MTIME:                     0xF181BFF8 (24 MHz; advances with the time CSR)
//   Interrupts: AIA (APLIC/IMSIC), no PLIC.
//
// Memory layout for the ACT runner (runner preset spacemit_k3_pico_itx):
//   Runner load+entry:  0x1_0000_0000 (the stock OpenSBI slot)
//   Test ELF load:      0x1_1000_0000 (link.ld)
//   UART staging:       0x1_3000_0000
//
// sail.json maps a small RAM region at 0x0200_0000: tests/env/sail_macros.h hard-codes
// RVMODEL_MTIMECMP_ADDRESS 0x02004000 for signature builds, and the K3's DRAM starts at
// 0x1_0000_0000, so without it Sail takes store access faults the board never takes.

#ifndef _RVMODEL_MACROS_H
#define _RVMODEL_MACROS_H

#define LOAD_ADDR32(_REG, _ADDR)               \
    li   _REG, _ADDR                          ;\
    slli _REG, _REG, 32                       ;\
    srli _REG, _REG, 32

#define K3_UART0_BASE    0xD4017000
#define K3_UART_THR_OFF  0x00   /* Transmit Holding Register */
#define K3_UART_LSR_OFF  0x14   /* Line Status Register      */
#define K3_UART_LSR_THRE 0x20   /* Bit 5: TX Holding Empty   */

// K3 M-mode CLINT
#define K3_MSIP_ADDRESS     0xF1810000
#define K3_MTIME_ADDRESS    0xF181BFF8
// ACT act4 (#2864) requires mtime whenever machine timer interrupts are implemented.
#define RVMODEL_MTIME_ADDRESS K3_MTIME_ADDRESS
#define K3_MTIMECMP_ADDRESS 0xF1814000

#define RVMODEL_DATA_SECTION \
    .pushsection .data,"aw",@progbits;  \
    .p2align 3;                          \
    .global tohost;                      \
tohost:                                  \
    .dword 0;                            \
    .global rvmodel_runner_mtvec;        \
rvmodel_runner_mtvec:                    \
    .dword 0;                            \
    .popsection

#define STANDARD_SM_SUPPORTED

##### STARTUP #####

// The runner's trap handler, saved before ACT installs its own: the halt macros put it back
// so their ecall reaches the runner even on failure paths that skip the trap epilogs.
// The K3 implements H but resets with misa.H = 0, which disables it: the H-only bits
// (mstatus.MPV/GVA, mip/mie.VSSIP, mhpmevent.VUINH) then read 0, while Sail (sail.json, H
// supported) has H enabled (k3-uart-weekly #5: Sm_mcsr_*, Sm_shadow, Sscofpmf_*_inhibit_*).
// misa.H is writable on the K3 (runner repo artifacts/onboarding/spacemit_k3_20261019), so set it.
#define RVMODEL_BOOT                     \
    csrr T1, mtvec                      ;\
    la   T2, rvmodel_runner_mtvec       ;\
    sd   T1, 0(T2)                      ;\
    li   T1, 1 << 7 /* misa.H */        ;\
    csrs misa, T1

//#define RVMODEL_BOOT_TO_MMODE

##### TERMINATION #####

// Write the HTIF status to tohost (1 = PASS, 3 = FAIL), restore the runner's mtvec (saved by
// RVMODEL_BOOT) and ecall. The K3's monitor hart does not run, so nothing polls tohost: the
// runner hart ends the case on this M-mode ecall (runner_machine_trap.c, ecall_m_tohost).
// Restoring mtvec matters on failure paths, which call the halt with ACT's handler installed.
// mstatus.MPRV is cleared first: a test that fails with MPRV set (the Sv *_mprv_* suites) would
// otherwise translate the tohost store through the test's page tables, and hand the runner an
// M-mode whose loads do the same, so the runner loops on load page faults until the UART
// timeout (k3-uart-weekly #5).
#define RVMODEL_HALT_PASS                              \
    li   a1, 0x20000 /* mstatus.MPRV */               ;\
    csrc mstatus, a1                                  ;\
    la   a0, tohost                                   ;\
    li   a1, 1                                        ;\
    sd   a1, 0(a0)                                    ;\
    la   a0, rvmodel_runner_mtvec                     ;\
    ld   a0, 0(a0)                                    ;\
    csrw mtvec, a0                                    ;\
    fence rw, rw                                      ;\
    ecall                                             ;\
    _rvmodel_halt_pass_loop:                          ;\
    wfi                                               ;\
    j    _rvmodel_halt_pass_loop

// RVMODEL_HALT_FAIL switches to M-mode first: ACT reports a failed check from the mode it ran
// in, and from S/U-mode the csrc mstatus and csrw mtvec below trap, which re-reported the
// failure in a loop (k3-uart-weekly #5: ~1500 dumps per test, over the portal's 2 MiB limit).
// The T-SBI ecall goes to ACT's M-mode handler, which returns here in M-mode. On the fail
// paths after ACT's epilogs, mtvec is already the runner's, so the ecall ends the case there
// with tohost still 0, which the runner also reports as FAIL.
#define RVMODEL_HALT_FAIL                              \
    RVTEST_TSBI_GOTO_MMODE                            ;\
    li   a1, 0x20000 /* mstatus.MPRV */               ;\
    csrc mstatus, a1                                  ;\
    la   a0, tohost                                   ;\
    li   a1, 3                                        ;\
    sd   a1, 0(a0)                                    ;\
    la   a0, rvmodel_runner_mtvec                     ;\
    ld   a0, 0(a0)                                    ;\
    csrw mtvec, a0                                    ;\
    fence rw, rw                                      ;\
    ecall                                             ;\
    _rvmodel_halt_fail_loop:                          ;\
    wfi                                               ;\
    j    _rvmodel_halt_fail_loop

##### IO #####

#define RVMODEL_IO_INIT(_R1, _R2, _R3)                \
    LOAD_ADDR32(_R1, K3_UART0_BASE)                  ;\
    li   _R2, 0x03                                   ;\
    sb   _R2, 0x0C(_R1)                              ; /* LCR: 8N1 */

#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR) \
1:                                                    ;\
    lbu  _R1, 0(_STR_PTR)                            ;\
    beqz _R1, 3f                                     ;\
2:                                                    ;\
    LOAD_ADDR32(_R2, K3_UART0_BASE)                  ;\
    addi _R2, _R2, K3_UART_LSR_OFF                  ;\
4:                                                    ;\
    lbu  _R3, 0(_R2)                                 ;\
    andi _R3, _R3, K3_UART_LSR_THRE                 ;\
    beqz _R3, 4b                                     ;\
    LOAD_ADDR32(_R2, K3_UART0_BASE)                  ;\
    sb   _R1, K3_UART_THR_OFF(_R2)                  ;\
    addi _STR_PTR, _STR_PTR, 1                       ;\
    j    1b                                          ;\
3:

##### Access Fault #####

// RVMODEL_ACCESS_FAULT_ADDRESS is deliberately not defined, so ACT skips its access-fault
// subtests (tests/env/check_defines.h). On the K3 a load from 0x0 (TCM) never completes and
// hangs the core (csr_probe trace, 2026-10-19); no address that faults cleanly is known yet.

// The CLINT is far from the test image: ACT must load CLINT addresses absolutely.
#define RVMODEL_CLINT_ABSOLUTE 1
#define RVMODEL_MTIMECMP_ADDRESS K3_MTIMECMP_ADDRESS

##### Machine Interrupts #####

#define RVMODEL_INTERRUPT_LATENCY 50

#define RVMODEL_TIMER_INT_SOON_DELAY 200

#define RVMODEL_MAX_CYCLES_PER_TIMER_TICK 100

#define RVMODEL_MSIP_ADDRESS K3_MSIP_ADDRESS

// The K3 has AIA (Smaia, IMSIC) and no PLIC. M-mode raises its own external interrupt through
// the M-level IMSIC interrupt file's indirect CSRs, with no MMIO: enable delivery (eidelivery = 1),
// accept every priority (eithreshold = 0), enable identity K3_MEXT_IID in eie0 and set it
// pending in eip0, which raises mip.MEIP. Clearing the eip0 bit drops MEIP again.
// Not yet measured on the board (k3-uart-weekly #5 ran with empty macros, so every MEI test
// took the next timer interrupt instead).
#define K3_CSR_MISELECT        0x350
#define K3_CSR_MIREG           0x351
#define K3_ISEL_EIDELIVERY     0x70
#define K3_ISEL_EITHRESHOLD    0x72
#define K3_ISEL_EIP0           0x80
#define K3_ISEL_EIE0           0xC0
#define K3_MEXT_IID            1

#define RVMODEL_SET_MEXT_INT(_R1, _R2)         \
    li   _R1, K3_ISEL_EIDELIVERY              ;\
    csrw K3_CSR_MISELECT, _R1                 ;\
    li   _R2, 1                               ;\
    csrw K3_CSR_MIREG, _R2                    ;\
    li   _R1, K3_ISEL_EITHRESHOLD             ;\
    csrw K3_CSR_MISELECT, _R1                 ;\
    csrw K3_CSR_MIREG, zero                   ;\
    li   _R1, K3_ISEL_EIE0                    ;\
    csrw K3_CSR_MISELECT, _R1                 ;\
    li   _R2, 1 << K3_MEXT_IID                ;\
    csrs K3_CSR_MIREG, _R2                    ;\
    li   _R1, K3_ISEL_EIP0                    ;\
    csrw K3_CSR_MISELECT, _R1                 ;\
    csrs K3_CSR_MIREG, _R2

#define RVMODEL_CLR_MEXT_INT(_R1, _R2)         \
    li   _R1, K3_ISEL_EIP0                    ;\
    csrw K3_CSR_MISELECT, _R1                 ;\
    li   _R2, 1 << K3_MEXT_IID                ;\
    csrc K3_CSR_MIREG, _R2

#define RVMODEL_SET_MSW_INT(_R1, _R2)  \
    LOAD_ADDR32(_R2, K3_MSIP_ADDRESS) ;\
    li _R1, 1                         ;\
    sw _R1, 0(_R2);

#define RVMODEL_CLR_MSW_INT(_R1, _R2)  \
    LOAD_ADDR32(_R2, K3_MSIP_ADDRESS) ;\
    sw zero, 0(_R2);

##### Supervisor Interrupts #####

// RVMODEL_SET/CLR_SEXT_INT and RVMODEL_SET/CLR_SSW_INT are left undefined on purpose: ACT then
// raises them through mip.SEIP and mip.SSIP (tests/env/check_defines.h, rvtest_setup.h), which
// the K3 implements. Defining them empty told ACT a controller exists and raised nothing
// (k3-uart-weekly #5: every SEI/SSI test took the timer interrupt instead).

##### Guest External Interrupts #####

// The X100 has 7 guest interrupt files (GEILEN 7, hgeie writable 0xfe), so ACT needs a way to set
// and clear an hgeip bit. On the K3 that is a write to a guest interrupt file of the AIA IMSIC,
// whose addresses (hart and guest index bits of the IMSIC at 0xe0400000) are not measured on the
// board yet. Until then these raise nothing, as in the K3 hypervisor config
// (megrez-hypervisor-sail015): the Sail reference build replaces them with its own
// (sail_macros.h), and on the board the few tests that need a guest external interrupt fail
// visibly instead of blocking every build.
// TODO: implement via the K3 IMSIC guest interrupt files and verify on the board.
#define RVMODEL_SET_GUEST_EXT_INT(_GEI, _R1, _R2)
#define RVMODEL_CLR_GUEST_EXT_INT(_GEI, _R1, _R2)

##### Sscofpmf #####

// Counter and event for the Sscofpmf tests (required by ACT act4 since the Sscofpmf suites).
// SpacemiT X100 (K3): event 0x06 counts loads; source: the K3 Pico-ITX device tree in the board's u-boot.itb maps the SBI L1D read-access event (0x10000) to 0x06 on counters 3-16 (riscv,event-to-mhpmevent).
// Documented, not yet measured on the board. The Sail reference counts EV_FENCE for the same
// selector (sail.json event_selectors) and the reference build triggers it with a fence.
#define RVMODEL_HPM_COUNTER 3
#define RVMODEL_MHPMEVENT_VAL 0x06
#define RVMODEL_MHPMEVENT_CODE(_R1, _R2) \
    lw _R2, 0(_R1)

#endif // _RVMODEL_MACROS_H
