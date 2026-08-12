// --------------------------------------------------------------------------------------------------------------------------------
// svh_hgatp_bare_trans_VSmode.S
// Config: sail-rv32-max | VS=Sv32 ON, hgatp=Bare
// Pair:   svh_hgatp_bare_trans_sv39_VSmode.S
// Coverpoints mapped (SvH_cg): cp_hgatp_bare_trans
// What this proves (one line):
//   With hgatp Bare, VS Sv32 alone turns GVA into the real physical address.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. VS sw/lw through VS paging with hgatp=Bare (GVA→GPA→SPA) → Successful
//  2. M-mode SPA readback confirms VS store → Successful
//  3. hgatp readback still Bare → Successful
//
// Total Expected Faults :: 0
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_hgatp_bare_trans_VSmode.S"
#define SIGUPD_COUNT 3
#define TRAP_SIGUPD_COUNT 16
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set va_data, 0x008001000                     // guest VA for data
  .set va_code, 0x90000000                      // guest VA for code

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- VS-stage (vsatp Sv32): GVA -> GPA; hgatp Bare ⇒ GPA==SPA ----
  SUPERPAGE_VS_PTE_SETUP(sv32, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // map va_code → PA(code), 4 MiB leaf

  csrr a0, mscratch                         // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // VA≠PA code entry

  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)  // non-leaf → L0 table (PA)
  VS_PTE_SETUP(sv32, PA, test_region, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)  // leaf: va_data → PA(test_region)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv32, PA)                     // vsatp ON (PPN = PA of VS root)
  csrw hgatp, x0                            // hgatp Bare
  hfence.vvma                               // flush VS-stage TLB
  hfence.gvma                               // flush G-stage TLB (legal in M)

  LI(t0, 0xDEADBEEF)                        // preload SPA
  la t1, test_region                        // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)

  LI(a5, va_data)                               // a5 = guest VA pointer
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: VS sw/lw with hgatp=Bare | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a2, 0x257A0031)                            // value to store
  sw   a2, 0(a5)                                // cp_hgatp_bare_trans: GVA→GPA (VS only; GPA==SPA)
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // load back through VS paging
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test1_vs:                                        // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_vs, test1_vs_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: M-mode SPA readback | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  la t1, test_region                        // t1 = SPA of data page
  lw t2, 0(t1)                              // M-mode SPA readback
  test2_spa:                                        // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, t2, test2_spa, test2_spa_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: hgatp readback still Bare | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  test3_hgatp:                                      // SIGUPD label
  RVTEST_SIGUPD_CSR_READ(hgatp, a4, test3_hgatp, test3_hgatp_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                      // 4 KiB page align
test_region:                                  // SPA backing for va_data leaf
  .word 0                                     // payload word (initially poisoned in M)
  .word 0                                     // padding in same page
  .word 0                                     // padding in same page
  .word 0                                     // padding in same page


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                      // 4 KiB page align
rvtest_vlvl0_pg_tbl:                          // VS-stage L0 PTE storage (4 KiB)
  .zero(4096)                                  // reserve 4 KiB page-table storage


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_vs_str:    .string "\"Mismatch on VS lw after sw (hgatp Bare) in Test Case 1!\""  // mismatch string
test2_spa_str:   .string "\"Mismatch on SPA readback after VS store in Test Case 2!\""  // mismatch string
test3_hgatp_str: .string "\"Mismatch on hgatp readback (expect Bare) in Test Case 3!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                With hgatp Bare, VS Sv32 alone turns GVA into the...
  //                      │
  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 1                      Test 2                      Test 3          
  //                │                           │                           │             
  //       VS sw/lw through VS          M-mode SPA rdback        hgatp rdback still Bare  
  //                ▼                           ▼                           ▼             
  //          GPA→SPA) → OK                    PASS                        PASS           
