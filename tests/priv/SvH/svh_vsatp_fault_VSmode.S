// --------------------------------------------------------------------------------------------------------------------------------
// svh_vsatp_fault_VSmode.S
// Config: sail-rv32-max | VS=Sv32 ON, hgatp=Bare
// Coverpoints mapped (SvH_cg): cp_vsatp_invalid_pte, cp_vsatp_nonleaf_lvl0
// What this proves (one line):
//   VS faults on V=0/nonleaf lw+sw; HS HLV/HSV with SPVP=1 fault invalid PTE.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. VS lw of V=0 leaf at va_inv → Expected Fault (a3 stays 0)
//  2. VS sw of V=0 leaf at va_inv → Expected Fault (s2 stays 0)
//  3. VS lw of L0 non-leaf at va_nleaf → Expected Fault (a4 stays 0)
//  4. VS sw of L0 non-leaf at va_nleaf → Expected Fault (s3 stays 0)
//  5. HS hlv.w with SPVP=1 on V=0 leaf → Expected Fault (a6 stays 0)
//  6. HS hsv.w with SPVP=1 on V=0 leaf → Expected Fault (s4 stays 0)
//  7. Restore valid leaf at va_ok; VS lw → Successful (0x257A0310)
//  8. VS jalr to V=0 leaf at va_inv → Expected Fault (fetch-page-fault; s5 stays 0)
//
// Total Expected Faults :: 7
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vsatp_fault_VSmode.S"
#define SIGUPD_COUNT 8
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set va_ok,     0x008001000                    // GVA for valid R/W leaf (case 7 baseline)
  .set va_inv,    0x008002000                    // GVA for V=0 invalid leaf
  .set va_nleaf,  0x008003000                    // GVA for L0 non-leaf PTE
  .set va_code,   0x90000000                     // GVA where VS executes this code (VA≠PA)

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- VS-stage (vsatp Sv32): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  SUPERPAGE_VS_PTE_SETUP(sv32, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // VS superpage: va_code → PA(code); X/R A=D=1

  csrr a0, mscratch                         // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // VA≠PA code entry

  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_ok, LEVEL1)  // VS non-leaf: data VPN1 → VS L0 table PA

  VS_PTE_SETUP(sv32, PA, test_region_ok, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V), va_ok, LEVEL0)  // VS leaf: va_ok → PA(test_region_ok) R/W A=D=1 V=1
  VS_PTE_SETUP(sv32, PA, test_region_inv, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R), va_inv, LEVEL0)  // VS leaf: va_inv V=0 (X set so invalid_pte_x matches)
  VS_PTE_SETUP(sv32, PA, test_region_nleaf, (PTE_V), va_nleaf, LEVEL0)  // VS L0 non-leaf: V=1 XWR=000 (illegal at leaf level)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv32, PA)                     // vsatp ON (PPN = PA of VS root)
  csrw hgatp, x0                            // hgatp Bare
  hfence.vvma                               // flush VS-stage TLB
  hfence.gvma                               // flush G-stage TLB (legal in M)

  LI(t0, 0x257A0310)                        // preload SPA
  la t1, test_region_ok                     // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: VS lw of V=0 leaf | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_inv)                                // a5 = GVA of V=0 leaf
  LI(a3, 0)                                     // sentinel — stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a3, 0(a5)                                // VS load: V=0 leaf → load page-fault (a3 stays 0)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test1_v0_lw:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_v0_lw, test1_v0_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: VS sw of V=0 leaf | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_inv)                                // a5 = GVA of V=0 leaf
  LI(s2, 0)                                     // sentinel — stays 0 if store page-faults
  LI(t0, 0xDEADBEEF)                            // store payload (must not land at SPA)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store: V=0 leaf → store page-fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test2_v0_sw:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test2_v0_sw, test2_v0_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: VS lw of L0 non-leaf | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_nleaf)                              // a5 = GVA pointing at L0 non-leaf PTE
  LI(a4, 0)                                     // sentinel — stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a4, 0(a5)                                // VS load: non-leaf at L0 → load page-fault (a4 stays 0)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test3_nleaf_lw:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test3_nleaf_lw, test3_nleaf_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: VS sw of L0 non-leaf | Expected: Expected Fault
// Coverpoints: cp_vsatp_nonleaf_lvl0_rw
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_nleaf)                              // a5 = GVA of L0 non-leaf
  LI(s3, 0)                                     // sentinel — stays 0 if store page-faults
  LI(t0, 0xCAFEBABE)                            // store payload (must not land)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store: non-leaf at L0 → store page-fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test4_nleaf_sw:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test4_nleaf_sw, test4_nleaf_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: HS hlv.w on V=0 leaf with SPVP=1 | Expected: Expected Fault
// Coverpoints: cp_vsatp_invalid_pte_rw
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, HSTATUS_SPVP)                          // t0 = SPVP bit mask (hstatus[8])
  csrs hstatus, t0                              // SPVP=1 → HLV uses VS-stage translation
  LI(a5, va_inv)                                // a5 = GVA of V=0 leaf
  LI(a6, 0)                                     // sentinel — stays 0 if hlv.w page-faults
  RVTEST_GOTO_LOWER_MODE HSmode                 // M→HS (mret; HS uses vsatp when SPVP=1)
  hlv.w a6, (a5)                                // HS hyper-load through vsatp V=0 → page-fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test5_hlv:                                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test5_hlv, test5_hlv_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: HS hsv.w on V=0 leaf with SPVP=1 | Expected: Expected Fault
// Coverpoints: cp_vsatp_invalid_pte_rw
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_inv)                                // a5 = GVA of V=0 leaf
  LI(s4, 0)                                     // sentinel — stays 0 if hsv.w page-faults
  LI(t0, 0xBADCAFE)                             // store payload (must not land)
  RVTEST_GOTO_LOWER_MODE HSmode                 // M→HS
  hsv.w t0, (a5)                                // HS hyper-store through vsatp V=0 → page-fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  LI(t0, HSTATUS_SPVP)                          // t0 = SPVP bit mask
  csrc hstatus, t0                              // clear SPVP (tidy for harness)

  test6_hsv:                                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s4, test6_hsv, test6_hsv_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: Valid leaf VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_ok)                                  // a5 = GVA of valid R/W leaf
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a7, 0(a5)                                // VS load through valid leaf; expect 0x257A0310
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test7_ok:                                        // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test7_ok, test7_ok_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: VS jalr into V=0 leaf | Expected: Expected Fault (cp_vsatp_invalid_pte_x)
// Redirect ifetch walks the V=0 leaf; sail_to_rvvi promotes that walk to VS_PTE_I + TRAP.
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_inv)                                // a5 = GVA of V=0 leaf (not a legal fetch target)
  LI(s5, 0)                                     // sentinel — stays 0 if target never runs
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  nop                                           // pad so priv_mode_vs samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch of V=0 leaf → fetch page-fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test8_v0_ifetch:                                 // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s5, test8_v0_ifetch, test8_v0_ifetch_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region_ok:                                 // SPA backing va_ok (valid R/W leaf)
  .word 0                                       // payload word (preloaded 0x257A0310)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_inv:                                // SPA behind V=0 leaf (must never be accessed)
  .word 0                                       // unused payload
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_nleaf:                              // SPA named as L0 non-leaf PTE target (XWR=000)
  .word 0                                       // unused payload
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_v0_lw_str:    .string "\"Mismatch on VS lw of V=0 leaf (expect fault) in Test Case 1!\""  // mismatch string
test2_v0_sw_str:    .string "\"Mismatch on VS sw of V=0 leaf (expect fault) in Test Case 2!\""  // mismatch string
test3_nleaf_lw_str: .string "\"Mismatch on VS lw of L0 non-leaf (expect fault) in Test Case 3!\""  // mismatch string
test4_nleaf_sw_str: .string "\"Mismatch on VS sw of L0 non-leaf (expect fault) in Test Case 4!\""  // mismatch string
test5_hlv_str:      .string "\"Mismatch on HS hlv.w of V=0 leaf (expect fault) in Test Case 5!\""  // mismatch string
test6_hsv_str:      .string "\"Mismatch on HS hsv.w of V=0 leaf (expect fault) in Test Case 6!\""  // mismatch string
test7_ok_str:       .string "\"Mismatch on VS lw of valid leaf in Test Case 7!\""  // mismatch string
test8_v0_ifetch_str:.string "\"Mismatch on VS ifetch of V=0 leaf (expect fault) in Test Case 8!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                VS faults on V=0/nonleaf lw+sw; HS HLV/HSV with S...
  //                      │
  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 1                      Test 2                      Test 3          
  //                │                           │                           │             
  //        VS lw of V=0 leaf           VS sw of V=0 leaf          VS lw of L0 non-leaf   
  //                ▼                           ▼                           ▼             
  //            FAULT a3=0                  FAULT s2=0                  FAULT a4=0        

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 4                      Test 5                      Test 6          
  //                │                           │                           │             
  //       VS sw of L0 non-leaf      HS hlv.w with SPVP=1 on     HS hsv.w with SPVP=1 on  
  //                ▼                           ▼                           ▼             
  //            FAULT s3=0                  FAULT a6=0                  FAULT s4=0        

  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 7                             Test 8
  //         │                         │
  //      Restore valid leaf         VS jalr to V=0 leaf
  //         │                         │
  //      VS lw                      FAULT fetch flt s5=0
  //         ▼                         ▼
  //      0x257A0310                 
