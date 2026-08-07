// --------------------------------------------------------------------------------------------------------------------------------
// svh_g_pte_attr_RV64_VSmode.S
// Config: sail-rv64-max | vsatp=Bare, hgatp=Sv39x4 ON, HS HLV/HSV
// Pair:   svh_g_pte_attr_VSmode.S
// Coverpoints mapped (SvH_cg): cp_hgatp_pte_rsw, cp_hgatp_reserved_fields, cp_hgatp_svpbmt
// What this proves (one line):
//   Sv39x4 G PTE RSW ok via HS HLV+HSV; reserved/PBMT encodings dump Sail result.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. G leaf RSW=00: HS HSV+HLV → Successful (0x257A0240)
//  2. G leaf RSW=11: HS HSV+HLV → Successful (0x257A0241)
//  3. G leaf PTE_RSVD set: HS HLV + HSV → Expected Fault if Sail checks reserved (a4 stays 0)
//  4. G leaf PTE_PBMT=1 (PBMTE=1): HS HLV + HSV → dump (impl-dependent)
//  5. Restore valid leaf: HS HLV → Successful (0x257A0241)
//
// Total Expected Faults :: 1–2 (Sail-dependent for cases 3–4)
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_g_pte_attr_RV64_VSmode.S"
#define SIGUPD_COUNT 5
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VSMODE / _SMODE (ecall a0=4/2)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE (mret + PA↔VA relocate)
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set gpa_data, 0x0000000000C002000            // GPA HS HLV/HSV will use (vsatp Bare)

  // ---- G-stage Sv39x4 only (VS Bare): 3-level GPA→PA walk; leaf RSW/RSVD/PBMT vary per case ----
  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_data, LEVEL2)  // G non-leaf L2 → L1 table for data GPA
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf L1 → L0 table for data GPA
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf RSW=00 U=1 R/W (valid baseline)

  csrw vsatp, x0                                // VS Bare — isolate G-stage attribute bins
  csrw satp, x0                                 // HS satp Bare
  HGATP_SETUP(sv39x4)                           // turn on G-stage Sv39x4
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0x257A0240)                            // known SPA preload for case 1
  la t1, test_region
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)

  LI(t1, gpa_data)                              // t1 = GPA for all HS HLV/HSV

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: G leaf RSW=00 HS HSV+HLV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  RVTEST_TSBI_GOTO_SMODE                        // M→HS (T-SBI ecall a0=2; PA/identity enter)
  LI(t0, 0x257A0240)
  hsv.w t0, (t1)                                // HS hyper-store to guest address
  nop
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)
  LI(a3, 0)
  hlv.w a3, (t1)                                // HS hyper-load from guest address
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test1_rsw00:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_rsw00, test1_rsw00_str)  // signature: dump a3 (test1_rsw00) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: G leaf RSW=11 HS HSV+HLV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_SOFT), gpa_data, LEVEL0)  // G leaf RSW=11 (PTE_SOFT) for case 2
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  RVTEST_TSBI_GOTO_SMODE                        // M→HS (T-SBI ecall a0=2; PA/identity enter)
  LI(t0, 0x257A0241)
  LI(t1, gpa_data)                              // t1 = GPA for all HS HLV/HSV
  hsv.w t0, (t1)                                // HS hyper-store to guest address
  nop
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)
  LI(a6, 0)
  hlv.w a6, (t1)                                // HS hyper-load from guest address
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test2_rsw11:
  RVTEST_SIGUPD(x2, x5, x4, a6, test2_rsw11, test2_rsw11_str)  // signature: dump a6 (test2_rsw11) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: G leaf PTE_RSVD set HS HLV+HSV | Expected: Expected Fault (Sail-dependent)
// cp_hgatp_reserved_fields_rw bin: read_write_acc with g_pte_d_reserved
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_RSVD), gpa_data, LEVEL0)  // G leaf with reserved bits set (Sail may fault)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  RVTEST_TSBI_GOTO_SMODE                        // M→HS (T-SBI ecall a0=2; PA/identity enter)
  LI(a4, 0)                                     // sentinel: stays 0 if HLV traps
  LI(t1, gpa_data)                              // t1 = GPA for all HS HLV/HSV
  hlv.w a4, (t1)                                // HS load; Sail may fault on reserved bits
  nop
  LI(t0, 0xDEADBEEF)                            // would-be HSV payload
  hsv.w t0, (t1)                                // HS store; scores write_acc on reserved leaf
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test3_rsvd:
  RVTEST_SIGUPD(x2, x5, x4, a4, test3_rsvd, test3_rsvd_str)  // signature: dump a4 (test3_rsvd) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: G leaf PTE_PBMT=1 (PBMTE=1) HS HLV+HSV | Expected: dump (impl-dependent)
// cp_hgatp_svpbmt_rw bin: read_write_acc with g_pte_d_svpbmt
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, MENVCFG_PBMTE)
  csrs menvcfg, t0                              // set menvcfg (e.g. PBMTE for PBMT PTE bits)
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | _RISCV_ULL(0x1000000000000000)), gpa_data, LEVEL0)  // G leaf with PBMT=1 (needs menvcfg.PBMTE)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  RVTEST_TSBI_GOTO_SMODE                        // M→HS (T-SBI ecall a0=2; PA/identity enter)
  LI(a7, 0)                                     // dump register (pass or fault on HLV)
  LI(t1, gpa_data)                              // t1 = GPA for all HS HLV/HSV
  hlv.w a7, (t1)                                // HS load; Sail behavior impl-dependent
  nop
  LI(t0, 0x257A0244)                            // HSV probe payload (may fault)
  hsv.w t0, (t1)                                // HS store; scores write_acc on PBMT leaf
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test4_pbmt:
  RVTEST_SIGUPD(x2, x5, x4, a7, test4_pbmt, test4_pbmt_str)  // signature: dump a7 (test4_pbmt) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: Restore valid G leaf HS HLV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // restore valid G leaf RSW=00
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  RVTEST_TSBI_GOTO_SMODE                        // M→HS (T-SBI ecall a0=2; PA/identity enter)
  LI(s2, 0)
  LI(t1, gpa_data)                              // t1 = GPA for all HS HLV/HSV
  hlv.w s2, (t1)                                // expect 0x257A0241 from case 2
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test5_restore:
  RVTEST_SIGUPD(x2, x5, x4, s2, test5_restore, test5_restore_str)  // signature: dump s2 (test5_restore) for PASS/FAIL

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

test1_rsw00_str:   .string "\"Mismatch on HS HLV/HSV with G RSW=00 in Test Case 1!\""
test2_rsw11_str:   .string "\"Mismatch on HS HLV/HSV with G RSW=11 in Test Case 2!\""
test3_rsvd_str:    .string "\"Mismatch on HS HLV/HSV with G PTE_RSVD in Test Case 3!\""
test4_pbmt_str:    .string "\"Mismatch on HS HLV/HSV with G PTE_PBMT=1 in Test Case 4!\""
test5_restore_str: .string "\"Mismatch on HS HLV after valid G leaf restore in Test Case 5!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
