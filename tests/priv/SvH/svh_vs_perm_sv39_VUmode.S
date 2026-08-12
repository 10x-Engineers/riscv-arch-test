// --------------------------------------------------------------------------------------------------------------------------------
// svh_vs_perm_sv39_VUmode.S
// Config: sail-rv64-max | VS=Sv39 ON, hgatp=Bare, SUM=0, stimulus in VU
// Pair:   svh_vs_perm_VUmode.S
// Coverpoints mapped (SvH_cg): cp_vsatp_perm_checks
// What this proves (one line):
//   VU enforces U=1 XWR allow/deny and blocks U=0 S-pages (lw+sw).
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. Leaf U=1 XWR=111: VU sw+lw → Successful (0x257A0701)
//  2. Leaf U=1 X-only: VU lw → Expected Fault (a4 stays 0)
//  3. Leaf U=1 X-only: VU sw → Expected Fault (SPA stays 0x257A0702)
//  4. Leaf U=1 R-only: VU lw → Successful (0x257A0704); VU sw → Expected Fault
//  5. Leaf U=1 R/W: VU sw+lw → Successful (0x257A0705)
//  6. Leaf U=1 R/X: VU lw → Successful (0x257A0706); VU sw → Expected Fault
//  7. Leaf U=0 XWR=111: VU lw → Expected Fault (a6 stays 0)
//  8. Leaf U=1 V-only: VU lw → Expected Fault (a7 stays 0)   // urwx1000
//  9. Leaf U=0 XWR=111: VU sw → Expected Fault (SPA stays 0x257A0707)  // urwx0111×write
// 10. Leaf U=0 V-only: VU lw → Expected Fault (s3 stays 0)   // urwx0000×read
// 11. Leaf U=0 V-only: VU sw → Expected Fault (SPA stays 0)   // urwx0000×write
// 12. Leaf U=1 V-only: VU sw → Expected Fault (SPA stays 0)   // urwx1000×write
//
// Total Expected Faults :: 10
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vs_perm_sv39_VUmode.S"
#define SIGUPD_COUNT 12
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE VUmode
#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set va_u_rwx,  0x008001000                   // GVA: U=1 XWR=111
  .set va_u_xonly,0x008002000                   // GVA: U=1 X-only
  .set va_u_ronly,0x008003000                   // GVA: U=1 R-only
  .set va_s_rwx,  0x008004000                   // GVA: U=0 XWR=111 (VU deny)
  .set va_u_rw,   0x008005000                   // GVA: U=1 R/W
  .set va_u_rx,   0x008006000                   // GVA: U=1 R/X
  .set va_u_vonly,0x008007000                   // GVA: U=1 V-only
  .set va_s_vonly,0x008008000                   // GVA: U=0 V-only
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
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_u_rwx, LEVEL2)  // VS non-leaf: va_u_rwx VPN2 → L1 table PA(rvtest_vlvl1_pg_tbl) V=1
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_u_rwx, LEVEL1)  // non-leaf: data VPN1 -> VS L0 table PA

  // Permission matrix leaves (U=1 allow / U=0 deny / V-only deny)
  VS_PTE_SETUP(sv39, PA, test_region_u_rwx, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), va_u_rwx, LEVEL0)  // VS leaf U=1 XWR=111 (VU allow)
  VS_PTE_SETUP(sv39, PA, test_region_u_xonly, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V), va_u_xonly, LEVEL0)  // VS leaf U=1 X-only (no R → load/store fault)
  VS_PTE_SETUP(sv39, PA, test_region_u_ronly, (PTE_D | PTE_A | PTE_U | PTE_R | PTE_V), va_u_ronly, LEVEL0)  // VS leaf U=1 R-only (load OK, store faults)
  VS_PTE_SETUP(sv39, PA, test_region_s_rwx, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V), va_s_rwx, LEVEL0)  // VS leaf U=0 XWR=111 (S-page; VU must fault)
  VS_PTE_SETUP(sv39, PA, test_region_u_rw, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), va_u_rw, LEVEL0)  // VS leaf U=1 R/W (no X)
  VS_PTE_SETUP(sv39, PA, test_region_u_rx, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), va_u_rx, LEVEL0)  // VS leaf U=1 R/X (load OK, store faults)
  VS_PTE_SETUP(sv39, PA, test_region_u_vonly, (PTE_D | PTE_A | PTE_U | PTE_V), va_u_vonly, LEVEL0)  // VS leaf U=1 V-only (XWR=000 → fault)
  VS_PTE_SETUP(sv39, PA, test_region_s_vonly, (PTE_D | PTE_A | PTE_V), va_s_vonly, LEVEL0)  // VS leaf U=0 V-only (deny)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv39, PA)                         // VS-stage ON
  csrw hgatp, x0                                // G Bare
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, SSTATUS_SUM)                           // SUM=0 — VU still uses U=1 pages; U=0 still denied
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM

  // Preload SPAs with distinct patterns (M-mode baseline)
  LI(t0, 0x257A0701)                        // preload SPA
  la t1, test_region_u_rwx                  // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0702)                        // preload SPA
  la t1, test_region_u_xonly                // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0704)                        // preload SPA
  la t1, test_region_u_ronly                // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0707)                        // preload SPA
  la t1, test_region_s_rwx                  // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0705)                        // preload SPA
  la t1, test_region_u_rw                   // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0706)                        // preload SPA
  la t1, test_region_u_rx                   // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: U=1 XWR=111 VU sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rwx)                              // a5 = U-page RWX GVA (U=1 XWR=111)
  LI(t0, 0x257A0701)                            // SPA pattern / store value for case 1 (0x257A0701)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // guest store through current PTE perms (expect allow)
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test1_urw_rwx:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_urw_rwx, test1_urw_rwx_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: U=1 X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_xonly)                            // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(a4, 0)                                     // sentinel — a4 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a4, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test2_ux_lw:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_ux_lw, test2_ux_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: U=1 X-only VU sw | Expected: Expected Fault
// SPA check — a zero store-src sentinel would also pass if the store wrongly succeeded.
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_xonly)                            // a5 = U-page X-only GVA (U=1 XWR=001)
  LI(t0, 0xDEADBEEF)                            // must not appear in SPA
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // X-only → store-page-fault
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  la t1, test_region_u_xonly                    // t1 = SPA of U-page X-only region
  lw a3, 0(t1)                                  // expect preload 0x257A0702
  test3_ux_sw:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_ux_sw, test3_ux_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: U=1 R-only VU lw OK, VU sw fault | Expected: Successful (lw) + Expected Fault (sw)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_ronly)                            // a5 = U-page R-only GVA (U=1 XWR=011)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a3, 0(a5)                                // R-only → load OK (expect 0x257A0704)
  nop                                           // trap-skip pad
  LI(a4, 0)                                     // sentinel — a4 stays 0 if store is skipped by trap
  sw   a4, 0(a5)                                // R-only → store-page-fault (SPA unchanged)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test4_ur_only:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test4_ur_only, test4_ur_only_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: U=1 R/W VU sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rw)                               // a5 = U-page R/W GVA (U=1 XWR=110)
  LI(t0, 0x257A0705)                            // SPA pattern / store value for case 5 (0x257A0705)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // U=1 R/W → store OK
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // U=1 R/W → load OK (expect 0x257A0705)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test5_urw:                                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test5_urw, test5_urw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: U=1 R/X VU lw OK, VU sw fault | Expected: Successful (lw) + Expected Fault (sw)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rx)                               // a5 = U-page R/X GVA (U=1 XWR=101)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a3, 0(a5)                                // R/X → load OK (expect 0x257A0706)
  nop                                           // trap-skip pad
  LI(a4, 0)                                     // sentinel — a4 stays 0 if store is skipped by trap
  sw   a4, 0(a5)                                // R/X → store-page-fault (SPA unchanged)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test6_urx:                                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test6_urx, test6_urx_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: U=0 XWR=111 VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_rwx)                              // a5 = S-page RWX GVA (U=0 XWR=111; VU must fault)
  LI(a6, 0)                                     // sentinel — a6 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a6, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test7_s_lw:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test7_s_lw, test7_s_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: U=1 V-only VU lw | Expected: Expected Fault (urwx1000)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_vonly)                            // a5 = U-page V-only GVA (U=1 XWR=000)
  LI(a7, 0)                                     // sentinel — a7 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a7, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test8_uv_lw:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a7, test8_uv_lw, test8_uv_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 9: U=0 XWR=111 VU sw | Expected: Expected Fault (urwx0111×write)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_rwx)                              // a5 = S-page RWX GVA (U=0 XWR=111; VU must fault)
  LI(t0, 0xDEADBEEF)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU cannot use U=0 pages → store-page-fault
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  la t1, test_region_s_rwx                      // t1 = SPA of S-page RWX region (VU deny)
  lw s2, 0(t1)                                  // expect preload 0x257A0707
  test9_s_sw:                                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s2, test9_s_sw, test9_s_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 10: U=0 V-only VU lw | Expected: Expected Fault (urwx0000×read)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_vonly)                            // a5 = S-page V-only GVA (U=0 XWR=000)
  LI(s3, 0)                                     // sentinel — s3 stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   s3, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test10_sv_lw:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s3, test10_sv_lw, test10_sv_lw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 11: U=0 V-only VU sw | Expected: Expected Fault (urwx0000×write)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_vonly)                            // a5 = S-page V-only GVA (U=0 XWR=000)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // guest store through current PTE perms
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  la t1, test_region_s_vonly                    // t1 = SPA of S-page V-only region
  lw s4, 0(t1)                                  // expect zero preload (never written)
  test11_sv_sw:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s4, test11_sv_sw, test11_sv_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 12: U=1 V-only VU sw | Expected: Expected Fault (urwx1000×write)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_vonly)                            // a5 = U-page V-only GVA (U=1 XWR=000)
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA if store faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // guest store through current PTE perms
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  la t1, test_region_u_vonly                    // t1 = SPA of U-page V-only region
  lw s5, 0(t1)                                  // expect zero preload (never written)
  test12_uv_sw:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, s5, test12_uv_sw, test12_uv_sw_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region_u_rwx:                              // SPA backing va_u_rwx (U=1 XWR=111)
  .word 0                                       // data word (initially 0 / preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_u_xonly:                            // SPA backing va_u_xonly (U=1 X-only)
  .word 0                                       // data word (initially 0 / preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_u_ronly:                            // SPA backing va_u_ronly (U=1 R-only)
  .word 0                                       // data word (initially 0 / preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_s_rwx:                              // SPA backing va_s_rwx (U=0 XWR=111)
  .word 0                                       // data word (initially 0 / preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_u_rw:                               // SPA backing va_u_rw (U=1 R/W XWR=110)
  .word 0                                       // data word (initially 0 / preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_u_rx:                               // SPA backing va_u_rx (U=1 R/X)
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
test1_urw_rwx_str:  .string "\"Mismatch on U=1 RWX VU lw in Test Case 1!\""  // mismatch string
test2_ux_lw_str:    .string "\"Mismatch on U=1 X-only VU lw (expect fault) in Test Case 2!\""  // mismatch string
test3_ux_sw_str:    .string "\"Mismatch on U=1 X-only VU sw (expect fault) in Test Case 3!\""  // mismatch string
test4_ur_only_str:  .string "\"Mismatch on U=1 R-only VU lw in Test Case 4!\""  // mismatch string
test5_urw_str:      .string "\"Mismatch on U=1 R/W VU lw in Test Case 5!\""  // mismatch string
test6_urx_str:      .string "\"Mismatch on U=1 R/X VU lw in Test Case 6!\""  // mismatch string
test7_s_lw_str:     .string "\"Mismatch on U=0 VU lw (expect fault) in Test Case 7!\""  // mismatch string
test8_uv_lw_str:    .string "\"Mismatch on U=1 V-only VU lw (expect fault) in Test Case 8!\""  // mismatch string
test9_s_sw_str:     .string "\"Mismatch on U=0 VU sw (expect fault) in Test Case 9!\""  // mismatch string
test10_sv_lw_str:   .string "\"Mismatch on U=0 V-only VU lw (expect fault) in Test Case 10!\""  // mismatch string
test11_sv_sw_str:   .string "\"Mismatch on U=0 V-only VU sw (expect fault) in Test Case 11!\""  // mismatch string
test12_uv_sw_str:   .string "\"Mismatch on U=1 V-only VU sw (expect fault) in Test Case 12!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                VU enforces U=1 XWR allow/deny and blocks U=0 S-p...
  //                      │
  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 1                      Test 2                      Test 3          
  //                │                           │                           │             
  //         Leaf U=1 XWR=111            Leaf U=1 X-only             Leaf U=1 X-only      
  //                │                           │                           │             
  //             VU sw+lw                     VU lw                       VU sw           
  //                ▼                           ▼                           ▼             
  //            0x257A0701                  FAULT a4=0            FAULT SPA 0x257A0702)   

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 4                      Test 5                      Test 6          
  //                │                           │                           │             
  //         Leaf U=1 R-only               Leaf U=1 R/W                Leaf U=1 R/X       
  //                │                           │                           │             
  //              VU lw                      VU sw+lw                     VU lw           
  //                ▼                           ▼                           ▼             
  //         FAULT 0x257A0704               0x257A0705               FAULT 0x257A0706     

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 7                      Test 8                      Test 9          
  //                │                           │                           │             
  //         Leaf U=0 XWR=111            Leaf U=1 V-only             Leaf U=0 XWR=111     
  //                │                           │                           │             
  //              VU lw                       VU lw                       VU sw           
  //                ▼                           ▼                           ▼             
  //            FAULT a6=0                  FAULT a7=0            FAULT SPA 0x257A0707)   

  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //             Test 10                     Test 11                     Test 12          
  //                │                           │                           │             
  //         Leaf U=0 V-only             Leaf U=0 V-only             Leaf U=1 V-only      
  //                │                           │                           │             
  //              VU lw                       VU sw                       VU sw           
  //                ▼                           ▼                           ▼             
  //            FAULT s3=0                 FAULT SPA=0                 FAULT SPA=0        
