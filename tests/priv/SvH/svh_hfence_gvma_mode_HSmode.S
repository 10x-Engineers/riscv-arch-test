// --------------------------------------------------------------------------------------------------------------------------------
// svh_hfence_gvma_mode_HSmode.S
// Config: sail-rv32-max | Bare↔Sv32x4 + HFENCE.GVMA
// Coverpoints mapped (SvH_cg): cp_hgatp_mode_change_hfence
// What this proves (one line):
//   Changing hgatp.MODE then HFENCE.GVMA keeps HS HLV coherent.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. hgatp Bare→Sv32x4 + HFENCE.GVMA x0,x0; HS HLV → Successful (0x257A0911)
//  2. hgatp Sv32x4→Bare + HFENCE.GVMA; HS HLV of SPA → Successful (0x257A0912)
//
// Total Expected Faults :: 0
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_hfence_gvma_mode_HSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set gpa_data, 0x00C002000                    // GPA HS HLV uses after hgatp becomes Sv32x4
  .set gpa_code, 0x80000000                     // GPA of code identity superpage (4 MiB aligned)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------
  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)  // G superpage: gpa_code → PA(code) U=1 X/R; LEVEL1 = 4 MiB
  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf: VPN1 for data GPA → G L0
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf: gpa_data → PA(test_region) U=1 R/W A=D=1


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  csrw vsatp, x0                                // vsatp Bare — HLV address is a GPA when G is on
  csrw hgatp, x0                                // start Bare (address used as-is until MODE switch)
  hfence.gvma                                   // flush G TLB after forcing Bare

  LI(t0, 0x257A0911)                        // preload SPA
  la t1, test_region                        // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
  HGATP_SETUP(sv32x4)                           // Bare → Sv32x4 (G paging now on)
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  hfence.gvma                                   // HS HFENCE.GVMA x0,x0 after MODE change: drop stale Bare G TLB
  LI(t1, gpa_data)                              // t1 = GPA (must walk G now, not treat as SPA)
  hlv.w a3, (t1)                                // HS HLV of GPA through new Sv32x4 map; expect 0x257A0911
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test1_bare_to_paged:                              // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_bare_to_paged, test1_bare_to_paged_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0x257A0912)                        // preload SPA
  la t1, test_region                        // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)

  csrw hgatp, x0                                // Sv32x4 → Bare (HLV address is now SPA)
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  hfence.gvma                                   // HS HFENCE.GVMA after MODE change: drop stale paged G TLB
  la t1, test_region                            // t1 = SPA (Bare: HLV uses address as-is)
  hlv.w a3, (t1)                                // HS HLV of SPA under Bare; expect 0x257A0912
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test2_paged_to_bare:                              // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test2_paged_to_bare, test2_paged_to_bare_str) // SIGUPD

RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data
// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing gpa_data (and Bare HLV target)
  .word 0                                       // data word (preloaded in M)
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
test1_bare_to_paged_str: .string "\"Mismatch on Bare→Paged HFENCE.GVMA HLV in Test Case 1!\""  // mismatch string
test2_paged_to_bare_str: .string "\"Mismatch on Paged→Bare HFENCE.GVMA HLV in Test Case 2!\""  // mismatch string
RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                hgatp MODE change
  //                      │
  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 1                    Test 2
  //    Bare → Sv32x4              Sv32x4 → Bare
  //         │                         │
  //    HFENCE.GVMA               HFENCE.GVMA
  //         │                         │
  //         ▼                         ▼
  //    HLV(gpa_data)             HLV(test_region)
  //         │                         │
  //      G walk                    No G walk
  //         │                         │
  //         ▼                         ▼
  //  test_region / SPA          test_region / SPA
  //         │                         │
  //    0x257A0911                 0x257A0912
