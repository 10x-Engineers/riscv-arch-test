// --------------------------------------------------------------------------------------------------------------------------------
// svh_g_adbit_VSmode.S
// Config: sail-rv32-max | VS=Sv32 + G=Sv32x4 (both ON), Svade
// Coverpoints mapped (SvH_cg): cp_hgatp_adbit_behavior
// What this proves (one line):
//   HS HLV/HSV with G leaf A=0 fault under Svade; VS leaf A=D=1 co-samples vs_pte_ad_set.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. VS A=1 D=1 XWR=111, G A=0 D=0 U=1 XWR=111: HS HLV → Expected Fault (s2 stays 0)
//  2. Same PTEs: HS HSV → Expected Fault (SPA stays 0x257A0251)
//
// Total Expected Faults :: 2
// Note: VS A=0 co-sample (vs_pte_ad_unset) omitted — Sail reports page-fault
//   (not guest-page) on that two-stage path and breaks trap-sig. Do not force it.
// Converter: HLV must keep all two-stage walk leaves (not stop at 2) so G A=0
//   co-samples with READ_ACCESS on case 1.
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_g_adbit_VSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 128
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VSMODE / _SMODE (ecall a0=4/2)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE (mret + PA↔VA relocate)
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_data,                 0x008001000     // GVA HS HLV/HSV will use (via SPVP=1)
  .set gpa_data,                0x00C002000     // GPA behind va_data
  .set gpa_code,                0x012000000     // GPA for code (needed if VS ever hops; HS uses PA)
  .set gpa_rvtest_Vroot_pg_tbl, 0x01000A000     // GPA of VS root page table
  .set gpa_rvtest_vlvl0_pg_tbl, 0x01000B000     // GPA of VS L0 page table

  // ---- G-stage maps: code + VS page-table pages + data leaf with A=0 ----
  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)  // code GPA → PA

  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL1)  // non-leaf → G L0 for VS root GPA
  G_PTE_SETUP(sv32x4, rvtest_Vroot_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL0)  // VS root R/W
  G_PTE_SETUP(sv32x4, rvtest_vlvl0_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl0_pg_tbl, LEVEL0)  // VS L0 R/W

  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // non-leaf for data GPA
  // G leaf A=D=0 U=1 XWRV=1111 → g_pte_ad_unset (Svade must fault on access)
  G_PTE_SETUP(sv32x4, test_region, (PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf A=D=0 U=1 XWR=111 (Svade must fault)

  // ---- VS-stage: va_data → gpa_data with A=D=1 (so only G A=0 causes the fault) ----
  VS_PTE_SETUP(sv32, GPA, gpa_rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)  // non-leaf → VS L0 (GPA)
  // VS leaf A=D=1 XWRV=1111 → vs_pte_ad_set (U=0; HS HLV uses SPVP=1 so SUM not needed)
  VS_PTE_SETUP(sv32, GPA, gpa_data, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)  // VS leaf A=D=1 XWR=111 U=0 (only G A=0 should fault)

  csrw satp, x0                                 // HS satp Bare
  VSATP_SETUP(sv32, GPA)                        // VS-stage ON (PPN is GPA of VS root)
  HGATP_SETUP(sv32x4)                           // G-stage ON
  hfence.vvma                                   // flush VS TLB
  hfence.gvma                                   // flush G TLB

  LI(t0, 0x257A0251)                            // known SPA preload for HSV fault check
  la t1, test_region
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)

  LI(t0, HSTATUS_SPVP)                          // SPVP=1 → HLV/HSV use VS S-mode perms
  csrs hstatus, t0                              // set hstatus.SPVP=1 so HLV/HSV use VS S-mode perms

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: VS A=1 D=1, G A=0 — HS HLV | Expected: Expected Fault (Svade)
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // clear stale walks before HS hop
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  RVTEST_TSBI_GOTO_SMODE                        // M→HS (HLV is an HS instruction)
  LI(s2, 0)                                     // sentinel in callee-saved (survives ecall)
  LI(a5, va_data)                               // a5 = GVA (two-stage: VS then G)
  hlv.w s2, (a5)                                // VS OK → G A=0 → load guest-page fault
  nop                                           // trap-skip padding
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test1_hlv_ad_set:
  RVTEST_SIGUPD(x2, x5, x4, s2, test1_hlv_ad_set, test1_hlv_ad_set_str)  // signature: dump s2 (test1_hlv_ad_set) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: VS A=1 D=1, G A=0 — HS HSV | Expected: Expected Fault (Svade)
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  RVTEST_TSBI_GOTO_SMODE                        // M→HS (T-SBI ecall a0=2; PA/identity enter)
  LI(t2, 0xBAD00FAD)                            // would-be store payload
  LI(a5, va_data)
  hsv.w t2, (a5)                                // VS OK → G A=0 → store guest-page fault
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t3, test_region
  lw s3, 0(t3)                                  // expect preload 0x257A0251 unchanged
  test2_hsv_ad_set:
  RVTEST_SIGUPD(x2, x5, x4, s3, test2_hsv_ad_set, test2_hsv_ad_set_str)  // signature: dump s3 (test2_hsv_ad_set) for PASS/FAIL

  LI(t0, HSTATUS_SPVP)
  csrc hstatus, t0                              // restore SPVP=0

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
.align 12
rvtest_vlvl0_pg_tbl:
  .zero(4096)

test1_hlv_ad_set_str: .string "\"Mismatch on HS HLV with VS A=1 G A=0 (expect fault) in Test Case 1!\""
test2_hsv_ad_set_str: .string "\"Mismatch on HS HSV with VS A=1 G A=0 (expect SPA unchanged) in Test Case 2!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
