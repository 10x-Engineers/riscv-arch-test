// --------------------------------------------------------------------------------------------------------------------------------
// svh_vsstatus_mxr_sum_VSmode.S
// Config: sail-rv32-max | VS=Sv32 ON, hgatp=Bare
// Coverpoints mapped (SvH_cg): cp_vsstatus_mxr_sum
// What this proves (one line):
//   VS MXR×SUM×page-type (X-only S/U, RWX S/U) control load/store permissions.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. MXR=0 SUM=0, S-page X-only: VS lw → Expected Fault (a3 stays 0)
//  2. MXR=1 SUM=0, S-page X-only: VS lw → Successful (0x257A0501)
//  3. MXR=1 SUM=0, S-page X-only: VS sw → Expected Fault (a4 stays 0)
//  4. MXR=0 SUM=0, U-page X-only: VS lw → Expected Fault (a6 stays 0)
//  5. MXR=1 SUM=0, U-page X-only: VS lw → Expected Fault (a7 stays 0)
//  6. MXR=1 SUM=1, U-page X-only: VS lw → Successful (0xDEADBEEF)
//  7. MXR=0 SUM=1, U-page XWR=111: VS lw → Successful (0x257A0502)
//  8. MXR=1 SUM=1, U-page XWR=111: VS sw+lw → Successful (0x257A0508)
//  9. MXR=0 SUM=0, U-page XWR=111: VS sw → Expected Fault (s2 stays 0)
// 10. MXR=0 SUM=0, S-page XWR=111: VS sw+lw → Successful (0x257A050A)
// 11. MXR=0 SUM=1 S-page X-only: VS lw → Expected Fault (s3 stays 0)
// 12. MXR=1 SUM=1 S-page XWR=111: VS lw → Successful (0x257A050A)
// 13. MXR=0 SUM=1 U-page X-only: VS lw → Expected Fault (s4 stays 0)
// 14. MXR=1 SUM=1 U-page X-only: VS sw → Expected Fault (s5 stays 0)
// 15. MXR=1 SUM=0 U-page XWR=111: VS lw → Expected Fault (s6 stays 0)
// 16. MXR=1 SUM=1 S-page X-only: VS sw → Expected Fault (s7 stays 0)
//
// Total Expected Faults :: 9
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vsstatus_mxr_sum_VSmode.S"
#define SIGUPD_COUNT 16
#define TRAP_SIGUPD_COUNT 128
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VSMODE / _SMODE (ecall a0=4/2)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE (mret + PA↔VA relocate)
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_x_s,  0x008001000                     // GVA: S-page (U=0) X-only leaf
  .set va_x_u,  0x008002000                     // GVA: U-page X-only leaf
  .set va_u_rw, 0x008003000                     // GVA: U-page R/W/X leaf (needs SUM=1)
  .set va_s_rw, 0x008004000                     // GVA: S-page R/W/X leaf
  .set va_code, 0x90000000                      // GVA where VS executes this code

  // ---- VS-stage (vsatp Sv32): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  SUPERPAGE_VS_PTE_SETUP(sv32, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // leaf: va_code -> PA(code); LEVEL1 = 4 MiB X/R

  csrr a0, mscratch                             // a0 = Msave_area (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: VS entry PC is under va_code

  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_x_s, LEVEL1)  // non-leaf: data VPN1 -> VS L0 table PA

  // S-page X-only (XWR=001, U=0) — MXR decides whether load is allowed
  VS_PTE_SETUP(sv32, PA, test_region_x_s, (PTE_D | PTE_A | PTE_X | PTE_V), va_x_s, LEVEL0)  // leaf: va_x_s -> PA(test_region_x_s) X-only U=0

  // U-page X-only — needs MXR for load, but U=1 still blocks without SUM
  VS_PTE_SETUP(sv32, PA, test_region_x_u, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V), va_x_u, LEVEL0)  // leaf: va_x_u -> PA(test_region_x_u) X-only U=1

  // U-page R/W/X — SUM=1 required for any U=1 access
  VS_PTE_SETUP(sv32, PA, test_region_u_rw, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), va_u_rw, LEVEL0)  // leaf: va_u_rw -> PA(test_region_u_rw) U=1 R/W/X

  // S-page R/W/X — readable/writable regardless of MXR/SUM
  VS_PTE_SETUP(sv32, PA, test_region_s_rw, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V), va_s_rw, LEVEL0)  // leaf: va_s_rw -> PA(test_region_s_rw) U=0 R/W/X

  VSATP_SETUP(sv32, PA)                         // vsatp = Sv32, PPN = PA of VS root
  csrw hgatp, x0                                // hgatp = Bare (no G-stage)
  hfence.vvma                                   // invalidate VS-stage TLB entries
  hfence.gvma                                   // invalidate G-stage TLB entries (harmless with Bare)

  LI(t0, 0x257A0501)                            // SPA pattern for S-page X-only (case 2 read target)
  la t1, test_region_x_s                        // SPA of S-page X-only region
  sw t0, 0(t1)                                  // preload (MXR=1 load expects 0x257A0501)
  LI(t0, 0xDEADBEEF)                            // SPA pattern for U-page X-only (case 6 read target)
  la t1, test_region_x_u                        // SPA of U-page X-only region
  sw t0, 0(t1)                                  // preload (cases 4–5 fault; case 6 MXR+SUM load)
  LI(t0, 0x257A0502)                            // SPA pattern for U-page R/W/X (case 7 read target)
  la t1, test_region_u_rw                       // SPA of U-page R/W/X region
  sw t0, 0(t1)                                  // preload (SUM=1 load expects 0x257A0502)
  LI(t0, 0x257A050A)                            // SPA pattern for S-page R/W/X (case 10)
  la t1, test_region_s_rw                       // SPA of S-page R/W/X region
  sw t0, 0(t1)                                  // preload (case 10 store overwrites then load checks)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: MXR=0 SUM=0 S-page X-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear HS MXR and SUM
  csrc vsstatus, t0                             // clear VS MXR and SUM — strict permission checks

  LI(a5, va_x_s)                                // a5 = GVA of S-page X-only leaf
  LI(a3, 0)                                     // a3 stays 0 if lw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  lw   a3, 0(a5)                                // X-only without MXR → load-page-fault; insn skipped
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test1_mxr0_xs:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_mxr0_xs, test1_mxr0_xs_str)  // record case 1 fault sentinel in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: MXR=1 SUM=0 S-page X-only VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — X-only pages become readable
  hfence.vvma                                   // flush TLB after MXR change (permission reinterpretation)

  LI(a5, va_x_s)                                // a5 = same S-page X-only GVA
  LI(a4, 0)                                     // a4 will hold load result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  lw   a4, 0(a5)                                // MXR=1 treats X-only as readable; expect 0x257A0501
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test2_mxr1_xs_lw:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_mxr1_xs_lw, test2_mxr1_xs_lw_str)  // record case 2 lw result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: MXR=1 SUM=0 S-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (MXR still 1; writes ignore MXR)
  LI(a3, 0)                                     // a3 stays 0 if sw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  sw   a3, 0(a5)                                // X-only has no W; MXR does not help stores → store-page-fault
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test3_mxr1_xs_sw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_mxr1_xs_sw, test3_mxr1_xs_sw_str)  // record case 3 fault sentinel in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: MXR=0 SUM=0 U-page X-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks
  csrc sstatus, t0                              // clear MXR and SUM again
  csrc vsstatus, t0                             // clear VS MXR and SUM — U-page blocked without SUM
  hfence.vvma                                   // flush TLB after flag change

  LI(a5, va_x_u)                                // a5 = GVA of U-page X-only leaf
  LI(a6, 0)                                     // a6 stays 0 if lw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  lw   a6, 0(a5)                                // U-page blocked by SUM=0 → fault
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test4_mxr0_xu:
  RVTEST_SIGUPD(x2, x5, x4, a6, test4_mxr0_xu, test4_mxr0_xu_str)  // record case 4 fault sentinel in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: MXR=1 SUM=0 U-page X-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — still blocked: SUM=0 denies U=1
  hfence.vvma                                   // flush TLB after MXR change

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA
  LI(a7, 0)                                     // a7 stays 0 if lw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  lw   a7, 0(a5)                                // MXR alone cannot bypass U-page without SUM → fault
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test5_mxr1_xu:
  RVTEST_SIGUPD(x2, x5, x4, a7, test5_mxr1_xu, test5_mxr1_xu_str)  // record case 5 fault sentinel in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: MXR=1 SUM=1 U-page X-only VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (MXR already set)
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — U X-only readable with MXR
  hfence.vvma                                   // flush TLB after SUM change

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA
  LI(a3, 0)                                     // a3 will hold load result
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  lw   a3, 0(a5)                                // MXR+SUM allow U X-only load; expect 0xDEADBEEF
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test6_mxr1_sum1_xu:
  RVTEST_SIGUPD(x2, x5, x4, a3, test6_mxr1_sum1_xu, test6_mxr1_sum1_xu_str)  // record case 6 lw result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: MXR=0 SUM=1 U-page XWR=111 VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask
  csrc sstatus, t0                              // clear HS MXR (SUM stays 1)
  csrc vsstatus, t0                             // clear VS MXR — R bit on U RWX is enough
  hfence.vvma                                   // flush TLB after MXR clear

  LI(a5, va_u_rw)                               // a5 = GVA of U=1 R/W/X leaf
  LI(a4, 0)                                     // a4 will hold load result
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  lw   a4, 0(a5)                                // SUM=1 allows U-page load via R; expect 0x257A0502
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test7_sum1_urw_lw:
  RVTEST_SIGUPD(x2, x5, x4, a4, test7_sum1_urw_lw, test7_sum1_urw_lw_str)  // record case 7 lw result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: MXR=1 SUM=1 U-page XWR=111 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (SUM still 1)
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR
  hfence.vvma                                   // flush TLB before write path

  LI(a5, va_u_rw)                               // a5 = GVA of U=1 R/W/X leaf
  LI(t0, 0x257A0508)                            // store value for case 8
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  sw   t0, 0(a5)                                // SUM=1 allows U-page store
  nop                                           // trap-skip padding after store
  lw   a6, 0(a5)                                // load back; expect 0x257A0508
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test8_sum1_urw_swlw:
  RVTEST_SIGUPD(x2, x5, x4, a6, test8_sum1_urw_swlw, test8_sum1_urw_swlw_str)  // record case 8 lw result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 9: MXR=0 SUM=0 U-page XWR=111 VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks
  csrc sstatus, t0                              // clear both — U-page blocked again
  csrc vsstatus, t0                             // clear VS MXR and SUM
  hfence.vvma                                   // flush TLB after flag clear

  LI(a5, va_u_rw)                               // a5 = GVA of U=1 R/W/X leaf
  LI(s2, 0)                                     // s2 stays 0 if sw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  sw   s2, 0(a5)                                // U-page with SUM=0 → store-page-fault
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test9_sum0_urw_sw:
  RVTEST_SIGUPD(x2, x5, x4, s2, test9_sum0_urw_sw, test9_sum0_urw_sw_str)  // record case 9 fault sentinel in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 10: MXR=0 SUM=0 S-page XWR=111 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_rw)                               // a5 = GVA of S-page R/W/X leaf
  LI(t0, 0x257A050A)                            // store value for case 10
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  sw   t0, 0(a5)                                // S-page R/W/X store permitted regardless of MXR/SUM
  nop                                           // trap-skip padding after store
  lw   a7, 0(a5)                                // load back; expect 0x257A050A
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test10_srw_swlw:
  RVTEST_SIGUPD(x2, x5, x4, a7, test10_srw_swlw, test10_srw_swlw_str)  // signature: dump a7 (test10_srw_swlw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 11: MXR=0 SUM=1 S-page X-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM
  LI(t0, SSTATUS_SUM)
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_s)
  LI(s3, 0)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s3, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test11_sum1_mxr0_xs:
  RVTEST_SIGUPD(x2, x5, x4, s3, test11_sum1_mxr0_xs, test11_sum1_mxr0_xs_str)  // signature: dump s3 (test11_sum1_mxr0_xs) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 12: MXR=1 SUM=1 S-page XWR=111 VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_s_rw)
  LI(s2, 0)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s2, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test12_mxr1_sum1_srw:
  RVTEST_SIGUPD(x2, x5, x4, s2, test12_mxr1_sum1_srw, test12_mxr1_sum1_srw_str)  // signature: dump s2 (test12_mxr1_sum1_srw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 13: MXR=0 SUM=1 U-page X-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_u)
  LI(s4, 0)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s4, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test13_sum1_mxr0_xu:
  RVTEST_SIGUPD(x2, x5, x4, s4, test13_sum1_mxr0_xu, test13_sum1_mxr0_xu_str)  // signature: dump s4 (test13_sum1_mxr0_xu) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 14: MXR=1 SUM=1 U-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_u)
  LI(s5, 0)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   s5, 0(a5)                                // guest store through current PTE perms
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test14_mxr1_sum1_xu_sw:
  RVTEST_SIGUPD(x2, x5, x4, s5, test14_mxr1_sum1_xu_sw, test14_mxr1_sum1_xu_sw_str)  // signature: dump s5 (test14_mxr1_sum1_xu_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 15: MXR=1 SUM=0 U-page XWR=111 VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_u_rw)
  LI(s6, 0)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s6, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test15_mxr1_sum0_urw:
  RVTEST_SIGUPD(x2, x5, x4, s6, test15_mxr1_sum0_urw, test15_mxr1_sum0_urw_str)  // signature: dump s6 (test15_mxr1_sum0_urw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 16: MXR=1 SUM=1 S-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_s)
  LI(s7, 0)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   s7, 0(a5)                                // guest store through current PTE perms
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test16_mxr1_sum1_xs_sw:
  RVTEST_SIGUPD(x2, x5, x4, s7, test16_mxr1_sum1_xs_sw, test16_mxr1_sum1_xs_sw_str)  // signature: dump s7 (test16_mxr1_sum1_xs_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

.align 12                                       // 4 KiB page align
test_region_x_s:                                // real PA backing va_x_s (S-page X-only)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_x_u:                                // real PA backing va_x_u (U-page X-only)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_u_rw:                               // real PA backing va_u_rw (U-page R/W/X)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_s_rw:                               // real PA backing va_s_rw (S-page R/W/X)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // align to 4 KiB page
rvtest_vlvl0_pg_tbl:                            // VS-stage level-0 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage

test1_mxr0_xs_str:       .string "\"Mismatch on MXR=0 S-page X-only VS lw (expect fault) in Test Case 1!\""
test2_mxr1_xs_lw_str:    .string "\"Mismatch on MXR=1 S-page X-only VS lw in Test Case 2!\""
test3_mxr1_xs_sw_str:    .string "\"Mismatch on MXR=1 S-page X-only VS sw (expect fault) in Test Case 3!\""
test4_mxr0_xu_str:       .string "\"Mismatch on MXR=0 U-page X-only VS lw (expect fault) in Test Case 4!\""
test5_mxr1_xu_str:       .string "\"Mismatch on MXR=1 SUM=0 U-page X-only VS lw (expect fault) in Test Case 5!\""
test6_mxr1_sum1_xu_str:  .string "\"Mismatch on MXR=1 SUM=1 U-page X-only VS lw in Test Case 6!\""
test7_sum1_urw_lw_str:   .string "\"Mismatch on SUM=1 U-page VS lw in Test Case 7!\""
test8_sum1_urw_swlw_str: .string "\"Mismatch on SUM=1 U-page VS sw+lw in Test Case 8!\""
test9_sum0_urw_sw_str:   .string "\"Mismatch on SUM=0 U-page VS sw (expect fault) in Test Case 9!\""
test10_srw_swlw_str:         .string "\"Mismatch on S-page R/W/X VS sw+lw in Test Case 10!\""
test11_sum1_mxr0_xs_str:     .string "\"Mismatch on SUM=1 MXR=0 S X-only VS lw (expect fault) in Test Case 11!\""
test12_mxr1_sum1_srw_str:    .string "\"Mismatch on MXR=1 SUM=1 S RWX VS lw in Test Case 12!\""
test13_sum1_mxr0_xu_str:     .string "\"Mismatch on SUM=1 MXR=0 U X-only VS lw (expect fault) in Test Case 13!\""
test14_mxr1_sum1_xu_sw_str:  .string "\"Mismatch on MXR=1 SUM=1 U X-only VS sw (expect fault) in Test Case 14!\""
test15_mxr1_sum0_urw_str:    .string "\"Mismatch on MXR=1 SUM=0 U RWX VS lw (expect fault) in Test Case 15!\""
test16_mxr1_sum1_xs_sw_str:  .string "\"Mismatch on MXR=1 SUM=1 S X-only VS sw (expect fault) in Test Case 16!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
