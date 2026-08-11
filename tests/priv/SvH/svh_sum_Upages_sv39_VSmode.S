// --------------------------------------------------------------------------------------------------------------------------------
// svh_sum_Upages_sv39_VSmode.S
// Config: sail-rv64-max | VS=Sv39 ON, hgatp=Bare
// Pair:   svh_sum_Upages_VSmode.S
// Coverpoints mapped (SvH_cg): cp_vsatp_sum_effects_rw, vsatp_sum_set
// What this proves (one line):
//   VS SUM controls whether VS can R/W U=1 pages (fault when SUM=0).
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. SUM=0: VS lw of U=1 page → Expected Fault (a3 stays 0)
//  2. SUM=0: SPA still poisoned (0xDEADBEEF) → Successful
//  3. SUM=1: VS lw of U=1 page → Successful (0x257A0201)
//  4. SUM=1: SPA readback confirms store → Successful (0x257A0201)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_sum_Upages_sv39_VSmode.S"
#define SIGUPD_COUNT 4
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set va_data,                 0x008001000     // GVA for U=1 data page (SUM target)
  .set va_code,                 0x0000000090000000      // GVA where VS executes this code (U=0)

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- VS-stage (vsatp Sv39): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)  // VS non-leaf: va_code VPN2 → VS L1 table PA
  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // leaf: va_code -> PA(code); LEVEL1 = 4 MiB X/R

  csrr a0, mscratch                         // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // VA≠PA code entry

  // Data page: U=1 leaf with full XWR (coverpoint vs_pte_xwr111_u_d = 8'b11?11111)
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_data, LEVEL2)  // VS non-leaf: va_data VPN2 → VS L1 table PA
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)  // non-leaf: va_data VPN1 -> VS L0 table PA
  VS_PTE_SETUP(sv39, PA, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)  // leaf: va_data -> PA(test_region) U=1 R/W/X


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv39, PA)                     // vsatp ON (PPN = PA of VS root)
  csrw hgatp, x0                            // hgatp Bare
  hfence.vvma                               // flush VS-stage TLB
  hfence.gvma                               // flush G-stage TLB (legal in M)

  LI(t0, 0xDEADBEEF)                        // preload SPA
  la t1, test_region                        // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)

  LI(a5, va_data)                               // a5 = GVA pointer for guest load/store


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: SUM=0 VS lw of U=1 page | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrc sstatus, t0                              // clear HS SUM (shadow for vsstatus)
  csrc vsstatus, t0                             // clear VS SUM — guest cannot touch U=1 pages
  LI(a3, 0)                                     // a3 stays 0 if lw is skipped by trap handler
  LI(a4, 0)                                     // a4 stays 0 if sw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a3, 0(a5)                                // U=1 page with SUM=0 → load-page-fault; insn skipped
  nop                                           // trap-skip pad
  sw   a4, 0(a5)                                // same leaf → store-page-fault; insn skipped
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test1_sum0_lw:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_sum0_lw, test1_sum0_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: SUM=0 SPA unchanged | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // M-mode: SPA must still be poison (SUM=0 guest store never committed)
  la t1, test_region                        // t1 = SPA of data page
  lw t2, 0(t1)                              // M-mode SPA readback
  test2_sum0_spa:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, t2, test2_sum0_spa, test2_sum0_spa_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: SUM=1 VS lw of U=1 page | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // Split store and load into separate VS entries so each access re-walks the leaf.
  // A TLB hit would drop VS_PTE_D from .rvvi and miss coverpoint leaf_pte on the second access.
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest may R/W U=1 pages
  hfence.vvma                                   // flush stale TLB entries after SUM change

  LI(a6, 0x257A0201)                            // value to store through U=1 page
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   a6, 0(a5)                                // SUM=1 store through U=1 leaf → SPA
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  hfence.vvma                                   // force next VS load to page-walk (coverpoint sampling)
  LI(a7, 0)                                     // a7 will hold VS load result
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a7, 0(a5)                                // SUM=1 load of U=1 page; expect 0x257A0201
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test3_sum1_lw:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test3_sum1_lw, test3_sum1_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: SUM=1 SPA readback | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // M-mode: SPA must show guest store (stronger than VS lw alone)
  la t1, test_region                        // t1 = SPA of data page
  lw t3, 0(t1)                              // M-mode SPA readback
  test4_sum1_spa:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, t3, test4_sum1_spa, test4_sum1_spa_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region:                                    // real PA backing va_data (U=1 leaf target)
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)

.align 12                                       // align to 4 KiB page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_vlvl1_pg_tbl:                            // VS-stage L1 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage
rvtest_vlvl0_pg_tbl:                            // VS-stage level-0 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_sum0_lw_str:  .string "\"Mismatch on SUM=0 lw of U=1 page (expect fault) in Test Case 1!\""  // mismatch string
test2_sum0_spa_str: .string "\"Mismatch on SPA unchanged after SUM=0 in Test Case 2!\""  // mismatch string
test3_sum1_lw_str:  .string "\"Mismatch on SUM=1 lw of U=1 page in Test Case 3!\""  // mismatch string
test4_sum1_spa_str: .string "\"Mismatch on SPA after SUM=1 store in Test Case 4!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                VS SUM controls whether VS can R/W U=1 pages (fau...
  //                      │
  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 1                             Test 2
  //         │                         │
  //      SUM=0                      SUM=0
  //         │                         │
  //      VS lw of U=1 page          SPA still poisoned
  //         ▼                         ▼
  //      FAULT a3=0                 PASS

  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 3                             Test 4
  //         │                         │
  //      SUM=1                      SUM=1
  //         │                         │
  //      VS lw of U=1 page          SPA rdback confirms
  //         ▼                         ▼
  //      0x257A0201                 0x257A0201
