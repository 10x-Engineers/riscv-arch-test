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
//  4. Leaf XWR=011 (R only) U=0: VS lw → Successful (0x257A0403); VS sw → Expected Fault
//  5. Leaf XWR=110 (R/W) U=0: VS sw+lw → Successful (0x257A0405)
//  6. Leaf XWR=101 (R/X) U=0: VS lw → Successful (0x257A0406); VS sw → Expected Fault
//  7. Leaf U=1 XWR=111 SUM=0: VS lw → Expected Fault (a6 stays 0)
//  8. Leaf U=1 XWR=111 SUM=0: VS sw → Expected Fault (SPA stays 0x257A0404)
//
// Total Expected Faults :: 6
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vs_perm_VSmode.S"
#define SIGUPD_COUNT 8
#define TRAP_SIGUPD_COUNT 128
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VSMODE / _SMODE (ecall a0=4/2)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE (mret + PA↔VA relocate)
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_rwx,   0x008001000                    // GVA: S-page (U=0) with XWR=111
  .set va_xonly, 0x008002000                    // GVA: S-page (U=0) X-only (XWR=001)
  .set va_ronly, 0x008003000                    // GVA: S-page (U=0) R-only (XWR=011 / legal rwx100)
  .set va_u_rwx, 0x008004000                    // GVA: U=1 page with XWR=111
  .set va_rw,    0x008005000                    // GVA: S-page (U=0) R/W (XWR=110)
  .set va_rx,    0x008006000                    // GVA: S-page (U=0) R/X (XWR=101)
  .set va_code,  0x90000000                     // GVA where VS executes this code

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


  VSATP_SETUP(sv32, PA)                         // turn on VS-stage paging (vsatp MODE + root PPN)
  csrw hgatp, x0                                // write hgatp (hypervisor page-table root / Bare if x0)
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  // SUM=0 for all cases — guest cannot access U=1 pages
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrc sstatus, t0                              // clear HS SUM
  csrc vsstatus, t0                             // clear VS SUM

  // Preload each SPA with distinct payloads (M-mode baseline for load cases)
  LI(t0, 0x257A0401)                            // SPA pattern for R/W/X S-page (case 1)
  la t1, test_region_rwx                        // SPA of full-permission S-page region
  sw t0, 0(t1)                                  // preload (case 1 load expects 0x257A0401)
  LI(t0, 0x257A0402)                            // SPA pattern for X-only page (cases 2–3)
  la t1, test_region_xonly                      // SPA of X-only region
  sw t0, 0(t1)                                  // preload (load/store should fault before use)
  LI(t0, 0x257A0403)                            // SPA pattern for R-only page (case 4)
  la t1, test_region_ronly                      // SPA of R-only region
  sw t0, 0(t1)                                  // preload (R-only load should succeed)
  LI(t0, 0x257A0404)                            // SPA pattern for U=1 page (cases 7–8)
  la t1, test_region_u                          // SPA of U=1 region
  sw t0, 0(t1)                                  // preload (U-page access should fault with SUM=0)
  LI(t0, 0x257A0405)                            // SPA pattern for R/W S-page (case 5)
  la t1, test_region_rw                         // SPA of R/W region
  sw t0, 0(t1)                                  // preload (case 5 load expects 0x257A0405 after store)
  LI(t0, 0x257A0406)                            // SPA pattern for R/X S-page (case 6)
  la t1, test_region_rx                         // SPA of R/X region
  sw t0, 0(t1)                                  // preload (R/X load should succeed)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: S-page XWR=111 VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rwx)                                // a5 = GVA of full-permission S-page
  LI(t0, 0x257A0401)                            // store value for case 1 R/W/X S-page
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  sw   t0, 0(a5)                                // store through R/W/X S-page → SPA
  nop                                           // trap-skip padding after store
  lw   a3, 0(a5)                                // load back; expect 0x257A0401
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test1_rwx:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_rwx, test1_rwx_str)  // record case 1 lw result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: S-page X-only VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_xonly)                              // a5 = GVA of X-only S-page
  LI(a4, 0)                                     // a4 stays 0 if lw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  lw   a4, 0(a5)                                // no read perm on X-only leaf → load-page-fault
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test2_xonly_lw:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_xonly_lw, test2_xonly_lw_str)  // record case 2 fault sentinel in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: S-page X-only VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_xonly)                              // a5 = GVA of X-only S-page
  LI(t0, 0xDEADBEEF)                            // must not land in SPA if fault works
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  sw   t0, 0(a5)                                // no write perm on X-only leaf → store-page-fault
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  la t1, test_region_xonly
  lw a3, 0(t1)                                  // expect preload 0x257A0402 unchanged
  test3_xonly_sw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_xonly_sw, test3_xonly_sw_str)  // record case 3 SPA in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: S-page R-only VS lw OK, VS sw fault | Expected: lw Successful, sw Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_ronly)                              // a5 = GVA of R-only S-page
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  lw   a3, 0(a5)                                // R-only load permitted → success (0x257A0403)
  nop                                           // trap-skip padding after load
  LI(a4, 0)                                     // a4 stays 0 if sw is skipped by trap handler
  sw   a4, 0(a5)                                // no write perm on R-only leaf → store-page-fault
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test4_ronly:
  RVTEST_SIGUPD(x2, x5, x4, a3, test4_ronly, test4_ronly_str)  // record case 4 lw result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: S-page R/W (XWR=110) VS sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rw)                                 // a5 = GVA of R/W S-page
  LI(t0, 0x257A0405)                            // store value for case 5 R/W S-page
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  sw   t0, 0(a5)                                // store through R/W S-page → SPA
  nop                                           // trap-skip padding after store
  lw   a3, 0(a5)                                // load back; expect 0x257A0405
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test5_rw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test5_rw, test5_rw_str)  // record case 5 lw result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: S-page R/X (XWR=101) VS lw OK, VS sw fault | Expected: lw Successful, sw Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_rx)                                 // a5 = GVA of R/X S-page
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  lw   a3, 0(a5)                                // R/X load permitted → success (0x257A0406)
  nop                                           // trap-skip padding after load
  LI(a4, 0)                                     // a4 stays 0 if sw is skipped by trap handler
  sw   a4, 0(a5)                                // no write perm on R/X leaf → store-page-fault
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test6_rx:
  RVTEST_SIGUPD(x2, x5, x4, a3, test6_rx, test6_rx_str)  // record case 6 lw result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: U=1 XWR=111 SUM=0 VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rwx)                              // a5 = GVA of U=1 page (SUM still 0)
  LI(a6, 0)                                     // a6 stays 0 if lw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  lw   a6, 0(a5)                                // U-page with SUM=0 → load-page-fault; insn skipped
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test7_u_lw:
  RVTEST_SIGUPD(x2, x5, x4, a6, test7_u_lw, test7_u_lw_str)  // record case 7 fault sentinel in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: U=1 XWR=111 SUM=0 VS sw | Expected: Expected Fault
// SPA check: a zero sentinel in the store src would also SIGUPD-pass if the store wrongly succeeded.
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rwx)                              // a5 = GVA of U=1 page (SUM still 0)
  LI(t0, 0xDEADBEEF)                            // distinct payload — must not land in SPA
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate (guest code VA≠PA; T-SBI enter lacks relocate)
  sw   t0, 0(a5)                                // U-page with SUM=0 → store-page-fault; insn skipped
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  la t1, test_region_u
  lw a7, 0(t1)                                  // expect preload 0x257A0404 unchanged
  test8_u_sw:
  RVTEST_SIGUPD(x2, x5, x4, a7, test8_u_sw, test8_u_sw_str)  // signature: dump a7 (test8_u_sw) for PASS/FAIL


//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

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
.align 12
test_region_rx:
  .word 0
  .word 0
  .word 0
  .word 0

.align 12
rvtest_vlvl0_pg_tbl:
  .zero(4096)

test1_rwx_str:         .string "\"Mismatch on S-page R/W/X VS lw in Test Case 1!\""
test2_xonly_lw_str:    .string "\"Mismatch on S-page X-only VS lw (expect fault) in Test Case 2!\""
test3_xonly_sw_str:    .string "\"Mismatch on S-page X-only VS sw (expect fault) in Test Case 3!\""
test4_ronly_str:       .string "\"Mismatch on S-page R-only VS lw in Test Case 4!\""
test5_rw_str:          .string "\"Mismatch on S-page R/W VS lw in Test Case 5!\""
test6_rx_str:          .string "\"Mismatch on S-page R/X VS lw in Test Case 6!\""
test7_u_lw_str:        .string "\"Mismatch on U=1 VS lw with SUM=0 (expect fault) in Test Case 7!\""
test8_u_sw_str:        .string "\"Mismatch on U=1 VS sw with SUM=0 (expect fault) in Test Case 8!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
