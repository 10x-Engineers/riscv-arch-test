// --------------------------------------------------------------------------------------------------------------------------------
// svh_vsstatus_mxr_sum_sv39_VSmode.S
// Config: sail-rv64-max | VS=Sv39 ON, hgatp=Bare
// Pair:   svh_vsstatus_mxr_sum_VSmode.S
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
// 10b. MXR=0 SUM=0, S-page XWR=111: VS lw only → Successful (0x257A050A) // unset,unset,rwx111_s,read fresh walk
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
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vsstatus_mxr_sum_sv39_VSmode.S"
#define SIGUPD_COUNT 34
#define TRAP_SIGUPD_COUNT 256
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
  .set va_x_s,  0x008001000                     // GVA: S-page (U=0) X-only leaf
  .set va_x_u,  0x008002000                     // GVA: U-page X-only leaf
  .set va_u_rw, 0x008003000                     // GVA: U-page R/W/X leaf (needs SUM=1)
  .set va_s_rw, 0x008004000                     // GVA: S-page R/W/X leaf
  .set va_code,                 0x0000000090000000      // GVA where guest executes this code

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- VS-stage (vsatp Sv39): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)  // VS non-leaf: va_code VPN2 → L1 table PA(rvtest_vlvl1_pg_tbl) V=1
  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // leaf: va_code -> PA(code); LEVEL1 megapage X/R

  csrr a0, mscratch                             // a0 = Msave_area (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: entry PC under va_code

  // Shared L2+L1 non-leafs (same VPN2/VPN1 for all data VAs under 0x00800x000)
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_x_s, LEVEL2)  // VS non-leaf: va_x_s VPN2 → L1 table PA(rvtest_vlvl1_pg_tbl) V=1
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_x_s, LEVEL1)  // non-leaf: data VPN1 -> VS L0 table PA

  // S-page X-only (XWR=001, U=0) — MXR decides whether load is allowed
  VS_PTE_SETUP(sv39, PA, test_region_x_s, (PTE_D | PTE_A | PTE_X | PTE_V), va_x_s, LEVEL0)  // leaf: va_x_s -> PA(test_region_x_s) X-only U=0

  // U-page X-only — needs MXR for load, but U=1 still blocks without SUM
  VS_PTE_SETUP(sv39, PA, test_region_x_u, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V), va_x_u, LEVEL0)  // leaf: va_x_u -> PA(test_region_x_u) X-only U=1

  // U-page R/W/X — SUM=1 required for any U=1 access
  VS_PTE_SETUP(sv39, PA, test_region_u_rw, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), va_u_rw, LEVEL0)  // leaf: va_u_rw -> PA(test_region_u_rw) U=1 R/W/X

  // S-page R/W/X — readable/writable regardless of MXR/SUM
  VS_PTE_SETUP(sv39, PA, test_region_s_rw, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V), va_s_rw, LEVEL0)  // leaf: va_s_rw -> PA(test_region_s_rw) U=0 R/W/X


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv39, PA)                         // vsatp = Sv39, PPN = PA of VS root
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


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: MXR=0 SUM=0 S-page X-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear HS MXR and SUM
  csrc vsstatus, t0                             // clear VS MXR and SUM — strict permission checks

  LI(a5, va_x_s)                                // a5 = GVA of S-page X-only leaf
  LI(a3, 0)                                     // a3 stays 0 if lw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a3, 0(a5)                                // X-only without MXR → load-page-fault; insn skipped
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test1_mxr0_xs:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_mxr0_xs, test1_mxr0_xs_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: MXR=1 SUM=0 S-page X-only VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — X-only pages become readable
  hfence.vvma                                   // flush TLB after MXR change (permission reinterpretation)

  LI(a5, va_x_s)                                // a5 = same S-page X-only GVA
  LI(a4, 0)                                     // a4 will hold load result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a4, 0(a5)                                // MXR=1 treats X-only as readable; expect 0x257A0501
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test2_mxr1_xs_lw:                                // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_mxr1_xs_lw, test2_mxr1_xs_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: MXR=1 SUM=0 S-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (MXR still 1; writes ignore MXR)
  LI(a3, 0)                                     // a3 stays 0 if sw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   a3, 0(a5)                                // X-only has no W; MXR does not help stores → store-page-fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test3_mxr1_xs_sw:                                // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_mxr1_xs_sw, test3_mxr1_xs_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: MXR=0 SUM=0 U-page X-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks
  csrc sstatus, t0                              // clear MXR and SUM again
  csrc vsstatus, t0                             // clear VS MXR and SUM — U-page blocked without SUM
  hfence.vvma                                   // flush TLB after flag change

  LI(a5, va_x_u)                                // a5 = GVA of U-page X-only leaf
  LI(a6, 0)                                     // a6 stays 0 if lw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a6, 0(a5)                                // U-page blocked by SUM=0 → fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test4_mxr0_xu:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test4_mxr0_xu, test4_mxr0_xu_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: MXR=1 SUM=0 U-page X-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — still blocked: SUM=0 denies U=1
  hfence.vvma                                   // flush TLB after MXR change

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA
  LI(a7, 0)                                     // a7 stays 0 if lw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a7, 0(a5)                                // MXR alone cannot bypass U-page without SUM → fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test5_mxr1_xu:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test5_mxr1_xu, test5_mxr1_xu_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: MXR=1 SUM=1 U-page X-only VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (MXR already set)
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — U X-only readable with MXR
  hfence.vvma                                   // flush TLB after SUM change

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA
  LI(a3, 0)                                     // a3 will hold load result
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a3, 0(a5)                                // MXR+SUM allow U X-only load; expect 0xDEADBEEF
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test6_mxr1_sum1_xu:                              // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test6_mxr1_sum1_xu, test6_mxr1_sum1_xu_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: MXR=0 SUM=1 U-page XWR=111 VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask
  csrc sstatus, t0                              // clear HS MXR (SUM stays 1)
  csrc vsstatus, t0                             // clear VS MXR — R bit on U RWX is enough
  hfence.vvma                                   // flush TLB after MXR clear

  LI(a5, va_u_rw)                               // a5 = GVA of U=1 R/W/X leaf
  LI(a4, 0)                                     // a4 will hold load result
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a4, 0(a5)                                // SUM=1 allows U-page load via R; expect 0x257A0502
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test7_sum1_urw_lw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test7_sum1_urw_lw, test7_sum1_urw_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: MXR=1 SUM=1 U-page XWR=111 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (SUM still 1)
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR
  hfence.vvma                                   // flush TLB before write path

  LI(a5, va_u_rw)                               // a5 = GVA of U=1 R/W/X leaf
  LI(t0, 0x257A0508)                            // store value for case 8
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // SUM=1 allows U-page store
  nop                                           // trap-skip pad
  lw   a6, 0(a5)                                // load back; expect 0x257A0508
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test8_sum1_urw_swlw:                             // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test8_sum1_urw_swlw, test8_sum1_urw_swlw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 9: MXR=0 SUM=0 U-page XWR=111 VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks
  csrc sstatus, t0                              // clear both — U-page blocked again
  csrc vsstatus, t0                             // clear VS MXR and SUM
  hfence.vvma                                   // flush TLB after flag clear

  LI(a5, va_u_rw)                               // a5 = GVA of U=1 R/W/X leaf
  LI(s2, 0)                                     // s2 stays 0 if sw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   s2, 0(a5)                                // U-page with SUM=0 → store-page-fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test9_sum0_urw_sw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test9_sum0_urw_sw, test9_sum0_urw_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 10: MXR=0 SUM=0 S-page XWR=111 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_rw)                               // a5 = GVA of S-page R/W/X leaf
  LI(t0, 0x257A050A)                            // store value for case 10
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // S-page R/W/X store permitted regardless of MXR/SUM
  nop                                           // trap-skip pad
  lw   a7, 0(a5)                                // load back; expect 0x257A050A
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test10_srw_swlw:                                 // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test10_srw_swlw, test10_srw_swlw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 10b: MXR=0 SUM=0 S-page XWR=111 VS lw only | Expected: Successful
// Fresh walk so leaf PTE lands in .rvvi for unset,unset,rwx111_s,read_acc (sw+lw TLB-hit drops it).
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x257A050A)                            // SPA pattern / store value for case 10b (0x257A050A)
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  sw t0, 0(t1)                                  // M-mode preload/write at SPA of S-page RWX region (case 10b)
  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s11, 0)                                    // s11 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s11, 0(a5)                               // VS load from S-page RWX: MXR=0 SUM=0 → success
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test10b_srw_lw:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s11, test10b_srw_lw, test10b_srw_lw_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s3, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test11_sum1_mxr0_xs:                             // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test11_sum1_mxr0_xs, test11_sum1_mxr0_xs_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 12: MXR=1 SUM=1 S-page XWR=111 VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s2, 0)                                     // s2 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s2, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test12_mxr1_sum1_srw:                            // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test12_mxr1_sum1_srw, test12_mxr1_sum1_srw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 13: MXR=0 SUM=1 U-page X-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(s4, 0)                                     // sentinel — s4 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s4, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test13_sum1_mxr0_xu:                             // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s4, test13_sum1_mxr0_xu, test13_sum1_mxr0_xu_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 14: MXR=1 SUM=1 U-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(s5, 0)                                     // sentinel — s5 stays 0 if store is skipped by trap
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   s5, 0(a5)                                // guest store through current PTE perms
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test14_mxr1_sum1_xu_sw:                          // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s5, test14_mxr1_sum1_xu_sw, test14_mxr1_sum1_xu_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 15: MXR=1 SUM=0 U-page XWR=111 VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(s6, 0)                                     // sentinel — s6 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s6, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test15_mxr1_sum0_urw:                            // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s6, test15_mxr1_sum0_urw, test15_mxr1_sum0_urw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 16: MXR=1 SUM=1 S-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(s7, 0)                                     // sentinel — s7 stays 0 if store is skipped by trap
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   s7, 0(a5)                                // guest store through current PTE perms
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test16_mxr1_sum1_xs_sw:                          // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s7, test16_mxr1_sum1_xs_sw, test16_mxr1_sum1_xs_sw_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s2, 0(a5)                                // VS load from S-page RWX: MXR=0 SUM=1 → success
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test17_sum1_mxr0_srw:                            // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test17_sum1_mxr0_srw, test17_sum1_mxr0_srw_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store to S-page RWX: MXR=1 SUM=0 → success (W allowed)
  nop                                           // trap-skip pad
  lw   s3, 0(a5)                                // VS load from S-page RWX: MXR=1 SUM=0 → success
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test18_mxr1_sum0_srw_sw:                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test18_mxr1_sum0_srw_sw, test18_mxr1_sum0_srw_sw_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store to S-page X-only: MXR=0 SUM=1 → store-page-fault (no W)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  lw s4, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page X-only region)

  test19_sum1_xs_sw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s4, test19_sum1_xs_sw, test19_sum1_xs_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 20: MXR=0 SUM=1 U-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store to U-page X-only: MXR=0 SUM=1 → store-page-fault (no W)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  lw s5, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page X-only region)

  test20_sum1_xu_sw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s5, test20_sum1_xu_sw, test20_sum1_xu_sw_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  nop                                           // pad so priv_mode samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch of S-page RWX: MXR=0 SUM=0 → success (X allowed); ret trampoline returns
  LI(s8, 0x257A0515)                            // magic proving jalr returned (case 21)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test21_srw_jalr:                                 // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s8, test21_srw_jalr, test21_srw_jalr_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  nop                                           // pad so priv_mode samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch of S-page RWX: MXR=0 SUM=1 → success (X allowed); ret trampoline returns
  LI(s9, 0x257A0516)                            // magic proving jalr returned (case 22)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test22_sum1_srw_jalr:                            // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s9, test22_sum1_srw_jalr, test22_sum1_srw_jalr_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  nop                                           // pad so priv_mode samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch of U-page RWX: MXR=1 SUM=1 → success (X allowed); ret trampoline returns
  LI(s10, 0x257A0517)                           // magic proving jalr returned (case 23)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test23_urw_jalr:                                 // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s10, test23_urw_jalr, test23_urw_jalr_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store to S-page RWX: MXR=1 SUM=1 → success (W allowed)
  nop                                           // trap-skip pad
  lw   s2, 0(a5)                                // VS load from S-page RWX: MXR=1 SUM=1 → success
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test24_mxr1_sum1_srw_sw:                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test24_mxr1_sum1_srw_sw, test24_mxr1_sum1_srw_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 25: MXR=1 SUM=0 U-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrc sstatus, t0                              // clear HS SUM
  csrc vsstatus, t0                             // clear VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store to U-page X-only: MXR=1 SUM=0 → store-page-fault (U=1 blocked without SUM)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  lw s3, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page X-only region)

  test25_mxr1_xu_sw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test25_mxr1_xu_sw, test25_mxr1_xu_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 26: MXR=1 SUM=0 S-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store to S-page X-only: MXR=1 SUM=0 → store-page-fault (no W)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  lw s4, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page X-only region)

  test26_mxr1_xs_sw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s4, test26_mxr1_xs_sw, test26_mxr1_xs_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 27: MXR=1 SUM=0 U-page XWR=111 VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store to U-page RWX: MXR=1 SUM=0 → store-page-fault (U=1 blocked without SUM)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_u_rw                       // t1 = SPA of U-page RWX region
  lw s5, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page RWX region)

  test27_mxr1_sum0_urw_sw:                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s5, test27_mxr1_sum0_urw_sw, test27_mxr1_sum0_urw_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 28: MXR=0 SUM=0 U-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear HS MXR and SUM
  csrc vsstatus, t0                             // clear VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store to U-page X-only: MXR=0 SUM=0 → store-page-fault (U=1 blocked without SUM)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  lw s2, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page X-only region)

  test28_mxr0_xu_sw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test28_mxr0_xu_sw, test28_mxr0_xu_sw_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s3, 0(a5)                                // VS load from U-page RWX: MXR=1 SUM=1 → success
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test29_mxr1_sum1_urw_lw:                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test29_mxr1_sum1_urw_lw, test29_mxr1_sum1_urw_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 30: MXR=1 SUM=1 S-page X-only VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(s4, 0)                                     // s4 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s4, 0(a5)                                // VS load from S-page X-only: MXR=1 SUM=1 → success; MXR makes X readable
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test30_mxr1_sum1_xs_lw:                          // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s4, test30_mxr1_sum1_xs_lw, test30_mxr1_sum1_xs_lw_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s5, 0(a5)                                // VS load from S-page RWX: MXR=1 SUM=0 → success
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test31_mxr1_sum0_srw_lw:                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s5, test31_mxr1_sum0_srw_lw, test31_mxr1_sum0_srw_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 32: MXR=1 SUM=0 S-page XWR=111 VS jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x00008067)                            // ret
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  sw t0, 0(t1)                                  // write ret trampoline at SPA of S-page RWX region
  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s6, 0)                                     // s6 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  nop                                           // pad so priv_mode samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch of S-page RWX: MXR=1 SUM=0 → success (X allowed); ret trampoline returns
  LI(s6, 0x257A0520)                            // magic proving jalr returned (case 32)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test32_mxr1_sum0_srw_jalr:                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s6, test32_mxr1_sum0_srw_jalr, test32_mxr1_sum0_srw_jalr_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s7, 0(a5)                                // VS load from S-page X-only: MXR=1 SUM=1 → success; MXR makes X readable
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test33_mxr1_sum1_xs_lw2:                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s7, test33_mxr1_sum1_xs_lw2, test33_mxr1_sum1_xs_lw2_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
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

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // align to 4 KiB page
rvtest_vlvl1_pg_tbl:                            // VS-stage L1 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage level-0 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
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
test10b_srw_lw_str:          .string "\"Mismatch on S-page R/W/X VS lw-only in Test Case 10b!\""
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
