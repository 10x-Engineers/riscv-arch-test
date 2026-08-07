// --------------------------------------------------------------------------------------------------------------------------------
// svh_vs_pte_attr_VSmode.S
// Config: sail-rv32-max | VS=Sv32 ON, hgatp=Bare
// Coverpoints mapped (SvH_cg): cp_vsatp_pte_rsw
// What this proves (one line):
//   VS-stage PTE RSW[9:8] is preserved; stores and loads succeed for all RSW encodings.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. RSW=00: VS sw → Successful (SPA 0x257A0301)
//  2. RSW=00: VS lw only (fresh hop + hfence) → Successful (0x257A0301)
//  3. RSW=01: VS sw → Successful (SPA 0x257A0302)
//  4. RSW=01: VS lw only → Successful (0x257A0302)   // clears auto[1]×read
//  5. RSW=10: VS sw → Successful (SPA 0x257A0303)
//  6. RSW=10: VS lw only → Successful (0x257A0303)   // clears auto[2]×read
//  7. RSW=11: VS sw → Successful (SPA 0x257A0304)
//  8. RSW=11: VS lw only → Successful (0x257A0304)
//
// Note: sw+lw in the same VS hop TLB-hits the load so VS_PTE_D is missing on
// the read sample; RSW read bins need a separate hop after hfence.vvma.
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vs_pte_attr_VSmode.S"
#define SIGUPD_COUNT 8
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VSMODE / _SMODE (ecall a0=4/2)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE (mret + PA↔VA relocate)
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_data,                 0x008001000     // GVA for R/W data leaf (same VA, varying RSW bits)
  .set va_code,                 0x90000000      // GVA where VS executes this code (U=0)

  // ---- VS-stage (vsatp Sv32): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  SUPERPAGE_VS_PTE_SETUP(sv32, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // code leaf

  csrr a0, mscratch                             // a0 = Msave_area for V_SAVE_AREA_SETUP
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // guest PC under va_code

  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)  // non-leaf → VS L0
  VS_PTE_SETUP(sv32, PA, test_region, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)  // RSW=00 leaf

  VSATP_SETUP(sv32, PA)                         // VS-stage ON
  csrw hgatp, x0                                // G Bare
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a5, va_data)                               // a5 = GVA for all cases

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: RSW=00 VS sw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0x257A0301)
  RVTEST_GOTO_LOWER_MODE VSmode                 // VA≠PA enter (V_SAVE_AREA)
  sw   t0, 0(a5)                                // store through RSW=00 leaf
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t1, test_region
  lw s2, 0(t1)                                  // expect 0x257A0301 in SPA
  test1_rsw00_sw:
  RVTEST_SIGUPD(x2, x5, x4, s2, test1_rsw00_sw, test1_rsw00_sw_str)  // signature: dump s2 (test1_rsw00_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: RSW=00 VS lw only | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush so lw rewalks (RSW read bin)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   a3, 0(a5)                                // expect 0x257A0301
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test2_rsw00_lw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test2_rsw00_lw, test2_rsw00_lw_str)  // signature: dump a3 (test2_rsw00_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: RSW=01 VS sw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv32, PA, test_region, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | 0x100), va_data, LEVEL0)  // RSW=01
  hfence.vvma                                   // flush VS-stage TLB

  LI(t0, 0x257A0302)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   t0, 0(a5)                                // guest store through current PTE perms (expect allow)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t1, test_region
  lw s3, 0(t1)                                  // load from SPA
  test3_rsw01_sw:
  RVTEST_SIGUPD(x2, x5, x4, s3, test3_rsw01_sw, test3_rsw01_sw_str)  // signature: dump s3 (test3_rsw01_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: RSW=01 VS lw only | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   a4, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test4_rsw01_lw:
  RVTEST_SIGUPD(x2, x5, x4, a4, test4_rsw01_lw, test4_rsw01_lw_str)  // signature: dump a4 (test4_rsw01_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: RSW=10 VS sw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv32, PA, test_region, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | 0x200), va_data, LEVEL0)  // RSW=10
  hfence.vvma                                   // flush VS-stage TLB

  LI(t0, 0x257A0303)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   t0, 0(a5)                                // guest store through current PTE perms (expect allow)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t1, test_region
  lw s4, 0(t1)                                  // load from SPA
  test5_rsw10_sw:
  RVTEST_SIGUPD(x2, x5, x4, s4, test5_rsw10_sw, test5_rsw10_sw_str)  // signature: dump s4 (test5_rsw10_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: RSW=10 VS lw only | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   a6, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test6_rsw10_lw:
  RVTEST_SIGUPD(x2, x5, x4, a6, test6_rsw10_lw, test6_rsw10_lw_str)  // signature: dump a6 (test6_rsw10_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: RSW=11 VS sw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv32, PA, test_region, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_SOFT), va_data, LEVEL0)  // RSW=11
  hfence.vvma                                   // flush VS-stage TLB

  LI(t0, 0x257A0304)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   t0, 0(a5)                                // guest store through current PTE perms (expect allow)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t1, test_region
  lw s5, 0(t1)                                  // load from SPA
  test7_rsw11_sw:
  RVTEST_SIGUPD(x2, x5, x4, s5, test7_rsw11_sw, test7_rsw11_sw_str)  // signature: dump s5 (test7_rsw11_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: RSW=11 VS lw only | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   a7, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test8_rsw11_lw:
  RVTEST_SIGUPD(x2, x5, x4, a7, test8_rsw11_lw, test8_rsw11_lw_str)  // signature: dump a7 (test8_rsw11_lw) for PASS/FAIL

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
rvtest_vlvl0_pg_tbl:
  .zero(4096)

test1_rsw00_sw_str: .string "\"Mismatch on RSW=00 VS sw SPA in Test Case 1!\""
test2_rsw00_lw_str: .string "\"Mismatch on RSW=00 VS lw in Test Case 2!\""
test3_rsw01_sw_str: .string "\"Mismatch on RSW=01 VS sw SPA in Test Case 3!\""
test4_rsw01_lw_str: .string "\"Mismatch on RSW=01 VS lw in Test Case 4!\""
test5_rsw10_sw_str: .string "\"Mismatch on RSW=10 VS sw SPA in Test Case 5!\""
test6_rsw10_lw_str: .string "\"Mismatch on RSW=10 VS lw in Test Case 6!\""
test7_rsw11_sw_str: .string "\"Mismatch on RSW=11 VS sw SPA in Test Case 7!\""
test8_rsw11_lw_str: .string "\"Mismatch on RSW=11 VS lw in Test Case 8!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
