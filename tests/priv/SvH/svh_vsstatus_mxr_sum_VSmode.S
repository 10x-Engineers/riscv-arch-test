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
// 17. MXR=0 SUM=1 S-page XWR=111: VS lw → Successful (0x257A050A)
// 18. MXR=1 SUM=0 S-page XWR=111: VS sw+lw → Successful (0x257A0512)
// 19. MXR=0 SUM=1 S-page X-only: VS sw → Expected Fault (SPA stays 0x257A0501)
// 20. MXR=0 SUM=1 U-page X-only: VS sw → Expected Fault (SPA stays 0xDEADBEEF)
// 21. MXR=0 SUM=0 S-page XWR=111: VS jalr → Successful then return (s8=0x257A0515)
// 22. MXR=0 SUM=1 S-page XWR=111: VS jalr → Successful (s9=0x257A0516)
// 23. MXR=1 SUM=1 U-page XWR=111: VS jalr → Successful (s10=0x257A0517)
// 24. MXR=1 SUM=1 S-page XWR=111: VS sw+lw → Successful (0x257A0518)
// 25. MXR=1 SUM=0 U-page X-only: VS sw → Expected Fault (SPA stays 0xDEADBEEF)
// 26. MXR=1 SUM=0 S-page X-only: VS sw → Expected Fault (SPA stays preload)
// 27. MXR=1 SUM=0 U-page XWR=111: VS sw → Expected Fault (SPA unchanged)
// 28. MXR=0 SUM=0 U-page X-only: VS sw → Expected Fault (SPA unchanged)
// 29. MXR=1 SUM=1 U-page XWR=111: VS lw only → Successful (0x257A051D)  // set,set,rwx111_u,read fresh walk
// 30. MXR=1 SUM=1 S-page X-only: VS lw → Successful (0x257A0501)       // set,set,rwx001_s,read
// 31. MXR=1 SUM=0 S-page XWR=111: VS lw only → Successful (0x257A051F) // unset,set,rwx111_s,read
// 32. MXR=1 SUM=0 S-page XWR=111: VS jalr → Successful (s11=0x257A0520) // unset,set,rwx111_s,exec
//
// Total Expected Faults :: 15
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vsstatus_mxr_sum_VSmode.S"
#define SIGUPD_COUNT 33
#define TRAP_SIGUPD_COUNT 256
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

  test1_mxr0_xs:                                // signature dump point for case 1
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

  test2_mxr1_xs_lw:                             // signature dump point for case 2
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

  test3_mxr1_xs_sw:                             // signature dump point for case 3
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

  test4_mxr0_xu:                                // signature dump point for case 4
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

  test5_mxr1_xu:                                // signature dump point for case 5
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

  test6_mxr1_sum1_xu:                           // signature dump point for case 6
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

  test7_sum1_urw_lw:                            // signature dump point for case 7
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

  test8_sum1_urw_swlw:                          // signature dump point for case 8
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

  test9_sum0_urw_sw:                            // signature dump point for case 9
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

  test10_srw_swlw:                              // signature dump point for case 10
  RVTEST_SIGUPD(x2, x5, x4, a7, test10_srw_swlw, test10_srw_swlw_str)  // signature: dump a7 (test10_srw_swlw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 11: MXR=0 SUM=1 S-page X-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(s3, 0)                                     // sentinel — s3 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s3, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test11_sum1_mxr0_xs:                          // signature dump point for case 11
  RVTEST_SIGUPD(x2, x5, x4, s3, test11_sum1_mxr0_xs, test11_sum1_mxr0_xs_str)  // signature: dump s3 (test11_sum1_mxr0_xs) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 12: MXR=1 SUM=1 S-page XWR=111 VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s2, 0)                                     // s2 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s2, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test12_mxr1_sum1_srw:                         // signature dump point for case 12
  RVTEST_SIGUPD(x2, x5, x4, s2, test12_mxr1_sum1_srw, test12_mxr1_sum1_srw_str)  // signature: dump s2 (test12_mxr1_sum1_srw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 13: MXR=0 SUM=1 U-page X-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(s4, 0)                                     // sentinel — s4 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s4, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test13_sum1_mxr0_xu:                          // signature dump point for case 13
  RVTEST_SIGUPD(x2, x5, x4, s4, test13_sum1_mxr0_xu, test13_sum1_mxr0_xu_str)  // signature: dump s4 (test13_sum1_mxr0_xu) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 14: MXR=1 SUM=1 U-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(s5, 0)                                     // sentinel — s5 stays 0 if store is skipped by trap
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   s5, 0(a5)                                // guest store through current PTE perms
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test14_mxr1_sum1_xu_sw:                       // signature dump point for case 14
  RVTEST_SIGUPD(x2, x5, x4, s5, test14_mxr1_sum1_xu_sw, test14_mxr1_sum1_xu_sw_str)  // signature: dump s5 (test14_mxr1_sum1_xu_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 15: MXR=1 SUM=0 U-page XWR=111 VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(s6, 0)                                     // sentinel — s6 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s6, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test15_mxr1_sum0_urw:                         // signature dump point for case 15
  RVTEST_SIGUPD(x2, x5, x4, s6, test15_mxr1_sum0_urw, test15_mxr1_sum0_urw_str)  // signature: dump s6 (test15_mxr1_sum0_urw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 16: MXR=1 SUM=1 S-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(s7, 0)                                     // sentinel — s7 stays 0 if store is skipped by trap
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   s7, 0(a5)                                // guest store through current PTE perms
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test16_mxr1_sum1_xs_sw:                       // signature dump point for case 16
  RVTEST_SIGUPD(x2, x5, x4, s7, test16_mxr1_sum1_xs_sw, test16_mxr1_sum1_xs_sw_str)  // signature: dump s7 (test16_mxr1_sum1_xs_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 17: MXR=0 SUM=1 S-page XWR=111 VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrc sstatus, t0                              // clear HS MXR
  csrc vsstatus, t0                             // clear VS MXR — guest sees these
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s2, 0)                                     // s2 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s2, 0(a5)                                // VS load from S-page RWX: MXR=0 SUM=1 → success
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test17_sum1_mxr0_srw:                         // signature dump point for case 17
  RVTEST_SIGUPD(x2, x5, x4, s2, test17_sum1_mxr0_srw, test17_sum1_mxr0_srw_str)  // dump s2 (case 17 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 18: MXR=1 SUM=0 S-page XWR=111 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — guest sees these
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrc sstatus, t0                              // clear HS SUM
  csrc vsstatus, t0                             // clear VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(t0, 0x257A0512)                            // SPA pattern / store value for case 18 (0x257A0512)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   t0, 0(a5)                                // VS store to S-page RWX: MXR=1 SUM=0 → success (W allowed)
  nop                                           // trap-skip padding after store
  lw   s3, 0(a5)                                // VS load from S-page RWX: MXR=1 SUM=0 → success
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test18_mxr1_sum0_srw_sw:                      // signature dump point for case 18
  RVTEST_SIGUPD(x2, x5, x4, s3, test18_mxr1_sum0_srw_sw, test18_mxr1_sum0_srw_sw_str)  // dump s3 (case 18 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 19: MXR=0 SUM=1 S-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrc sstatus, t0                              // clear HS MXR
  csrc vsstatus, t0                             // clear VS MXR — guest sees these
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   t0, 0(a5)                                // VS store to S-page X-only: MXR=0 SUM=1 → store-page-fault (no W)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  lw s4, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page X-only region)

  test19_sum1_xs_sw:                            // signature dump point for case 19
  RVTEST_SIGUPD(x2, x5, x4, s4, test19_sum1_xs_sw, test19_sum1_xs_sw_str)  // dump s4 SPA (case 19; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 20: MXR=0 SUM=1 U-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   t0, 0(a5)                                // VS store to U-page X-only: MXR=0 SUM=1 → store-page-fault (no W)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  lw s5, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page X-only region)

  test20_sum1_xu_sw:                            // signature dump point for case 20
  RVTEST_SIGUPD(x2, x5, x4, s5, test20_sum1_xu_sw, test20_sum1_xu_sw_str)  // dump s5 SPA (case 20; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 21: MXR=0 SUM=0 S-page XWR=111 VS jalr | Expected: Successful
// Preload a `ret` at SPA so jalr returns; signature records magic in s8.
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear HS MXR and SUM
  csrc vsstatus, t0                             // clear VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  // Write `ret` (0x00008067) + marker store path: use existing RWX page as trampoline
  LI(t0, 0x00008067)                            // ret
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  sw t0, 0(t1)                                  // write ret trampoline at SPA of S-page RWX region

  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s8, 0)                                     // s8 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  nop                                           // pad so priv_mode samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch of S-page RWX: MXR=0 SUM=0 → success (X allowed); ret trampoline returns
  LI(s8, 0x257A0515)                            // magic proving jalr returned (case 21)
  nop                                           // trap-skip padding
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test21_srw_jalr:                              // signature dump point for case 21
  RVTEST_SIGUPD(x2, x5, x4, s8, test21_srw_jalr, test21_srw_jalr_str)  // dump s8 (case 21 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 22: MXR=0 SUM=1 S-page XWR=111 VS jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(t0, 0x00008067)                            // encoding of ret (jalr x0, ra, 0) trampoline
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  sw t0, 0(t1)                                  // write ret trampoline at SPA of S-page RWX region

  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s9, 0)                                     // s9 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  nop                                           // pad so priv_mode samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch of S-page RWX: MXR=0 SUM=1 → success (X allowed); ret trampoline returns
  LI(s9, 0x257A0516)                            // magic proving jalr returned (case 22)
  nop                                           // trap-skip padding
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test22_sum1_srw_jalr:                         // signature dump point for case 22
  RVTEST_SIGUPD(x2, x5, x4, s9, test22_sum1_srw_jalr, test22_sum1_srw_jalr_str)  // dump s9 (case 22 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 23: MXR=1 SUM=1 U-page XWR=111 VS jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(t0, 0x00008067)                            // encoding of ret (jalr x0, ra, 0) trampoline
  la t1, test_region_u_rw                       // t1 = SPA of U-page RWX region
  sw t0, 0(t1)                                  // write ret trampoline at SPA of U-page RWX region

  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(s10, 0)                                    // s10 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  nop                                           // pad so priv_mode samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch of U-page RWX: MXR=1 SUM=1 → success (X allowed); ret trampoline returns
  LI(s10, 0x257A0517)                           // magic proving jalr returned (case 23)
  nop                                           // trap-skip padding
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test23_urw_jalr:                              // signature dump point for case 23
  RVTEST_SIGUPD(x2, x5, x4, s10, test23_urw_jalr, test23_urw_jalr_str)  // dump s10 (case 23 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 24: MXR=1 SUM=1 S-page XWR=111 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrs sstatus, t0                              // set HS MXR and SUM
  csrs vsstatus, t0                             // set VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(t0, 0x257A0518)                            // SPA pattern / store value for case 24 (0x257A0518)
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  sw t0, 0(t1)                                  // restore data after jalr trampoline

  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(t0, 0x257A0518)                            // SPA pattern / store value for case 24 (0x257A0518)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   t0, 0(a5)                                // VS store to S-page RWX: MXR=1 SUM=1 → success (W allowed)
  nop                                           // trap-skip padding after store
  lw   s2, 0(a5)                                // VS load from S-page RWX: MXR=1 SUM=1 → success
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test24_mxr1_sum1_srw_sw:                      // signature dump point for case 24
  RVTEST_SIGUPD(x2, x5, x4, s2, test24_mxr1_sum1_srw_sw, test24_mxr1_sum1_srw_sw_str)  // dump s2 (case 24 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 25: MXR=1 SUM=0 U-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrc sstatus, t0                              // clear HS SUM
  csrc vsstatus, t0                             // clear VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   t0, 0(a5)                                // VS store to U-page X-only: MXR=1 SUM=0 → store-page-fault (U=1 blocked without SUM)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  lw s3, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page X-only region)

  test25_mxr1_xu_sw:                            // signature dump point for case 25
  RVTEST_SIGUPD(x2, x5, x4, s3, test25_mxr1_xu_sw, test25_mxr1_xu_sw_str)  // dump s3 SPA (case 25; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 26: MXR=1 SUM=0 S-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   t0, 0(a5)                                // VS store to S-page X-only: MXR=1 SUM=0 → store-page-fault (no W)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  lw s4, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page X-only region)

  test26_mxr1_xs_sw:                            // signature dump point for case 26
  RVTEST_SIGUPD(x2, x5, x4, s4, test26_mxr1_xs_sw, test26_mxr1_xs_sw_str)  // dump s4 SPA (case 26; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 27: MXR=1 SUM=0 U-page XWR=111 VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   t0, 0(a5)                                // VS store to U-page RWX: MXR=1 SUM=0 → store-page-fault (U=1 blocked without SUM)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_u_rw                       // t1 = SPA of U-page RWX region
  lw s5, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page RWX region)

  test27_mxr1_sum0_urw_sw:                      // signature dump point for case 27
  RVTEST_SIGUPD(x2, x5, x4, s5, test27_mxr1_sum0_urw_sw, test27_mxr1_sum0_urw_sw_str)  // dump s5 SPA (case 27; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 28: MXR=0 SUM=0 U-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear HS MXR and SUM
  csrc vsstatus, t0                             // clear VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   t0, 0(a5)                                // VS store to U-page X-only: MXR=0 SUM=0 → store-page-fault (U=1 blocked without SUM)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  lw s2, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page X-only region)

  test28_mxr0_xu_sw:                            // signature dump point for case 28
  RVTEST_SIGUPD(x2, x5, x4, s2, test28_mxr0_xu_sw, test28_mxr0_xu_sw_str)  // dump s2 SPA (case 28; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 29: MXR=1 SUM=1 U-page XWR=111 VS lw | Expected: Successful (fresh walk)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrs sstatus, t0                              // set HS MXR and SUM
  csrs vsstatus, t0                             // set VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x257A051D)                            // SPA pattern / store value for case 29 (0x257A051D)
  la t1, test_region_u_rw                       // t1 = SPA of U-page RWX region
  sw t0, 0(t1)                                  // M-mode preload/write at SPA of U-page RWX region (case 29)
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(s3, 0)                                     // s3 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s3, 0(a5)                                // VS load from U-page RWX: MXR=1 SUM=1 → success
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test29_mxr1_sum1_urw_lw:                      // signature dump point for case 29
  RVTEST_SIGUPD(x2, x5, x4, s3, test29_mxr1_sum1_urw_lw, test29_mxr1_sum1_urw_lw_str)  // dump s3 (case 29 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 30: MXR=1 SUM=1 S-page X-only VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(s4, 0)                                     // s4 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s4, 0(a5)                                // VS load from S-page X-only: MXR=1 SUM=1 → success; MXR makes X readable
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test30_mxr1_sum1_xs_lw:                       // signature dump point for case 30
  RVTEST_SIGUPD(x2, x5, x4, s4, test30_mxr1_sum1_xs_lw, test30_mxr1_sum1_xs_lw_str)  // dump s4 (case 30 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 31: MXR=1 SUM=0 S-page XWR=111 VS lw only | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrc sstatus, t0                              // clear HS SUM
  csrc vsstatus, t0                             // clear VS SUM — guest sees these
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x257A051F)                            // SPA pattern / store value for case 31 (0x257A051F)
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  sw t0, 0(t1)                                  // M-mode preload/write at SPA of S-page RWX region (case 31)
  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s5, 0)                                     // s5 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s5, 0(a5)                                // VS load from S-page RWX: MXR=1 SUM=0 → success
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test31_mxr1_sum0_srw_lw:                      // signature dump point for case 31
  RVTEST_SIGUPD(x2, x5, x4, s5, test31_mxr1_sum0_srw_lw, test31_mxr1_sum0_srw_lw_str)  // dump s5 (case 31 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 32: MXR=1 SUM=0 S-page XWR=111 VS jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x00008067)                            // ret
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  sw t0, 0(t1)                                  // write ret trampoline at SPA of S-page RWX region
  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s6, 0)                                     // s6 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  nop                                           // pad so priv_mode samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch of S-page RWX: MXR=1 SUM=0 → success (X allowed); ret trampoline returns
  LI(s6, 0x257A0520)                            // magic proving jalr returned (case 32)
  nop                                           // trap-skip padding
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test32_mxr1_sum0_srw_jalr:                    // signature dump point for case 32
  RVTEST_SIGUPD(x2, x5, x4, s6, test32_mxr1_sum0_srw_jalr, test32_mxr1_sum0_srw_jalr_str)  // dump s6 (case 32 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 33: MXR=1 SUM=1 S-page X-only VS lw (re-set flags + fence) | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrs sstatus, t0                              // set HS MXR and SUM
  csrs vsstatus, t0                             // set VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x257A0501)                            // SPA pattern / store value for case 33 (0x257A0501)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  sw t0, 0(t1)                                  // M-mode preload/write at SPA of S-page X-only region (case 33)
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(s7, 0)                                     // s7 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   s7, 0(a5)                                // VS load from S-page X-only: MXR=1 SUM=1 → success; MXR makes X readable
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test33_mxr1_sum1_xs_lw2:                      // signature dump point for case 33
  RVTEST_SIGUPD(x2, x5, x4, s7, test33_mxr1_sum1_xs_lw2, test33_mxr1_sum1_xs_lw2_str)  // dump s7 (case 33 result) for PASS/FAIL

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
test17_sum1_mxr0_srw_str:    .string "\"Mismatch on SUM=1 MXR=0 S RWX VS lw in Test Case 17!\""
test18_mxr1_sum0_srw_sw_str: .string "\"Mismatch on MXR=1 SUM=0 S RWX VS sw+lw in Test Case 18!\""
test19_sum1_xs_sw_str:       .string "\"Mismatch on SUM=1 S X-only VS sw (expect fault) in Test Case 19!\""
test20_sum1_xu_sw_str:       .string "\"Mismatch on SUM=1 U X-only VS sw (expect fault) in Test Case 20!\""
test21_srw_jalr_str:         .string "\"Mismatch on S RWX VS jalr in Test Case 21!\""
test22_sum1_srw_jalr_str:    .string "\"Mismatch on SUM=1 S RWX VS jalr in Test Case 22!\""
test23_urw_jalr_str:         .string "\"Mismatch on SUM=1 U RWX VS jalr in Test Case 23!\""
test24_mxr1_sum1_srw_sw_str: .string "\"Mismatch on MXR=1 SUM=1 S RWX VS sw+lw in Test Case 24!\""
test25_mxr1_xu_sw_str:       .string "\"Mismatch on MXR=1 SUM=0 U X-only VS sw (expect fault) in Test Case 25!\""
test26_mxr1_xs_sw_str:       .string "\"Mismatch on MXR=1 SUM=0 S X-only VS sw (expect fault) in Test Case 26!\""
test27_mxr1_sum0_urw_sw_str: .string "\"Mismatch on MXR=1 SUM=0 U RWX VS sw (expect fault) in Test Case 27!\""
test28_mxr0_xu_sw_str:       .string "\"Mismatch on MXR=0 U X-only VS sw (expect fault) in Test Case 28!\""
test29_mxr1_sum1_urw_lw_str: .string "\"Mismatch on MXR=1 SUM=1 U RWX VS lw in Test Case 29!\""
test30_mxr1_sum1_xs_lw_str:  .string "\"Mismatch on MXR=1 SUM=1 S X-only VS lw in Test Case 30!\""
test31_mxr1_sum0_srw_lw_str: .string "\"Mismatch on MXR=1 SUM=0 S RWX VS lw in Test Case 31!\""
test32_mxr1_sum0_srw_jalr_str: .string "\"Mismatch on MXR=1 SUM=0 S RWX VS jalr in Test Case 32!\""
test33_mxr1_sum1_xs_lw2_str: .string "\"Mismatch on MXR=1 SUM=1 S X-only VS lw in Test Case 33!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
