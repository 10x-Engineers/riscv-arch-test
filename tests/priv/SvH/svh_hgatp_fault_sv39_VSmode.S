// --------------------------------------------------------------------------------------------------------------------------------
// svh_hgatp_fault_sv39_VSmode.S
// Config: sail-rv64-max | vsatp=Bare, hgatp=Sv39x4 ON
// Pair:   svh_hgatp_fault_VSmode.S
// Coverpoints mapped (SvH_cg): cp_hgatp_invalid_pte, cp_hgatp_nonleaf_lvl0, hgatp_exception_reporting
// What this proves (one line):
//   Invalid G PTE (V=0) and L0 non-leaf-only entry cause guest-page faults; trap cause matches access type.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. G leaf V=0 (D|A|U|X|W|R set): VS Bare lw → Expected Fault (a3 stays 0)
//  2. G L0 PTE_V only (non-leaf XWR=000): VS Bare lw → Expected Fault (a4 stays 0)
//  3. HS HLV to V=0 GPA → Expected Fault (a6 stays 0)
//  4. HS HSV to V=0 GPA → Expected Fault (s2 stays 0)
//  5. HS HSV to L0 non-leaf GPA → Expected Fault (s3 stays 0)
//  5b. HS HLV to L0 non-leaf GPA → Expected Fault (s5 stays 0)  // nonleaf×read_acc
//  6. Restore valid U=1 R/W G leaf: VS Bare lw → Successful (0x257A0221)
//  7. VS Bare jalr to V=0 G leaf GPA → Expected Fault (fetch-guest-page-fault; s4 stays 0)
//  8. G leaf V=0: VS Bare sw → Expected Fault (SPA unchanged)  // exception_reporting write
//
// Total Expected Faults :: 7
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_hgatp_fault_sv39_VSmode.S"
#define SIGUPD_COUNT 9
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set gpa_data, 0x00C002000                     // GPA for data (vsatp Bare ⇒ address-as-GPA)
  .set gpa_code, 0x0000000080000000                      // identity GPA superpage for code + G PTs at 0x8000_0000

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- G-stage (hgatp Sv39x4 ON): GPA -> PA ----
  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL2)  // gpa_code -> PA(code)

  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_data, LEVEL2)  // G non-leaf: VPN2 for data GPA → G L1
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf: VPN1 for data GPA → G L0
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_G), gpa_data, LEVEL0)  // valid baseline leaf (cases overwrite)

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- vsatp Bare + hgatp ON ----
  csrw vsatp, x0                            // VS Bare
  HGATP_SETUP(sv39x4)                       // G-stage ON
  hfence.vvma                               // flush VS-stage TLB
  hfence.gvma                               // flush G-stage TLB (legal in M)

  LI(t0, 0x257A0221)                        // preload SPA
  la t1, test_region                        // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)

  LI(a5, gpa_data)                              // a5 = GPA pointer for VS Bare lw


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: G leaf V=0 | Expected: Expected Fault
// Coverpoints: cp_hgatp_invalid_pte_rw
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R), gpa_data, LEVEL0)  // U=1 XWR=111
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a3, 0)                                     // sentinel: stays 0 if trap fires
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  lw   a3, 0(a5)                                // invalid G leaf → fault before load completes
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test1_v0:                                        // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_v0, test1_v0_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: G L0 non-leaf PTE_V only | Expected: Expected Fault
// Coverpoints: cp_hgatp_nonleaf_lvl0_rw
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_V), gpa_data, LEVEL0)  // G leaf U=0 V-only (XWR=000 → fault)
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a4, 0)                                     // sentinel: stays 0 if trap fires
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  lw   a4, 0(a5)                                // walk stops at non-leaf L0 → guest-page fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test2_nonleaf:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_nonleaf, test2_nonleaf_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: HS HLV to V=0 GPA | Expected: Expected Fault
// Coverpoints: cp_hgatp_invalid_pte_rw
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R), gpa_data, LEVEL0)  // U=1 XWR=111
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(a6, 0)                                     // sentinel: stays 0 if trap fires
  LI(t1, gpa_data)                              // t1 = GPA pointer for HLV/HSV
  hlv.w a6, (t1)                                // HS hypervisor load hits V=0 → guest-page fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test3_hlv_v0:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test3_hlv_v0, test3_hlv_v0_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: HS HSV to V=0 GPA | Expected: Expected Fault
// Coverpoints: cp_hgatp_invalid_pte_rw
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.gvma                                   // flush G TLB before HS write path

  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(s2, 0)                                     // sentinel: stays 0 if trap fires
  LI(t0, 0xDEADBEEF)                            // store payload (must not land)
  LI(t1, gpa_data)                              // t1 = GPA pointer for HSV
  hsv.w t0, (t1)                                // HS hypervisor store hits V=0 → guest-page fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test4_hsv_v0:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test4_hsv_v0, test4_hsv_v0_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: HS HSV to L0 non-leaf GPA | Expected: Expected Fault
// Coverpoints: cp_hgatp_nonleaf_lvl0_rw
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_V), gpa_data, LEVEL0)  // G leaf U=0 V-only (XWR=000 → fault)
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(s3, 0)                                     // sentinel: stays 0 if trap fires
  LI(t0, 0xCAFEBABE)                            // store payload (must not land)
  LI(t1, gpa_data)                              // t1 = GPA pointer for HSV
  hsv.w t0, (t1)                                // HS store through non-leaf L0 → guest-page fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test5_hsv_nonleaf:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test5_hsv_nonleaf, test5_hsv_nonleaf_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5b: HS HLV to L0 non-leaf GPA | Expected: Expected Fault
// Coverpoints: cp_hgatp_nonleaf_lvl0_rw
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.gvma                                   // flush G TLB before HS read of non-leaf L0
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(s5, 0)                                     // sentinel — stays 0 if HLV guest-page-faults
  LI(t1, gpa_data)                              // t1 = GPA pointer for HLV
  hlv.w s5, (t1)                                // HS load through non-leaf L0 → guest-page fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test5b_hlv_nonleaf:                              // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s5, test5b_hlv_nonleaf, test5b_hlv_nonleaf_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: Restore valid U=1 R/W G leaf | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_G), gpa_data, LEVEL0)  // restore U=1 XWR=111+G leaf
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a7, 0)                                     // clear result register before load
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  lw   a7, 0(a5)                                // expect 0x257A0221
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test6_restore:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test6_restore, test6_restore_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: VS Bare jalr into V=0 G leaf | Expected: Expected Fault (cp_hgatp_invalid_pte_x)
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R), gpa_data, LEVEL0)  // U=1 XWR=111
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(s4, 0)                                     // sentinel — stays 0 if target never runs
  LI(a5, gpa_data)                              // a5 = GPA fetch target (vsatp Bare)
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  nop                                           // pad so priv_mode_vs samples prev=VS on jalr
  jalr ra, a5, 0                                // ifetch through invalid G leaf → fetch-guest-page-fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test7_v0_ifetch:                                 // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s4, test7_v0_ifetch, test7_v0_ifetch_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: VS Bare sw into V=0 G leaf | Expected: Expected Fault (exception_reporting write)
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R), gpa_data, LEVEL0)  // U=1 XWR=111
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a5, gpa_data)                              // a5 = GPA to store
  LI(t0, 0xDEADBEEF)                            // payload that must not land at SPA
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  nop                                           // pad before faulting store
  sw   t0, 0(a5)                                // VS Bare store: G leaf V=0 → guest-page
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  la t1, test_region                        // t1 = SPA of data page
  lw a3, 0(t1)                              // M-mode SPA readback
  test8_v0_sw:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test8_v0_sw, test8_v0_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                      // 4 KiB page align
test_region:                                  // SPA backing for GPA data leaf
  .word 0                                     // payload word (preloaded in M)
  .word 0                                     // padding in same page
  .word 0                                     // padding in same page
  .word 0                                     // padding in same page

.align 12                                      // 4 KiB page align

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                      // extra 4 KiB align before G L1 table
rvtest_hlvl1_pg_tbl:                           // G-stage L1 PTE storage (Sv39x4 VPN2)
  .zero(4096)                                  // reserve 4 KiB page-table page
rvtest_hlvl0_pg_tbl:                          // G-stage L0 PTE storage (4 KiB)
  .zero(4096)                                  // reserve 4 KiB page-table storage


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_v0_str:         .string "\"Mismatch on VS lw with G leaf V=0 (expect fault) in Test Case 1!\""  // mismatch string
test2_nonleaf_str:    .string "\"Mismatch on VS lw with G L0 non-leaf only (expect fault) in Test Case 2!\""  // mismatch string
test3_hlv_v0_str:     .string "\"Mismatch on HS HLV with G leaf V=0 (expect fault) in Test Case 3!\""  // mismatch string
test4_hsv_v0_str:     .string "\"Mismatch on HS HSV with G leaf V=0 (expect fault) in Test Case 4!\""  // mismatch string
test5_hsv_nonleaf_str:.string "\"Mismatch on HS HSV with G L0 non-leaf (expect fault) in Test Case 5!\""  // mismatch string
test5b_hlv_nonleaf_str:.string "\"Mismatch on HS HLV with G L0 non-leaf (expect fault) in Test Case 5b!\""  // mismatch string
test6_restore_str:    .string "\"Mismatch on VS lw after valid G leaf restore in Test Case 6!\""  // mismatch string
test7_v0_ifetch_str:  .string "\"Mismatch on VS ifetch with G leaf V=0 (expect fault) in Test Case 7!\""  // mismatch string
test8_v0_sw_str:      .string "\"Mismatch on VS sw with G leaf V=0 (expect fault) in Test Case 8!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                Invalid G PTE (V=0) and L0 non-leaf-only entry ca...
  //                      │
  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 1                      Test 2                      Test 3          
  //                │                           │                           │             
  //     G leaf V=0 (D|A|U|X|W|R         G L0 PTE_V only            HS HLV to V=0 GPA     
  //                │                           │                           │             
  //            VS Bare lw                  VS Bare lw                  FAULT a6=0        
  //                ▼                           ▼                                         
  //            FAULT a3=0                  FAULT a4=0                                    

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 4                      Test 5                     Test 5b          
  //                │                           │                           │             
  //        HS HSV to V=0 GPA       HS HSV to L0 non-leaf GPA   HS HLV to L0 non-leaf GPA 
  //                ▼                           ▼                           ▼             
  //            FAULT s2=0                  FAULT s3=0                  FAULT s5=0        

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 6                      Test 7                      Test 8          
  //                │                           │                           │             
  //     Restore valid U=1 R/W G      VS Bare jalr to V=0 G             G leaf V=0        
  //                │                           │                           │             
  //            VS Bare lw          FAULT fetch-guest-page-fa…          VS Bare sw        
  //                ▼                                                       ▼             
  //            0x257A0221                                           FAULT SPA same)      
