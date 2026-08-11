// --------------------------------------------------------------------------------------------------------------------------------
// svh_two_stage_rw_VSmode.S
// Config: sail-rv32-max | VS=Sv32 + G=Sv32x4 (both ON)
// Pair:   svh_two_stage_rw_sv39_VSmode.S
// Coverpoints mapped (SvH_cg): two_stage_write, two_stage_read
// What this proves (one line):
//   VS store/load through both stages reaches the real SPA.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. VS sw/lw through two-stage translation (GVA→GPA→SPA) → Successful
//  2. M-mode SPA readback confirms VS store → Successful
//
// Total Expected Faults :: 0
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_two_stage_rw_VSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 16
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set va_data,                 0x008001000     // GVA used by VS sw/lw (data)
  .set va_code,                 0x90000000      // GVA where VS executes this code
  .set gpa_data,                0x00C002000     // GPA behind va_data
  .set gpa_code,                0x012000000     // GPA behind va_code (4 MiB aligned)
  .set gpa_rvtest_Vroot_pg_tbl, 0x01000A000     // GPA of VS root page table
  .set gpa_rvtest_vlvl0_pg_tbl, 0x01000B000     // GPA of VS level-0 page table

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- G-stage (hgatp Sv32x4): GPA -> PA  (walks as U-mode → U=1 on leaves) ----
  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)  // gpa_code -> PA(code); LEVEL1 = 4 MiB leaf

  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL1)  // non-leaf: G VPN1 slot -> G L0 table
  G_PTE_SETUP(sv32x4, rvtest_Vroot_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL0)  // leaf: GPA(VS root) -> PA(VS root) R/W
  G_PTE_SETUP(sv32x4, rvtest_vlvl0_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl0_pg_tbl, LEVEL0)  // leaf: GPA(VS L0) -> PA(VS L0) R/W

  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // non-leaf: G VPN1 for data -> G L0 table
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // leaf: gpa_data -> PA(test_region) R/W

  // ---- VS-stage (vsatp Sv32): GVA -> GPA  (leaf U=0 so VS R/W without SUM) ----

  VS_PTE_SETUP(sv32, GPA, gpa_code, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // leaf: va_code -> gpa_code (X/R)

  csrr a0, mscratch                         // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // VA≠PA code entry

  VS_PTE_SETUP(sv32, GPA, gpa_rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)  // non-leaf: va_data VPN1 -> VS L0 table GPA
  VS_PTE_SETUP(sv32, GPA, gpa_data, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)  // leaf: va_data -> gpa_data (W/R)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv32, GPA)                    // vsatp ON (PPN = GPA of VS root)
  HGATP_SETUP(sv32x4)                       // G-stage ON
  hfence.vvma                               // flush VS-stage TLB
  hfence.gvma                               // flush G-stage TLB (legal in M)

  // Known pattern at SPA before guest store (two_stage_write check from M later)
  LI(t0, 0xDEADBEEF)                        // preload SPA
  la t1, test_region                        // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)

  LI(a5, va_data)                               // a5 = GVA pointer for store/load
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: VS sw/lw through two-stage translation | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a2, 0x257A0005)                            // value to store
  sw   a2, 0(a5)                                // two_stage_write: GVA->GPA->PA store
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // two_stage_read: GVA->GPA->PA load
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test1_vs:                                        // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_vs, test1_vs_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: M-mode SPA readback | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // M-mode: SPA must show guest store (stronger than VS lw alone)
  la t1, test_region                        // t1 = SPA of data page
  lw t2, 0(t1)                              // M-mode SPA readback
  test2_spa:                                        // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, t2, test2_spa, test2_spa_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region:                                    // real PA backing gpa_data
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // align to 4 KiB page
rvtest_hlvl0_pg_tbl:                            // G-stage level-0 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage
.align 12                                       // align to 4 KiB page
rvtest_vlvl0_pg_tbl:                            // VS-stage level-0 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_vs_str:  .string "\"Mismatch on VS lw after two-stage sw in Test Case 1!\""  // mismatch string
test2_spa_str: .string "\"Mismatch on SPA readback after two-stage store in Test Case 2!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //           VS two-stage store/load
  //                      │
  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 1                    Test 2
  //    VS sw (GVA→GPA→SPA)      M read SPA
  //         │                         │
  //    VS + G walk               No VS hop
  //         │                         │
  //         ▼                         ▼
  //    VS lw same GVA            lw test_region
  //         │                         │
  //         ▼                         ▼
  //    0x257A0101                 0x257A0101
