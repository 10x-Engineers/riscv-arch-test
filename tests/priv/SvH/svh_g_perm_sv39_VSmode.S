// --------------------------------------------------------------------------------------------------------------------------------
// svh_g_perm_sv39_VSmode.S
// Config: sail-rv64-max | vsatp=Bare, hgatp=Sv39x4 ON
// Pair:   svh_g_perm_VSmode.S
// Coverpoints mapped (SvH_cg): cp_hgatp_perm_checks, cp_hgatp_pte_g_bit
// What this proves (one line):
//   G-stage U/XWR allow/deny (VS Bare) and G-bit on HS HLV/HSV (XWR=111).
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. G leaf U=1 XWR=111+G: VS Bare sw+lw → Successful (0x257A0201)
//  2. G leaf U=0 XWR=111+G: VS Bare lw → Expected Fault (a4 stays 0)
//  3. G leaf U=0 XWR=111+G: VS Bare sw → Expected Fault (SPA stays 0x257A0201)
//  4. G leaf U=1 X-only: VS Bare lw → Expected Fault (a6 stays 0)
//  5. G leaf U=1 V-only (XWR=000): VS Bare lw → Expected Fault (s3 stays 0)
//  6. Restore U=1 XWR=111+G: VS Bare lw → Successful (0x257A0201)
//  7. HS HLV of G leaf with G=1 XWR=111 → Successful (0x257A0201)
//  8. HS HSV of G leaf with G=1 XWR=111 → Successful (store+HLV 0x257A0208)
//  9. G leaf U=1 V-only: VS Bare sw → Expected Fault (SPA stays 0x257A0208)
// 10. G leaf U=0 V-only: VS Bare sw → Expected Fault (SPA stays 0x257A0208)
//
// Total Expected Faults :: 6
// Note: Do NOT execute hfence.gvma in VS — it is a virtual-instruction exception.
//   Flush G TLB only from M (or HS). M-mode hfence after each PTE rewrite is enough
//   for the next VS hop to rewalk.
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_g_perm_sv39_VSmode.S"
#define SIGUPD_COUNT 10
#define TRAP_SIGUPD_COUNT 128
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set gpa_data, 0x00C002000                     // GPA for data (vsatp Bare ⇒ address used as GPA)
  .set gpa_code,                0x0000000080000000                      // identity GPA superpage for VS ifetch

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- G-stage (hgatp Sv39x4 ON): walks as U-mode → U=1 on leaves for success ----
  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL2)  // code GPA → PA(code), U=1 X

  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_data, LEVEL2)  // G non-leaf: data GPA VPN2 → G L1 table
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // non-leaf: data VPN1 → G L0 table
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V | PTE_G), gpa_data, LEVEL0)  // U=1 XWR=111+G leaf


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  csrw vsatp, x0                            // VS Bare
  HGATP_SETUP(sv39x4)                       // G-stage ON
  hfence.vvma                               // flush VS-stage TLB
  hfence.gvma                               // flush G-stage TLB (legal in M)

  LI(t0, 0x257A0201)                        // preload SPA
  la t1, test_region                        // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)

  LI(a5, gpa_data)                              // a5 = GPA used by VS Bare loads/stores


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: G leaf U=1 XWR=111+G VS sw/lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a2, 0x257A0201)                            // value to store through G-stage
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  sw   a2, 0(a5)                                // VS store through G-stage (U=1 XWR=111)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  hfence.gvma                                   // force next VS load to rewalk leaf (G_PTE_D in .rvvi)
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  lw   a3, 0(a5)                                // expect 0x257A0201
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test1_u1_rwx:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_u1_rwx, test1_u1_rwx_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: G leaf U=0 XWR=111+G VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V | PTE_G), gpa_data, LEVEL0)  // U=0
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a4, 0)                                     // sentinel: stays 0 if load faults
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  lw   a4, 0(a5)                                // U=0 → guest-page fault (G walks as U)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test2_u0_lw:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_u0_lw, test2_u0_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: G leaf U=0 XWR=111+G VS sw | Expected: Expected Fault
// Check SPA (not a constant sentinel) so a wrongly successful store fails SIGUPD.
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0xDEADBEEF)                            // would-be store payload
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  sw   t0, 0(a5)                                // U=0 → store guest-page fault
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  la t3, test_region                            // t3 = SPA of data page
  lw s2, 0(t3)                                  // expect preload 0x257A0201 unchanged
  test3_u0_sw:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test3_u0_sw, test3_u0_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: G leaf U=1 X-only | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=1 X-only+G (no R → fault on load/store)
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a6, 0)                                     // sentinel — stays 0 if load faults
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  lw   a6, 0(a5)                                // no R → guest-page fault
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test4_xonly:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test4_xonly, test4_xonly_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: G leaf U=1 V-only (XWR=000) | Expected: Expected Fault
// Coverpoints: cp_hgatp_perm_checks_rw
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=1 V-only+G (XWR=000 → fault)
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(s3, 0)                                     // sentinel — stays 0 if load faults
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  lw   s3, 0(a5)                                // V-only → fault
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test5_vonly_u1:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test5_vonly_u1, test5_vonly_u1_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: Restore U=1 XWR=111+G VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V | PTE_G), gpa_data, LEVEL0)  // restore U=1 XWR=111+G leaf
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a7, 0)                                     // clear result register before load
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  lw   a7, 0(a5)                                // expect 0x257A0201
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test6_restore:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test6_restore, test6_restore_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: HS HLV of G leaf with G=1 XWR=111 | Expected: Successful
// Coverpoints: cp_hgatp_pte_g_bit_rw
//---------------------------------------------------------------------------------------------------------------------------------
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(s4, 0)                                     // sentinel / result register
  LI(t1, gpa_data)                              // t1 = GPA for HS HLV/HSV
  hfence.gvma                                   // force walk for G_PTE_D + G bit (legal in HS)
  hlv.w s4, (t1)                                // HS hyper-load of guest GPA
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test7_hlv_g:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s4, test7_hlv_g, test7_hlv_g_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: HS HSV of G leaf with G=1 XWR=111 | Expected: Successful
// Coverpoints: cp_hgatp_pte_g_bit_rw
//---------------------------------------------------------------------------------------------------------------------------------
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(t0, 0x257A0208)                            // HSV store payload
  LI(t1, gpa_data)                              // t1 = GPA for HS HLV/HSV
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)
  hsv.w t0, (t1)                                // G=1 XWR=111 → store succeeds
  nop                                           // trap-skip pad
  hfence.gvma                                   // rewalk before HLV sample
  LI(s5, 0)                                     // s5 will hold HLV after HSV
  hlv.w s5, (t1)                                // expect 0x257A0208
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test8_hsv_g:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s5, test8_hsv_g, test8_hsv_g_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 9: G leaf U=1 V-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=1 V-only+G (XWR=000 → fault)
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  sw   t0, 0(a5)                                // V-only → store guest-page fault
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  la t3, test_region                            // t3 = SPA of data page
  lw s6, 0(t3)                                  // expect 0x257A0208 from case 8
  test9_vonly_u1_sw:                                // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s6, test9_vonly_u1_sw, test9_vonly_u1_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 10: G leaf U=0 V-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=0 V-only+G (XWR=000 → fault)
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  sw   t0, 0(a5)                                // guest store (expect fault; SPA must stay unchanged)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  la t3, test_region                            // t3 = SPA of data page
  lw s7, 0(t3)                                  // expect 0x257A0208 still
  test10_vonly_u0_sw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s7, test10_vonly_u0_sw, test10_vonly_u0_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing data page
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_hlvl1_pg_tbl:                            // G-stage L1 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L0 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_u1_rwx_str:   .string "\"Mismatch on VS sw/lw with G U=1 XWR=111+G in Test Case 1!\""  // mismatch string
test2_u0_lw_str:    .string "\"Mismatch on VS lw with G U=0 XWR=111 (expect fault) in Test Case 2!\""  // mismatch string
test3_u0_sw_str:    .string "\"Mismatch on VS sw with G U=0 XWR=111 (expect SPA unchanged) in Test Case 3!\""  // mismatch string
test4_xonly_str:    .string "\"Mismatch on VS lw with G X-only (expect fault) in Test Case 4!\""  // mismatch string
test5_vonly_u1_str: .string "\"Mismatch on VS lw with G U=1 V-only (expect fault) in Test Case 5!\""  // mismatch string
test6_restore_str:  .string "\"Mismatch on VS lw after G perm restore in Test Case 6!\""  // mismatch string
test7_hlv_g_str:    .string "\"Mismatch on HS HLV of G leaf with G=1 in Test Case 7!\""  // mismatch string
test8_hsv_g_str:       .string "\"Mismatch on HS HSV of G leaf with G=1 in Test Case 8!\""  // mismatch string
test9_vonly_u1_sw_str: .string "\"Mismatch on VS sw with G U=1 V-only (expect SPA unchanged) in Test Case 9!\""  // mismatch string
test10_vonly_u0_sw_str:.string "\"Mismatch on VS sw with G U=0 V-only (expect SPA unchanged) in Test Case 10!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                G-stage U/XWR allow/deny (VS Bare) and G-bit on H...
  //                      │
  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 1                      Test 2                      Test 3          
  //                │                           │                           │             
  //       G leaf U=1 XWR=111+G        G leaf U=0 XWR=111+G        G leaf U=0 XWR=111+G   
  //                │                           │                           │             
  //          VS Bare sw+lw                 VS Bare lw                  VS Bare sw        
  //                ▼                           ▼                           ▼             
  //            0x257A0201                  FAULT a4=0            FAULT SPA 0x257A0201)   

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 4                      Test 5                      Test 6          
  //                │                           │                           │             
  //        G leaf U=1 X-only           G leaf U=1 V-only         Restore U=1 XWR=111+G   
  //                │                           │                           │             
  //            VS Bare lw                  VS Bare lw                  VS Bare lw        
  //                ▼                           ▼                           ▼             
  //            FAULT a6=0                  FAULT s3=0                  0x257A0201        

  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 7                             Test 8
  //         │                         │
  //      HS HLV of G leaf           HS HSV of G leaf
  //         ▼                         ▼
  //      0x257A0201                 store+HLV 0x257A0208

  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 9                             Test 10
  //         │                         │
  //      G leaf U=1 V-only          G leaf U=0 V-only
  //         │                         │
  //      VS Bare sw                 VS Bare sw
  //         ▼                         ▼
  //      FAULT SPA 0x257A0208)      FAULT SPA 0x257A0208)
