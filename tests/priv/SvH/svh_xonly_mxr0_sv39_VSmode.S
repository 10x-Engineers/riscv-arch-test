// --------------------------------------------------------------------------------------------------------------------------------
// svh_xonly_mxr0_sv39_VSmode.S
// Config: sail-rv64-max | VS=Sv39 ON, hgatp=Bare, MXR=0
// Pair:   svh_xonly_mxr0_VSmode.S
// Coverpoints mapped (SvH_cg): xonly_mxr0_vs_vs
// What this proves (one line):
//   VS load of X-only page with MXR=0 raises load-page-fault.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. MXR=0 SUM=0, S-page X-only: VS lw → Expected Fault (a3 stays 0)
//  2. MXR=0 SUM=0, S-page X-only: VS ifetch OK on code (control) → Successful (a4=0x257A0802)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_xonly_mxr0_sv39_VSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set va_x,    0x008001000                     // GVA of X-only data page (VS lw target)
  .set va_code,                 0x0000000090000000  // GVA where VS executes this code (VA≠PA; X/R)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)  // VS non-leaf: va_code VPN2 → VS L1 table PA
  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // VS leaf: va_code → PA(code) X/R A=D=1 U=0; LEVEL1 = 2 MiB
  csrr a0, mscratch                         // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // VA≠PA code entry

  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_x, LEVEL2)  // VS non-leaf: va_x VPN2 → VS L1 table PA
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_x, LEVEL1)  // VS non-leaf: va_x VPN1 → VS L0 table PA
  VS_PTE_SETUP(sv39, PA, test_region_x, (PTE_D | PTE_A | PTE_X | PTE_V), va_x, LEVEL0)  // VS leaf: va_x → PA(test_region_x) X-only (R=0 W=0) U=0


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv39, PA)                     // vsatp ON (PPN = PA of VS root)
  csrw hgatp, x0                            // hgatp Bare
  hfence.vvma                               // flush VS-stage TLB
  hfence.gvma                               // flush G-stage TLB (legal in M)

  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // bits to clear: MXR (X-as-R) and SUM (S access to U)
  csrc sstatus, t0                              // HS sstatus: MXR=0 SUM=0
  csrc vsstatus, t0                             // vsstatus: MXR=0 SUM=0 so VS cannot read X-only

  LI(t0, 0x257A0801)                        // preload SPA
  la t1, test_region_x                      // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: VS lw X-only MXR=0 | Expected: Expected Fault (sentinel 0)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x)                                  // a5 = GVA of X-only page
  LI(a3, 0)                                     // sentinel — stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a3, 0(a5)                                // VS load X-only with MXR=0 → load page-fault (a3 stays 0)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test1_mxr0_lw:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_mxr0_lw, test1_mxr0_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: Control addi (no memory) | Expected: Successful (0x257A0802)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a4, 0x257A0801)                            // control start value (same pattern as SPA poison)
  addi a4, a4, 1                                // a4 = 0x257A0802 — proves VS ifetch of X/R code returned to M
  test2_ctrl:                                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_ctrl, test2_ctrl_str)  // record control (expect 0x257A0802)

RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data
// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region_x:                                  // SPA backing va_x (X-only VS leaf)
  .word 0                                       // payload word (preloaded in M; VS must not read)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_vlvl1_pg_tbl:                            // VS-stage L1 (mid) PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_mxr0_lw_str: .string "\"Mismatch on VS X-only MXR=0 lw (expect fault) in Test Case 1!\""  // mismatch string
test2_ctrl_str:    .string "\"Mismatch on control addi in Test Case 2!\""  // mismatch string
RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                VS load of X-only page with MXR=0 raises load-pag...
  //                      │
  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 1                             Test 2
  //         │                         │
  //      MXR=0 SUM=0, S-page        MXR=0 SUM=0, S-page
  //         │                         │
  //      VS lw                      VS ifetch OK on code
  //         ▼                         ▼
  //      FAULT a3=0                 a4=0x257A0802
