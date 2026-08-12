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

// Mode hops (T-SBI) — return-to-M always uses RVTEST_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VUMODE (ecall a0=5)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE VUmode
#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set va_x_u,  0x008002000                     // GVA: U-page X-only leaf
  .set va_u_rw, 0x008003000                     // GVA: U-page R/W/X leaf
  .set va_s_rw, 0x008004000                     // GVA: S-page R/W/X leaf (VU must fault)
  .set va_x_s,  0x008001000                     // GVA: S-page X-only leaf (VU must fault)
  .set va_code,                 0x0000000090000000      // GVA where guest executes this code

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- VS-stage (vsatp Sv39): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)  // VS non-leaf: va_code VPN2 → L1 table PA(rvtest_vlvl1_pg_tbl) V=1
  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // leaf: va_code -> PA(code); LEVEL1 megapage X/R

  csrr a0, mscratch                             // a0 = Msave_area (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: entry PC under va_code

  // Shared L2+L1 non-leafs (same VPN2/VPN1 for all data VAs under 0x00800x000)
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_x_s, LEVEL2)  // VS non-leaf: va_x_s VPN2 → L1 table PA(rvtest_vlvl1_pg_tbl) V=1
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_x_s, LEVEL1)  // non-leaf: data VPN1 -> VS L0 table PA

  VS_PTE_SETUP(sv39, PA, test_region_x_s, (PTE_D | PTE_A | PTE_X | PTE_V), va_x_s, LEVEL0)  // S X-only
  VS_PTE_SETUP(sv39, PA, test_region_x_u, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V), va_x_u, LEVEL0)  // U X-only
  VS_PTE_SETUP(sv39, PA, test_region_u_rw, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), va_u_rw, LEVEL0)  // VS leaf U=1 XWR=111 (U-page for MXR/SUM)
  VS_PTE_SETUP(sv39, PA, test_region_s_rw, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V), va_s_rw, LEVEL0)  // VS leaf U=0 XWR=111 (S-page; VU must fault)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv39, PA)                         // turn on VS-stage paging (vsatp MODE + root PPN)
  csrw hgatp, x0                                // write hgatp (hypervisor page-table root / Bare if x0)
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0xDEADBEEF)                        // preload SPA
  la t1, test_region_x_u                    // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0604)                        // preload SPA
  la t1, test_region_u_rw                   // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A060A)                        // preload SPA
  la t1, test_region_s_rw                   // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0601)                        // preload SPA
  la t1, test_region_x_s                    // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: MXR=0 SUM=0 U-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(a3, 0)                                     // sentinel — a3 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a3, 0(a5)                                // X-only without MXR → load-page-fault
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test1_mxr0_xu:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_mxr0_xu, test1_mxr0_xu_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: MXR=1 SUM=0 U-page X-only VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(a4, 0)                                     // a4 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a4, 0(a5)                                // MXR=1 makes U X-only readable; expect 0xDEADBEEF
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test2_mxr1_xu_lw:                                // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_mxr1_xu_lw, test2_mxr1_xu_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: MXR=1 SUM=0 U-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xBAD00FAD)                            // must not overwrite 0xDEADBEEF preload
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // X-only has no W → store-page-fault
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  lw a3, 0(t1)                                  // expect 0xDEADBEEF still
  test3_mxr1_xu_sw:                                 // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_mxr1_xu_sw, test3_mxr1_xu_sw_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a4, 0(a5)                                // U-page R bit; expect 0x257A0604
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test4_sum1_urw_lw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test4_sum1_urw_lw, test4_sum1_urw_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: MXR=1 SUM=1 U-page XWR=111 VU sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(t0, 0x257A0605)                            // SPA pattern / store value for case 5 (0x257A0605)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // guest store through current PTE perms
  nop                                           // trap-skip pad
  lw   a6, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test5_sum1_urw_swlw:                             // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test5_sum1_urw_swlw, test5_sum1_urw_swlw_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // guest store through current PTE perms
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test6_sum0_urw_swlw:                             // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test6_sum0_urw_swlw, test6_sum0_urw_swlw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: MXR=0 SUM=0 S-page XWR=111 VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(a6, 0)                                     // sentinel — a6 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a6, 0(a5)                                // VU cannot use U=0 pages
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test7_srw_lw:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test7_srw_lw, test7_srw_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: MXR=1 SUM=1 S-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrs sstatus, t0                              // set sstatus MXR/SUM (also write vsstatus on next line)
  csrs vsstatus, t0                             // set vsstatus MXR/SUM (guest sees these)
  hfence.vvma                                   // flush VS-stage TLB

  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(a7, 0)                                     // sentinel — a7 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a7, 0(a5)                                // S-page still blocked in VU
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test8_mxr1_sum1_xs:                              // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test8_mxr1_sum1_xs, test8_mxr1_sum1_xs_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   s2, 0(a5)                                // VU load from S-page RWX: MXR=0 SUM=1 → load-page-fault (VU cannot use U=0 S-page); s2 stays 0
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test9_sum1_srw:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test9_sum1_srw, test9_sum1_srw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 10: MXR=0 SUM=0 S-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear HS MXR and SUM
  csrc vsstatus, t0                             // clear VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(s3, 0)                                     // sentinel — s3 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   s3, 0(a5)                                // VU load from S-page X-only: MXR=0 SUM=0 → load-page-fault (VU cannot use U=0 S-page); s3 stays 0
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test10_sum0_xs:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test10_sum0_xs, test10_sum0_xs_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 11: MXR=0 SUM=1 U-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(s4, 0)                                     // sentinel — s4 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   s4, 0(a5)                                // VU load from U-page X-only: MXR=0 SUM=1 → load-page-fault (X-only without MXR); s4 stays 0
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test11_sum1_mxr0_xu:                             // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s4, test11_sum1_mxr0_xu, test11_sum1_mxr0_xu_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 12: MXR=0 SUM=1 U-page XWR=111 VU sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(t0, 0x257A060C)                            // SPA pattern / store value for case 12 (0x257A060C)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU store to U-page RWX: MXR=0 SUM=1 → success (W allowed)
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // VU load from U-page RWX: MXR=0 SUM=1 → success
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test12_sum1_mxr0_urw_sw:                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test12_sum1_mxr0_urw_sw, test12_sum1_mxr0_urw_sw_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU store to S-page RWX: MXR=1 SUM=0 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  lw a4, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page RWX region)

  test13_mxr1_srw_sw:                              // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test13_mxr1_srw_sw, test13_mxr1_srw_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 14: MXR=1 SUM=1 S-page XWR=111 VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s5, 0)                                     // sentinel — s5 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   s5, 0(a5)                                // VU load from S-page RWX: MXR=1 SUM=1 → load-page-fault (VU cannot use U=0 S-page); s5 stays 0
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test14_mxr1_sum1_srw:                            // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s5, test14_mxr1_sum1_srw, test14_mxr1_sum1_srw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 15: MXR=0 SUM=0 S-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear HS MXR and SUM
  csrc vsstatus, t0                             // clear VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU store to S-page X-only: MXR=0 SUM=0 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  lw a6, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page X-only region)

  test15_xs_sw:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test15_xs_sw, test15_xs_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 16: MXR=1 SUM=1 U-page X-only VU jalr | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrs sstatus, t0                              // set HS MXR and SUM
  csrs vsstatus, t0                             // set VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(s6, 0)                                     // sentinel — s6 stays 0 if target never runs
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  nop                                           // pad so priv_mode samples prev=VU on jalr
  jalr ra, a5, 0                                // VU ifetch of U-page X-only: MXR=1 SUM=1 → fetch-page-fault (permission deny)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test16_xu_jalr:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s6, test16_xu_jalr, test16_xu_jalr_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 17: MXR=1 SUM=1 S-page XWR=111 VU jalr | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(s7, 0)                                     // sentinel — s7 stays 0 if target never runs
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  nop                                           // pad so priv_mode samples prev=VU on jalr
  jalr ra, a5, 0                                // VU ifetch of S-page RWX: MXR=1 SUM=1 → fetch-page-fault (VU cannot fetch U=0 S-page)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test17_srw_jalr:                                 // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s7, test17_srw_jalr, test17_srw_jalr_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU store to U-page RWX: MXR=1 SUM=0 → success (W allowed)
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // VU load from U-page RWX: MXR=1 SUM=0 → success
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test18_mxr1_sum0_urw:                            // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test18_mxr1_sum0_urw, test18_mxr1_sum0_urw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 19: MXR=1 SUM=0 S-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(s8, 0)                                     // sentinel — s8 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   s8, 0(a5)                                // VU load from S-page X-only: MXR=1 SUM=0 → load-page-fault (VU cannot use U=0 S-page); s8 stays 0
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test19_mxr1_xs:                                  // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s8, test19_mxr1_xs, test19_mxr1_xs_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU store to S-page X-only: MXR=0 SUM=1 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  lw a4, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page X-only region)

  test20_sum1_xs_sw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test20_sum1_xs_sw, test20_sum1_xs_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 21: MXR=1 SUM=1 U-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrs sstatus, t0                              // set HS MXR and SUM
  csrs vsstatus, t0                             // set VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change

  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU store to U-page X-only: MXR=1 SUM=1 → store-page-fault (no W)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  lw a6, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page X-only region)

  test21_mxr1_sum1_xu_sw:                          // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test21_mxr1_sum1_xu_sw, test21_mxr1_sum1_xu_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 22: MXR=1 SUM=1 S-page XWR=111 VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrs sstatus, t0                              // set HS MXR and SUM
  csrs vsstatus, t0                             // set VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU store to S-page RWX: MXR=1 SUM=1 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  lw a3, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page RWX region)

  test22_sum1_srw_sw:                              // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test22_sum1_srw_sw, test22_sum1_srw_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 23: MXR=0 SUM=0 U-page XWR=111 VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear HS MXR and SUM
  csrc vsstatus, t0                             // clear VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x257A0617)                        // preload SPA
  la t1, test_region_u_rw                   // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(a4, 0)                                     // a4 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a4, 0(a5)                                // VU load from U-page RWX: MXR=0 SUM=0 → success
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test23_sum0_urw_lw:                              // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test23_sum0_urw_lw, test23_sum0_urw_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 24: MXR=1 SUM=0 U-page XWR=111 VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x257A0618)                        // preload SPA
  la t1, test_region_u_rw                   // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(a6, 0)                                     // a6 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a6, 0(a5)                                // VU load from U-page RWX: MXR=1 SUM=0 → success
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test24_mxr1_sum0_urw_lw:                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test24_mxr1_sum0_urw_lw, test24_mxr1_sum0_urw_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 25: MXR=1 SUM=0 S-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU store to S-page X-only: MXR=1 SUM=0 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  lw a7, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page X-only region)

  test25_mxr1_xs_sw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test25_mxr1_xs_sw, test25_mxr1_xs_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 26: MXR=1 SUM=1 S-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_SUM)                           // t0 = SUM bit mask (sstatus[18])
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU store to S-page X-only: MXR=1 SUM=1 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_x_s                        // t1 = SPA of S-page X-only region
  lw s2, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page X-only region)

  test26_mxr1_sum1_xs_sw:                          // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test26_mxr1_sum1_xs_sw, test26_mxr1_sum1_xs_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 27: MXR=0 SUM=1 U-page X-only VU sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrc sstatus, t0                              // clear HS MXR
  csrc vsstatus, t0                             // clear VS MXR — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU store to U-page X-only: MXR=0 SUM=1 → store-page-fault (no W)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  lw s3, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page X-only region)

  test27_sum1_xu_sw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test27_sum1_xu_sw, test27_sum1_xu_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 28: MXR=0 SUM=1 S-page X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_s)                                // a5 = S-page X-only GVA (U=0 XWR=001)
  LI(s4, 0)                                     // sentinel — s4 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   s4, 0(a5)                                // VU load from S-page X-only: MXR=0 SUM=1 → load-page-fault (VU cannot use U=0 S-page); s4 stays 0
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test28_sum1_xs_lw:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s4, test28_sum1_xs_lw, test28_sum1_xs_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 29: MXR=1 SUM=1 U-page X-only VU lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR)                           // t0 = MXR bit mask (sstatus[19])
  csrs sstatus, t0                              // set HS MXR
  csrs vsstatus, t0                             // set VS MXR — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(s5, 0)                                     // s5 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   s5, 0(a5)                                // VU load from U-page X-only: MXR=1 SUM=1 → success; MXR makes X readable
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test29_mxr1_sum1_xu_lw:                          // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s5, test29_mxr1_sum1_xu_lw, test29_mxr1_sum1_xu_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 30: MXR=0 SUM=0 U-page XWR=111 VU jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrc sstatus, t0                              // clear HS MXR and SUM
  csrc vsstatus, t0                             // clear VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x00008067)                        // preload SPA
  la t1, test_region_u_rw                   // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(s6, 0)                                     // s6 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  nop                                           // pad so priv_mode samples prev=VU on jalr
  jalr ra, a5, 0                                // VU ifetch of U-page RWX: MXR=0 SUM=0 → success (X allowed); ret trampoline returns
  LI(s6, 0x257A061E)                            // magic proving jalr returned (case 30)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test30_urw_jalr:                                 // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s6, test30_urw_jalr, test30_urw_jalr_str) // SIGUPD

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
  LI(t0, 0x00008067)                        // preload SPA
  la t1, test_region_x_u                    // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(a5, va_x_u)                                // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(s7, 0)                                     // s7 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  nop                                           // pad so priv_mode samples prev=VU on jalr
  jalr ra, a5, 0                                // VU ifetch of U-page X-only: MXR=1 SUM=0 → success (X allowed); ret trampoline returns
  LI(s7, 0x257A061F)                            // magic proving jalr returned (case 31)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test31_xu_jalr_ok:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s7, test31_xu_jalr_ok, test31_xu_jalr_ok_str) // SIGUPD

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
  LI(t0, 0x00008067)                        // preload SPA
  la t1, test_region_u_rw                   // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(s8, 0)                                     // s8 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  nop                                           // pad so priv_mode samples prev=VU on jalr
  jalr ra, a5, 0                                // VU ifetch of U-page RWX: MXR=0 SUM=1 → success (X allowed); ret trampoline returns
  LI(s8, 0x257A0620)                            // magic proving jalr returned (case 32)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test32_sum1_urw_jalr:                            // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s8, test32_sum1_urw_jalr, test32_sum1_urw_jalr_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU store to S-page RWX: MXR=0 SUM=1 → store-page-fault (VU cannot use U=0 S-page)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_s_rw                       // t1 = SPA of S-page RWX region
  lw a3, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of S-page RWX region)

  test33_sum1_mxr0_srw_sw:                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test33_sum1_mxr0_srw_sw, test33_sum1_mxr0_srw_sw_str) // SIGUPD

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
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU store to U-page X-only: MXR=1 SUM=0 → store-page-fault (no W)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region_x_u                        // t1 = SPA of U-page X-only region
  // restore ret for later if overwritten — SPA should stay preload/ret
  lw a4, 0(t1)                                  // M-mode SPA readback; expect preload unchanged (SPA of U-page X-only region)

  test34_mxr1_xu_sw2:                              // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test34_mxr1_xu_sw2, test34_mxr1_xu_sw2_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 35: MXR=1 SUM=0 S-page XWR=111 VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(a5, va_s_rw)                               // a5 = S-page RWX GVA (U=0 XWR=111)
  LI(a6, 0)                                     // sentinel — a6 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a6, 0(a5)                                // VU load from S-page RWX: MXR=1 SUM=0 → load-page-fault (VU cannot use U=0 S-page); a6 stays 0
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test35_mxr1_sum0_srw_lw:                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test35_mxr1_sum0_srw_lw, test35_mxr1_sum0_srw_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 36: MXR=1 SUM=1 U-page XWR=111 VU lw only | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // t0 = MXR|SUM bit masks (sstatus[19|18])
  csrs sstatus, t0                              // set HS MXR and SUM
  csrs vsstatus, t0                             // set VS MXR and SUM — guest sees these
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x257A0624)                        // preload SPA
  la t1, test_region_u_rw                   // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(a7, 0)                                     // a7 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a7, 0(a5)                                // VU load from U-page RWX: MXR=1 SUM=1 → success
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test36_mxr1_sum1_urw_lw:                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test36_mxr1_sum1_urw_lw, test36_mxr1_sum1_urw_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 37: MXR=1 SUM=1 U-page XWR=111 VU jalr | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS-stage TLB after flag/PTE change
  LI(t0, 0x00008067)                        // preload SPA
  la t1, test_region_u_rw                   // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(a5, va_u_rw)                               // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(s2, 0)                                     // s2 will hold result (0 if fault skipped insn)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  nop                                           // pad so priv_mode samples prev=VU on jalr
  jalr ra, a5, 0                                // VU ifetch of U-page RWX: MXR=1 SUM=1 → success (X allowed); ret trampoline returns
  LI(s2, 0x257A0625)                            // magic proving jalr returned (case 37)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test37_mxr1_sum1_urw_jalr:                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test37_mxr1_sum1_urw_jalr, test37_mxr1_sum1_urw_jalr_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
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

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_vlvl1_pg_tbl:                            // VS-stage L1 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_mxr0_xu_str:       .string "\"Mismatch on MXR=0 U X-only VU lw (expect fault) in Test Case 1!\""  // mismatch string
test2_mxr1_xu_lw_str:    .string "\"Mismatch on MXR=1 U X-only VU lw in Test Case 2!\""  // mismatch string
test3_mxr1_xu_sw_str:    .string "\"Mismatch on MXR=1 U X-only VU sw (expect fault) in Test Case 3!\""  // mismatch string
test4_sum1_urw_lw_str:   .string "\"Mismatch on SUM=1 U RWX VU lw in Test Case 4!\""  // mismatch string
test5_sum1_urw_swlw_str: .string "\"Mismatch on SUM=1 U RWX VU sw+lw in Test Case 5!\""  // mismatch string
test6_sum0_urw_swlw_str: .string "\"Mismatch on SUM=0 U RWX VU sw+lw in Test Case 6!\""  // mismatch string
test7_srw_lw_str:        .string "\"Mismatch on S RWX VU lw (expect fault) in Test Case 7!\""  // mismatch string
test8_mxr1_sum1_xs_str:  .string "\"Mismatch on MXR=1 SUM=1 S X-only VU lw (expect fault) in Test Case 8!\""  // mismatch string
test9_sum1_srw_str:      .string "\"Mismatch on SUM=1 S RWX VU lw (expect fault) in Test Case 9!\""  // mismatch string
test10_sum0_xs_str:      .string "\"Mismatch on SUM=0 S X-only VU lw (expect fault) in Test Case 10!\""  // mismatch string
test11_sum1_mxr0_xu_str: .string "\"Mismatch on SUM=1 MXR=0 U X-only VU lw (expect fault) in Test Case 11!\""  // mismatch string
test12_sum1_mxr0_urw_sw_str: .string "\"Mismatch on SUM=1 MXR=0 U RWX VU sw+lw in Test Case 12!\""  // mismatch string
test13_mxr1_srw_sw_str:  .string "\"Mismatch on MXR=1 S RWX VU sw (expect fault) in Test Case 13!\""  // mismatch string
test14_mxr1_sum1_srw_str:.string "\"Mismatch on MXR=1 SUM=1 S RWX VU lw (expect fault) in Test Case 14!\""  // mismatch string
test15_xs_sw_str:        .string "\"Mismatch on S X-only VU sw (expect fault) in Test Case 15!\""  // mismatch string
test16_xu_jalr_str:      .string "\"Mismatch on U X-only VU jalr (expect fault) in Test Case 16!\""  // mismatch string
test17_srw_jalr_str:     .string "\"Mismatch on S RWX VU jalr (expect fault) in Test Case 17!\""  // mismatch string
test18_mxr1_sum0_urw_str:.string "\"Mismatch on MXR=1 SUM=0 U RWX VU sw+lw in Test Case 18!\""  // mismatch string
test19_mxr1_xs_str:      .string "\"Mismatch on MXR=1 S X-only VU lw (expect fault) in Test Case 19!\""  // mismatch string
test20_sum1_xs_sw_str:   .string "\"Mismatch on SUM=1 S X-only VU sw (expect fault) in Test Case 20!\""  // mismatch string
test21_mxr1_sum1_xu_sw_str: .string "\"Mismatch on MXR=1 SUM=1 U X-only VU sw (expect fault) in Test Case 21!\""  // mismatch string
test22_sum1_srw_sw_str:     .string "\"Mismatch on SUM=1 S RWX VU sw (expect fault) in Test Case 22!\""  // mismatch string
test23_sum0_urw_lw_str:     .string "\"Mismatch on SUM=0 U RWX VU lw in Test Case 23!\""  // mismatch string
test24_mxr1_sum0_urw_lw_str:.string "\"Mismatch on MXR=1 SUM=0 U RWX VU lw in Test Case 24!\""  // mismatch string
test25_mxr1_xs_sw_str:      .string "\"Mismatch on MXR=1 S X-only VU sw (expect fault) in Test Case 25!\""  // mismatch string
test26_mxr1_sum1_xs_sw_str: .string "\"Mismatch on MXR=1 SUM=1 S X-only VU sw (expect fault) in Test Case 26!\""  // mismatch string
test27_sum1_xu_sw_str:      .string "\"Mismatch on SUM=1 U X-only VU sw (expect fault) in Test Case 27!\""  // mismatch string
test28_sum1_xs_lw_str:      .string "\"Mismatch on SUM=1 S X-only VU lw (expect fault) in Test Case 28!\""  // mismatch string
test29_mxr1_sum1_xu_lw_str: .string "\"Mismatch on MXR=1 SUM=1 U X-only VU lw in Test Case 29!\""  // mismatch string
test30_urw_jalr_str:        .string "\"Mismatch on SUM=0 U RWX VU jalr in Test Case 30!\""  // mismatch string
test31_xu_jalr_ok_str:      .string "\"Mismatch on MXR=1 U X-only VU jalr in Test Case 31!\""  // mismatch string
test32_sum1_urw_jalr_str:   .string "\"Mismatch on SUM=1 U RWX VU jalr in Test Case 32!\""  // mismatch string
test33_sum1_mxr0_srw_sw_str:.string "\"Mismatch on SUM=1 MXR=0 S RWX VU sw (expect fault) in Test Case 33!\""  // mismatch string
test34_mxr1_xu_sw2_str:     .string "\"Mismatch on MXR=1 U X-only VU sw (expect fault) in Test Case 34!\""  // mismatch string
test35_mxr1_sum0_srw_lw_str:.string "\"Mismatch on MXR=1 SUM=0 S RWX VU lw (expect fault) in Test Case 35!\""  // mismatch string
test36_mxr1_sum1_urw_lw_str:.string "\"Mismatch on MXR=1 SUM=1 U RWX VU lw in Test Case 36!\""  // mismatch string
test37_mxr1_sum1_urw_jalr_str: .string "\"Mismatch on MXR=1 SUM=1 U RWX VU jalr in Test Case 37!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                VU MXR×SUM×U-page (X-only / RWX) control load/sto...
  //                      │
  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 1                      Test 2                      Test 3          
  //                │                           │                           │             
  //    MXR=0 SUM=0, U-page X-only  MXR=1 SUM=0, U-page X-only  MXR=1 SUM=0, U-page X-only
  //                │                           │                           │             
  //              VU lw                       VU lw                       VU sw           
  //                ▼                           ▼                           ▼             
  //            FAULT a3=0                  0xDEADBEEF            FAULT SPA 0xDEADBEEF)   

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 4                      Test 5                      Test 6          
  //                │                           │                           │             
  //       MXR=0 SUM=1, U-page         MXR=1 SUM=1, U-page         MXR=0 SUM=0, U-page    
  //                │                           │                           │             
  //              VU lw                      VU sw+lw                    VU sw+lw         
  //                ▼                           ▼                           ▼             
  //            0x257A0604                  0x257A0605                  0x257A0606        

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 7                      Test 8                      Test 9          
  //                │                           │                           │             
  //       MXR=0 SUM=0, S-page      MXR=1 SUM=1, S-page X-only     MXR=0 SUM=1, S-page    
  //                │                           │                           │             
  //              VU lw                       VU lw                       VU lw           
  //                ▼                           ▼                           ▼             
  //            FAULT a6=0                  FAULT a7=0                  FAULT s2=0        

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //             Test 10                     Test 11                     Test 12          
  //                │                           │                           │             
  //    MXR=0 SUM=0, S-page X-only  MXR=0 SUM=1, U-page X-only     MXR=0 SUM=1, U-page    
  //                │                           │                           │             
  //              VU lw                       VU lw                      VU sw+lw         
  //                ▼                           ▼                           ▼             
  //            FAULT s3=0                  FAULT s4=0                  0x257A060C        

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //             Test 13                     Test 14                     Test 15          
  //                │                           │                           │             
  //       MXR=1 SUM=0, S-page         MXR=1 SUM=1, S-page      MXR=0 SUM=0, S-page X-only
  //                │                           │                           │             
  //              VU sw                       VU lw                       VU sw           
  //                ▼                           ▼                           ▼             
  //      FAULT SPA 0x257A060A)             FAULT s5=0            FAULT SPA 0x257A0601)   

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //             Test 16                     Test 17                     Test 18          
  //                │                           │                           │             
  //    MXR=1 SUM=1, U-page X-only     MXR=1 SUM=1, S-page         MXR=1 SUM=0, U-page    
  //                │                           │                           │             
  //             VU jalr                     VU jalr                     VU sw+lw         
  //                ▼                           ▼                           ▼             
  //            FAULT s6=0                  FAULT s7=0                  0x257A0612        

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //             Test 19                     Test 20                     Test 21          
  //                │                           │                           │             
  //    MXR=1 SUM=0, S-page X-only  MXR=0 SUM=1, S-page X-only  MXR=1 SUM=1, U-page X-only
  //                │                           │                           │             
  //              VU lw                       VU sw                       VU sw           
  //                ▼                           ▼                           ▼             
  //            FAULT s8=0            FAULT SPA 0x257A0601)       FAULT SPA 0xDEADBEEF)   

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //             Test 22                     Test 23                     Test 24          
  //                │                           │                           │             
  //       MXR=1 SUM=1, S-page         MXR=0 SUM=0, U-page         MXR=1 SUM=0, U-page    
  //                │                           │                           │             
  //              VU sw                     VU lw only                  VU lw only        
  //                ▼                           ▼                           ▼             
  //         FAULT SPA same)                0x257A0617                  0x257A0618        

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //             Test 25                     Test 26                     Test 27          
  //                │                           │                           │             
  //    MXR=1 SUM=0, S-page X-only  MXR=1 SUM=1, S-page X-only  MXR=0 SUM=1, U-page X-only
  //                │                           │                           │             
  //              VU sw                       VU sw                       VU sw           
  //                ▼                           ▼                           ▼             
  //              FAULT                       FAULT                       FAULT           

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //             Test 28                     Test 29                     Test 30          
  //                │                           │                           │             
  //    MXR=1 SUM=0, U-page X-only  MXR=0 SUM=1, S-page X-only  MXR=1 SUM=1, U-page X-only
  //                │                           │                           │             
  //        VU sw (already 3);                VU lw                       VU lw           
  //                                            ▼                           ▼             
  //                                          FAULT                     0xDEADBEEF        

  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 31                            Test 32
  //         │                         │
  //      MXR=0 SUM=0, U-page        MXR=1 SUM=0, U-page
  //         │                         │
  //      VU jalr                    VU jalr
  //         ▼                         ▼
  //      PASS                       ret
