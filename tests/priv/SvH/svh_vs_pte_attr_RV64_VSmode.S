// --------------------------------------------------------------------------------------------------------------------------------
// svh_vs_pte_attr_RV64_VSmode.S
// Config: sail-rv64-max | VS=Sv39 ON, hgatp=Bare
// Pair:   svh_vs_pte_attr_VSmode.S
// Coverpoints mapped (SvH_cg): cp_vsatp_pte_rsw, cp_vsatp_reserved_fields, cp_vsatp_svpbmt
// What this proves (one line):
//   VS Sv39 PTE RSW 00..11 succeed with lw+sw; reserved/PBMT dump Sail result.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. RSW=00 leaf R/W: VS sw+lw → Successful (0x257A0301)
//  2. RSW=01 (0x100): VS sw+lw → Successful (0x257A0302)
//  3. RSW=10 (0x200): VS sw+lw → Successful (0x257A0303)
//  4. RSW=11 (PTE_SOFT): VS sw+lw → Successful (0x257A0304)
//  5. Reserved walk PTE[60:54] ones + all-ones: VS lw each → Expected Fault (sentinel 0)
//     Note: bits 59/60 are soft-RSW under Svrsw60t59b (sail-rv64-max) — lw succeeds; still
//     scores walking_one_59/60 on vs_pte_d (not a true reserved fault).
//  6. Reserved bits 54–58 + all-ones: VS sw each → Expected Fault (SPA unchanged)
//  6b. Soft-RSW bits 59/60: VS sw → Successful (distinct SPA patterns)
//  7. Reserved bit54 X-leaf: VS jalr → Expected Fault (fetch fault)
//  7b. Soft-RSW bits 59/60 X-leaf: VS jalr → Successful (ret trampoline)
//  8. PBMT=1/2/3 with menvcfg+henvcfg.PBMTE=1: VS lw (+sw on PBMT=1) → dump Sail result
//  9. PBMT=1 X-leaf: VS jalr → dump (fault or allow)
//
// Total Expected Faults :: ≥14 (reserved 54–58); bits 59/60 soft-RSW allow
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vs_pte_attr_RV64_VSmode.S"
#define SIGUPD_COUNT 31
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
// PTE[60:54] reserved walking-ones; PBMT is PTE[62:61]
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
#define PTE_PBMT3 (_RISCV_ULL(3) << 61)          /* == PTE_PBMT */

RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set va_rsw00,   0x0000000080010000           // GVA for RSW=00 R/W leaf
  .set va_rsw01,   0x0000000080020000           // GVA for RSW=01 leaf
  .set va_rsw10,   0x0000000080030000           // GVA for RSW=10 leaf
  .set va_rsw11,   0x0000000080040000           // GVA for RSW=11 (PTE_SOFT) leaf
  .set va_rsvd,    0x0000000080050000           // GVA for reserved-bits leaf (PTE[60:54])
  .set va_pbmt,    0x0000000080060000           // GVA for PBMT-encoded leaf
  .set va_code,    0x0000000090000000           // GVA where VS executes this code

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- VS-stage (vsatp Sv39): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)  // non-leaf: va_code VPN2 -> VS L1 table PA
  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // leaf: va_code -> PA(code); LEVEL1 = 2 MiB X/R

  csrr a0, mscratch                         // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // VA≠PA code entry

  // RSW=00 leaf at va_rsw00
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_rsw00, LEVEL2)  // non-leaf: va_rsw00 VPN2 -> VS L1 table PA
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_rsw00, LEVEL1)  // non-leaf: va_rsw00 VPN1 -> VS L0 table PA
  VS_PTE_SETUP(sv39, PA, test_region0, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V), va_rsw00, LEVEL0)  // leaf: va_rsw00 -> PA(test_region0) R/W; RSW=00

  // RSW=01 leaf at va_rsw01
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_rsw01, LEVEL2)  // non-leaf: va_rsw01 VPN2 -> VS L1 table PA
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_rsw01, LEVEL1)  // non-leaf: va_rsw01 VPN1 -> VS L0 table PA
  VS_PTE_SETUP(sv39, PA, test_region1, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | 0x100), va_rsw01, LEVEL0)  // leaf: RSW=01

  // RSW=10 leaf at va_rsw10
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_rsw10, LEVEL2)  // non-leaf: va_rsw10 VPN2 -> VS L1 table PA
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_rsw10, LEVEL1)  // non-leaf: va_rsw10 VPN1 -> VS L0 table PA
  VS_PTE_SETUP(sv39, PA, test_region2, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | 0x200), va_rsw10, LEVEL0)  // leaf: RSW=10

  // RSW=11 leaf at va_rsw11
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_rsw11, LEVEL2)  // non-leaf: va_rsw11 VPN2 -> VS L1 table PA
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_rsw11, LEVEL1)  // non-leaf: va_rsw11 VPN1 -> VS L0 table PA
  VS_PTE_SETUP(sv39, PA, test_region3, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_SOFT), va_rsw11, LEVEL0)  // leaf: RSW=11

  // Reserved PTE[60:54] leaf at va_rsvd (otherwise valid R/W V=1)
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_rsvd, LEVEL2)  // non-leaf: va_rsvd VPN2 -> VS L1 table PA
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_rsvd, LEVEL1)  // non-leaf: va_rsvd VPN1 -> VS L0 table PA
  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_RSVD), va_rsvd, LEVEL0)  // leaf: reserved bits set

  // PBMT leaf at va_pbmt
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_pbmt, LEVEL2)  // non-leaf: va_pbmt VPN2 -> VS L1 table PA
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_pbmt, LEVEL1)  // non-leaf: va_pbmt VPN1 -> VS L0 table PA
  VS_PTE_SETUP(sv39, PA, test_region5, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_PBMT), va_pbmt, LEVEL0)  // leaf: PBMT encoding


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv39, PA)                     // vsatp ON (PPN = PA of VS root)
  csrw hgatp, x0                            // hgatp Bare
  hfence.vvma                               // flush VS-stage TLB
  hfence.gvma                               // flush G-stage TLB (legal in M)

  // Preload each SPA with distinct payloads (M-mode, before guest accesses)
  LI(t0, 0x257A0301)                        // preload SPA
  la t1, test_region0                       // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0302)                        // preload SPA
  la t1, test_region1                       // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0303)                        // preload SPA
  la t1, test_region2                       // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0304)                        // preload SPA
  la t1, test_region3                       // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0305)                        // preload SPA
  la t1, test_region4                       // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0306)                        // preload SPA
  la t1, test_region5                       // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: RSW=00 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rsw00)                              // a5 = GVA of RSW=00 leaf
  LI(t0, 0x257A0301)                            // payload for case 1
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store through RSW=00 leaf
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // VS load; expect 0x257A0301
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test1_rsw00:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_rsw00, test1_rsw00_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: RSW=01 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rsw01)                              // a5 = GVA of RSW=01 leaf
  LI(t0, 0x257A0302)                            // payload for case 2
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store through RSW=01 leaf
  nop                                           // trap-skip pad
  lw   a4, 0(a5)                                // VS load; expect 0x257A0302
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test2_rsw01:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_rsw01, test2_rsw01_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2b: RSW=01 VS lw only (fresh hop) | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS TLB so lw rewalks (RSW read bin)
  LI(a5, va_rsw01)                              // a5 = GVA of RSW=01 leaf
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s2, 0(a5)                                // VS load through RSW=01 leaf; expect 0x257A0302
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test2b_rsw01_lw:                                 // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test2b_rsw01_lw, test2b_rsw01_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: RSW=10 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rsw10)                              // a5 = GVA of RSW=10 leaf
  LI(t0, 0x257A0303)                            // payload for case 3
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store through RSW=10 leaf
  nop                                           // trap-skip pad
  lw   a6, 0(a5)                                // VS load; expect 0x257A0303
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test3_rsw10:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test3_rsw10, test3_rsw10_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3b: RSW=10 VS lw only (fresh hop) | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS TLB so lw rewalks (RSW read bin)
  LI(a5, va_rsw10)                              // a5 = GVA of RSW=10 leaf
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s3, 0(a5)                                // VS load through RSW=10 leaf; expect 0x257A0303
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test3b_rsw10_lw:                                 // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test3b_rsw10_lw, test3b_rsw10_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: RSW=11 (PTE_SOFT) VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rsw11)                              // a5 = GVA of RSW=11 leaf
  LI(t0, 0x257A0304)                            // payload for case 4
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store through RSW=11 leaf
  nop                                           // trap-skip pad
  lw   a7, 0(a5)                                // VS load; expect 0x257A0304
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test4_rsw11:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test4_rsw11, test4_rsw11_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4b: RSW=11 VS lw only (fresh hop) | Expected: Successful
// Separate hop so .rvvi keeps VS_PTE_D for cp_vsatp_pte_rsw <auto[3],read_acc>.
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS TLB so lw rewalks (RSW read bin)
  LI(a5, va_rsw11)                              // a5 = GVA of RSW=11 leaf
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s4, 0(a5)                                // VS load through RSW=11 leaf; expect 0x257A0304
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test4b_rsw11_lw:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s4, test4b_rsw11_lw, test4b_rsw11_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5a–5h: Reserved PTE[60:54] walking-ones + all-ones VS lw | Expected: Expected Fault
// Macro lines use /* */ then `\`: `//` would eat the backslash and break continuation.
//---------------------------------------------------------------------------------------------------------------------------------
#define RSVD_LW_CASE(bitmask, reg, label, strlabel)                 /* one reserved-bit VS lw case */ \
  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | (bitmask)), va_rsvd, LEVEL0); /* VS leaf A=D=1 R/W + reserved bitmask */ \
  hfence.vvma;                                                      /* flush VS TLB so lw rewalks */ \
  LI(a5, va_rsvd);                                                  /* a5 = GVA of reserved leaf */ \
  LI(reg, 0);                                                       /* sentinel — stays 0 if load faults */ \
  RVTEST_GOTO_LOWER_MODE VSmode;                                    /* M→VS mret + PA↔VA relocate */ \
  lw   reg, 0(a5);                                                  /* VS load through reserved leaf */ \
  nop;                                                              /* trap-skip padding after load */ \
  RVTEST_GOTO_MMODE;                                           /* back to M */ \
  label:                                                            /* signature dump point for this bit */ \
  RVTEST_SIGUPD(x2, x5, x4, reg, label, strlabel)                   /* dump load result (0 if page-fault) */

  RSVD_LW_CASE(PTE_BIT54, a6, test5a_b54, test5a_b54_str)  // VS lw reserved bit54; expect fault (a6 stays 0)
  RSVD_LW_CASE(PTE_BIT55, a7, test5b_b55, test5b_b55_str)  // VS lw reserved bit55; expect fault (a7 stays 0)
  RSVD_LW_CASE(PTE_BIT56, s2, test5c_b56, test5c_b56_str)  // VS lw reserved bit56; expect fault (s2 stays 0)
  RSVD_LW_CASE(PTE_BIT57, s3, test5d_b57, test5d_b57_str)  // VS lw reserved bit57; expect fault (s3 stays 0)
  RSVD_LW_CASE(PTE_BIT58, s4, test5e_b58, test5e_b58_str)  // VS lw reserved bit58; expect fault (s4 stays 0)
  RSVD_LW_CASE(PTE_BIT59, s5, test5f_b59, test5f_b59_str)  // VS lw soft-RSW bit59; dump result (may succeed)
  RSVD_LW_CASE(PTE_BIT60, s6, test5g_b60, test5g_b60_str)  // VS lw soft-RSW bit60; dump result (may succeed)
  RSVD_LW_CASE(PTE_RSVD_ALL, s7, test5h_all, test5h_all_str)  // VS lw reserved [60:54] all-ones; expect fault

#undef RSVD_LW_CASE

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6a–6f: Reserved bits 54–58 + all-ones VS sw | Expected: Expected Fault
// Macro lines use /* */ then `\`: `//` would eat the backslash and break continuation.
//---------------------------------------------------------------------------------------------------------------------------------
#define RSVD_SW_CASE(bitmask, label, strlabel)                      /* one reserved-bit VS sw case */ \
  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | (bitmask)), va_rsvd, LEVEL0); /* VS leaf A=D=1 R/W + reserved bitmask */ \
  hfence.vvma;                                                      /* flush VS TLB so sw rewalks */ \
  LI(a5, va_rsvd);                                                  /* a5 = GVA of reserved leaf */ \
  LI(t0, 0xBAD00FAD);                                               /* payload that must not land if fault */ \
  RVTEST_GOTO_LOWER_MODE VSmode;                                    /* M→VS mret + PA↔VA relocate */ \
  sw   t0, 0(a5);                                                   /* VS store through reserved leaf */ \
  nop;                                                              /* trap-skip padding after store */ \
  RVTEST_GOTO_MMODE;                                           /* back to M */ \
  la t1, test_region4                                               ; /* t1 = SPA of data page */ \
  lw a3, 0(t1)                                                      ; /* M-mode SPA readback */ \
  label:                                                            /* signature dump point for this bit */ \
  RVTEST_SIGUPD(x2, x5, x4, a3, label, strlabel)                   /* dump SPA word */

  RSVD_SW_CASE(PTE_BIT54, test6a_sw54, test6a_sw54_str)  // VS sw reserved bit54; expect fault (SPA unchanged)
  RSVD_SW_CASE(PTE_BIT55, test6b_sw55, test6b_sw55_str)  // VS sw reserved bit55; expect fault (SPA unchanged)
  RSVD_SW_CASE(PTE_BIT56, test6c_sw56, test6c_sw56_str)  // VS sw reserved bit56; expect fault (SPA unchanged)
  RSVD_SW_CASE(PTE_BIT57, test6d_sw57, test6d_sw57_str)  // VS sw reserved bit57; expect fault (SPA unchanged)
  RSVD_SW_CASE(PTE_BIT58, test6e_sw58, test6e_sw58_str)  // VS sw reserved bit58; expect fault (SPA unchanged)
  RSVD_SW_CASE(PTE_RSVD_ALL, test6f_sw_all, test6f_sw_all_str)  // VS sw reserved all-ones; expect fault (SPA unchanged)
#undef RSVD_SW_CASE

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6g–6h: Soft-RSW bits 59/60 VS sw | Expected: Successful (Svrsw60t59b)
//---------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_BIT59), va_rsvd, LEVEL0)  // VS leaf soft-RSW bit59 R/W (Svrsw60t59b allow)
  hfence.vvma                                   // flush VS TLB after PTE rewrite
  LI(a5, va_rsvd)                               // a5 = GVA of reserved/soft-RSW leaf
  LI(t0, 0x257A0359)                            // payload for soft-RSW bit59 store
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store through bit59 leaf — expect success
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // VS load; expect 0x257A0359
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test6g_sw59:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test6g_sw59, test6g_sw59_str) // SIGUPD

  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_BIT60), va_rsvd, LEVEL0)  // VS leaf soft-RSW bit60 R/W
  hfence.vvma                                   // flush VS TLB after PTE rewrite
  LI(a5, va_rsvd)                               // a5 = GVA of soft-RSW leaf
  LI(t0, 0x257A0360)                            // payload for soft-RSW bit60 store
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store through bit60 leaf — expect success
  nop                                           // trap-skip pad
  lw   a4, 0(a5)                                // VS load; expect 0x257A0360
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test6h_sw60:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test6h_sw60, test6h_sw60_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: Reserved bit54 X-leaf VS jalr | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V | PTE_BIT54), va_rsvd, LEVEL0)  // VS X-leaf + reserved bit54 (must fetch-fault)
  hfence.vvma                                   // flush VS TLB after PTE rewrite
  LI(a5, va_rsvd)                               // a5 = GVA fetch target
  LI(a4, 0)                                     // sentinel — stays 0 if target never runs
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  nop                                           // pad so priv_mode_vs samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch reserved bit54 X-leaf → fetch page-fault
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test7_rsvd_jalr:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test7_rsvd_jalr, test7_rsvd_jalr_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7b–7c: Soft-RSW bits 59/60 X-leaf VS jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0x00008067)                        // preload SPA
  la t1, test_region4                       // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V | PTE_BIT59), va_rsvd, LEVEL0)  // VS X-leaf + soft-RSW bit59 (allow)
  hfence.vvma                                   // flush VS TLB after PTE rewrite
  LI(a5, va_rsvd)                               // a5 = GVA fetch target
  LI(s2, 0)                                     // sentinel — stays 0 if jalr faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  nop                                           // pad so priv_mode_vs samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch soft-RSW bit59 — expect success + ret
  LI(s2, 0x257A0759)                            // reached only if jalr returned; success marker
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test7b_jalr59:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test7b_jalr59, test7b_jalr59_str) // SIGUPD

  LI(t0, 0x00008067)                        // preload SPA
  la t1, test_region4                       // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V | PTE_BIT60), va_rsvd, LEVEL0)  // VS X-leaf + soft-RSW bit60 (allow)
  hfence.vvma                                   // flush VS TLB after PTE rewrite
  LI(a5, va_rsvd)                               // a5 = GVA fetch target
  LI(s3, 0)                                     // sentinel — stays 0 if jalr faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  nop                                           // pad so priv_mode_vs samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch soft-RSW bit60 — expect success + ret
  LI(s3, 0x257A0760)                            // reached only if jalr returned; success marker
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test7c_jalr60:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test7c_jalr60, test7c_jalr60_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8a–8c: PBMT=1/2/3 with PBMTE=0 (covergroup bins only no_support={0})
// Expect fault; scores cp_vsatp_svpbmt_* × no_support × auto[1/2/3].
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, MENVCFG_PBMTE)                         // t0 = menvcfg.PBMTE mask
  csrc menvcfg, t0                              // clear menvcfg.PBMTE — PBMT encodings unsupported
  LI(t0, HENVCFG_PBMTE)                         // t0 = henvcfg.PBMTE mask
  csrc henvcfg, t0                              // clear henvcfg.PBMTE (VS-stage PBMT also off)

  VS_PTE_SETUP(sv39, PA, test_region5, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_PBMT1), va_pbmt, LEVEL0)  // VS leaf PBMT=1 R/W with PBMTE=0
  hfence.vvma                                   // flush VS TLB after PTE rewrite
  LI(a5, va_pbmt)                               // a5 = GVA of PBMT leaf
  LI(a6, 0)                                     // sentinel — stays 0 if load faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a6, 0(a5)                                // VS load PBMT=1 PBMTE=0 → expect fault
  nop                                           // trap-skip pad
  sw   a6, 0(a5)                                // VS store same leaf → expect fault if load trapped
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test8a_pbmt1_nosup:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test8a_pbmt1_nosup, test8a_pbmt1_nosup_str) // SIGUPD

  VS_PTE_SETUP(sv39, PA, test_region5, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_PBMT2), va_pbmt, LEVEL0)  // VS leaf PBMT=2 R/W with PBMTE=0
  hfence.vvma                                   // flush VS TLB after PTE rewrite
  LI(a5, va_pbmt)                               // a5 = GVA of PBMT leaf
  LI(a7, 0)                                     // sentinel — stays 0 if load faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a7, 0(a5)                                // VS load PBMT=2 PBMTE=0 → expect fault
  nop                                           // trap-skip pad
  sw   a7, 0(a5)                                // VS store same leaf → expect fault
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test8b_pbmt2_nosup:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test8b_pbmt2_nosup, test8b_pbmt2_nosup_str) // SIGUPD

  VS_PTE_SETUP(sv39, PA, test_region5, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_PBMT3), va_pbmt, LEVEL0)  // VS leaf PBMT=3 R/W with PBMTE=0
  hfence.vvma                                   // flush VS TLB after PTE rewrite
  LI(a5, va_pbmt)                               // a5 = GVA of PBMT leaf
  LI(s2, 0)                                     // sentinel — stays 0 if load faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s2, 0(a5)                                // VS load PBMT=3 PBMTE=0 → expect fault
  nop                                           // trap-skip pad
  sw   s2, 0(a5)                                // VS store same leaf → expect fault
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test8c_pbmt3_nosup:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test8c_pbmt3_nosup, test8c_pbmt3_nosup_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8d/9: PBMT=1 X-leaf VS jalr (PBMTE=0) | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv39, PA, test_region5, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V | PTE_PBMT1), va_pbmt, LEVEL0)  // VS X-leaf PBMT=1 with PBMTE=0
  hfence.vvma                                   // flush VS TLB after PTE rewrite
  LI(a5, va_pbmt)                               // a5 = GVA fetch target
  LI(s3, 0)                                     // sentinel — stays 0 if jalr faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  nop                                           // pad so priv_mode_vs samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch PBMT=1 PBMTE=0 → expect fetch fault
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test8d_pbmt1_nosup_x:                             // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test8d_pbmt1_nosup_x, test8d_pbmt1_nosup_x_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region0:                                   // real PA backing va_rsw00 (RSW=00)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region1:                                   // real PA backing va_rsw01 (RSW=01)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region2:                                   // real PA backing va_rsw10 (RSW=10)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region3:                                   // real PA backing va_rsw11 (RSW=11 / PTE_SOFT)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region4:                                   // real PA backing va_rsvd (PTE_RSVD set)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region5:                                   // real PA backing va_pbmt (PTE_PBMT set)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // align to 4 KiB page
rvtest_vlvl1_pg_tbl:                            // VS-stage level-1 PTE storage (Sv39 VPN2)
  .zero(4096)                                   // 4 KiB page-table storage
.align 12                                       // align to 4 KiB page
rvtest_vlvl0_pg_tbl:                            // VS-stage level-0 PTE storage (Sv39 VPN1)
  .zero(4096)                                   // 4 KiB page-table storage


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_rsw00_str:    .string "\"Mismatch on RSW=00 VS sw+lw in Test Case 1!\""  // mismatch string
test2_rsw01_str:    .string "\"Mismatch on RSW=01 VS sw+lw in Test Case 2!\""  // mismatch string
test2b_rsw01_lw_str:.string "\"Mismatch on RSW=01 VS lw-only in Test Case 2b!\""  // mismatch string
test3_rsw10_str:    .string "\"Mismatch on RSW=10 VS sw+lw in Test Case 3!\""  // mismatch string
test3b_rsw10_lw_str:.string "\"Mismatch on RSW=10 VS lw-only in Test Case 3b!\""  // mismatch string
test4_rsw11_str:    .string "\"Mismatch on RSW=11 VS sw+lw in Test Case 4!\""  // mismatch string
test4b_rsw11_lw_str:.string "\"Mismatch on RSW=11 VS lw-only in Test Case 4b!\""  // mismatch string
test5a_b54_str:     .string "\"Mismatch on reserved bit54 VS lw (expect fault) in Test Case 5a!\""  // mismatch string
test5b_b55_str:     .string "\"Mismatch on reserved bit55 VS lw (expect fault) in Test Case 5b!\""  // mismatch string
test5c_b56_str:     .string "\"Mismatch on reserved bit56 VS lw (expect fault) in Test Case 5c!\""  // mismatch string
test5d_b57_str:     .string "\"Mismatch on reserved bit57 VS lw (expect fault) in Test Case 5d!\""  // mismatch string
test5e_b58_str:     .string "\"Mismatch on reserved bit58 VS lw (expect fault) in Test Case 5e!\""  // mismatch string
test5f_b59_str:     .string "\"Mismatch on reserved bit59 VS lw (expect fault) in Test Case 5f!\""  // mismatch string
test5g_b60_str:     .string "\"Mismatch on reserved bit60 VS lw (expect fault) in Test Case 5g!\""  // mismatch string
test5h_all_str:     .string "\"Mismatch on reserved all-ones VS lw (expect fault) in Test Case 5h!\""  // mismatch string
test6a_sw54_str:    .string "\"Mismatch on reserved bit54 VS sw (expect fault) in Test Case 6a!\""  // mismatch string
test6b_sw55_str:    .string "\"Mismatch on reserved bit55 VS sw (expect fault) in Test Case 6b!\""  // mismatch string
test6c_sw56_str:    .string "\"Mismatch on reserved bit56 VS sw (expect fault) in Test Case 6c!\""  // mismatch string
test6d_sw57_str:    .string "\"Mismatch on reserved bit57 VS sw (expect fault) in Test Case 6d!\""  // mismatch string
test6e_sw58_str:    .string "\"Mismatch on reserved bit58 VS sw (expect fault) in Test Case 6e!\""  // mismatch string
test6f_sw_all_str:  .string "\"Mismatch on reserved all-ones VS sw (expect fault) in Test Case 6f!\""  // mismatch string
test6g_sw59_str:    .string "\"Mismatch on soft-RSW bit59 VS sw in Test Case 6g!\""  // mismatch string
test6h_sw60_str:    .string "\"Mismatch on soft-RSW bit60 VS sw in Test Case 6h!\""  // mismatch string
test7_rsvd_jalr_str:.string "\"Mismatch on reserved bit54 VS jalr (expect fault) in Test Case 7!\""  // mismatch string
test7b_jalr59_str:  .string "\"Mismatch on soft-RSW bit59 VS jalr in Test Case 7b!\""  // mismatch string
test7c_jalr60_str:  .string "\"Mismatch on soft-RSW bit60 VS jalr in Test Case 7c!\""  // mismatch string
test8a_pbmt1_nosup_str: .string "\"Mismatch on PBMT=1 PBMTE=0 VS (expect fault) in Test Case 8a!\""  // mismatch string
test8b_pbmt2_nosup_str: .string "\"Mismatch on PBMT=2 PBMTE=0 VS (expect fault) in Test Case 8b!\""  // mismatch string
test8c_pbmt3_nosup_str: .string "\"Mismatch on PBMT=3 PBMTE=0 VS (expect fault) in Test Case 8c!\""  // mismatch string
test8d_pbmt1_nosup_x_str: .string "\"Mismatch on PBMT=1 PBMTE=0 VS jalr (expect fault) in Test Case 8d!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                VS Sv39 PTE RSW 00..11 succeed with lw+sw; reserv...
  //                      │
  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 1                      Test 2                      Test 3          
  //                │                           │                           │             
  //         RSW=00 leaf R/W              RSW=01 (0x100)              RSW=10 (0x200)      
  //                │                           │                           │             
  //             VS sw+lw                    VS sw+lw                    VS sw+lw         
  //                ▼                           ▼                           ▼             
  //            0x257A0301                  0x257A0302                  0x257A0303        

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 4                      Test 5                      Test 6          
  //                │                           │                           │             
  //        RSW=11 (PTE_SOFT)        Reserved walk PTE[60:54]     Reserved bits 54–58 +   
  //                │                           │                           │             
  //             VS sw+lw                   VS lw each                  VS sw each        
  //                ▼                           ▼                           ▼             
  //            0x257A0304              FAULT sentinel 0)            FAULT SPA same)      

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //             Test 6b                      Test 7                     Test 7b          
  //                │                           │                           │             
  //       Soft-RSW bits 59/60        Reserved bit54 X-leaf     Soft-RSW bits 59/60 X-leaf
  //                │                           │                           │             
  //              VS sw                      VS jalr                     VS jalr          
  //                ▼                           ▼                           ▼             
  //      distinct SPA patterns         FAULT fetch fault)            ret trampoline      

  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 8                             Test 9
  //         │                         │
  //      PBMT=1/2/3 with            PBMT=1 X-leaf
  //         │                         │
  //      VS lw (+sw on PBMT=1)      VS jalr
  //         ▼                         ▼
  //      dump Sail result           FAULT fault or allow
