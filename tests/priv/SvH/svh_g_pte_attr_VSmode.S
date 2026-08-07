// --------------------------------------------------------------------------------------------------------------------------------
// svh_g_pte_attr_VSmode.S
// Config: sail-rv32-max | vsatp=Bare, hgatp=Sv32x4 ON
// Coverpoints mapped (SvH_cg): cp_hgatp_pte_rsw
// What this proves (one line):
//   G-stage leaf RSW[1:0] is preserved; HS HLV+HSV succeed for all encodings.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. G leaf RSW=00: HS HLV + HSV → Successful (0x257A0210)
//  2. G leaf RSW=01: HS HLV + HSV → Successful (0x257A0211)
//  3. G leaf RSW=10: HS HLV + HSV → Successful (0x257A0212)
//  4. G leaf RSW=11: HS HLV + HSV → Successful (0x257A0213)
//
// Total Expected Faults :: 0
// Note: hfence.gvma here runs in HS (legal). RSW is PTE bits [9:8] (PTE_SOFT=0x300).
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_g_pte_attr_VSmode.S"
#define SIGUPD_COUNT 4
#define TRAP_SIGUPD_COUNT 16
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VSMODE / _SMODE (ecall a0=4/2)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE (mret + PA↔VA relocate)
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set gpa_data, 0x00C002000                    // GPA HS HLV/HSV will use
  .set gpa_code, 0x80000000                     // identity code GPA (optional for HS-only)

  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)  // G-stage superpage: code/data GPA → PA

  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // non-leaf → G L0
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // RSW=00 leaf

  csrw vsatp, x0                                // VS Bare — isolate G-stage RSW bins
  HGATP_SETUP(sv32x4)                           // turn on G-stage paging (hgatp MODE + root PPN)
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0x257A0210)
  la t1, test_region
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)

  LI(t1, gpa_data)                              // t1 = GPA for all HS HLV/HSV

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: G leaf RSW=00 HS HLV+HSV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // RSW=00
  hfence.gvma                                   // M flush before HS hop

  RVTEST_TSBI_GOTO_SMODE                        // M→HS
  LI(t0, 0x257A0210)
  hsv.w t0, (t1)                                // write_acc with RSW=00
  nop
  hfence.gvma                                   // legal in HS — force HLV to rewalk
  hlv.w a3, (t1)                                // read_acc with RSW=00; expect 0x257A0210
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test1_rsw00:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_rsw00, test1_rsw00_str)  // signature: dump a3 (test1_rsw00) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: G leaf RSW=01 HS HLV+HSV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | 0x100), gpa_data, LEVEL0)  // RSW=01 (bit 8)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  RVTEST_TSBI_GOTO_SMODE                        // M→HS (T-SBI ecall a0=2; PA/identity enter)
  LI(t0, 0x257A0211)
  LI(t1, gpa_data)
  hsv.w t0, (t1)                                // HS hyper-store to guest address
  nop
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)
  hlv.w a4, (t1)                                // expect 0x257A0211
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test2_rsw01:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_rsw01, test2_rsw01_str)  // signature: dump a4 (test2_rsw01) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: G leaf RSW=10 HS HLV+HSV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | 0x200), gpa_data, LEVEL0)  // RSW=10 (bit 9)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  RVTEST_TSBI_GOTO_SMODE                        // M→HS (T-SBI ecall a0=2; PA/identity enter)
  LI(t0, 0x257A0212)
  LI(t1, gpa_data)
  hsv.w t0, (t1)                                // HS hyper-store to guest address
  nop
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)
  hlv.w a6, (t1)                                // expect 0x257A0212
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test3_rsw10:
  RVTEST_SIGUPD(x2, x5, x4, a6, test3_rsw10, test3_rsw10_str)  // signature: dump a6 (test3_rsw10) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: G leaf RSW=11 HS HLV+HSV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_SOFT), gpa_data, LEVEL0)  // RSW=11
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  RVTEST_TSBI_GOTO_SMODE                        // M→HS (T-SBI ecall a0=2; PA/identity enter)
  LI(t0, 0x257A0213)
  LI(t1, gpa_data)
  hsv.w t0, (t1)                                // HS hyper-store to guest address
  nop
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)
  hlv.w a7, (t1)                                // expect 0x257A0213
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test4_rsw11:
  RVTEST_SIGUPD(x2, x5, x4, a7, test4_rsw11, test4_rsw11_str)  // signature: dump a7 (test4_rsw11) for PASS/FAIL

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
rvtest_hlvl0_pg_tbl:
  .zero(4096)

test1_rsw00_str: .string "\"Mismatch on HS HLV/HSV with G RSW=00 in Test Case 1!\""
test2_rsw01_str: .string "\"Mismatch on HS HLV/HSV with G RSW=01 in Test Case 2!\""
test3_rsw10_str: .string "\"Mismatch on HS HLV/HSV with G RSW=10 in Test Case 3!\""
test4_rsw11_str: .string "\"Mismatch on HS HLV/HSV with G RSW=11 in Test Case 4!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
