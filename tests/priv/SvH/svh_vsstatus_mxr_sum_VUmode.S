// --------------------------------------------------------------------------------------------------------------------------------
// svh_vsstatus_mxr_sum_VUmode.S
// Config: sail-rv32-max | VS=Sv32 ON, hgatp=Bare, stimulus in VU
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
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vsstatus_mxr_sum_VUmode.S"
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
  .set va_code, 0x90000000                      // GVA where VU executes this code (needs U=1)

  // ---- VS-stage (vsatp Sv32): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  // VU ifetch requires U=1 on the code leaf (unlike VS which uses U=0).
  SUPERPAGE_VS_PTE_SETUP(sv32, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // VS-stage superpage: code GVA → PA/GPA

  csrr a0, mscratch                             // a0 = Msave_area (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: VU entry PC under va_code

  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_x_s, LEVEL1)  // non-leaf: data VPN1 -> VS L0

  VS_PTE_SETUP(sv32, PA, test_region_x_s, (PTE_D | PTE_A | PTE_X | PTE_V), va_x_s, LEVEL0)  // S X-only
  VS_PTE_SETUP(sv32, PA, test_region_x_u, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V), va_x_u, LEVEL0)  // U X-only
  VS_PTE_SETUP(sv32, PA, test_region_u_rw, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), va_u_rw, LEVEL0)  // VS leaf U=1 XWR=111 (U-page for MXR/SUM)
  VS_PTE_SETUP(sv32, PA, test_region_s_rw, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V), va_s_rw, LEVEL0)  // VS leaf U=0 XWR=111 (S-page; VU must fault)

  VSATP_SETUP(sv32, PA)                         // turn on VS-stage paging (vsatp MODE + root PPN)
  csrw hgatp, x0                                // write hgatp (hypervisor page-table root / Bare if x0)
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0xDEADBEEF)                            // SPA pattern for U-page X-only (case 2 MXR=1 load)
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0604)                            // SPA pattern / store value for case setup (0x257A0604)
  la t1, test_region_u_rw                       // t1 = SPA of U-page RWX region
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)
  LI(t0, 0x257A060A)                            // SPA pattern / store value for case setup (0x257A060A)
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0601)                            // SPA pattern / store value for case setup (0x257A0601)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: MXR=0 SUM=0 U-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(a3, 0)                                     // sentinel — a3 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VUmode mret + PA↔VA relocate (U=1 code)
  lw   a3, 0(a5)                                // X-only without MXR → load-page-fault
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test1_mxr0_xu:                                // signature dump point for case 1
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_mxr0_xu, test1_mxr0_xu_str)  // signature: dump a3 (test1_mxr0_xu) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: MXR=1 SUM=0 U-page X-only VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(a4, 0)                                     // a4 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a4, 0(a5)                                // MXR=1 makes U X-only readable; expect 0xDEADBEEF
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test2_mxr1_xu_lw:                             // signature dump point for case 2
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_mxr1_xu_lw, test2_mxr1_xu_lw_str)  // signature: dump a4 (test2_mxr1_xu_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: MXR=1 SUM=0 U-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xBAD00FAD)                            // must not overwrite 0xDEADBEEF preload
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // X-only has no W → store-page-fault
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  lw a3, 0(t1)                                  // expect 0xDEADBEEF still
  test3_mxr1_xu_sw:                             // signature dump point for case 3
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_mxr1_xu_sw, test3_mxr1_xu_sw_str)  // signature: dump a3 (test3_mxr1_xu_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: MXR=0 SUM=1 U-page XWR=111 VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(a4, 0)                                     // a4 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a4, 0(a5)                                // U-page R bit; expect 0x257A0604
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test4_sum1_urw_lw:                            // signature dump point for case 4
  RVTEST_SIGUPD(x2, x5, x4, a4, test4_sum1_urw_lw, test4_sum1_urw_lw_str)  // signature: dump a4 (test4_sum1_urw_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: MXR=1 SUM=1 U-page XWR=111 VU sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(t0, 0x257A0605)                            // SPA pattern / store value for case 5 (0x257A0605)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // guest store through current PTE perms
  nop                                           // trap-skip padding after store
  lw   a6, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test5_sum1_urw_swlw:                          // signature dump point for case 5
  RVTEST_SIGUPD(x2, x5, x4, a6, test5_sum1_urw_swlw, test5_sum1_urw_swlw_str)  // signature: dump a6 (test5_sum1_urw_swlw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: MXR=0 SUM=0 U-page XWR=111 VU sw+lw | Expected: Successful
// (Unlike VS, VU may access U=1 pages with SUM=0.)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(t0, 0x257A0606)                            // SPA pattern / store value for case 6 (0x257A0606)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // guest store through current PTE perms
  nop                                           // trap-skip padding after store
  lw   a3, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test6_sum0_urw_swlw:                          // signature dump point for case 6
  RVTEST_SIGUPD(x2, x5, x4, a3, test6_sum0_urw_swlw, test6_sum0_urw_swlw_str)  // signature: dump a3 (test6_sum0_urw_swlw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: MXR=0 SUM=0 S-page XWR=111 VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(a6, 0)                                     // sentinel — a6 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a6, 0(a5)                                // VU cannot use U=0 pages
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test7_srw_lw:                                 // signature dump point for case 7
  RVTEST_SIGUPD(x2, x5, x4, a6, test7_srw_lw, test7_srw_lw_str)  // signature: dump a6 (test7_srw_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: MXR=1 SUM=1 S-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(a7, 0)                                     // sentinel — a7 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a7, 0(a5)                                // S-page still blocked in VU
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test8_mxr1_sum1_xs:                           // signature dump point for case 8
  RVTEST_SIGUPD(x2, x5, x4, a7, test8_mxr1_sum1_xs, test8_mxr1_sum1_xs_str)  // signature: dump a7 (test8_mxr1_sum1_xs) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 9: MXR=0 SUM=1 S-page XWR=111 VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrc sstatus, t0                              // clear HS MXR
  csrc vsstatus, t0                             // clear VS MXR — guest sees these
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s2, 0)                                     // sentinel — s2 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   s2, 0(a5)                                // VU load from S-page RWX: MXR=0 SUM=1 → load-page-fault (VU cannot use U=0 S-page); s2 stays 0
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test9_sum1_srw:                               // signature dump point for case 9
  RVTEST_SIGUPD(x2, x5, x4, s2, test9_sum1_srw, test9_sum1_srw_str)  // dump s2 (case 9; expect 0 / fault sentinel)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 10: MXR=0 SUM=0 S-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear HS MXR and SUM
  csrc vsstatus, t0                             // clear VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(s3, 0)                                     // sentinel — s3 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   s3, 0(a5)                                // VU load from S-page X-only: MXR=0 SUM=0 → load-page-fault (VU cannot use U=0 S-page); s3 stays 0
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test10_sum0_xs:                               // signature dump point for case 10
  RVTEST_SIGUPD(x2, x5, x4, s3, test10_sum0_xs, test10_sum0_xs_str)  // dump s3 (case 10; expect 0 / fault sentinel)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 11: MXR=0 SUM=1 U-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(s4, 0)                                     // sentinel — s4 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   s4, 0(a5)                                // VU load from U-page X-only: MXR=0 SUM=1 → load-page-fault (X-only without MXR); s4 stays 0
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test11_sum1_mxr0_xu:                          // signature dump point for case 11
  RVTEST_SIGUPD(x2, x5, x4, s4, test11_sum1_mxr0_xu, test11_sum1_mxr0_xu_str)  // dump s4 (case 11; expect 0 / fault sentinel)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 12: MXR=0 SUM=1 U-page XWR=111 VU sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(t0, 0x257A060C)                            // SPA pattern / store value for case 12 (0x257A060C)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // VU store to U-page RWX: MXR=0 SUM=1 → success (W allowed)
  nop                                           // trap-skip padding after store
  lw   a3, 0(a5)                                // VU load from U-page RWX: MXR=0 SUM=1 → success
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test12_sum1_mxr0_urw_sw:                      // signature dump point for case 12
  RVTEST_SIGUPD(x2, x5, x4, a3, test12_sum1_mxr0_urw_sw, test12_sum1_mxr0_urw_sw_str)  // dump a3 (case 12 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 13: MXR=1 SUM=0 S-page XWR=111 VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — guest sees these
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrc sstatus, t0                              // clear HS SUM
  csrc vsstatus, t0                             // clear VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // VU store to S-page RWX: MXR=1 SUM=0 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  lw a4, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page RWX region)

  test13_mxr1_srw_sw:                           // signature dump point for case 13
  RVTEST_SIGUPD(x2, x5, x4, a4, test13_mxr1_srw_sw, test13_mxr1_srw_sw_str)  // dump a4 SPA (case 13; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 14: MXR=1 SUM=1 S-page XWR=111 VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s5, 0)                                     // sentinel — s5 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   s5, 0(a5)                                // VU load from S-page RWX: MXR=1 SUM=1 → load-page-fault (VU cannot use U=0 S-page); s5 stays 0
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test14_mxr1_sum1_srw:                         // signature dump point for case 14
  RVTEST_SIGUPD(x2, x5, x4, s5, test14_mxr1_sum1_srw, test14_mxr1_sum1_srw_str)  // dump s5 (case 14; expect 0 / fault sentinel)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 15: MXR=0 SUM=0 S-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear HS MXR and SUM
  csrc vsstatus, t0                             // clear VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // VU store to S-page X-only: MXR=0 SUM=0 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  lw a6, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page X-only region)

  test15_xs_sw:                                 // signature dump point for case 15
  RVTEST_SIGUPD(x2, x5, x4, a6, test15_xs_sw, test15_xs_sw_str)  // dump a6 SPA (case 15; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 16: MXR=1 SUM=1 U-page X-only VU jalr | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrs sstatus, t0                              // set HS MXR and SUM
  csrs vsstatus, t0                             // set VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(s6, 0)                                     // sentinel — s6 stays 0 if target never runs
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  nop                                           // pad so priv_mode samples prev=VU on jalr
  jalr ra, a5, 0                                // VU ifetch of U-page X-only: MXR=1 SUM=1 → fetch-page-fault (permission deny)
  nop                                           // trap-skip padding after faulting jalr (not reached)
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test16_xu_jalr:                               // signature dump point for case 16
  RVTEST_SIGUPD(x2, x5, x4, s6, test16_xu_jalr, test16_xu_jalr_str)  // dump s6 (case 16; expect 0 / fault sentinel)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 17: MXR=1 SUM=1 S-page XWR=111 VU jalr | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s7, 0)                                     // sentinel — s7 stays 0 if target never runs
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  nop                                           // pad so priv_mode samples prev=VU on jalr
  jalr ra, a5, 0                                // VU ifetch of S-page RWX: MXR=1 SUM=1 → fetch-page-fault (VU cannot fetch U=0 S-page)
  nop                                           // trap-skip padding after faulting jalr (not reached)
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test17_srw_jalr:                              // signature dump point for case 17
  RVTEST_SIGUPD(x2, x5, x4, s7, test17_srw_jalr, test17_srw_jalr_str)  // dump s7 (case 17; expect 0 / fault sentinel)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 18: MXR=1 SUM=0 U-page XWR=111 VU sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — guest sees these
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrc sstatus, t0                              // clear HS SUM
  csrc vsstatus, t0                             // clear VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(t0, 0x257A0612)                            // SPA pattern / store value for case 18 (0x257A0612)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // VU store to U-page RWX: MXR=1 SUM=0 → success (W allowed)
  nop                                           // trap-skip padding after store
  lw   a3, 0(a5)                                // VU load from U-page RWX: MXR=1 SUM=0 → success
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test18_mxr1_sum0_urw:                         // signature dump point for case 18
  RVTEST_SIGUPD(x2, x5, x4, a3, test18_mxr1_sum0_urw, test18_mxr1_sum0_urw_str)  // dump a3 (case 18 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 19: MXR=1 SUM=0 S-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(s8, 0)                                     // sentinel — s8 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   s8, 0(a5)                                // VU load from S-page X-only: MXR=1 SUM=0 → load-page-fault (VU cannot use U=0 S-page); s8 stays 0
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test19_mxr1_xs:                               // signature dump point for case 19
  RVTEST_SIGUPD(x2, x5, x4, s8, test19_mxr1_xs, test19_mxr1_xs_str)  // dump s8 (case 19; expect 0 / fault sentinel)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 20: MXR=0 SUM=1 S-page X-only VU sw | Expected: Expected Fault
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
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // VU store to S-page X-only: MXR=0 SUM=1 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  lw a4, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page X-only region)

  test20_sum1_xs_sw:                            // signature dump point for case 20
  RVTEST_SIGUPD(x2, x5, x4, a4, test20_sum1_xs_sw, test20_sum1_xs_sw_str)  // dump a4 SPA (case 20; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 21: MXR=1 SUM=1 U-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrs sstatus, t0                              // set HS MXR and SUM
  csrs vsstatus, t0                             // set VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // VU store to U-page X-only: MXR=1 SUM=1 → store-page-fault (no W)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  lw a6, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page X-only region)

  test21_mxr1_sum1_xu_sw:                       // signature dump point for case 21
  RVTEST_SIGUPD(x2, x5, x4, a6, test21_mxr1_sum1_xu_sw, test21_mxr1_sum1_xu_sw_str)  // dump a6 SPA (case 21; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 22: MXR=1 SUM=1 S-page XWR=111 VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrs sstatus, t0                              // set HS MXR and SUM
  csrs vsstatus, t0                             // set VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // VU store to S-page RWX: MXR=1 SUM=1 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  lw a3, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page RWX region)

  test22_sum1_srw_sw:                           // signature dump point for case 22
  RVTEST_SIGUPD(x2, x5, x4, a3, test22_sum1_srw_sw, test22_sum1_srw_sw_str)  // dump a3 SPA (case 22; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 23: MXR=0 SUM=0 U-page XWR=111 VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear HS MXR and SUM
  csrc vsstatus, t0                             // clear VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x257A0617)                            // SPA pattern / store value for case 23 (0x257A0617)
  la t1, test_region_u_rw                       // t1 = SPA of U-page RWX region
  sw t0, 0(t1)                                  // M-mode preload/write at SPA of U-page RWX region (case 23)
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(a4, 0)                                     // a4 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a4, 0(a5)                                // VU load from U-page RWX: MXR=0 SUM=0 → success
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test23_sum0_urw_lw:                           // signature dump point for case 23
  RVTEST_SIGUPD(x2, x5, x4, a4, test23_sum0_urw_lw, test23_sum0_urw_lw_str)  // dump a4 (case 23 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 24: MXR=1 SUM=0 U-page XWR=111 VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x257A0618)                            // SPA pattern / store value for case 24 (0x257A0618)
  la t1, test_region_u_rw                       // t1 = SPA of U-page RWX region
  sw t0, 0(t1)                                  // M-mode preload/write at SPA of U-page RWX region (case 24)
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(a6, 0)                                     // a6 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a6, 0(a5)                                // VU load from U-page RWX: MXR=1 SUM=0 → success
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test24_mxr1_sum0_urw_lw:                      // signature dump point for case 24
  RVTEST_SIGUPD(x2, x5, x4, a6, test24_mxr1_sum0_urw_lw, test24_mxr1_sum0_urw_lw_str)  // dump a6 (case 24 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 25: MXR=1 SUM=0 S-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // VU store to S-page X-only: MXR=1 SUM=0 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  lw a7, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page X-only region)

  test25_mxr1_xs_sw:                            // signature dump point for case 25
  RVTEST_SIGUPD(x2, x5, x4, a7, test25_mxr1_xs_sw, test25_mxr1_xs_sw_str)  // dump a7 SPA (case 25; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 26: MXR=1 SUM=1 S-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // VU store to S-page X-only: MXR=1 SUM=1 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  lw s2, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page X-only region)

  test26_mxr1_sum1_xs_sw:                       // signature dump point for case 26
  RVTEST_SIGUPD(x2, x5, x4, s2, test26_mxr1_sum1_xs_sw, test26_mxr1_sum1_xs_sw_str)  // dump s2 SPA (case 26; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 27: MXR=0 SUM=1 U-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrc sstatus, t0                              // clear HS MXR
  csrc vsstatus, t0                             // clear VS MXR — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // VU store to U-page X-only: MXR=0 SUM=1 → store-page-fault (no W)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  lw s3, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page X-only region)

  test27_sum1_xu_sw:                            // signature dump point for case 27
  RVTEST_SIGUPD(x2, x5, x4, s3, test27_sum1_xu_sw, test27_sum1_xu_sw_str)  // dump s3 SPA (case 27; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 28: MXR=0 SUM=1 S-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(s4, 0)                                     // sentinel — s4 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   s4, 0(a5)                                // VU load from S-page X-only: MXR=0 SUM=1 → load-page-fault (VU cannot use U=0 S-page); s4 stays 0
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test28_sum1_xs_lw:                            // signature dump point for case 28
  RVTEST_SIGUPD(x2, x5, x4, s4, test28_sum1_xs_lw, test28_sum1_xs_lw_str)  // dump s4 (case 28; expect 0 / fault sentinel)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 29: MXR=1 SUM=1 U-page X-only VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(s5, 0)                                     // s5 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   s5, 0(a5)                                // VU load from U-page X-only: MXR=1 SUM=1 → success; MXR makes X readable
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test29_mxr1_sum1_xu_lw:                       // signature dump point for case 29
  RVTEST_SIGUPD(x2, x5, x4, s5, test29_mxr1_sum1_xu_lw, test29_mxr1_sum1_xu_lw_str)  // dump s5 (case 29 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 30: MXR=0 SUM=0 U-page XWR=111 VU jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear HS MXR and SUM
  csrc vsstatus, t0                             // clear VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x00008067)                            // encoding of ret (jalr x0, ra, 0) trampoline
  la t1, test_region_u_rw                       // t1 = SPA of U-page RWX region
  sw t0, 0(t1)                                  // write ret trampoline at SPA of U-page RWX region
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(s6, 0)                                     // s6 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  nop                                           // pad so priv_mode samples prev=VU on jalr
  jalr ra, a5, 0                                // VU ifetch of U-page RWX: MXR=0 SUM=0 → success (X allowed); ret trampoline returns
  LI(s6, 0x257A061E)                            // magic proving jalr returned (case 30)
  nop                                           // trap-skip padding
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test30_urw_jalr:                              // signature dump point for case 30
  RVTEST_SIGUPD(x2, x5, x4, s6, test30_urw_jalr, test30_urw_jalr_str)  // dump s6 (case 30 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 31: MXR=1 SUM=0 U-page X-only VU jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — guest sees these
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrc sstatus, t0                              // clear HS SUM
  csrc vsstatus, t0                             // clear VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x00008067)                            // encoding of ret (jalr x0, ra, 0) trampoline
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  sw t0, 0(t1)                                  // write ret trampoline at SPA of U-page X-only region
  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(s7, 0)                                     // s7 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  nop                                           // pad so priv_mode samples prev=VU on jalr
  jalr ra, a5, 0                                // VU ifetch of U-page X-only: MXR=1 SUM=0 → success (X allowed); ret trampoline returns
  LI(s7, 0x257A061F)                            // magic proving jalr returned (case 31)
  nop                                           // trap-skip padding
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test31_xu_jalr_ok:                            // signature dump point for case 31
  RVTEST_SIGUPD(x2, x5, x4, s7, test31_xu_jalr_ok, test31_xu_jalr_ok_str)  // dump s7 (case 31 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 32: MXR=0 SUM=1 U-page XWR=111 VU jalr | Expected: Successful (pad unset/set×rwx111_u exec)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrc sstatus, t0                              // clear HS MXR
  csrc vsstatus, t0                             // clear VS MXR — guest sees these
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x00008067)                            // encoding of ret (jalr x0, ra, 0) trampoline
  la t1, test_region_u_rw                       // t1 = SPA of U-page RWX region
  sw t0, 0(t1)                                  // write ret trampoline at SPA of U-page RWX region
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(s8, 0)                                     // s8 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  nop                                           // pad so priv_mode samples prev=VU on jalr
  jalr ra, a5, 0                                // VU ifetch of U-page RWX: MXR=0 SUM=1 → success (X allowed); ret trampoline returns
  LI(s8, 0x257A0620)                            // magic proving jalr returned (case 32)
  nop                                           // trap-skip padding
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test32_sum1_urw_jalr:                         // signature dump point for case 32
  RVTEST_SIGUPD(x2, x5, x4, s8, test32_sum1_urw_jalr, test32_sum1_urw_jalr_str)  // dump s8 (case 32 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 33: MXR=0 SUM=1 S-page XWR=111 VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrc sstatus, t0                              // clear HS MXR
  csrc vsstatus, t0                             // clear VS MXR — guest sees these
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // VU store to S-page RWX: MXR=0 SUM=1 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  lw a3, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page RWX region)

  test33_sum1_mxr0_srw_sw:                      // signature dump point for case 33
  RVTEST_SIGUPD(x2, x5, x4, a3, test33_sum1_mxr0_srw_sw, test33_sum1_mxr0_srw_sw_str)  // dump a3 SPA (case 33; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 34: MXR=1 SUM=0 U-page X-only VU sw (fenced) | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — guest sees these
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrc sstatus, t0                              // clear HS SUM
  csrc vsstatus, t0                             // clear VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // VU store to U-page X-only: MXR=1 SUM=0 → store-page-fault (no W)
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  // restore ret for later if overwritten — SPA should stay preload/ret
  lw a4, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page X-only region)

  test34_mxr1_xu_sw2:                           // signature dump point for case 34
  RVTEST_SIGUPD(x2, x5, x4, a4, test34_mxr1_xu_sw2, test34_mxr1_xu_sw2_str)  // dump a4 SPA (case 34; expect preload unchanged)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 35: MXR=1 SUM=0 S-page XWR=111 VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(a6, 0)                                     // sentinel — a6 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a6, 0(a5)                                // VU load from S-page RWX: MXR=1 SUM=0 → load-page-fault (VU cannot use U=0 S-page); a6 stays 0
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test35_mxr1_sum0_srw_lw:                      // signature dump point for case 35
  RVTEST_SIGUPD(x2, x5, x4, a6, test35_mxr1_sum0_srw_lw, test35_mxr1_sum0_srw_lw_str)  // dump a6 (case 35; expect 0 / fault sentinel)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 36: MXR=1 SUM=1 U-page XWR=111 VU lw only | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrs sstatus, t0                              // set HS MXR and SUM
  csrs vsstatus, t0                             // set VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x257A0624)                            // SPA pattern / store value for case 36 (0x257A0624)
  la t1, test_region_u_rw                       // t1 = SPA of U-page RWX region
  sw t0, 0(t1)                                  // M-mode preload/write at SPA of U-page RWX region (case 36)
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(a7, 0)                                     // a7 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a7, 0(a5)                                // VU load from U-page RWX: MXR=1 SUM=1 → success
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test36_mxr1_sum1_urw_lw:                      // signature dump point for case 36
  RVTEST_SIGUPD(x2, x5, x4, a7, test36_mxr1_sum1_urw_lw, test36_mxr1_sum1_urw_lw_str)  // dump a7 (case 36 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 37: MXR=1 SUM=1 U-page XWR=111 VU jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x00008067)                            // encoding of ret (jalr x0, ra, 0) trampoline
  la t1, test_region_u_rw                       // t1 = SPA of U-page RWX region
  sw t0, 0(t1)                                  // write ret trampoline at SPA of U-page RWX region
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(s2, 0)                                     // s2 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  nop                                           // pad so priv_mode samples prev=VU on jalr
  jalr ra, a5, 0                                // VU ifetch of U-page RWX: MXR=1 SUM=1 → success (X allowed); ret trampoline returns
  LI(s2, 0x257A0625)                            // magic proving jalr returned (case 37)
  nop                                           // trap-skip padding
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test37_mxr1_sum1_urw_jalr:                    // signature dump point for case 37
  RVTEST_SIGUPD(x2, x5, x4, s2, test37_mxr1_sum1_urw_jalr, test37_mxr1_sum1_urw_jalr_str)  // dump s2 (case 37 result) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

.align 12                                       // 4 KiB page align
test_region_x_s:                                // SPA backing va_x_s (S-page X-only)
  .word 0                                       // data word (initially 0 / preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_x_u:                                // SPA backing va_x_u (U-page X-only)
  .word 0                                       // data word (initially 0 / preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_u_rw:                               // SPA backing va_u_rw (U-page RWX)
  .word 0                                       // data word (initially 0 / preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_s_rw:                               // SPA backing va_s_rw (S-page RWX)
  .word 0                                       // data word (initially 0 / preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page

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
