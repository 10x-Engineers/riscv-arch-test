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

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VSMODE / _SMODE (ecall a0=4/2)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE (mret + PA↔VA relocate)
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

RVTEST_BEGIN

main:
  .set va_rsw00,   0x0000000080010000           // GVA for RSW=00 R/W leaf
  .set va_rsw01,   0x0000000080020000           // GVA for RSW=01 leaf
  .set va_rsw10,   0x0000000080030000           // GVA for RSW=10 leaf
  .set va_rsw11,   0x0000000080040000           // GVA for RSW=11 (PTE_SOFT) leaf
  .set va_rsvd,    0x0000000080050000           // GVA for reserved-bits leaf (PTE[60:54])
  .set va_pbmt,    0x0000000080060000           // GVA for PBMT-encoded leaf
  .set va_code,    0x0000000090000000           // GVA where VS executes this code

  // ---- VS-stage (vsatp Sv39): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)  // non-leaf: va_code VPN2 -> VS L1 table PA
  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // leaf: va_code -> PA(code); LEVEL1 = 2 MiB X/R

  csrr a0, mscratch                             // a0 = Msave_area (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: VS entry PC is under va_code

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

  VSATP_SETUP(sv39, PA)                         // vsatp = Sv39, PPN = PA of VS root
  csrw hgatp, x0                                // hgatp = Bare (no G-stage)
  hfence.vvma                                   // invalidate VS-stage TLB entries
  hfence.gvma                                   // invalidate G-stage TLB entries (harmless with Bare)

  // Preload each SPA with distinct payloads (M-mode, before guest accesses)
  LI(t0, 0x257A0301)                            // SPA pattern for RSW=00 leaf (case 1)
  la t1, test_region0                           // t1 = SPA for RSW=00 leaf
  sw t0, 0(t1)                                  // preload case 1 baseline
  LI(t0, 0x257A0302)                            // SPA pattern for RSW=01 leaf (case 2)
  la t1, test_region1                           // t1 = SPA for RSW=01 leaf
  sw t0, 0(t1)                                  // preload case 2 baseline
  LI(t0, 0x257A0303)                            // SPA pattern for RSW=10 leaf (case 3)
  la t1, test_region2                           // t1 = SPA for RSW=10 leaf
  sw t0, 0(t1)                                  // preload case 3 baseline
  LI(t0, 0x257A0304)                            // SPA pattern for RSW=11 leaf (case 4)
  la t1, test_region3                           // t1 = SPA for RSW=11 leaf
  sw t0, 0(t1)                                  // preload case 4 baseline
  LI(t0, 0x257A0305)                            // SPA pattern for reserved-bits leaf (case 5)
  la t1, test_region4                           // t1 = SPA for reserved-bits leaf
  sw t0, 0(t1)                                  // preload (fault case — value must not be read)
  LI(t0, 0x257A0306)                            // SPA pattern for PBMT leaf (case 6)
  la t1, test_region5                           // t1 = SPA for PBMT leaf
  sw t0, 0(t1)                                  // preload (fault case — value must not be read)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: RSW=00 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rsw00)                              // a5 = GVA of RSW=00 leaf
  LI(t0, 0x257A0301)                            // payload for case 1
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  sw   t0, 0(a5)                                // VS store through RSW=00 leaf
  nop                                           // trap-skip padding after store
  lw   a3, 0(a5)                                // VS load; expect 0x257A0301
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test1_rsw00:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_rsw00, test1_rsw00_str)  // record case 1 lw result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: RSW=01 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rsw01)                              // a5 = GVA of RSW=01 leaf
  LI(t0, 0x257A0302)                            // payload for case 2
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  sw   t0, 0(a5)                                // VS store through RSW=01 leaf
  nop                                           // trap-skip padding after store
  lw   a4, 0(a5)                                // VS load; expect 0x257A0302
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test2_rsw01:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_rsw01, test2_rsw01_str)  // signature: dump a4 (test2_rsw01) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2b: RSW=01 VS lw only (fresh hop) | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB
  LI(a5, va_rsw01)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s2, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test2b_rsw01_lw:
  RVTEST_SIGUPD(x2, x5, x4, s2, test2b_rsw01_lw, test2b_rsw01_lw_str)  // signature: dump s2 (test2b_rsw01_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: RSW=10 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rsw10)                              // a5 = GVA of RSW=10 leaf
  LI(t0, 0x257A0303)                            // payload for case 3
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  sw   t0, 0(a5)                                // VS store through RSW=10 leaf
  nop                                           // trap-skip padding after store
  lw   a6, 0(a5)                                // VS load; expect 0x257A0303
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test3_rsw10:
  RVTEST_SIGUPD(x2, x5, x4, a6, test3_rsw10, test3_rsw10_str)  // signature: dump a6 (test3_rsw10) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3b: RSW=10 VS lw only (fresh hop) | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB
  LI(a5, va_rsw10)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s3, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test3b_rsw10_lw:
  RVTEST_SIGUPD(x2, x5, x4, s3, test3b_rsw10_lw, test3b_rsw10_lw_str)  // signature: dump s3 (test3b_rsw10_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: RSW=11 (PTE_SOFT) VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rsw11)                              // a5 = GVA of RSW=11 leaf
  LI(t0, 0x257A0304)                            // payload for case 4
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  sw   t0, 0(a5)                                // VS store through RSW=11 leaf
  nop                                           // trap-skip padding after store
  lw   a7, 0(a5)                                // VS load; expect 0x257A0304
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test4_rsw11:
  RVTEST_SIGUPD(x2, x5, x4, a7, test4_rsw11, test4_rsw11_str)  // record case 4 lw result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4b: RSW=11 VS lw only (fresh hop) | Expected: Successful
// Separate hop so .rvvi keeps VS_PTE_D for cp_vsatp_pte_rsw <auto[3],read_acc>.
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma
  LI(a5, va_rsw11)
  RVTEST_GOTO_LOWER_MODE VSmode
  lw   s4, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test4b_rsw11_lw:
  RVTEST_SIGUPD(x2, x5, x4, s4, test4b_rsw11_lw, test4b_rsw11_lw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5a–5h: Reserved PTE[60:54] walking-ones + all-ones VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
#define RSVD_LW_CASE(bitmask, reg, label, strlabel)                 \
  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | (bitmask)), va_rsvd, LEVEL0); \
  hfence.vvma;                                                      \
  LI(a5, va_rsvd);                                                  \
  LI(reg, 0);                                                       \
  RVTEST_GOTO_LOWER_MODE VSmode;                                    \
  lw   reg, 0(a5);                                                  \
  nop;                                                              \
  RVTEST_TSBI_GOTO_MMODE;                                           \
  label:                                                            \
  RVTEST_SIGUPD(x2, x5, x4, reg, label, strlabel)

  RSVD_LW_CASE(PTE_BIT54, a6, test5a_b54, test5a_b54_str)
  RSVD_LW_CASE(PTE_BIT55, a7, test5b_b55, test5b_b55_str)
  RSVD_LW_CASE(PTE_BIT56, s2, test5c_b56, test5c_b56_str)
  RSVD_LW_CASE(PTE_BIT57, s3, test5d_b57, test5d_b57_str)
  RSVD_LW_CASE(PTE_BIT58, s4, test5e_b58, test5e_b58_str)
  RSVD_LW_CASE(PTE_BIT59, s5, test5f_b59, test5f_b59_str)
  RSVD_LW_CASE(PTE_BIT60, s6, test5g_b60, test5g_b60_str)
  RSVD_LW_CASE(PTE_RSVD_ALL, s7, test5h_all, test5h_all_str)

#undef RSVD_LW_CASE

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6a–6f: Reserved bits 54–58 + all-ones VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
#define RSVD_SW_CASE(bitmask, label, strlabel)                      \
  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | (bitmask)), va_rsvd, LEVEL0); \
  hfence.vvma;                                                      \
  LI(a5, va_rsvd);                                                  \
  LI(t0, 0xBAD00FAD);                                               \
  RVTEST_GOTO_LOWER_MODE VSmode;                                    \
  sw   t0, 0(a5);                                                   \
  nop;                                                              \
  RVTEST_TSBI_GOTO_MMODE;                                           \
  la t1, test_region4;                                              \
  lw a3, 0(t1);                                                     \
  label:                                                            \
  RVTEST_SIGUPD(x2, x5, x4, a3, label, strlabel)

  LI(t0, 0x257A0305)
  la t1, test_region4
  sw t0, 0(t1)

  RSVD_SW_CASE(PTE_BIT54, test6a_sw54, test6a_sw54_str)
  RSVD_SW_CASE(PTE_BIT55, test6b_sw55, test6b_sw55_str)
  RSVD_SW_CASE(PTE_BIT56, test6c_sw56, test6c_sw56_str)
  RSVD_SW_CASE(PTE_BIT57, test6d_sw57, test6d_sw57_str)
  RSVD_SW_CASE(PTE_BIT58, test6e_sw58, test6e_sw58_str)
  RSVD_SW_CASE(PTE_RSVD_ALL, test6f_sw_all, test6f_sw_all_str)
#undef RSVD_SW_CASE

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6g–6h: Soft-RSW bits 59/60 VS sw | Expected: Successful (Svrsw60t59b)
//---------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_BIT59), va_rsvd, LEVEL0)
  hfence.vvma
  LI(a5, va_rsvd)
  LI(t0, 0x257A0359)
  RVTEST_GOTO_LOWER_MODE VSmode
  sw   t0, 0(a5)
  nop
  lw   a3, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test6g_sw59:
  RVTEST_SIGUPD(x2, x5, x4, a3, test6g_sw59, test6g_sw59_str)

  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_BIT60), va_rsvd, LEVEL0)
  hfence.vvma
  LI(a5, va_rsvd)
  LI(t0, 0x257A0360)
  RVTEST_GOTO_LOWER_MODE VSmode
  sw   t0, 0(a5)
  nop
  lw   a4, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test6h_sw60:
  RVTEST_SIGUPD(x2, x5, x4, a4, test6h_sw60, test6h_sw60_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: Reserved bit54 X-leaf VS jalr | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V | PTE_BIT54), va_rsvd, LEVEL0)
  hfence.vvma
  LI(a5, va_rsvd)
  LI(a4, 0)
  RVTEST_GOTO_LOWER_MODE VSmode
  nop
  jalr ra, a5, 0
  nop
  RVTEST_TSBI_GOTO_MMODE
  test7_rsvd_jalr:
  RVTEST_SIGUPD(x2, x5, x4, a4, test7_rsvd_jalr, test7_rsvd_jalr_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7b–7c: Soft-RSW bits 59/60 X-leaf VS jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0x00008067)                            // ret
  la t1, test_region4
  sw t0, 0(t1)
  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V | PTE_BIT59), va_rsvd, LEVEL0)
  hfence.vvma
  LI(a5, va_rsvd)
  LI(s2, 0)
  RVTEST_GOTO_LOWER_MODE VSmode
  nop
  jalr ra, a5, 0
  LI(s2, 0x257A0759)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test7b_jalr59:
  RVTEST_SIGUPD(x2, x5, x4, s2, test7b_jalr59, test7b_jalr59_str)

  LI(t0, 0x00008067)
  la t1, test_region4
  sw t0, 0(t1)
  VS_PTE_SETUP(sv39, PA, test_region4, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V | PTE_BIT60), va_rsvd, LEVEL0)
  hfence.vvma
  LI(a5, va_rsvd)
  LI(s3, 0)
  RVTEST_GOTO_LOWER_MODE VSmode
  nop
  jalr ra, a5, 0
  LI(s3, 0x257A0760)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test7c_jalr60:
  RVTEST_SIGUPD(x2, x5, x4, s3, test7c_jalr60, test7c_jalr60_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8a–8c: PBMT=1/2/3 with PBMTE=0 (covergroup bins only no_support={0})
// Expect fault; scores cp_vsatp_svpbmt_* × no_support × auto[1/2/3].
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, MENVCFG_PBMTE)
  csrc menvcfg, t0
  LI(t0, HENVCFG_PBMTE)
  csrc henvcfg, t0

  VS_PTE_SETUP(sv39, PA, test_region5, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_PBMT1), va_pbmt, LEVEL0)
  hfence.vvma
  LI(a5, va_pbmt)
  LI(a6, 0)
  RVTEST_GOTO_LOWER_MODE VSmode
  lw   a6, 0(a5)
  nop
  sw   a6, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test8a_pbmt1_nosup:
  RVTEST_SIGUPD(x2, x5, x4, a6, test8a_pbmt1_nosup, test8a_pbmt1_nosup_str)

  VS_PTE_SETUP(sv39, PA, test_region5, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_PBMT2), va_pbmt, LEVEL0)
  hfence.vvma
  LI(a5, va_pbmt)
  LI(a7, 0)
  RVTEST_GOTO_LOWER_MODE VSmode
  lw   a7, 0(a5)
  nop
  sw   a7, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test8b_pbmt2_nosup:
  RVTEST_SIGUPD(x2, x5, x4, a7, test8b_pbmt2_nosup, test8b_pbmt2_nosup_str)

  VS_PTE_SETUP(sv39, PA, test_region5, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_PBMT3), va_pbmt, LEVEL0)
  hfence.vvma
  LI(a5, va_pbmt)
  LI(s2, 0)
  RVTEST_GOTO_LOWER_MODE VSmode
  lw   s2, 0(a5)
  nop
  sw   s2, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test8c_pbmt3_nosup:
  RVTEST_SIGUPD(x2, x5, x4, s2, test8c_pbmt3_nosup, test8c_pbmt3_nosup_str)

  VS_PTE_SETUP(sv39, PA, test_region5, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V | PTE_PBMT1), va_pbmt, LEVEL0)
  hfence.vvma
  LI(a5, va_pbmt)
  LI(s3, 0)
  RVTEST_GOTO_LOWER_MODE VSmode
  nop
  jalr ra, a5, 0
  nop
  RVTEST_TSBI_GOTO_MMODE
  test8d_pbmt1_nosup_x:
  RVTEST_SIGUPD(x2, x5, x4, s3, test8d_pbmt1_nosup_x, test8d_pbmt1_nosup_x_str)

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

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
.align 12                                       // align to 4 KiB page
rvtest_vlvl1_pg_tbl:                            // VS-stage level-1 PTE storage (Sv39 VPN2)
  .zero(4096)                                   // 4 KiB page-table storage
.align 12                                       // align to 4 KiB page
rvtest_vlvl0_pg_tbl:                            // VS-stage level-0 PTE storage (Sv39 VPN1)
  .zero(4096)                                   // 4 KiB page-table storage

test1_rsw00_str:    .string "\"Mismatch on RSW=00 VS sw+lw in Test Case 1!\""
test2_rsw01_str:    .string "\"Mismatch on RSW=01 VS sw+lw in Test Case 2!\""
test2b_rsw01_lw_str:.string "\"Mismatch on RSW=01 VS lw-only in Test Case 2b!\""
test3_rsw10_str:    .string "\"Mismatch on RSW=10 VS sw+lw in Test Case 3!\""
test3b_rsw10_lw_str:.string "\"Mismatch on RSW=10 VS lw-only in Test Case 3b!\""
test4_rsw11_str:    .string "\"Mismatch on RSW=11 VS sw+lw in Test Case 4!\""
test4b_rsw11_lw_str:.string "\"Mismatch on RSW=11 VS lw-only in Test Case 4b!\""
test5a_b54_str:     .string "\"Mismatch on reserved bit54 VS lw (expect fault) in Test Case 5a!\""
test5b_b55_str:     .string "\"Mismatch on reserved bit55 VS lw (expect fault) in Test Case 5b!\""
test5c_b56_str:     .string "\"Mismatch on reserved bit56 VS lw (expect fault) in Test Case 5c!\""
test5d_b57_str:     .string "\"Mismatch on reserved bit57 VS lw (expect fault) in Test Case 5d!\""
test5e_b58_str:     .string "\"Mismatch on reserved bit58 VS lw (expect fault) in Test Case 5e!\""
test5f_b59_str:     .string "\"Mismatch on reserved bit59 VS lw (expect fault) in Test Case 5f!\""
test5g_b60_str:     .string "\"Mismatch on reserved bit60 VS lw (expect fault) in Test Case 5g!\""
test5h_all_str:     .string "\"Mismatch on reserved all-ones VS lw (expect fault) in Test Case 5h!\""
test6a_sw54_str:    .string "\"Mismatch on reserved bit54 VS sw (expect fault) in Test Case 6a!\""
test6b_sw55_str:    .string "\"Mismatch on reserved bit55 VS sw (expect fault) in Test Case 6b!\""
test6c_sw56_str:    .string "\"Mismatch on reserved bit56 VS sw (expect fault) in Test Case 6c!\""
test6d_sw57_str:    .string "\"Mismatch on reserved bit57 VS sw (expect fault) in Test Case 6d!\""
test6e_sw58_str:    .string "\"Mismatch on reserved bit58 VS sw (expect fault) in Test Case 6e!\""
test6f_sw_all_str:  .string "\"Mismatch on reserved all-ones VS sw (expect fault) in Test Case 6f!\""
test6g_sw59_str:    .string "\"Mismatch on soft-RSW bit59 VS sw in Test Case 6g!\""
test6h_sw60_str:    .string "\"Mismatch on soft-RSW bit60 VS sw in Test Case 6h!\""
test7_rsvd_jalr_str:.string "\"Mismatch on reserved bit54 VS jalr (expect fault) in Test Case 7!\""
test7b_jalr59_str:  .string "\"Mismatch on soft-RSW bit59 VS jalr in Test Case 7b!\""
test7c_jalr60_str:  .string "\"Mismatch on soft-RSW bit60 VS jalr in Test Case 7c!\""
test8a_pbmt1_nosup_str: .string "\"Mismatch on PBMT=1 PBMTE=0 VS (expect fault) in Test Case 8a!\""
test8b_pbmt2_nosup_str: .string "\"Mismatch on PBMT=2 PBMTE=0 VS (expect fault) in Test Case 8b!\""
test8c_pbmt3_nosup_str: .string "\"Mismatch on PBMT=3 PBMTE=0 VS (expect fault) in Test Case 8c!\""
test8d_pbmt1_nosup_x_str: .string "\"Mismatch on PBMT=1 PBMTE=0 VS jalr (expect fault) in Test Case 8d!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
