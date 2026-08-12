// --------------------------------------------------------------------------------------------------------------------------------
// svh_two_stage_mxr_VUmode.S
// Config: sail-rv32-max | VU + VS=Sv32 + G=Sv32x4 (both ON)
// Pair:   svh_two_stage_mxr_sv39_VUmode.S
// Coverpoints mapped (SvH_cg): cp_two_stage_mxr
// What this proves (one line):
//   In VU, vsstatus.MXR lets loads from U=1 X-only pages; MXR=0 faults those loads (two-stage).
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. VU lw of U=1 X-only page with MXR=0 → Expected Fault (a3 stays 0)
//  2. VU lw of U=1 X-only page with MXR=1 → Successful (0x257A0101)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_two_stage_mxr_VUmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set va_data,                 0x008001000     // GVA for the VU load from U=1 X-only data
  .set va_code,                 0x90000000      // GVA where VU executes this code
  .set gpa_data,                0x00C002000     // GPA behind va_data
  .set gpa_code,                0x012000000     // GPA behind va_code (4 MiB aligned)
  .set gpa_rvtest_Vroot_pg_tbl, 0x01000A000     // GPA of VS root page table
  .set gpa_rvtest_vlvl0_pg_tbl, 0x01000B000     // GPA of VS level-0 page table

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- G-stage (hgatp Sv32x4): GPA -> PA; U=1 on leaves (G walk is U-mode) ----
  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)  // gpa_code -> PA(code) so VU can execute
  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL1)  // point G-stage root entry to G L0 table
  G_PTE_SETUP(sv32x4, rvtest_Vroot_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL0)  // map GPA(VS root) -> PA(VS root) for page-table walks
  G_PTE_SETUP(sv32x4, rvtest_vlvl0_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl0_pg_tbl, LEVEL0)  // map GPA(VS L0) -> PA(VS L0) for page-table walks

  // G-stage data leaf: X-only (R=0,X=1), U=1
  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // point G-stage data entry to G L0 table
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V), gpa_data, LEVEL0)  // map gpa_data -> PA(test_region) as execute-only

  // ---- VS-stage (vsatp Sv32): GVA -> GPA; U=1 code + U=1 X-only data (VU requires U=1) ----
  VS_PTE_SETUP(sv32, GPA, gpa_code, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // map va_code -> gpa_code so VU can fetch code
  csrr a0, mscratch                         // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // VA≠PA code entry

  VS_PTE_SETUP(sv32, GPA, gpa_rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)  // point VS data entry to VS L0 table GPA
  VS_PTE_SETUP(sv32, GPA, gpa_data, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V), va_data, LEVEL0)  // map va_data -> gpa_data as U=1 execute-only


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv32, GPA)                    // vsatp ON (PPN = GPA of VS root)
  HGATP_SETUP(sv32x4)                       // G-stage ON
  hfence.vvma                               // flush VS-stage TLB
  hfence.gvma                               // flush G-stage TLB (legal in M)

  LI(t0, 0x257A0101)                        // preload SPA
  la t1, test_region                        // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)

  LI(a5, va_data)                               // a5 = guest virtual address to load


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: MXR=0 load of X-only page | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  // MXR=0: clear in HS before VU entry (VU cannot csrrc sstatus — virtual-instruction)
  LI(t0, SSTATUS_MXR)                           // t0 = bit mask for MXR
  csrc sstatus, t0                              // clear HS sstatus.MXR
  csrc vsstatus, t0                             // clear VS view MXR
  LI(a3, 0)                                     // a3 stays 0 if the load faults and is skipped
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a3, 0(a5)                                // expect fault → skipped
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test1_mxr0:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_mxr0, test1_mxr0_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: MXR=1 load of X-only page | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // MXR=1: set in HS before VU entry
  LI(t0, SSTATUS_MXR)                           // t0 = bit mask for MXR
  csrs sstatus, t0                              // set HS sstatus.MXR
  csrs vsstatus, t0                             // set VS view MXR
  hfence.vvma                                   // status change may affect TLB perm cache; flush VS TLB
  LI(a4, 0)                                     // a4 should receive the real memory value
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a4, 0(a5)                                // expect 0x257A0101
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test2_mxr1:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_mxr1, test2_mxr1_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region:                                    // real PA backing the X-only guest data page
  .word 0                                       // data slot used by the load
  .word 0                                       // padding in the same page
  .word 0                                       // padding in the same page
  .word 0                                       // padding in the same page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // align to 4 KiB page
rvtest_hlvl0_pg_tbl:                            // G-stage level-0 PTE storage
  .zero(4096)                                   // reserve one page for G L0 table
.align 12                                       // align to 4 KiB page
rvtest_vlvl0_pg_tbl:                            // VS-stage level-0 PTE storage
  .zero(4096)                                   // reserve one page for VS L0 table


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_mxr0_str: .string "\"Mismatch on VU MXR=0 X-only load (expect fault) in Test Case 1!\""  // mismatch string
test2_mxr1_str: .string "\"Mismatch on VU MXR=1 X-only load in Test Case 2!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                In VU, vsstatus.MXR lets loads from U=1 X-only pa...
  //                      │
  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 1                             Test 2
  //         │                         │
  //      VU lw of U=1 X-only        VU lw of U=1 X-only
  //         ▼                         ▼
  //      FAULT a3=0                 0x257A0101
