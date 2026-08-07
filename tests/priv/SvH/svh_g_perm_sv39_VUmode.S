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
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set gpa_data, 0x00C002000                     // GPA for data (vsatp Bare ⇒ address used as GPA)
  .set gpa_code,                0x0000000080000000                      // identity GPA superpage (U=1 for VU ifetch)

  // G-stage walks as U-mode → U=1 on leaves for success; code leaf also U=1 for VU.
  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL2)  // G-stage superpage: code/data GPA → PA

  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_data, LEVEL2)
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // non-leaf → G L0
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V | PTE_G), gpa_data, LEVEL0)  // U=1 XWR=111+G

  csrw vsatp, x0                                // VS Bare
  HGATP_SETUP(sv39x4)                           // G-stage ON
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // legal in M

  LI(t0, 0x257A0801)                            // preload SPA
  la t1, test_region
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)

  LI(a5, gpa_data)                              // VU Bare address = GPA

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: G leaf U=1 XWR=111+G VU sw/lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a2, 0x257A0801)
  RVTEST_TSBI_GOTO_VUMODE                       // M→VU (PA/identity)
  sw   a2, 0(a5)                                // VU store through G-stage
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)
  hfence.gvma                                   // legal M flush so next VU load rewalks
  RVTEST_TSBI_GOTO_VUMODE                       // M→VU (T-SBI ecall a0=5; PA/identity enter)
  lw   a3, 0(a5)                                // expect 0x257A0801
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test1_u1_rwx:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_u1_rwx, test1_u1_rwx_str)  // signature: dump a3 (test1_u1_rwx) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: G leaf U=0 XWR=111+G VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V | PTE_G), gpa_data, LEVEL0)  // U=0
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a4, 0)
  RVTEST_TSBI_GOTO_VUMODE                       // M→VU (T-SBI ecall a0=5; PA/identity enter)
  lw   a4, 0(a5)                                // U=0 → guest-page fault
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test2_u0_lw:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_u0_lw, test2_u0_lw_str)  // signature: dump a4 (test2_u0_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: G leaf U=0 XWR=111+G VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0xDEADBEEF)
  RVTEST_TSBI_GOTO_VUMODE                       // M→VU (T-SBI ecall a0=5; PA/identity enter)
  sw   t0, 0(a5)                                // U=0 → store guest-page fault
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t3, test_region
  lw s2, 0(t3)                                  // expect preload 0x257A0801
  test3_u0_sw:
  RVTEST_SIGUPD(x2, x5, x4, s2, test3_u0_sw, test3_u0_sw_str)  // signature: dump s2 (test3_u0_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: G leaf U=1 X-only | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=1 X-only+G (no R → fault on load/store)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a6, 0)
  RVTEST_TSBI_GOTO_VUMODE                       // M→VU (T-SBI ecall a0=5; PA/identity enter)
  lw   a6, 0(a5)                                // no R → fault
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test4_xonly:
  RVTEST_SIGUPD(x2, x5, x4, a6, test4_xonly, test4_xonly_str)  // signature: dump a6 (test4_xonly) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: G leaf U=1 V-only | Expected: Expected Fault (urwx1000)
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=1 V-only+G (XWR=000 → fault)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(s3, 0)
  RVTEST_TSBI_GOTO_VUMODE                       // M→VU (T-SBI ecall a0=5; PA/identity enter)
  lw   s3, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test5_vonly_u1:
  RVTEST_SIGUPD(x2, x5, x4, s3, test5_vonly_u1, test5_vonly_u1_str)  // signature: dump s3 (test5_vonly_u1) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: Restore U=1 XWR=111+G VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=1 XWR=111+G (allow)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a7, 0)
  RVTEST_TSBI_GOTO_VUMODE                       // M→VU (T-SBI ecall a0=5; PA/identity enter)
  lw   a7, 0(a5)                                // expect 0x257A0801
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test6_restore:
  RVTEST_SIGUPD(x2, x5, x4, a7, test6_restore, test6_restore_str)  // signature: dump a7 (test6_restore) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: G leaf U=1 V-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=1 V-only+G (XWR=000 → fault)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0xBAD00FAD)
  RVTEST_TSBI_GOTO_VUMODE                       // M→VU (T-SBI ecall a0=5; PA/identity enter)
  sw   t0, 0(a5)                                // guest store (expect fault; SPA must stay unchanged)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t3, test_region
  lw s6, 0(t3)                                  // expect 0x257A0801 unchanged
  test7_vonly_u1_sw:
  RVTEST_SIGUPD(x2, x5, x4, s6, test7_vonly_u1_sw, test7_vonly_u1_sw_str)  // signature: dump s6 (test7_vonly_u1_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: G leaf U=0 V-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_V | PTE_G), gpa_data, LEVEL0)  // G leaf U=0 V-only+G (deny)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0xBAD00FAD)
  RVTEST_TSBI_GOTO_VUMODE                       // M→VU (T-SBI ecall a0=5; PA/identity enter)
  sw   t0, 0(a5)                                // guest store (expect fault; SPA must stay unchanged)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t3, test_region
  lw s7, 0(t3)                                  // expect 0x257A0801 still
  test8_vonly_u0_sw:
  RVTEST_SIGUPD(x2, x5, x4, s7, test8_vonly_u0_sw, test8_vonly_u0_sw_str)  // signature: dump s7 (test8_vonly_u0_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 9: G leaf U=0 V-only VU lw | Expected: Expected Fault (urwx0000×read)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(s4, 0)
  RVTEST_TSBI_GOTO_VUMODE                       // M→VU (T-SBI ecall a0=5; PA/identity enter)
  lw   s4, 0(a5)                                // U=0 V-only → fault
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test9_vonly_u0_lw:
  RVTEST_SIGUPD(x2, x5, x4, s4, test9_vonly_u0_lw, test9_vonly_u0_lw_str)  // signature: dump s4 (test9_vonly_u0_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

.align 12
test_region:
  .word 0
  .word 0
  .word 0
  .word 0

.align 12
rvtest_hlvl1_pg_tbl:
  .zero(4096)
.align 12
rvtest_hlvl0_pg_tbl:
  .zero(4096)

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
