// --------------------------------------------------------------------------------------------------------------------------------
// svh_xonly_mxr0_gstage_HSmode.S
// Config: sail-rv32-max | vsatp=Bare, hgatp=Sv32x4, HS HLV, MXR=0
// Coverpoints mapped (SvH_cg): xonly_mxr0_g_hs
// What this proves (one line):
//   HS HLV of G-stage X-only leaf with MXR=0 raises guest-page-fault.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. G X-only U=1, MXR=0: HS hlv.w → Expected Fault (a3 stays 0)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_xonly_mxr0_gstage_HSmode.S"
#define SIGUPD_COUNT 1
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set gpa_data, 0x00C002000                    // GPA HS HLV will use (G X-only leaf → test_region SPA)
  .set gpa_code, 0x80000000                     // GPA of code identity superpage (4 MiB aligned)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------
  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)  // G superpage: gpa_code → PA(code) U=1 X/R; LEVEL1 = 4 MiB
  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf: VPN1 for data GPA → G L0
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V), gpa_data, LEVEL0)  // G leaf: gpa_data → PA(test_region) U=1 X-only (R=0 W=0)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  csrw vsatp, x0                            // VS Bare
  HGATP_SETUP(sv32x4)                       // G-stage ON
  hfence.vvma                               // flush VS-stage TLB
  hfence.gvma                               // flush G-stage TLB (legal in M)

  LI(t0, SSTATUS_MXR)                           // MXR bit — if 1, X-only would be readable
  csrc sstatus, t0                              // sstatus.MXR=0 so G X-only is not readable
  csrc vsstatus, t0                             // vsstatus.MXR=0 (G walk still honors MXR=0)

  LI(t0, 0x257A0821)                        // preload SPA
  la t1, test_region                        // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)

// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: G X-only U=1, MXR=0: HS hlv.w | Expected: Expected Fault (a3 stays 0)
//---------------------------------------------------------------------------------------------------------------------------------

  LI(t1, gpa_data)                              // t1 = GPA for HLV
  LI(a3, 0)                                     // sentinel — stays 0 if HLV guest-page-faults
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  hlv.w a3, (t1)                                // HS HLV of G X-only U=1 leaf, MXR=0 → guest-page-fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test1_g_xonly:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_g_xonly, test1_g_xonly_str) // SIGUPD

RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data
// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing gpa_data (G X-only leaf)
  .word 0                                       // payload word (preloaded in M; HLV must not read)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_g_xonly_str: .string "\"Mismatch on HS HLV G X-only MXR=0 (expect fault) in Test Case 1!\""  // mismatch string
RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                HS HLV of G-stage X-only leaf with MXR=0 raises g...
  //                      │
  //              Test 1
  //                      │
  //              G X-only U=1, MXR=0
  //                      │
  //              HS hlv.w
  //                      ▼
  //              FAULT a3=0
