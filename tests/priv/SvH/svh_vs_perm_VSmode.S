// --------------------------------------------------------------------------------------------------------------------------------
// svh_vs_perm_VSmode.S
// Config: sail-rv32-max | VS=Sv32 ON, hgatp=Bare, SUM=0
// Coverpoints mapped (SvH_cg): cp_vsatp_spages_sum_rwx, cp_vsatp_perm_checks
// What this proves (one line):
//   VS enforces U=0 S-page XWR allow/deny and blocks U=1 pages when SUM=0 (lw+sw).
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. Leaf XWR=111 U=0: VS sw+lw → Successful (0x257A0401)
//  2. Leaf XWR=001 (X only) U=0: VS lw → Expected Fault (a4 stays 0)
//  3. Leaf XWR=001 (X only) U=0: VS sw → Expected Fault (SPA stays 0x257A0402)
//  4. Leaf XWR=011 (R only) U=0: VS lw → Successful (0x257A0403)
//  4b. Leaf XWR=011 (R only) U=0: VS sw → Expected Fault (SPA unchanged)  // separate hop: TLB-hit sw drops PTE from .rvvi
//  5. Leaf XWR=110 (R/W) U=0: VS sw+lw → Successful (0x257A0405)
//  6. Leaf XWR=101 (R/X) U=0: VS lw → Successful (0x257A0406)
//  6b. Leaf XWR=101 (R/X) U=0: VS sw → Expected Fault (SPA unchanged)
//  7. Leaf U=1 XWR=111 SUM=0: VS lw → Expected Fault (a6 stays 0)
//  8. Leaf U=1 XWR=111 SUM=0: VS sw → Expected Fault (SPA stays 0x257A0404)
//  9. Leaf U=1 V-only SUM=0: VS sw → Expected Fault (SPA stays 0)  // urwx1000×write
//  9b. Leaf U=1 V-only SUM=0: VS lw → Expected Fault (s8 stays 0) // urwx1000×read
// 10. Leaf U=0 V-only SUM=0: VS lw → Expected Fault (s2 stays 0)  // urwx0000×read (matrix pad)
// 11. SUM=1 S-page XWR=111: VS sw → Successful (0x257A040B)       // spages_sum set×write
// 12. SUM=1 S-page R/W (110): VS sw+lw → Successful (0x257A040C)  // spages_sum set×rwx110 write; read needs fence hop
// 12b. SUM=1 S-page R/W (110): VS lw → Successful (0x257A040C)   // set×rwx110×read_acc
// 13. SUM=1 S-page R/X (101): VS lw → Successful (0x257A040D)     // spages_sum set×rwx101
// 13b. SUM=1 S-page R/X (101): VS sw → Expected Fault             // set×rwx101×write_acc
// 14. SUM=1 S-page X-only: VS ifetch → Successful (a3=0x257A040E) // spages_sum set×rwx001×exec (legacy name rwx)
// 15. SUM=1 S-page R-only: VS lw → Successful (0x257A040F)        // set×rwx100×read
// 16. SUM=1 S-page R-only: VS sw → Expected Fault                 // set×rwx100×write
// 17. SUM=1 S-page R-only: VS jalr → Expected Fault (no X)        // set×rwx100×exec
// 18. SUM=1 S-page R/W: VS jalr → Expected Fault (no X)           // set×rwx110×exec
//
// Total Expected Faults :: 12
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vs_perm_VSmode.S"
#define SIGUPD_COUNT 23
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set va_rwx,   0x008001000                    // GVA: S-page (U=0) with XWR=111
  .set va_xonly, 0x008002000                    // GVA: S-page (U=0) X-only (XWR=001)
  .set va_ronly, 0x008003000                    // GVA: S-page (U=0) R-only (XWR=011 / legal rwx100)
  .set va_u_rwx, 0x008004000                    // GVA: U=1 page with XWR=111
  .set va_rw,    0x008005000                    // GVA: S-page (U=0) R/W (XWR=110)
  .set va_rx,    0x008006000                    // GVA: S-page (U=0) R/X (XWR=101)
  .set va_u_vonly, 0x008007000                  // GVA: U=1 V-only (urwx1000)
  .set va_s_vonly, 0x008008000                  // GVA: U=0 V-only (urwx0000)
  .set va_xexec, 0x008009000                    // GVA: S-page X-only target for SUM=1 ifetch
  .set va_code,  0x90000000                     // GVA where VS executes this code

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- VS-stage (vsatp Sv32): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  SUPERPAGE_VS_PTE_SETUP(sv32, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // leaf: va_code -> PA(code); LEVEL1 = 4 MiB X/R

  csrr a0, mscratch                             // a0 = Msave_area (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: VS entry PC is under va_code

  // Shared L1 non-leaf (same VPN1 for all data VAs)
  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_rwx, LEVEL1)  // non-leaf: data VPN1 -> VS L0 table PA

  // Case 1: S-page R/W/X (U=0, XWR=111)
  VS_PTE_SETUP(sv32, PA, test_region_rwx, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V), va_rwx, LEVEL0)  // VS leaf U=0 R/W

  // Cases 2–3: S-page X-only (U=0, XWR=001)
  VS_PTE_SETUP(sv32, PA, test_region_xonly, (PTE_D | PTE_A | PTE_X | PTE_V), va_xonly, LEVEL0)  // leaf: va_xonly -> PA(test_region_xonly) X-only

  // Case 4: S-page R-only (U=0, XWR=011)
  VS_PTE_SETUP(sv32, PA, test_region_ronly, (PTE_D | PTE_A | PTE_R | PTE_V), va_ronly, LEVEL0)  // leaf: va_ronly -> PA(test_region_ronly) R-only

  // Cases 7–8: U=1 R/W/X (XWR=111, SUM stays 0)
  VS_PTE_SETUP(sv32, PA, test_region_u, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), va_u_rwx, LEVEL0)  // VS leaf U=1 XWR=111

  // Case 5: S-page R/W (U=0, XWR=110)
  VS_PTE_SETUP(sv32, PA, test_region_rw, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V), va_rw, LEVEL0)  // VS leaf U=0 R/W

  // Case 6: S-page R/X (U=0, XWR=101)
  VS_PTE_SETUP(sv32, PA, test_region_rx, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_rx, LEVEL0)  // VS leaf U=0 R/X

  // Case 9: U=1 V-only (XWR=000) — hits VS urwx1000×write
  VS_PTE_SETUP(sv32, PA, test_region_u_vonly, (PTE_D | PTE_A | PTE_U | PTE_V), va_u_vonly, LEVEL0)  // VS leaf: va_u_vonly → PA(test_region_u_vonly) U=1 XWR=000 V-only A=D=1

  // Case 10: U=0 V-only
  VS_PTE_SETUP(sv32, PA, test_region_s_vonly, (PTE_D | PTE_A | PTE_V), va_s_vonly, LEVEL0)  // VS leaf: va_s_vonly → PA(test_region_s_vonly) U=0 XWR=000 V-only A=D=1

  // Case 14: executable X-only page for SUM=1 ifetch (same PTE shape as va_xonly)
  VS_PTE_SETUP(sv32, PA, xonly_exec_page, (PTE_D | PTE_A | PTE_X | PTE_V), va_xexec, LEVEL0)  // VS leaf: va_xexec → PA(xonly_exec_page) U=0 XWR=001 X-only A=D=1


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv32, PA)                         // turn on VS-stage paging (vsatp MODE + root PPN)
  csrw hgatp, x0                                // write hgatp (hypervisor page-table root / Bare if x0)
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  // SUM=0 for all cases — guest cannot access U=1 pages
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrc sstatus, t0                              // clear HS SUM
  csrc vsstatus, t0                             // clear VS SUM

  // Preload each SPA with distinct payloads (M-mode baseline for load cases)
  LI(t0, 0x257A0401)                        // preload SPA
  la t1, test_region_rwx                    // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0402)                        // preload SPA
  la t1, test_region_xonly                  // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0403)                        // preload SPA
  la t1, test_region_ronly                  // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0404)                        // preload SPA
  la t1, test_region_u                      // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0405)                        // preload SPA
  la t1, test_region_rw                     // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0406)                        // preload SPA
  la t1, test_region_rx                     // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: S-page XWR=111 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rwx)                                // a5 = GVA of full-permission S-page
  LI(t0, 0x257A0401)                            // store value for case 1 R/W/X S-page
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // store through R/W/X S-page → SPA
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // load back; expect 0x257A0401
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test1_rwx:                                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_rwx, test1_rwx_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: S-page X-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_xonly)                              // a5 = GVA of X-only S-page
  LI(a4, 0)                                     // a4 stays 0 if lw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a4, 0(a5)                                // no read perm on X-only leaf → load-page-fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test2_xonly_lw:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_xonly_lw, test2_xonly_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: S-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_xonly)                              // a5 = GVA of X-only S-page
  LI(t0, 0xDEADBEEF)                            // must not land in SPA if fault works
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // no write perm on X-only leaf → store-page-fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  la t1, test_region_xonly                      // t1 = SPA of S-page X-only region
  lw a3, 0(t1)                                  // expect preload 0x257A0402 unchanged
  test3_xonly_sw:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_xonly_sw, test3_xonly_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: S-page R-only VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_ronly)                              // a5 = GVA of R-only S-page
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a3, 0(a5)                                // R-only load permitted → success (0x257A0403)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test4_ronly:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test4_ronly, test4_ronly_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4b: S-page R-only VS sw | Expected: Expected Fault (fresh walk; not TLB-hit after lw)
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_ronly)                              // a5 = S-page R-only GVA (U=0 XWR=011)
  LI(t0, 0xDEADBEEF)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // no write perm → store-page-fault; emits VS_PTE_D
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_ronly                      // t1 = SPA of S-page R-only region
  lw a4, 0(t1)                                  // expect preload 0x257A0403 unchanged

  test4b_ronly_sw:                                 // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test4b_ronly_sw, test4b_ronly_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: S-page R/W (XWR=110) VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rw)                                 // a5 = GVA of R/W S-page
  LI(t0, 0x257A0405)                            // store value for case 5 R/W S-page
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // store through R/W S-page → SPA
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // load back; expect 0x257A0405
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test5_rw:                                        // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test5_rw, test5_rw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: S-page R/X VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rx)                                 // a5 = GVA of R/X S-page
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a3, 0(a5)                                // R/X load permitted → success (0x257A0406)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test6_rx:                                        // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test6_rx, test6_rx_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6b: S-page R/X VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_rx)                                 // a5 = S-page R/X GVA (U=0 XWR=101)
  LI(t0, 0xDEADBEEF)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store to S-page R/X: SUM=0 → store-page-fault (no W)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_rx                         // t1 = SPA of S-page R/X region
  lw a4, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page R/X region)

  test6b_rx_sw:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test6b_rx_sw, test6b_rx_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: U=1 XWR=111 SUM=0 VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rwx)                              // a5 = GVA of U=1 page (SUM still 0)
  LI(a6, 0)                                     // a6 stays 0 if lw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a6, 0(a5)                                // U-page with SUM=0 → load-page-fault; insn skipped
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test7_u_lw:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test7_u_lw, test7_u_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: U=1 XWR=111 SUM=0 VS sw | Expected: Expected Fault
// SPA check: a zero sentinel in the store src would also SIGUPD-pass if the store wrongly succeeded.
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rwx)                              // a5 = GVA of U=1 page (SUM still 0)
  LI(t0, 0xDEADBEEF)                            // distinct payload — must not land in SPA
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // U-page with SUM=0 → store-page-fault; insn skipped
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  la t1, test_region_u                          // t1 = SPA of U-page RWX region
  lw a7, 0(t1)                                  // expect preload 0x257A0404 unchanged
  test8_u_sw:                                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test8_u_sw, test8_u_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 9: U=1 V-only VS sw | Expected: Expected Fault (VS urwx1000×write)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_vonly)                            // a5 = U-page V-only GVA (U=1 XWR=000)
  LI(t0, 0xDEADBEEF)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // V-only U=1 → store-page-fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  la t1, test_region_u_vonly                    // t1 = SPA of U-page V-only region
  lw a3, 0(t1)                                  // SPA must stay 0
  test9_u_vonly_sw:                                 // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test9_u_vonly_sw, test9_u_vonly_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 9b: U=1 V-only VS lw | Expected: Expected Fault (VS urwx1000×read)
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_u_vonly)                            // a5 = U-page V-only GVA (U=1 XWR=000)
  LI(s8, 0)                                     // sentinel — s8 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s8, 0(a5)                                // VS load from U-page V-only: SUM=0 → load-page-fault (U=1 blocked without SUM); s8 stays 0
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test9b_u_vonly_lw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s8, test9b_u_vonly_lw, test9b_u_vonly_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 10: U=0 V-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_vonly)                            // a5 = S-page V-only GVA (U=0 XWR=000)
  LI(s2, 0)                                     // sentinel — s2 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   s2, 0(a5)                                // V-only U=0 → load-page-fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test10_s_vonly_lw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test10_s_vonly_lw, test10_s_vonly_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 11: SUM=1 S-page XWR=111 VS sw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_rwx)                                // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(t0, 0x257A040B)                            // SPA pattern / store value for case 11 (0x257A040B)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store to S-page RWX: SUM=1 → success (W allowed)
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // VS load from S-page RWX: SUM=1 → success
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test11_sum1_rwx_sw:                              // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test11_sum1_rwx_sw, test11_sum1_rwx_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 12: SUM=1 S-page R/W VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rw)                                 // a5 = S-page R/W GVA (U=0 XWR=110)
  LI(t0, 0x257A040C)                            // SPA pattern / store value for case 12 (0x257A040C)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store to S-page R/W: SUM=1 → success (W allowed)
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // VS load from S-page R/W: SUM=1 → success
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test12_sum1_rw:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test12_sum1_rw, test12_sum1_rw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 13: SUM=1 S-page R/X VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0x257A040D)                        // preload SPA
  la t1, test_region_rx                     // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)

  LI(a5, va_rx)                                 // a5 = S-page R/X GVA (U=0 XWR=101)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a3, 0(a5)                                // VS load from S-page R/X: SUM=1 → success
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test13_sum1_rx:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test13_sum1_rx, test13_sum1_rx_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 14: SUM=1 S-page X-only ifetch | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // xonly_exec_page holds: addi a3,x0,imm ; jalr x0, ra, 0  (return)
  // Build return path: save ra, jalr to va_xexec, then SIGUPD a3.
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_xexec)                              // a5 = S-page X-only ifetch GVA (SUM=1 trampoline)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  jalr ra, a5, 0                                // ifetch X-only leaf (SUM=1 irrelevant for exec)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test14_sum1_x_ifetch:                            // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test14_sum1_x_ifetch, test14_sum1_x_ifetch_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 12b: SUM=1 S-page R/W VS lw only | Expected: Successful (set×rwx110×read with fresh walk)
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x257A040C)                        // preload SPA
  la t1, test_region_rw                     // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(a5, va_rw)                                 // a5 = S-page R/W GVA (U=0 XWR=110)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a3, 0(a5)                                // VS load from S-page R/W: SUM=1 → success
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test12b_sum1_rw_lw:                              // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test12b_sum1_rw_lw, test12b_sum1_rw_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 13b: SUM=1 S-page R/X VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_rx)                                 // a5 = S-page R/X GVA (U=0 XWR=101)
  LI(t0, 0xDEADBEEF)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store to S-page R/X: SUM=1 → store-page-fault (no W)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_rx                         // t1 = SPA of S-page R/X region
  lw a4, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page R/X region)

  test13b_sum1_rx_sw:                              // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test13b_sum1_rx_sw, test13b_sum1_rx_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 15: SUM=1 S-page R-only VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x257A040F)                        // preload SPA
  la t1, test_region_ronly                  // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(a5, va_ronly)                              // a5 = S-page R-only GVA (U=0 XWR=011)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a3, 0(a5)                                // VS load from S-page R-only: SUM=1 → success
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test15_sum1_ronly_lw:                            // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test15_sum1_ronly_lw, test15_sum1_ronly_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 16: SUM=1 S-page R-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_ronly)                              // a5 = S-page R-only GVA (U=0 XWR=011)
  LI(t0, 0xDEADBEEF)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  sw   t0, 0(a5)                                // VS store to S-page R-only: SUM=1 → store-page-fault (no W)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_ronly                      // t1 = SPA of S-page R-only region
  lw a4, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page R-only region)

  test16_sum1_ronly_sw:                            // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test16_sum1_ronly_sw, test16_sum1_ronly_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 17: SUM=1 S-page R-only VS jalr | Expected: Expected Fault (no X)
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_ronly)                              // a5 = S-page R-only GVA (U=0 XWR=011)
  LI(s2, 0)                                     // sentinel — s2 stays 0 if target never runs
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  nop                                           // pad so priv_mode samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch of S-page R-only: SUM=1 → fetch-page-fault (no X)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test17_sum1_ronly_jalr:                          // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test17_sum1_ronly_jalr, test17_sum1_ronly_jalr_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 18: SUM=1 S-page R/W VS jalr | Expected: Expected Fault (no X)
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_rw)                                 // a5 = S-page R/W GVA (U=0 XWR=110)
  LI(s3, 0)                                     // sentinel — s3 stays 0 if target never runs
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  nop                                           // pad so priv_mode samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch of S-page R/W: SUM=1 → fetch-page-fault (no X)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  test18_sum1_rw_jalr:                             // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test18_sum1_rw_jalr, test18_sum1_rw_jalr_str) // SIGUPD


//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region_rwx:                                // real PA backing va_rwx (S-page XWR=111)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_xonly:                              // real PA backing va_xonly (S-page X-only)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_ronly:                              // real PA backing va_ronly (S-page R-only)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_u:                                  // real PA backing va_u_rwx (U=1 page)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_rw:                                 // real PA backing va_rw (S-page R/W)
  .word 0                                       // data word (initially 0)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_rx:                                 // SPA backing va_rx (S-page R/X)
  .word 0                                       // data word (initially 0 / preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_u_vonly:                            // SPA backing va_u_vonly (U=1 V-only)
  .word 0                                       // data word (initially 0 / preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_s_vonly:                            // SPA backing va_s_vonly (U=0 V-only)
  .word 0                                       // data word (initially 0 / preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
xonly_exec_page:                                // SPA trampoline: X-only ifetch target (SUM=1)
  LI(a3, 0x257A040E)                            // payload proving ifetch of this X-only page
  jalr x0, ra, 0                                // return to caller in VS
  nop                                           // pad remainder of trampoline page
  nop                                           // pad remainder of trampoline page


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_rwx_str:         .string "\"Mismatch on S-page R/W/X VS lw in Test Case 1!\""  // mismatch string
test2_xonly_lw_str:    .string "\"Mismatch on S-page X-only VS lw (expect fault) in Test Case 2!\""  // mismatch string
test3_xonly_sw_str:    .string "\"Mismatch on S-page X-only VS sw (expect fault) in Test Case 3!\""  // mismatch string
test4_ronly_str:       .string "\"Mismatch on S-page R-only VS lw in Test Case 4!\""  // mismatch string
test4b_ronly_sw_str:   .string "\"Mismatch on S-page R-only VS sw (expect fault) in Test Case 4b!\""  // mismatch string
test5_rw_str:          .string "\"Mismatch on S-page R/W VS lw in Test Case 5!\""  // mismatch string
test6_rx_str:          .string "\"Mismatch on S-page R/X VS lw in Test Case 6!\""  // mismatch string
test6b_rx_sw_str:      .string "\"Mismatch on S-page R/X VS sw (expect fault) in Test Case 6b!\""  // mismatch string
test7_u_lw_str:        .string "\"Mismatch on U=1 VS lw with SUM=0 (expect fault) in Test Case 7!\""  // mismatch string
test8_u_sw_str:        .string "\"Mismatch on U=1 VS sw with SUM=0 (expect fault) in Test Case 8!\""  // mismatch string
test9_u_vonly_sw_str:  .string "\"Mismatch on U=1 V-only VS sw (expect fault) in Test Case 9!\""  // mismatch string
test9b_u_vonly_lw_str: .string "\"Mismatch on U=1 V-only VS lw (expect fault) in Test Case 9b!\""  // mismatch string
test10_s_vonly_lw_str: .string "\"Mismatch on U=0 V-only VS lw (expect fault) in Test Case 10!\""  // mismatch string
test11_sum1_rwx_sw_str:.string "\"Mismatch on SUM=1 S-page R/W/X VS sw in Test Case 11!\""  // mismatch string
test12_sum1_rw_str:    .string "\"Mismatch on SUM=1 S-page R/W VS lw in Test Case 12!\""  // mismatch string
test12b_sum1_rw_lw_str:.string "\"Mismatch on SUM=1 S-page R/W VS lw-only in Test Case 12b!\""  // mismatch string
test13_sum1_rx_str:    .string "\"Mismatch on SUM=1 S-page R/X VS lw in Test Case 13!\""  // mismatch string
test13b_sum1_rx_sw_str:.string "\"Mismatch on SUM=1 S-page R/X VS sw (expect fault) in Test Case 13b!\""  // mismatch string
test14_sum1_x_ifetch_str: .string "\"Mismatch on SUM=1 S-page X-only ifetch in Test Case 14!\""  // mismatch string
test15_sum1_ronly_lw_str: .string "\"Mismatch on SUM=1 S-page R-only VS lw in Test Case 15!\""  // mismatch string
test16_sum1_ronly_sw_str: .string "\"Mismatch on SUM=1 S-page R-only VS sw (expect fault) in Test Case 16!\""  // mismatch string
test17_sum1_ronly_jalr_str: .string "\"Mismatch on SUM=1 S-page R-only VS jalr (expect fault) in Test Case 17!\""  // mismatch string
test18_sum1_rw_jalr_str: .string "\"Mismatch on SUM=1 S-page R/W VS jalr (expect fault) in Test Case 18!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                VS enforces U=0 S-page XWR allow/deny and blocks ...
  //                      │
  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 1                      Test 2                      Test 3          
  //                │                           │                           │             
  //         Leaf XWR=111 U=0       Leaf XWR=001 (X only) U=0   Leaf XWR=001 (X only) U=0 
  //                │                           │                           │             
  //             VS sw+lw                     VS lw                       VS sw           
  //                ▼                           ▼                           ▼             
  //            0x257A0401                  FAULT a4=0            FAULT SPA 0x257A0402)   

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 4                     Test 4b                      Test 5          
  //                │                           │                           │             
  //    Leaf XWR=011 (R only) U=0   Leaf XWR=011 (R only) U=0     Leaf XWR=110 (R/W) U=0  
  //                │                           │                           │             
  //              VS lw                       VS sw                      VS sw+lw         
  //                ▼                           ▼                           ▼             
  //            0x257A0403               FAULT SPA same)                0x257A0405        

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 6                     Test 6b                      Test 7          
  //                │                           │                           │             
  //      Leaf XWR=101 (R/X) U=0      Leaf XWR=101 (R/X) U=0      Leaf U=1 XWR=111 SUM=0  
  //                │                           │                           │             
  //              VS lw                       VS sw                       VS lw           
  //                ▼                           ▼                           ▼             
  //            0x257A0406               FAULT SPA same)                FAULT a6=0        

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 8                      Test 9                     Test 9b          
  //                │                           │                           │             
  //      Leaf U=1 XWR=111 SUM=0      Leaf U=1 V-only SUM=0       Leaf U=1 V-only SUM=0   
  //                │                           │                           │             
  //              VS sw                       VS sw                       VS lw           
  //                ▼                           ▼                           ▼             
  //      FAULT SPA 0x257A0404)            FAULT SPA=0                  FAULT s8=0        

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //             Test 10                     Test 11                     Test 12          
  //                │                           │                           │             
  //      Leaf U=0 V-only SUM=0        SUM=1 S-page XWR=111       SUM=1 S-page R/W (110)  
  //                │                           │                           │             
  //              VS lw                       VS sw                      VS sw+lw         
  //                ▼                           ▼                           ▼             
  //            FAULT s2=0                  0x257A040B                  0x257A040C        

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //             Test 12b                    Test 13                     Test 13b         
  //                │                           │                           │             
  //      SUM=1 S-page R/W (110)      SUM=1 S-page R/X (101)      SUM=1 S-page R/X (101)  
  //                │                           │                           │             
  //              VS lw                       VS lw                       VS sw           
  //                ▼                           ▼                           ▼             
  //            0x257A040C                  0x257A040D                    FAULT           

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //             Test 14                     Test 15                     Test 16          
  //                │                           │                           │             
  //       SUM=1 S-page X-only         SUM=1 S-page R-only         SUM=1 S-page R-only    
  //                │                           │                           │             
  //            VS ifetch                     VS lw                       VS sw           
  //                ▼                           ▼                           ▼             
  //          a3=0x257A040E                 0x257A040F                    FAULT           

  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 17                            Test 18
  //         │                         │
  //      SUM=1 S-page R-only        SUM=1 S-page R/W
  //         │                         │
  //      VS jalr                    VS jalr
  //         ▼                         ▼
  //      FAULT no X)                FAULT no X)
