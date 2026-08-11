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
  .set gpa_data, 0x00C002000                    // GPA HS HLV/HSV will use (vsatp Bare ⇒ address-as-GPA)
  .set gpa_code, 0x80000000                     // identity code GPA (optional for HS-only)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------
  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)  // G superpage: gpa_code → PA(code); U=1 X/R A=D=1

  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf: VPN1 for data GPA → G L0
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf: gpa_data → PA(test_region) R/W U=1 RSW=00


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  csrw vsatp, x0                                // VS Bare — isolate G-stage RSW bins
  HGATP_SETUP(sv32x4)                           // hgatp = Sv32x4, PPN = G root
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0x257A0210)                            // known SPA preload for case 1
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // SPA preload (known pattern before HS HLV/HSV)

  LI(t1, gpa_data)                              // t1 = GPA for all HS HLV/HSV


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: G leaf RSW=00 HS HLV+HSV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf RSW=00 R/W U=1 A=D=1
  hfence.gvma                                   // M flush before HS hop so walk sees this leaf

  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(t0, 0x257A0210)                            // payload for RSW=00 HSV
  hsv.w t0, (t1)                                // HS hyper-store GPA → SPA through RSW=00 leaf
  nop                                           // trap-skip pad
  hfence.gvma                                   // legal in HS — force HLV to rewalk (not TLB-hit)
  hlv.w a3, (t1)                                // HS hyper-load; expect 0x257A0210
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test1_rsw00:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_rsw00, test1_rsw00_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: G leaf RSW=01 HS HLV+HSV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | 0x100), gpa_data, LEVEL0)  // G leaf RSW=01 (bit 8) R/W U=1
  hfence.gvma                                   // flush G TLB after PTE rewrite

  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(t0, 0x257A0211)                            // payload for RSW=01 HSV
  LI(t1, gpa_data)                              // t1 = GPA (reload after hop)
  hsv.w t0, (t1)                                // HS hyper-store through RSW=01 leaf
  nop                                           // trap-skip pad
  hfence.gvma                                   // flush G TLB so HLV rewalks
  hlv.w a4, (t1)                                // HS hyper-load; expect 0x257A0211
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test2_rsw01:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_rsw01, test2_rsw01_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: G leaf RSW=10 HS HLV+HSV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | 0x200), gpa_data, LEVEL0)  // G leaf RSW=10 (bit 9) R/W U=1
  hfence.gvma                                   // flush G TLB after PTE rewrite

  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(t0, 0x257A0212)                            // payload for RSW=10 HSV
  LI(t1, gpa_data)                              // t1 = GPA
  hsv.w t0, (t1)                                // HS hyper-store through RSW=10 leaf
  nop                                           // trap-skip pad
  hfence.gvma                                   // flush G TLB so HLV rewalks
  hlv.w a6, (t1)                                // HS hyper-load; expect 0x257A0212
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test3_rsw10:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test3_rsw10, test3_rsw10_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: G leaf RSW=11 HS HLV+HSV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_SOFT), gpa_data, LEVEL0)  // G leaf RSW=11 (PTE_SOFT bits 9:8)
  hfence.gvma                                   // flush G TLB after PTE rewrite

  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(t0, 0x257A0213)                            // payload for RSW=11 HSV
  LI(t1, gpa_data)                              // t1 = GPA
  hsv.w t0, (t1)                                // HS hyper-store through RSW=11 leaf
  nop                                           // trap-skip pad
  hfence.gvma                                   // flush G TLB so HLV rewalks
  hlv.w a7, (t1)                                // HS hyper-load; expect 0x257A0213
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test4_rsw11:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test4_rsw11, test4_rsw11_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing gpa_data
  .word 0                                       // payload word (HS HSV / M preload)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_rsw00_str: .string "\"Mismatch on HS HLV/HSV with G RSW=00 in Test Case 1!\""
test2_rsw01_str: .string "\"Mismatch on HS HLV/HSV with G RSW=01 in Test Case 2!\""
test3_rsw10_str: .string "\"Mismatch on HS HLV/HSV with G RSW=10 in Test Case 3!\""
test4_rsw11_str: .string "\"Mismatch on HS HLV/HSV with G RSW=11 in Test Case 4!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
