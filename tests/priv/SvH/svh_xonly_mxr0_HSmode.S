// --------------------------------------------------------------------------------------------------------------------------------
// svh_xonly_mxr0_HSmode.S
// Config: sail-rv32-max | vsatp=Sv32, hgatp=Bare, HS HLV SPVP=1, MXR=0
// Coverpoints mapped (SvH_cg): xonly_mxr0_vs_hs
// What this proves (one line):
//   HS HLV through VS X-only leaf with MXR=0 raises load-page-fault.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. MXR=0, SPVP=1, VS X-only: HS hlv.w → Expected Fault (a3 stays 0)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_xonly_mxr0_HSmode.S"
#define SIGUPD_COUNT 1
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_x, 0x008001000                        // GVA of X-only VS leaf (HS HLV address)

  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_x, LEVEL1)  // VS non-leaf: va_x VPN1 → VS L0 table PA
  VS_PTE_SETUP(sv32, PA, test_region_x, (PTE_D | PTE_A | PTE_X | PTE_V), va_x, LEVEL0)  // VS leaf: va_x → PA(test_region_x) X-only (R=0 W=0) U=0

  VSATP_SETUP(sv32, PA)                         // vsatp = Sv32 — HLV walks VS-stage with this root
  csrw hgatp, x0                                // hgatp Bare — VS GVA→PA only
  hfence.vvma                                   // flush VS-stage TLB after PTE install
  hfence.gvma                                   // flush G-stage TLB

  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // bits to clear: MXR (X-as-R) and SUM
  csrc sstatus, t0                              // sstatus MXR=0 SUM=0 (HLV uses these for VS-stage checks)
  csrc vsstatus, t0                             // vsstatus MXR=0 SUM=0

  LI(t0, HSTATUS_SPVP)                          // SPVP=1 → HLV checks perms as VS (not VU)
  csrs hstatus, t0                              // set hstatus.SPVP so HLV acts like VS on U=0 leaf

  LI(t0, 0x257A0811)                            // poison at SPA — successful HLV would copy this into a3
  la t1, test_region_x                          // t1 = SPA of X-only page
  sw t0, 0(t1)                                  // M store via PA

  LI(a5, va_x)                                  // a5 = GVA for HLV
  LI(a3, 0)                                     // sentinel — stays 0 if HLV page-faults
  RVTEST_TSBI_GOTO_SMODE                       // T-SBI: ecall a0=2 → HS (HLV legal in HS; code at PA)
  hlv.w a3, (a5)                                // HS HLV of VS X-only leaf, MXR=0 SPVP=1 → load page-fault
  nop                                           // trap-skip padding after faulting HLV
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M

  LI(t0, HSTATUS_SPVP)                          // restore SPVP after the case
  csrc hstatus, t0                              // clear hstatus.SPVP

  test1_hlv:                                    // signature dump point for case 1
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_hlv, test1_hlv_str)  // dump a3 (expect 0)

RVTEST_CODE_END
RVTEST_DATA_BEGIN
.align 12                                       // 4 KiB page align
test_region_x:                                  // SPA backing va_x (X-only VS leaf)
  .word 0                                       // payload word (preloaded in M; HLV must not read)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
test1_hlv_str: .string "\"Mismatch on HS HLV X-only MXR=0 (expect fault) in Test Case 1!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
