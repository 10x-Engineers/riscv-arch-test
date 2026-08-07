// --------------------------------------------------------------------------------------------------------------------------------
// svh_vsstatus_mxr_sum_sv39_VUmode.S
// Config: sail-rv64-max | VS=Sv39 ON, hgatp=Bare, stimulus in VU
// Pair:   svh_vsstatus_mxr_sum_VUmode.S
// Coverpoints mapped (SvH_cg): cp_vsstatus_mxr_sum
// What this proves (one line):
//   VU MXR×SUM×U-page (X-only / RWX) control load/store; S-pages fault in VU.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. MXR=0 SUM=0, U-page X-only: VU lw → Expected Fault (a3 stays 0)
//  2. MXR=1 SUM=0, U-page X-only: VU lw → Successful (0xDEADBEEF)
//  3. MXR=1 SUM=0, U-page X-only: VU sw → Expected Fault (SPA stays 0xDEADBEEF)
//  4. MXR=0 SUM=1, U-page XWR=111: VU lw → Successful (0x257A0604)
//  5. MXR=1 SUM=1, U-page XWR=111: VU sw+lw → Successful (0x257A0605)
//  6. MXR=0 SUM=0, U-page XWR=111: VU sw+lw → Successful (0x257A0606)  // VU needs U=1, not SUM
//  7. MXR=0 SUM=0, S-page XWR=111: VU lw → Expected Fault (a6 stays 0)
//  8. MXR=1 SUM=1, S-page X-only: VU lw → Expected Fault (a7 stays 0)
//  9. MXR=0 SUM=1, S-page XWR=111: VU lw → Expected Fault (s2 stays 0)
// 10. MXR=0 SUM=0, S-page X-only: VU lw → Expected Fault (s3 stays 0)
// 11. MXR=0 SUM=1, U-page X-only: VU lw → Expected Fault (s4 stays 0)
// 12. MXR=0 SUM=1, U-page XWR=111: VU sw+lw → Successful (0x257A060C)
// 13. MXR=1 SUM=0, S-page XWR=111: VU sw → Expected Fault (SPA stays 0x257A060A)
// 14. MXR=1 SUM=1, S-page XWR=111: VU lw → Expected Fault (s5 stays 0)
// 15. MXR=0 SUM=0, S-page X-only: VU sw → Expected Fault (SPA stays 0x257A0601)
// 16. MXR=1 SUM=1, U-page X-only: VU jalr → Expected Fault (s6 stays 0)
// 17. MXR=1 SUM=1, S-page XWR=111: VU jalr → Expected Fault (s7 stays 0)
// 18. MXR=1 SUM=0, U-page XWR=111: VU sw+lw → Successful (0x257A0612)
// 19. MXR=1 SUM=0, S-page X-only: VU lw → Expected Fault (s8 stays 0)
// 20. MXR=0 SUM=1, S-page X-only: VU sw → Expected Fault (SPA stays 0x257A0601)
// 21. MXR=1 SUM=1, U-page X-only: VU sw → Expected Fault (SPA stays 0xDEADBEEF)
// 22. MXR=1 SUM=1, S-page XWR=111: VU sw → Expected Fault (SPA unchanged)  // set,*,rwx111_s,write
// 23. MXR=0 SUM=0, U-page XWR=111: VU lw only → Successful (0x257A0617)   // unset,*,rwx111_u,read
// 24. MXR=1 SUM=0, U-page XWR=111: VU lw only → Successful (0x257A0618)
// 25. MXR=1 SUM=0, S-page X-only: VU sw → Expected Fault                 // *,set,rwx001_s,write
// 26. MXR=1 SUM=1, S-page X-only: VU sw → Expected Fault
// 27. MXR=0 SUM=1, U-page X-only: VU sw → Expected Fault                 // set,unset,rwx001_u,write
// 28. MXR=1 SUM=0, U-page X-only: VU sw (already 3); dedicated after fence
// 29. MXR=0 SUM=1, S-page X-only: VU lw → Expected Fault                 // set,unset,rwx001_s,read
// 30. MXR=1 SUM=1, U-page X-only: VU lw → Successful (0xDEADBEEF)        // set,set,rwx001_u,read
// 31. MXR=0 SUM=0, U-page XWR=111: VU jalr → Successful                 // unset,*,rwx111_u,exec
// 32. MXR=1 SUM=0, U-page X-only: VU jalr → Successful (ret)            // unset,set,rwx001_u,exec
//
// Total Expected Faults :: 20
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vsstatus_mxr_sum_sv39_VUmode.S"
#define SIGUPD_COUNT 37
#define TRAP_SIGUPD_COUNT 512
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VUMODE (ecall a0=5)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE VUmode
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_x_u,  0x008002000                     // GVA: U-page X-only leaf
  .set va_u_rw, 0x008003000                     // GVA: U-page R/W/X leaf
  .set va_s_rw, 0x008004000                     // GVA: S-page R/W/X leaf (VU must fault)
  .set va_x_s,  0x008001000                     // GVA: S-page X-only leaf (VU must fault)
  .set va_code,                 0x0000000090000000      // GVA where guest executes this code

  // ---- VS-stage (vsatp Sv39): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  // VU ifetch requires U=1 on the code leaf (unlike VS which uses U=0).
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)
  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // leaf: va_code -> PA(code); LEVEL1 megapage X/R

  csrr a0, mscratch                             // a0 = Msave_area (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: entry PC under va_code

  // Shared L2+L1 non-leafs (same VPN2/VPN1 for all data VAs under 0x00800x000)
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_x_s, LEVEL2)
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_x_s, LEVEL1)  // non-leaf: data VPN1 -> VS L0 table PA

  VS_PTE_SETUP(sv39, PA, test_region_x_s, (PTE_D | PTE_A | PTE_X | PTE_V), va_x_s, LEVEL0)  // S X-only
  VS_PTE_SETUP(sv39, PA, test_region_x_u, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V), va_x_u, LEVEL0)  // U X-only
  VS_PTE_SETUP(sv39, PA, test_region_u_rw, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), va_u_rw, LEVEL0)  // VS leaf U=1 XWR=111 (U-page for MXR/SUM)
  VS_PTE_SETUP(sv39, PA, test_region_s_rw, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V), va_s_rw, LEVEL0)  // VS leaf U=0 XWR=111 (S-page; VU must fault)

  VSATP_SETUP(sv39, PA)                         // turn on VS-stage paging (vsatp MODE + root PPN)
  csrw hgatp, x0                                // write hgatp (hypervisor page-table root / Bare if x0)
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0xDEADBEEF)
  la t1, test_region_x_u
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0604)
  la t1, test_region_u_rw
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)
  LI(t0, 0x257A060A)
  la t1, test_region_s_rw
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0601)
  la t1, test_region_x_s
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: MXR=0 SUM=0 U-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM

  LI(a5, va_x_u)
  LI(a3, 0)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VUmode mret + PA↔VA relocate (U=1 code)
  lw   a3, 0(a5)                                // X-only without MXR → load-page-fault
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test1_mxr0_xu:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_mxr0_xu, test1_mxr0_xu_str)  // signature: dump a3 (test1_mxr0_xu) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: MXR=1 SUM=0 U-page X-only VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_u)
  LI(a4, 0)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a4, 0(a5)                                // MXR=1 makes U X-only readable; expect 0xDEADBEEF
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test2_mxr1_xu_lw:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_mxr1_xu_lw, test2_mxr1_xu_lw_str)  // signature: dump a4 (test2_mxr1_xu_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: MXR=1 SUM=0 U-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x_u)
  LI(t0, 0xBAD00FAD)                            // must not overwrite 0xDEADBEEF preload
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // X-only has no W → store-page-fault
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t1, test_region_x_u
  lw a3, 0(t1)                                  // expect 0xDEADBEEF still
  test3_mxr1_xu_sw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_mxr1_xu_sw, test3_mxr1_xu_sw_str)  // signature: dump a3 (test3_mxr1_xu_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: MXR=0 SUM=1 U-page XWR=111 VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM
  LI(t0, SSTATUS_SUM)
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_u_rw)
  LI(a4, 0)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a4, 0(a5)                                // U-page R bit; expect 0x257A0604
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test4_sum1_urw_lw:
  RVTEST_SIGUPD(x2, x5, x4, a4, test4_sum1_urw_lw, test4_sum1_urw_lw_str)  // signature: dump a4 (test4_sum1_urw_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: MXR=1 SUM=1 U-page XWR=111 VU sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_u_rw)
  LI(t0, 0x257A0605)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // guest store through current PTE perms
  nop
  lw   a6, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test5_sum1_urw_swlw:
  RVTEST_SIGUPD(x2, x5, x4, a6, test5_sum1_urw_swlw, test5_sum1_urw_swlw_str)  // signature: dump a6 (test5_sum1_urw_swlw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: MXR=0 SUM=0 U-page XWR=111 VU sw+lw | Expected: Successful
// (Unlike VS, VU may access U=1 pages with SUM=0.)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_u_rw)
  LI(t0, 0x257A0606)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // guest store through current PTE perms
  nop
  lw   a3, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test6_sum0_urw_swlw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test6_sum0_urw_swlw, test6_sum0_urw_swlw_str)  // signature: dump a3 (test6_sum0_urw_swlw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: MXR=0 SUM=0 S-page XWR=111 VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_rw)
  LI(a6, 0)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a6, 0(a5)                                // VU cannot use U=0 pages
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test7_srw_lw:
  RVTEST_SIGUPD(x2, x5, x4, a6, test7_srw_lw, test7_srw_lw_str)  // signature: dump a6 (test7_srw_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: MXR=1 SUM=1 S-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_s)
  LI(a7, 0)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a7, 0(a5)                                // S-page still blocked in VU
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test8_mxr1_sum1_xs:
  RVTEST_SIGUPD(x2, x5, x4, a7, test8_mxr1_sum1_xs, test8_mxr1_sum1_xs_str)  // signature: dump a7 (test8_mxr1_sum1_xs) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 9: MXR=0 SUM=1 S-page XWR=111 VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrc sstatus, t0
  csrc vsstatus, t0
  LI(t0, SSTATUS_SUM)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma

  LI(a5, va_s_rw)
  LI(s2, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  lw   s2, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test9_sum1_srw:
  RVTEST_SIGUPD(x2, x5, x4, s2, test9_sum1_srw, test9_sum1_srw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 10: MXR=0 SUM=0 S-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)
  csrc sstatus, t0
  csrc vsstatus, t0
  hfence.vvma

  LI(a5, va_x_s)
  LI(s3, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  lw   s3, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test10_sum0_xs:
  RVTEST_SIGUPD(x2, x5, x4, s3, test10_sum0_xs, test10_sum0_xs_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 11: MXR=0 SUM=1 U-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma

  LI(a5, va_x_u)
  LI(s4, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  lw   s4, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test11_sum1_mxr0_xu:
  RVTEST_SIGUPD(x2, x5, x4, s4, test11_sum1_mxr0_xu, test11_sum1_mxr0_xu_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 12: MXR=0 SUM=1 U-page XWR=111 VU sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rw)
  LI(t0, 0x257A060C)
  RVTEST_GOTO_LOWER_MODE VUmode
  sw   t0, 0(a5)
  nop
  lw   a3, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test12_sum1_mxr0_urw_sw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test12_sum1_mxr0_urw_sw, test12_sum1_mxr0_urw_sw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 13: MXR=1 SUM=0 S-page XWR=111 VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrs sstatus, t0
  csrs vsstatus, t0
  LI(t0, SSTATUS_SUM)
  csrc sstatus, t0
  csrc vsstatus, t0
  hfence.vvma

  LI(a5, va_s_rw)
  LI(t0, 0xBAD00FAD)
  RVTEST_GOTO_LOWER_MODE VUmode
  sw   t0, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  la t1, test_region_s_rw
  lw a4, 0(t1)

  test13_mxr1_srw_sw:
  RVTEST_SIGUPD(x2, x5, x4, a4, test13_mxr1_srw_sw, test13_mxr1_srw_sw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 14: MXR=1 SUM=1 S-page XWR=111 VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma

  LI(a5, va_s_rw)
  LI(s5, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  lw   s5, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test14_mxr1_sum1_srw:
  RVTEST_SIGUPD(x2, x5, x4, s5, test14_mxr1_sum1_srw, test14_mxr1_sum1_srw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 15: MXR=0 SUM=0 S-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)
  csrc sstatus, t0
  csrc vsstatus, t0
  hfence.vvma

  LI(a5, va_x_s)
  LI(t0, 0xBAD00FAD)
  RVTEST_GOTO_LOWER_MODE VUmode
  sw   t0, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  la t1, test_region_x_s
  lw a6, 0(t1)

  test15_xs_sw:
  RVTEST_SIGUPD(x2, x5, x4, a6, test15_xs_sw, test15_xs_sw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 16: MXR=1 SUM=1 U-page X-only VU jalr | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma

  LI(a5, va_x_u)
  LI(s6, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  nop
  jalr ra, a5, 0
  nop
  RVTEST_TSBI_GOTO_MMODE

  test16_xu_jalr:
  RVTEST_SIGUPD(x2, x5, x4, s6, test16_xu_jalr, test16_xu_jalr_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 17: MXR=1 SUM=1 S-page XWR=111 VU jalr | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_rw)
  LI(s7, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  nop
  jalr ra, a5, 0
  nop
  RVTEST_TSBI_GOTO_MMODE

  test17_srw_jalr:
  RVTEST_SIGUPD(x2, x5, x4, s7, test17_srw_jalr, test17_srw_jalr_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 18: MXR=1 SUM=0 U-page XWR=111 VU sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrs sstatus, t0
  csrs vsstatus, t0
  LI(t0, SSTATUS_SUM)
  csrc sstatus, t0
  csrc vsstatus, t0
  hfence.vvma

  LI(a5, va_u_rw)
  LI(t0, 0x257A0612)
  RVTEST_GOTO_LOWER_MODE VUmode
  sw   t0, 0(a5)
  nop
  lw   a3, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test18_mxr1_sum0_urw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test18_mxr1_sum0_urw, test18_mxr1_sum0_urw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 19: MXR=1 SUM=0 S-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x_s)
  LI(s8, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  lw   s8, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test19_mxr1_xs:
  RVTEST_SIGUPD(x2, x5, x4, s8, test19_mxr1_xs, test19_mxr1_xs_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 20: MXR=0 SUM=1 S-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrc sstatus, t0
  csrc vsstatus, t0
  LI(t0, SSTATUS_SUM)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma

  LI(a5, va_x_s)
  LI(t0, 0xBAD00FAD)
  RVTEST_GOTO_LOWER_MODE VUmode
  sw   t0, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  la t1, test_region_x_s
  lw a4, 0(t1)

  test20_sum1_xs_sw:
  RVTEST_SIGUPD(x2, x5, x4, a4, test20_sum1_xs_sw, test20_sum1_xs_sw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 21: MXR=1 SUM=1 U-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma

  LI(a5, va_x_u)
  LI(t0, 0xBAD00FAD)
  RVTEST_GOTO_LOWER_MODE VUmode
  sw   t0, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  la t1, test_region_x_u
  lw a6, 0(t1)

  test21_mxr1_sum1_xu_sw:
  RVTEST_SIGUPD(x2, x5, x4, a6, test21_mxr1_sum1_xu_sw, test21_mxr1_sum1_xu_sw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 22: MXR=1 SUM=1 S-page XWR=111 VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma
  LI(a5, va_s_rw)
  LI(t0, 0xBAD00FAD)
  RVTEST_GOTO_LOWER_MODE VUmode
  sw   t0, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  la t1, test_region_s_rw
  lw a3, 0(t1)

  test22_sum1_srw_sw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test22_sum1_srw_sw, test22_sum1_srw_sw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 23: MXR=0 SUM=0 U-page XWR=111 VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)
  csrc sstatus, t0
  csrc vsstatus, t0
  hfence.vvma
  LI(t0, 0x257A0617)
  la t1, test_region_u_rw
  sw t0, 0(t1)
  LI(a5, va_u_rw)
  LI(a4, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  lw   a4, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test23_sum0_urw_lw:
  RVTEST_SIGUPD(x2, x5, x4, a4, test23_sum0_urw_lw, test23_sum0_urw_lw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 24: MXR=1 SUM=0 U-page XWR=111 VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma
  LI(t0, 0x257A0618)
  la t1, test_region_u_rw
  sw t0, 0(t1)
  LI(a5, va_u_rw)
  LI(a6, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  lw   a6, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test24_mxr1_sum0_urw_lw:
  RVTEST_SIGUPD(x2, x5, x4, a6, test24_mxr1_sum0_urw_lw, test24_mxr1_sum0_urw_lw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 25: MXR=1 SUM=0 S-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma
  LI(a5, va_x_s)
  LI(t0, 0xBAD00FAD)
  RVTEST_GOTO_LOWER_MODE VUmode
  sw   t0, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  la t1, test_region_x_s
  lw a7, 0(t1)

  test25_mxr1_xs_sw:
  RVTEST_SIGUPD(x2, x5, x4, a7, test25_mxr1_xs_sw, test25_mxr1_xs_sw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 26: MXR=1 SUM=1 S-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma
  LI(a5, va_x_s)
  LI(t0, 0xBAD00FAD)
  RVTEST_GOTO_LOWER_MODE VUmode
  sw   t0, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  la t1, test_region_x_s
  lw s2, 0(t1)

  test26_mxr1_sum1_xs_sw:
  RVTEST_SIGUPD(x2, x5, x4, s2, test26_mxr1_sum1_xs_sw, test26_mxr1_sum1_xs_sw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 27: MXR=0 SUM=1 U-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrc sstatus, t0
  csrc vsstatus, t0
  hfence.vvma
  LI(a5, va_x_u)
  LI(t0, 0xBAD00FAD)
  RVTEST_GOTO_LOWER_MODE VUmode
  sw   t0, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  la t1, test_region_x_u
  lw s3, 0(t1)

  test27_sum1_xu_sw:
  RVTEST_SIGUPD(x2, x5, x4, s3, test27_sum1_xu_sw, test27_sum1_xu_sw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 28: MXR=0 SUM=1 S-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma
  LI(a5, va_x_s)
  LI(s4, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  lw   s4, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test28_sum1_xs_lw:
  RVTEST_SIGUPD(x2, x5, x4, s4, test28_sum1_xs_lw, test28_sum1_xs_lw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 29: MXR=1 SUM=1 U-page X-only VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma
  LI(a5, va_x_u)
  LI(s5, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  lw   s5, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test29_mxr1_sum1_xu_lw:
  RVTEST_SIGUPD(x2, x5, x4, s5, test29_mxr1_sum1_xu_lw, test29_mxr1_sum1_xu_lw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 30: MXR=0 SUM=0 U-page XWR=111 VU jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)
  csrc sstatus, t0
  csrc vsstatus, t0
  hfence.vvma
  LI(t0, 0x00008067)
  la t1, test_region_u_rw
  sw t0, 0(t1)
  LI(a5, va_u_rw)
  LI(s6, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  nop
  jalr ra, a5, 0
  LI(s6, 0x257A061E)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test30_urw_jalr:
  RVTEST_SIGUPD(x2, x5, x4, s6, test30_urw_jalr, test30_urw_jalr_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 31: MXR=1 SUM=0 U-page X-only VU jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrs sstatus, t0
  csrs vsstatus, t0
  LI(t0, SSTATUS_SUM)
  csrc sstatus, t0
  csrc vsstatus, t0
  hfence.vvma
  LI(t0, 0x00008067)
  la t1, test_region_x_u
  sw t0, 0(t1)
  LI(a5, va_x_u)
  LI(s7, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  nop
  jalr ra, a5, 0
  LI(s7, 0x257A061F)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test31_xu_jalr_ok:
  RVTEST_SIGUPD(x2, x5, x4, s7, test31_xu_jalr_ok, test31_xu_jalr_ok_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 32: MXR=0 SUM=1 U-page XWR=111 VU jalr | Expected: Successful (pad unset/set×rwx111_u exec)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrc sstatus, t0
  csrc vsstatus, t0
  LI(t0, SSTATUS_SUM)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma
  LI(t0, 0x00008067)
  la t1, test_region_u_rw
  sw t0, 0(t1)
  LI(a5, va_u_rw)
  LI(s8, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  nop
  jalr ra, a5, 0
  LI(s8, 0x257A0620)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test32_sum1_urw_jalr:
  RVTEST_SIGUPD(x2, x5, x4, s8, test32_sum1_urw_jalr, test32_sum1_urw_jalr_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 33: MXR=0 SUM=1 S-page XWR=111 VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrc sstatus, t0
  csrc vsstatus, t0
  LI(t0, SSTATUS_SUM)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma
  LI(a5, va_s_rw)
  LI(t0, 0xBAD00FAD)
  RVTEST_GOTO_LOWER_MODE VUmode
  sw   t0, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  la t1, test_region_s_rw
  lw a3, 0(t1)

  test33_sum1_mxr0_srw_sw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test33_sum1_mxr0_srw_sw, test33_sum1_mxr0_srw_sw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 34: MXR=1 SUM=0 U-page X-only VU sw (fenced) | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)
  csrs sstatus, t0
  csrs vsstatus, t0
  LI(t0, SSTATUS_SUM)
  csrc sstatus, t0
  csrc vsstatus, t0
  hfence.vvma
  LI(a5, va_x_u)
  LI(t0, 0xBAD00FAD)
  RVTEST_GOTO_LOWER_MODE VUmode
  sw   t0, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  la t1, test_region_x_u
  // restore ret for later if overwritten — SPA should stay preload/ret
  lw a4, 0(t1)

  test34_mxr1_xu_sw2:
  RVTEST_SIGUPD(x2, x5, x4, a4, test34_mxr1_xu_sw2, test34_mxr1_xu_sw2_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 35: MXR=1 SUM=0 S-page XWR=111 VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma
  LI(a5, va_s_rw)
  LI(a6, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  lw   a6, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test35_mxr1_sum0_srw_lw:
  RVTEST_SIGUPD(x2, x5, x4, a6, test35_mxr1_sum0_srw_lw, test35_mxr1_sum0_srw_lw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 36: MXR=1 SUM=1 U-page XWR=111 VU lw only | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma
  LI(t0, 0x257A0624)
  la t1, test_region_u_rw
  sw t0, 0(t1)
  LI(a5, va_u_rw)
  LI(a7, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  lw   a7, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test36_mxr1_sum1_urw_lw:
  RVTEST_SIGUPD(x2, x5, x4, a7, test36_mxr1_sum1_urw_lw, test36_mxr1_sum1_urw_lw_str)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 37: MXR=1 SUM=1 U-page XWR=111 VU jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma
  LI(t0, 0x00008067)
  la t1, test_region_u_rw
  sw t0, 0(t1)
  LI(a5, va_u_rw)
  LI(s2, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  nop
  jalr ra, a5, 0
  LI(s2, 0x257A0625)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test37_mxr1_sum1_urw_jalr:
  RVTEST_SIGUPD(x2, x5, x4, s2, test37_mxr1_sum1_urw_jalr, test37_mxr1_sum1_urw_jalr_str)

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

.align 12
test_region_x_s:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
test_region_x_u:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
test_region_u_rw:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
test_region_s_rw:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
rvtest_vlvl1_pg_tbl:
  .zero(4096)
.align 12
rvtest_vlvl0_pg_tbl:
  .zero(4096)

test1_mxr0_xu_str:       .string "\"Mismatch on MXR=0 U X-only VU lw (expect fault) in Test Case 1!\""
test2_mxr1_xu_lw_str:    .string "\"Mismatch on MXR=1 U X-only VU lw in Test Case 2!\""
test3_mxr1_xu_sw_str:    .string "\"Mismatch on MXR=1 U X-only VU sw (expect fault) in Test Case 3!\""
test4_sum1_urw_lw_str:   .string "\"Mismatch on SUM=1 U RWX VU lw in Test Case 4!\""
test5_sum1_urw_swlw_str: .string "\"Mismatch on SUM=1 U RWX VU sw+lw in Test Case 5!\""
test6_sum0_urw_swlw_str: .string "\"Mismatch on SUM=0 U RWX VU sw+lw in Test Case 6!\""
test7_srw_lw_str:        .string "\"Mismatch on S RWX VU lw (expect fault) in Test Case 7!\""
test8_mxr1_sum1_xs_str:  .string "\"Mismatch on MXR=1 SUM=1 S X-only VU lw (expect fault) in Test Case 8!\""
test9_sum1_srw_str:      .string "\"Mismatch on SUM=1 S RWX VU lw (expect fault) in Test Case 9!\""
test10_sum0_xs_str:      .string "\"Mismatch on SUM=0 S X-only VU lw (expect fault) in Test Case 10!\""
test11_sum1_mxr0_xu_str: .string "\"Mismatch on SUM=1 MXR=0 U X-only VU lw (expect fault) in Test Case 11!\""
test12_sum1_mxr0_urw_sw_str: .string "\"Mismatch on SUM=1 MXR=0 U RWX VU sw+lw in Test Case 12!\""
test13_mxr1_srw_sw_str:  .string "\"Mismatch on MXR=1 S RWX VU sw (expect fault) in Test Case 13!\""
test14_mxr1_sum1_srw_str:.string "\"Mismatch on MXR=1 SUM=1 S RWX VU lw (expect fault) in Test Case 14!\""
test15_xs_sw_str:        .string "\"Mismatch on S X-only VU sw (expect fault) in Test Case 15!\""
test16_xu_jalr_str:      .string "\"Mismatch on U X-only VU jalr (expect fault) in Test Case 16!\""
test17_srw_jalr_str:     .string "\"Mismatch on S RWX VU jalr (expect fault) in Test Case 17!\""
test18_mxr1_sum0_urw_str:.string "\"Mismatch on MXR=1 SUM=0 U RWX VU sw+lw in Test Case 18!\""
test19_mxr1_xs_str:      .string "\"Mismatch on MXR=1 S X-only VU lw (expect fault) in Test Case 19!\""
test20_sum1_xs_sw_str:   .string "\"Mismatch on SUM=1 S X-only VU sw (expect fault) in Test Case 20!\""
test21_mxr1_sum1_xu_sw_str: .string "\"Mismatch on MXR=1 SUM=1 U X-only VU sw (expect fault) in Test Case 21!\""
test22_sum1_srw_sw_str:     .string "\"Mismatch on SUM=1 S RWX VU sw (expect fault) in Test Case 22!\""
test23_sum0_urw_lw_str:     .string "\"Mismatch on SUM=0 U RWX VU lw in Test Case 23!\""
test24_mxr1_sum0_urw_lw_str:.string "\"Mismatch on MXR=1 SUM=0 U RWX VU lw in Test Case 24!\""
test25_mxr1_xs_sw_str:      .string "\"Mismatch on MXR=1 S X-only VU sw (expect fault) in Test Case 25!\""
test26_mxr1_sum1_xs_sw_str: .string "\"Mismatch on MXR=1 SUM=1 S X-only VU sw (expect fault) in Test Case 26!\""
test27_sum1_xu_sw_str:      .string "\"Mismatch on SUM=1 U X-only VU sw (expect fault) in Test Case 27!\""
test28_sum1_xs_lw_str:      .string "\"Mismatch on SUM=1 S X-only VU lw (expect fault) in Test Case 28!\""
test29_mxr1_sum1_xu_lw_str: .string "\"Mismatch on MXR=1 SUM=1 U X-only VU lw in Test Case 29!\""
test30_urw_jalr_str:        .string "\"Mismatch on SUM=0 U RWX VU jalr in Test Case 30!\""
test31_xu_jalr_ok_str:      .string "\"Mismatch on MXR=1 U X-only VU jalr in Test Case 31!\""
test32_sum1_urw_jalr_str:   .string "\"Mismatch on SUM=1 U RWX VU jalr in Test Case 32!\""
test33_sum1_mxr0_srw_sw_str:.string "\"Mismatch on SUM=1 MXR=0 S RWX VU sw (expect fault) in Test Case 33!\""
test34_mxr1_xu_sw2_str:     .string "\"Mismatch on MXR=1 U X-only VU sw (expect fault) in Test Case 34!\""
test35_mxr1_sum0_srw_lw_str:.string "\"Mismatch on MXR=1 SUM=0 S RWX VU lw (expect fault) in Test Case 35!\""
test36_mxr1_sum1_urw_lw_str:.string "\"Mismatch on MXR=1 SUM=1 U RWX VU lw in Test Case 36!\""
test37_mxr1_sum1_urw_jalr_str: .string "\"Mismatch on MXR=1 SUM=1 U RWX VU jalr in Test Case 37!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
