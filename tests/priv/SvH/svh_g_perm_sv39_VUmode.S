// --------------------------------------------------------------------------------------------------------------------------------
// svh_g_perm_sv39_VUmode.S
// Config: sail-rv64-max | vsatp=Bare, hgatp=Sv39x4 ON, stimulus in VU
// Pair:   svh_g_perm_VUmode.S
// Coverpoints mapped (SvH_cg): cp_hgatp_perm_checks
// What this proves (one line):
//   G-stage U/XWR allow/deny from VU (vsatp Bare); U=0 and V-only deny.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. G leaf U=1 XWR=111+G: VU Bare sw+lw → Successful (0x257A0801)
//  2. G leaf U=0 XWR=111+G: VU Bare lw → Expected Fault (a4 stays 0)
//  3. G leaf U=0 XWR=111+G: VU Bare sw → Expected Fault (SPA stays 0x257A0801)
//  4. G leaf U=1 X-only: VU Bare lw → Expected Fault (a6 stays 0)
//  5. G leaf U=1 V-only: VU Bare lw → Expected Fault (s3 stays 0)
//  6. Restore U=1 XWR=111+G: VU Bare lw → Successful (0x257A0801)
//  7. G leaf U=1 V-only: VU Bare sw → Expected Fault (SPA stays 0x257A0801)
//  8. G leaf U=0 V-only: VU Bare sw → Expected Fault (SPA stays 0x257A0801)
//  9. G leaf U=0 V-only: VU Bare lw → Expected Fault (s4 stays 0)  // urwx0000×read
//
// Total Expected Faults :: 7
// Note: Do NOT execute hfence.gvma in VU — it is a virtual-instruction exception.
//   Flush G TLB only from M. M-mode hfence after each PTE rewrite is enough.
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_g_perm_sv39_VUmode.S"
#define SIGUPD_COUNT 9
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE.
// Enter: PA/identity (no V_SAVE_AREA) → RVTEST_TSBI_GOTO_VUMODE (ecall a0=5).
// Mode hops (Sv-style GOTO_* plus H T-SBI):
//   Enter PA/identity → RVTEST_TSBI_GOTO_VSMODE / _SMODE / _VUMODE
//   Enter VA≠PA (V_SAVE_AREA) → RVTEST_GOTO_LOWER_MODE
//   Return to M → always RVTEST_TSBI_GOTO_MMODE
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set gpa_data, 0x00C002000                     // GPA for data (vsatp Bare ⇒ address used as GPA)
  .set gpa_code,                0x0000000080000000                      // identity GPA superpage (U=1 for VU ifetch)

  // G-stage walks as U-mode → U=1 on leaves for success; code leaf also U=1 for VU.

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------
  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL2)  // G-stage superpage: code/data GPA → PA

  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_data, LEVEL2)  // G non-leaf: data GPA VPN2 → G L1 table
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // non-leaf → G L0
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V | PTE_G), gpa_data, LEVEL0)  // U=1 XWR=111+G


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  csrw vsatp, x0                                // VS Bare
  HGATP_SETUP(sv39x4)                           // G-stage ON
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // legal in M

  LI(t0, 0x257A0801)                            // preload SPA
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)

  LI(a5, gpa_data)                              // VU Bare address = GPA


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: G leaf U=1 XWR=111+G VU sw/lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a2, 0x257A0801)                            // value to store through G-stage
  RVTEST_TSBI_GOTO_VUMODE                      // M→VU (T-SBI)
  sw   a2, 0(a5)                                // VU store through G-stage
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  hfence.gvma                                   // legal M flush so next VU load rewalks
  RVTEST_TSBI_GOTO_VUMODE                      // M→VU (T-SBI)
  lw   a3, 0(a5)                                // expect 0x257A0801
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test1_u1_rwx:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_u1_rwx, test1_u1_rwx_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: G leaf U=0 XWR=111+G VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V | PTE_G), gpa_data, LEVEL0)  // U=0
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a4, 0)                                     // sentinel — stays 0 if load faults
  RVTEST_TSBI_GOTO_VUMODE                      // M→VU (T-SBI)
  lw   a4, 0(a5)                                // U=0 → guest-page fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test2_u0_lw:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_u0_lw, test2_u0_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: G leaf U=0 XWR=111+G VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0xDEADBEEF)                            // would-be store payload (must not land)
  RVTEST_TSBI_GOTO_VUMODE                      // M→VU (T-SBI)
  sw   t0, 0(a5)                                // U=0 → store guest-page fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  la t3, test_region                            // t3 = SPA of data page
  lw s2, 0(t3)                                  // expect preload 0x257A0801
  test3_u0_sw:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test3_u0_sw, test3_u0_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: G leaf U=1 X-only | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=1 X-only+G (no R → fault on load/store)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a6, 0)                                     // sentinel — stays 0 if load faults
  RVTEST_TSBI_GOTO_VUMODE                      // M→VU (T-SBI)
  lw   a6, 0(a5)                                // no R → fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test4_xonly:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test4_xonly, test4_xonly_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: G leaf U=1 V-only | Expected: Expected Fault (urwx1000)
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=1 V-only+G (XWR=000 → fault)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(s3, 0)                                     // sentinel — stays 0 if load faults
  RVTEST_TSBI_GOTO_VUMODE                      // M→VU (T-SBI)
  lw   s3, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test5_vonly_u1:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test5_vonly_u1, test5_vonly_u1_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: Restore U=1 XWR=111+G VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=1 XWR=111+G (allow)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a7, 0)                                     // clear result register before load
  RVTEST_TSBI_GOTO_VUMODE                      // M→VU (T-SBI)
  lw   a7, 0(a5)                                // expect 0x257A0801
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test6_restore:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test6_restore, test6_restore_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: G leaf U=1 V-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=1 V-only+G (XWR=000 → fault)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA
  RVTEST_TSBI_GOTO_VUMODE                      // M→VU (T-SBI)
  sw   t0, 0(a5)                                // guest store (expect fault; SPA must stay unchanged)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  la t3, test_region                            // t3 = SPA of data page
  lw s6, 0(t3)                                  // expect 0x257A0801 unchanged
  test7_vonly_u1_sw:                                // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s6, test7_vonly_u1_sw, test7_vonly_u1_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: G leaf U=0 V-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=0 V-only+G (deny)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA
  RVTEST_TSBI_GOTO_VUMODE                      // M→VU (T-SBI)
  sw   t0, 0(a5)                                // guest store (expect fault; SPA must stay unchanged)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  la t3, test_region                            // t3 = SPA of data page
  lw s7, 0(t3)                                  // expect 0x257A0801 still
  test8_vonly_u0_sw:                                // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s7, test8_vonly_u0_sw, test8_vonly_u0_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 9: G leaf U=0 V-only VU lw | Expected: Expected Fault (urwx0000×read)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(s4, 0)                                     // sentinel / result register
  RVTEST_TSBI_GOTO_VUMODE                      // M→VU (T-SBI)
  lw   s4, 0(a5)                                // U=0 V-only → fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test9_vonly_u0_lw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s4, test9_vonly_u0_lw, test9_vonly_u0_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

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
test1_u1_rwx_str:      .string "\"Mismatch on VU sw/lw with G U=1 XWR=111+G in Test Case 1!\""
test2_u0_lw_str:       .string "\"Mismatch on VU lw with G U=0 XWR=111 (expect fault) in Test Case 2!\""
test3_u0_sw_str:       .string "\"Mismatch on VU sw with G U=0 XWR=111 (expect SPA unchanged) in Test Case 3!\""
test4_xonly_str:       .string "\"Mismatch on VU lw with G X-only (expect fault) in Test Case 4!\""
test5_vonly_u1_str:    .string "\"Mismatch on VU lw with G U=1 V-only (expect fault) in Test Case 5!\""
test6_restore_str:     .string "\"Mismatch on VU lw after G perm restore in Test Case 6!\""
test7_vonly_u1_sw_str: .string "\"Mismatch on VU sw with G U=1 V-only (expect SPA unchanged) in Test Case 7!\""
test8_vonly_u0_sw_str: .string "\"Mismatch on VU sw with G U=0 V-only (expect SPA unchanged) in Test Case 8!\""
test9_vonly_u0_lw_str: .string "\"Mismatch on VU lw with G U=0 V-only (expect fault) in Test Case 9!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
