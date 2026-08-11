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

// Mode hops (Sv-style GOTO_* plus H T-SBI):
//   Enter PA/identity → RVTEST_TSBI_GOTO_VSMODE / _SMODE / _VUMODE
//   Enter VA≠PA (V_SAVE_AREA) → RVTEST_GOTO_LOWER_MODE
//   Return to M → always RVTEST_TSBI_GOTO_MMODE
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
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set gpa_data, 0x0000000000C002000            // GPA HS HLV/HSV will use (vsatp Bare)

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- G-stage Sv39x4 only (VS Bare): 3-level GPA→PA walk; leaf RSW/RSVD/PBMT vary per case ----
  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_data, LEVEL2)  // G non-leaf L2 → L1 table for data GPA
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf L1 → L0 table for data GPA
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf RSW=00 U=1 R/W (valid baseline)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  csrw vsatp, x0                                // VS Bare — isolate G-stage attribute bins
  csrw satp, x0                                 // HS satp Bare
  HGATP_SETUP(sv39x4)                           // turn on G-stage Sv39x4
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0x257A0240)                            // known SPA preload for case 1
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)

  LI(t1, gpa_data)                              // t1 = GPA for all HS HLV/HSV


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: G leaf RSW=00 HS HSV+HLV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(t0, 0x257A0240)                            // payload for RSW=00 HSV
  hsv.w t0, (t1)                                // HS hyper-store GPA → SPA through RSW=00 leaf
  nop                                           // trap-skip pad
  hfence.gvma                                   // flush G TLB so HLV rewalks (legal in HS)
  LI(a3, 0)                                     // clear result; stays 0 if HLV faults
  hlv.w a3, (t1)                                // HS hyper-load; expect 0x257A0240
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test1_rsw00:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_rsw00, test1_rsw00_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: G leaf RSW=11 HS HSV+HLV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_SOFT), gpa_data, LEVEL0)  // G leaf RSW=11 (PTE_SOFT) for case 2
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(t0, 0x257A0241)                            // payload for RSW=11 HSV
  LI(t1, gpa_data)                              // t1 = GPA for all HS HLV/HSV
  hsv.w t0, (t1)                                // HS hyper-store through RSW=11 leaf
  nop                                           // trap-skip pad
  hfence.gvma                                   // flush G TLB so HLV rewalks
  LI(a6, 0)                                     // clear result; stays 0 if HLV faults
  hlv.w a6, (t1)                                // HS hyper-load; expect 0x257A0241
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test2_rsw11:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test2_rsw11, test2_rsw11_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2b: G leaf RSW=01 (0x100) HS HSV+HLV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | 0x100), gpa_data, LEVEL0)  // G leaf RSW=01 (bit 8) U=1 R/W
  hfence.gvma                                   // flush G TLB after PTE rewrite
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(t0, 0x257A0242)                            // payload for RSW=01 HSV
  LI(t1, gpa_data)                              // t1 = GPA
  hsv.w t0, (t1)                                // HS hyper-store through RSW=01 leaf
  nop                                           // trap-skip pad
  hfence.gvma                                   // flush G TLB so HLV rewalks
  LI(a4, 0)                                     // clear result; stays 0 if HLV faults
  hlv.w a4, (t1)                                // HS hyper-load; expect 0x257A0242
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test2b_rsw01:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2b_rsw01, test2b_rsw01_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2c: G leaf RSW=10 (0x200) HS HSV+HLV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | 0x200), gpa_data, LEVEL0)  // G leaf RSW=10 (bit 9) U=1 R/W
  hfence.gvma                                   // flush G TLB after PTE rewrite
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(t0, 0x257A0243)                            // payload for RSW=10 HSV
  LI(t1, gpa_data)                              // t1 = GPA
  hsv.w t0, (t1)                                // HS hyper-store through RSW=10 leaf
  nop                                           // trap-skip pad
  hfence.gvma                                   // flush G TLB so HLV rewalks
  LI(a5, 0)                                     // clear result; stays 0 if HLV faults
  hlv.w a5, (t1)                                // HS hyper-load; expect 0x257A0243
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test2c_rsw10:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a5, test2c_rsw10, test2c_rsw10_str) // SIGUPD

// Test cases 3a–3h: G reserved PTE[60:54] walking-ones + all-ones HS HLV (+HSV)
// Soft-RSW [60:59] (Svrsw60t59b): HLV/HSV succeed; still score walking_one bins.
// Separate HLV/HSV hops + hfence.gvma so .rvvi keeps G_PTE_* (no TLB-hit silent walk).
// Distinct SPA patterns avoid HLV.W sign-extend DEADBEEF mistag (sail_to_rvvi filter).
// Macro lines use /* */ then `\`: `//` would eat the backslash and break continuation.
//---------------------------------------------------------------------------------------------------------------------------------
#define G_RSVD_CASE(bitmask, reg, label, strlabel)                  /* one reserved-bit HLV+HSV case */ \
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | (bitmask)), gpa_data, LEVEL0); /* G leaf A=D=1 U=1 R/W + reserved bitmask */ \
  hfence.gvma;                                                      /* flush G TLB so next HLV rewalks */ \
  LI(t0, 0x257A02C0);                                               /* SPA preload before HLV (not DEADBEEF) */ \
  la t1, test_region;                                               /* t1 = SPA of data page */ \
  sw t0, 0(t1);                                                     /* write preload at SPA */ \
  RVTEST_TSBI_GOTO_SMODE;                                           /* M→HS identity (HLV is HS-only) */ \
  LI(reg, 0);                                                       /* sentinel — stays 0 if HLV faults */ \
  LI(t1, gpa_data);                                                 /* t1 = GPA for HLV */ \
  hlv.w reg, (t1);                                                  /* HS hyper-load through reserved G leaf */ \
  nop;                                                              /* trap-skip padding after HLV */ \
  RVTEST_TSBI_GOTO_MMODE;                                           /* back to M */ \
  hfence.gvma;                                                      /* flush G TLB so HSV is a fresh walk */ \
  RVTEST_TSBI_GOTO_SMODE;                                           /* M→HS for HSV */ \
  LI(t0, 0x257A02C1);                                               /* HSV payload (must not land if fault) */ \
  LI(t1, gpa_data);                                                 /* t1 = GPA for HSV */ \
  hsv.w t0, (t1);                                                   /* HS hyper-store through same reserved G leaf */ \
  nop;                                                              /* trap-skip padding after HSV */ \
  RVTEST_TSBI_GOTO_MMODE;                                           /* back to M */ \
  label:                                                            /* signature dump point for this bit */ \
  RVTEST_SIGUPD(x2, x5, x4, reg, label, strlabel)                   /* dump HLV result (0 if guest-page) */

  G_RSVD_CASE(PTE_BIT54, a4, test3a_b54, test3a_b54_str)  // HS HLV+HSV reserved bit54; expect fault (a4 stays 0)
  G_RSVD_CASE(PTE_BIT55, a6, test3b_b55, test3b_b55_str)  // HS HLV+HSV reserved bit55; expect fault (a6 stays 0)
  G_RSVD_CASE(PTE_BIT56, a7, test3c_b56, test3c_b56_str)  // HS HLV+HSV reserved bit56; expect fault (a7 stays 0)
  G_RSVD_CASE(PTE_BIT57, s2, test3d_b57, test3d_b57_str)  // HS HLV+HSV reserved bit57; expect fault (s2 stays 0)
  G_RSVD_CASE(PTE_BIT58, s3, test3e_b58, test3e_b58_str)  // HS HLV+HSV reserved bit58; expect fault (s3 stays 0)
  G_RSVD_CASE(PTE_BIT59, s4, test3f_b59, test3f_b59_str)  // HS HLV+HSV soft-RSW bit59; dump result (may succeed)
  G_RSVD_CASE(PTE_BIT60, s5, test3g_b60, test3g_b60_str)  // HS HLV+HSV soft-RSW bit60; dump result (may succeed)
  G_RSVD_CASE(PTE_RSVD_ALL, s6, test3h_all, test3h_all_str)  // HS HLV+HSV reserved [60:54] all-ones; expect fault

#undef G_RSVD_CASE

//---------------------------------------------------------------------------------------------------------------------------------
// Test cases 4a–4c: G PBMT=1/2/3 with menvcfg.PBMTE=1 HS HLV+HSV
// (G-stage needs menvcfg.PBMTE only — vmem_pte.sail::pte_is_invalid)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, MENVCFG_PBMTE)                         // t0 = menvcfg.PBMTE mask
  csrs menvcfg, t0                              // set menvcfg.PBMTE=1 so G-stage PBMT is defined

  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_PBMT1), gpa_data, LEVEL0)  // G leaf PBMT=1 U=1 R/W
  hfence.gvma                                   // flush G TLB after PTE rewrite
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(a7, 0)                                     // sentinel / result for HLV
  LI(t1, gpa_data)                              // t1 = GPA
  hlv.w a7, (t1)                                // HS hyper-load PBMT=1 PBMTE=1 — dump Sail result
  nop                                           // trap-skip pad
  LI(t0, 0x257A0244)                            // payload for PBMT=1 HSV
  hsv.w t0, (t1)                                // HS hyper-store PBMT=1 — dump Sail result
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test4a_pbmt1:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test4a_pbmt1, test4a_pbmt1_str) // SIGUPD

  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_PBMT2), gpa_data, LEVEL0)  // G leaf PBMT=2 U=1 R/W
  hfence.gvma                                   // flush G TLB after PTE rewrite
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(s7, 0)                                     // sentinel / result for HLV
  LI(t1, gpa_data)                              // t1 = GPA
  hlv.w s7, (t1)                                // HS hyper-load PBMT=2 PBMTE=1 — dump Sail result
  nop                                           // trap-skip pad
  LI(t0, 0x257A0245)                            // payload for PBMT=2 HSV
  hsv.w t0, (t1)                                // HS hyper-store PBMT=2 — dump Sail result
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test4b_pbmt2:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s7, test4b_pbmt2, test4b_pbmt2_str) // SIGUPD

  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_PBMT3), gpa_data, LEVEL0)  // G leaf PBMT=3 U=1 R/W
  hfence.gvma                                   // flush G TLB after PTE rewrite
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(s8, 0)                                     // sentinel / result for HLV
  LI(t1, gpa_data)                              // t1 = GPA
  hlv.w s8, (t1)                                // HS hyper-load PBMT=3 PBMTE=1 — dump Sail result
  nop                                           // trap-skip pad
  LI(t0, 0x257A0246)                            // payload for PBMT=3 HSV
  hsv.w t0, (t1)                                // HS hyper-store PBMT=3 — dump Sail result
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test4c_pbmt3:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s8, test4c_pbmt3, test4c_pbmt3_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test cases 4d–4f: G PBMT=1/2/3 with PBMTE=0 (covergroup bins only no_support={0})
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, MENVCFG_PBMTE)                         // t0 = menvcfg.PBMTE mask
  csrc menvcfg, t0                              // clear menvcfg.PBMTE — G PBMT encodings unsupported

  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_PBMT1), gpa_data, LEVEL0)  // G leaf PBMT=1 with PBMTE=0
  hfence.gvma                                   // flush G TLB after PTE rewrite
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(s9, 0)                                     // sentinel — stays 0 if HLV faults
  LI(t1, gpa_data)                              // t1 = GPA
  hlv.w s9, (t1)                                // HS hyper-load PBMT=1 PBMTE=0 → expect fault
  nop                                           // trap-skip pad
  LI(t0, 0xDEADBEEF)                            // payload that must not land if HSV faults
  hsv.w t0, (t1)                                // HS hyper-store PBMT=1 PBMTE=0 → expect fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test4d_pbmt1_nosup:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s9, test4d_pbmt1_nosup, test4d_pbmt1_nosup_str) // SIGUPD

  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_PBMT2), gpa_data, LEVEL0)  // G leaf PBMT=2 with PBMTE=0
  hfence.gvma                                   // flush G TLB after PTE rewrite
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(s10, 0)                                    // sentinel — stays 0 if HLV faults
  LI(t1, gpa_data)                              // t1 = GPA
  hlv.w s10, (t1)                               // HS hyper-load PBMT=2 PBMTE=0 → expect fault
  nop                                           // trap-skip pad
  LI(t0, 0xDEADBEEF)                            // payload that must not land if HSV faults
  hsv.w t0, (t1)                                // HS hyper-store PBMT=2 PBMTE=0 → expect fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test4e_pbmt2_nosup:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s10, test4e_pbmt2_nosup, test4e_pbmt2_nosup_str) // SIGUPD

  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_PBMT3), gpa_data, LEVEL0)  // G leaf PBMT=3 with PBMTE=0
  hfence.gvma                                   // flush G TLB after PTE rewrite
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(s11, 0)                                    // sentinel — stays 0 if HLV faults
  LI(t1, gpa_data)                              // t1 = GPA
  hlv.w s11, (t1)                               // HS hyper-load PBMT=3 PBMTE=0 → expect fault
  nop                                           // trap-skip pad
  LI(t0, 0xDEADBEEF)                            // payload that must not land if HSV faults
  hsv.w t0, (t1)                                // HS hyper-store PBMT=3 PBMTE=0 → expect fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test4f_pbmt3_nosup:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s11, test4f_pbmt3_nosup, test4f_pbmt3_nosup_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: Restore valid G leaf HS HLV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // restore valid G leaf RSW=00 U=1 R/W
  LI(t0, 0x257A0241)                            // known SPA pattern for restore check
  la t1, test_region                            // t1 = SPA
  sw t0, 0(t1)                                  // write 0x257A0241 at SPA before HS HLV
  hfence.gvma                                   // flush G TLB so walk sees restored leaf

  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(s2, 0)                                     // clear result before HLV
  LI(t1, gpa_data)                              // t1 = GPA
  hlv.w s2, (t1)                                // HS hyper-load valid leaf; expect 0x257A0241
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test5_restore:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test5_restore, test5_restore_str) // SIGUPD

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
rvtest_hlvl1_pg_tbl:                            // G-stage L1 PTE storage (Sv39x4 VPN2)
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
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
