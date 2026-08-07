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
//  2b/2c. G leaf RSW=01/10: HS HSV+HLV → Successful (cp_hgatp_pte_rsw auto[1]/auto[2])
//  3. G leaf reserved walk PTE[60:54] ones + all-ones: HS HLV+HSV each → Expected Fault
//  4. G leaf PBMT=1/2/3 (menvcfg.PBMTE=1): HS HLV+HSV → dump
//  5. Restore valid leaf: HS HLV → Successful (0x257A0241)
//
// Total Expected Faults :: ≥8 (reserved); PBMT Sail-dependent
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_g_pte_attr_RV64_VSmode.S"
#define SIGUPD_COUNT 20
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VSMODE / _SMODE (ecall a0=4/2)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE (mret + PA↔VA relocate)
#include "riscv_arch_test.h"

#define PTE_BIT54 (_RISCV_ULL(1) << 54)
#define PTE_BIT55 (_RISCV_ULL(1) << 55)
#define PTE_BIT56 (_RISCV_ULL(1) << 56)
#define PTE_BIT57 (_RISCV_ULL(1) << 57)
#define PTE_BIT58 (_RISCV_ULL(1) << 58)
#define PTE_BIT59 (_RISCV_ULL(1) << 59)
#define PTE_BIT60 (_RISCV_ULL(1) << 60)
#define PTE_RSVD_ALL (_RISCV_ULL(0x7F) << 54)    /* bits 60:54 — coverpoint all_ones */
#define PTE_PBMT1 (_RISCV_ULL(1) << 61)
#define PTE_PBMT2 (_RISCV_ULL(1) << 62)
#define PTE_PBMT3 (_RISCV_ULL(3) << 61)

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
// Test case 2b: G leaf RSW=01 (0x100) HS HSV+HLV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | 0x100), gpa_data, LEVEL0)
  hfence.gvma
  RVTEST_TSBI_GOTO_SMODE
  LI(t0, 0x257A0242)
  LI(t1, gpa_data)
  hsv.w t0, (t1)
  nop
  hfence.gvma
  LI(a4, 0)
  hlv.w a4, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test2b_rsw01:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2b_rsw01, test2b_rsw01_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2c: G leaf RSW=10 (0x200) HS HSV+HLV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | 0x200), gpa_data, LEVEL0)
  hfence.gvma
  RVTEST_TSBI_GOTO_SMODE
  LI(t0, 0x257A0243)
  LI(t1, gpa_data)
  hsv.w t0, (t1)
  nop
  hfence.gvma
  LI(a5, 0)
  hlv.w a5, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test2c_rsw10:
  RVTEST_SIGUPD(x2, x5, x4, a5, test2c_rsw10, test2c_rsw10_str)

// Test cases 3a–3h: G reserved PTE[60:54] walking-ones + all-ones HS HLV (+HSV)
// Soft-RSW [60:59] (Svrsw60t59b): HLV/HSV succeed; still score walking_one bins.
// Separate HLV/HSV hops + hfence.gvma so .rvvi keeps G_PTE_* (no TLB-hit silent walk).
// Distinct SPA patterns avoid HLV.W sign-extend DEADBEEF mistag (sail_to_rvvi filter).
//---------------------------------------------------------------------------------------------------------------------------------
#define G_RSVD_CASE(bitmask, reg, label, strlabel)                  \
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | (bitmask)), gpa_data, LEVEL0); \
  hfence.gvma;                                                      \
  LI(t0, 0x257A02C0);                                               \
  la t1, test_region;                                               \
  sw t0, 0(t1);                                                     \
  RVTEST_TSBI_GOTO_SMODE;                                           \
  LI(reg, 0);                                                       \
  LI(t1, gpa_data);                                                 \
  hlv.w reg, (t1);                                                  \
  nop;                                                              \
  RVTEST_TSBI_GOTO_MMODE;                                           \
  hfence.gvma;                                                      \
  RVTEST_TSBI_GOTO_SMODE;                                           \
  LI(t0, 0x257A02C1);                                               \
  LI(t1, gpa_data);                                                 \
  hsv.w t0, (t1);                                                   \
  nop;                                                              \
  RVTEST_TSBI_GOTO_MMODE;                                           \
  label:                                                            \
  RVTEST_SIGUPD(x2, x5, x4, reg, label, strlabel)

  G_RSVD_CASE(PTE_BIT54, a4, test3a_b54, test3a_b54_str)
  G_RSVD_CASE(PTE_BIT55, a6, test3b_b55, test3b_b55_str)
  G_RSVD_CASE(PTE_BIT56, a7, test3c_b56, test3c_b56_str)
  G_RSVD_CASE(PTE_BIT57, s2, test3d_b57, test3d_b57_str)
  G_RSVD_CASE(PTE_BIT58, s3, test3e_b58, test3e_b58_str)
  G_RSVD_CASE(PTE_BIT59, s4, test3f_b59, test3f_b59_str)
  G_RSVD_CASE(PTE_BIT60, s5, test3g_b60, test3g_b60_str)
  G_RSVD_CASE(PTE_RSVD_ALL, s6, test3h_all, test3h_all_str)

#undef G_RSVD_CASE

//---------------------------------------------------------------------------------------------------------------------------------
// Test cases 4a–4c: G PBMT=1/2/3 with menvcfg.PBMTE=1 HS HLV+HSV
// (G-stage needs menvcfg.PBMTE only — vmem_pte.sail::pte_is_invalid)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, MENVCFG_PBMTE)
  csrs menvcfg, t0

  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_PBMT1), gpa_data, LEVEL0)
  hfence.gvma
  RVTEST_TSBI_GOTO_SMODE
  LI(a7, 0)
  LI(t1, gpa_data)
  hlv.w a7, (t1)
  nop
  LI(t0, 0x257A0244)
  hsv.w t0, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test4a_pbmt1:
  RVTEST_SIGUPD(x2, x5, x4, a7, test4a_pbmt1, test4a_pbmt1_str)

  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_PBMT2), gpa_data, LEVEL0)
  hfence.gvma
  RVTEST_TSBI_GOTO_SMODE
  LI(s7, 0)
  LI(t1, gpa_data)
  hlv.w s7, (t1)
  nop
  LI(t0, 0x257A0245)
  hsv.w t0, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test4b_pbmt2:
  RVTEST_SIGUPD(x2, x5, x4, s7, test4b_pbmt2, test4b_pbmt2_str)

  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_PBMT3), gpa_data, LEVEL0)
  hfence.gvma
  RVTEST_TSBI_GOTO_SMODE
  LI(s8, 0)
  LI(t1, gpa_data)
  hlv.w s8, (t1)
  nop
  LI(t0, 0x257A0246)
  hsv.w t0, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test4c_pbmt3:
  RVTEST_SIGUPD(x2, x5, x4, s8, test4c_pbmt3, test4c_pbmt3_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test cases 4d–4f: G PBMT=1/2/3 with PBMTE=0 (covergroup bins only no_support={0})
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, MENVCFG_PBMTE)
  csrc menvcfg, t0

  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_PBMT1), gpa_data, LEVEL0)
  hfence.gvma
  RVTEST_TSBI_GOTO_SMODE
  LI(s9, 0)
  LI(t1, gpa_data)
  hlv.w s9, (t1)
  nop
  LI(t0, 0xDEADBEEF)
  hsv.w t0, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test4d_pbmt1_nosup:
  RVTEST_SIGUPD(x2, x5, x4, s9, test4d_pbmt1_nosup, test4d_pbmt1_nosup_str)

  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_PBMT2), gpa_data, LEVEL0)
  hfence.gvma
  RVTEST_TSBI_GOTO_SMODE
  LI(s10, 0)
  LI(t1, gpa_data)
  hlv.w s10, (t1)
  nop
  LI(t0, 0xDEADBEEF)
  hsv.w t0, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test4e_pbmt2_nosup:
  RVTEST_SIGUPD(x2, x5, x4, s10, test4e_pbmt2_nosup, test4e_pbmt2_nosup_str)

  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_PBMT3), gpa_data, LEVEL0)
  hfence.gvma
  RVTEST_TSBI_GOTO_SMODE
  LI(s11, 0)
  LI(t1, gpa_data)
  hlv.w s11, (t1)
  nop
  LI(t0, 0xDEADBEEF)
  hsv.w t0, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test4f_pbmt3_nosup:
  RVTEST_SIGUPD(x2, x5, x4, s11, test4f_pbmt3_nosup, test4f_pbmt3_nosup_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: Restore valid G leaf HS HLV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // restore valid G leaf RSW=00
  LI(t0, 0x257A0241)
  la t1, test_region
  sw t0, 0(t1)
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  RVTEST_TSBI_GOTO_SMODE                        // M→HS (T-SBI ecall a0=2; PA/identity enter)
  LI(s2, 0)
  LI(t1, gpa_data)                              // t1 = GPA for all HS HLV/HSV
  hlv.w s2, (t1)                                // expect 0x257A0241
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
test2b_rsw01_str:  .string "\"Mismatch on HS HLV/HSV with G RSW=01 in Test Case 2b!\""
test2c_rsw10_str:  .string "\"Mismatch on HS HLV/HSV with G RSW=10 in Test Case 2c!\""
test3a_b54_str:    .string "\"Mismatch on G reserved bit54 HLV (expect fault) in Test Case 3a!\""
test3b_b55_str:    .string "\"Mismatch on G reserved bit55 HLV (expect fault) in Test Case 3b!\""
test3c_b56_str:    .string "\"Mismatch on G reserved bit56 HLV (expect fault) in Test Case 3c!\""
test3d_b57_str:    .string "\"Mismatch on G reserved bit57 HLV (expect fault) in Test Case 3d!\""
test3e_b58_str:    .string "\"Mismatch on G reserved bit58 HLV (expect fault) in Test Case 3e!\""
test3f_b59_str:    .string "\"Mismatch on G reserved bit59 HLV (expect fault) in Test Case 3f!\""
test3g_b60_str:    .string "\"Mismatch on G reserved bit60 HLV (expect fault) in Test Case 3g!\""
test3h_all_str:    .string "\"Mismatch on G reserved all-ones HLV (expect fault) in Test Case 3h!\""
test4a_pbmt1_str:  .string "\"Mismatch on G PBMT=1 HLV/HSV in Test Case 4a!\""
test4b_pbmt2_str:  .string "\"Mismatch on G PBMT=2 HLV/HSV in Test Case 4b!\""
test4c_pbmt3_str:  .string "\"Mismatch on G PBMT=3 HLV/HSV in Test Case 4c!\""
test4d_pbmt1_nosup_str: .string "\"Mismatch on G PBMT=1 PBMTE=0 (expect fault) in Test Case 4d!\""
test4e_pbmt2_nosup_str: .string "\"Mismatch on G PBMT=2 PBMTE=0 (expect fault) in Test Case 4e!\""
test4f_pbmt3_nosup_str: .string "\"Mismatch on G PBMT=3 PBMTE=0 (expect fault) in Test Case 4f!\""
test5_restore_str: .string "\"Mismatch on HS HLV after valid G leaf restore in Test Case 5!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
