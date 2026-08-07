// --------------------------------------------------------------------------------------------------------------------------------
// svh_vs_perm_VUmode.S
// Config: sail-rv32-max | VS=Sv32 ON, hgatp=Bare, SUM=0, stimulus in VU
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
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vs_perm_VUmode.S"
#define SIGUPD_COUNT 12
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE VUmode
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_u_rwx,  0x008001000                   // GVA: U=1 XWR=111
  .set va_u_xonly,0x008002000                   // GVA: U=1 X-only
  .set va_u_ronly,0x008003000                   // GVA: U=1 R-only
  .set va_s_rwx,  0x008004000                   // GVA: U=0 XWR=111 (VU deny)
  .set va_u_rw,   0x008005000                   // GVA: U=1 R/W
  .set va_u_rx,   0x008006000                   // GVA: U=1 R/X
  .set va_u_vonly,0x008007000                   // GVA: U=1 V-only
  .set va_s_vonly,0x008008000                   // GVA: U=0 V-only
  .set va_code,   0x90000000                    // GVA code (U=1 for VU)

  // ---- VS-stage (vsatp Sv32): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  // VU ifetch requires U=1 on the code leaf (unlike VS which uses U=0).
  SUPERPAGE_VS_PTE_SETUP(sv32, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // VS-stage superpage: code GVA → PA/GPA

  csrr a0, mscratch                             // a0 = Msave_area (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: VU entry PC under va_code

  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_u_rwx, LEVEL1)  // shared L1 non-leaf for data VAs

  // Permission matrix leaves (U=1 allow / U=0 deny / V-only deny)
  VS_PTE_SETUP(sv32, PA, test_region_u_rwx, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), va_u_rwx, LEVEL0)  // VS leaf U=1 XWR=111 (VU allow)
  VS_PTE_SETUP(sv32, PA, test_region_u_xonly, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V), va_u_xonly, LEVEL0)  // VS leaf U=1 X-only (no R → load/store fault)
  VS_PTE_SETUP(sv32, PA, test_region_u_ronly, (PTE_D | PTE_A | PTE_U | PTE_R | PTE_V), va_u_ronly, LEVEL0)  // VS leaf U=1 R-only (load OK, store faults)
  VS_PTE_SETUP(sv32, PA, test_region_s_rwx, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V), va_s_rwx, LEVEL0)  // VS leaf U=0 XWR=111 (S-page; VU must fault)
  VS_PTE_SETUP(sv32, PA, test_region_u_rw, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), va_u_rw, LEVEL0)  // VS leaf U=1 R/W (no X)
  VS_PTE_SETUP(sv32, PA, test_region_u_rx, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), va_u_rx, LEVEL0)  // VS leaf U=1 R/X (load OK, store faults)
  VS_PTE_SETUP(sv32, PA, test_region_u_vonly, (PTE_D | PTE_A | PTE_U | PTE_V), va_u_vonly, LEVEL0)  // VS leaf U=1 V-only (XWR=000 → fault)
  VS_PTE_SETUP(sv32, PA, test_region_s_vonly, (PTE_D | PTE_A | PTE_V), va_s_vonly, LEVEL0)  // VS leaf U=0 V-only (deny)

  VSATP_SETUP(sv32, PA)                         // VS-stage ON
  csrw hgatp, x0                                // G Bare
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, SSTATUS_SUM)                           // SUM=0 — VU still uses U=1 pages; U=0 still denied
  csrc sstatus, t0                              // clear sstatus MXR/SUM
  csrc vsstatus, t0                             // clear vsstatus MXR/SUM

  // Preload SPAs with distinct patterns (M-mode baseline)
  LI(t0, 0x257A0701)
  la t1, test_region_u_rwx
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0702)
  la t1, test_region_u_xonly
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0704)
  la t1, test_region_u_ronly
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0707)
  la t1, test_region_s_rwx
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0705)
  la t1, test_region_u_rw
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0706)
  la t1, test_region_u_rx
  sw t0, 0(t1)                                  // SPA preload (known pattern before guest access)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: U=1 XWR=111 VU sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rwx)
  LI(t0, 0x257A0701)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // guest store through current PTE perms (expect allow)
  nop
  lw   a3, 0(a5)                                // guest load through current PTE perms (expect allow)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test1_urw_rwx:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_urw_rwx, test1_urw_rwx_str)  // signature: dump a3 (test1_urw_rwx) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: U=1 X-only VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_xonly)
  LI(a4, 0)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a4, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test2_ux_lw:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_ux_lw, test2_ux_lw_str)  // signature: dump a4 (test2_ux_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: U=1 X-only VU sw | Expected: Expected Fault
// SPA check — a zero store-src sentinel would also pass if the store wrongly succeeded.
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_xonly)
  LI(t0, 0xDEADBEEF)                            // must not appear in SPA
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // X-only → store-page-fault
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t1, test_region_u_xonly
  lw a3, 0(t1)                                  // expect preload 0x257A0702
  test3_ux_sw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_ux_sw, test3_ux_sw_str)  // signature: dump a3 (test3_ux_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: U=1 R-only VU lw OK, VU sw fault | Expected: Successful (lw) + Expected Fault (sw)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_ronly)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a3, 0(a5)                                // R-only → load OK (expect 0x257A0704)
  nop
  LI(a4, 0)
  sw   a4, 0(a5)                                // R-only → store-page-fault (SPA unchanged)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test4_ur_only:
  RVTEST_SIGUPD(x2, x5, x4, a3, test4_ur_only, test4_ur_only_str)  // signature: dump a3 lw result (expect 0x257A0704)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: U=1 R/W VU sw+lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rw)
  LI(t0, 0x257A0705)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // U=1 R/W → store OK
  nop
  lw   a3, 0(a5)                                // U=1 R/W → load OK (expect 0x257A0705)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test5_urw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test5_urw, test5_urw_str)  // signature: dump a3 (test5_urw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: U=1 R/X VU lw OK, VU sw fault | Expected: Successful (lw) + Expected Fault (sw)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_rx)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a3, 0(a5)                                // R/X → load OK (expect 0x257A0706)
  nop
  LI(a4, 0)
  sw   a4, 0(a5)                                // R/X → store-page-fault (SPA unchanged)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test6_urx:
  RVTEST_SIGUPD(x2, x5, x4, a3, test6_urx, test6_urx_str)  // signature: dump a3 (test6_urx) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: U=0 XWR=111 VU lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_rwx)
  LI(a6, 0)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a6, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test7_s_lw:
  RVTEST_SIGUPD(x2, x5, x4, a6, test7_s_lw, test7_s_lw_str)  // signature: dump a6 (test7_s_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: U=1 V-only VU lw | Expected: Expected Fault (urwx1000)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_vonly)
  LI(a7, 0)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   a7, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test8_uv_lw:
  RVTEST_SIGUPD(x2, x5, x4, a7, test8_uv_lw, test8_uv_lw_str)  // signature: dump a7 (test8_uv_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 9: U=0 XWR=111 VU sw | Expected: Expected Fault (urwx0111×write)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_rwx)
  LI(t0, 0xDEADBEEF)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // VU cannot use U=0 pages → store-page-fault
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t1, test_region_s_rwx
  lw s2, 0(t1)                                  // expect preload 0x257A0707
  test9_s_sw:
  RVTEST_SIGUPD(x2, x5, x4, s2, test9_s_sw, test9_s_sw_str)  // signature: dump s2 (test9_s_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 10: U=0 V-only VU lw | Expected: Expected Fault (urwx0000×read)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_vonly)
  LI(s3, 0)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  lw   s3, 0(a5)                                // guest load (expect fault; sentinel stays 0)
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  test10_sv_lw:
  RVTEST_SIGUPD(x2, x5, x4, s3, test10_sv_lw, test10_sv_lw_str)  // signature: dump s3 (test10_sv_lw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 11: U=0 V-only VU sw | Expected: Expected Fault (urwx0000×write)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_s_vonly)
  LI(t0, 0xBAD00FAD)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // guest store through current PTE perms
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t1, test_region_s_vonly
  lw s4, 0(t1)                                  // expect zero preload (never written)
  test11_sv_sw:
  RVTEST_SIGUPD(x2, x5, x4, s4, test11_sv_sw, test11_sv_sw_str)  // signature: dump s4 (test11_sv_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 12: U=1 V-only VU sw | Expected: Expected Fault (urwx1000×write)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_u_vonly)
  LI(t0, 0xBAD00FAD)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (U=1 code leaf)
  sw   t0, 0(a5)                                // guest store through current PTE perms
  nop
  RVTEST_TSBI_GOTO_MMODE                        // return to M (T-SBI ecall a0=1; rtn2mmode relocates EPC)

  la t1, test_region_u_vonly
  lw s5, 0(t1)                                  // expect zero preload (never written)
  test12_uv_sw:
  RVTEST_SIGUPD(x2, x5, x4, s5, test12_uv_sw, test12_uv_sw_str)  // signature: dump s5 (test12_uv_sw) for PASS/FAIL

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

.align 12
test_region_u_rwx:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
test_region_u_xonly:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
test_region_u_ronly:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
test_region_s_rwx:
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
test_region_u_rx:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
test_region_u_vonly:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
test_region_s_vonly:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
rvtest_vlvl0_pg_tbl:
  .zero(4096)

test1_urw_rwx_str:  .string "\"Mismatch on U=1 RWX VU lw in Test Case 1!\""
test2_ux_lw_str:    .string "\"Mismatch on U=1 X-only VU lw (expect fault) in Test Case 2!\""
test3_ux_sw_str:    .string "\"Mismatch on U=1 X-only VU sw (expect fault) in Test Case 3!\""
test4_ur_only_str:  .string "\"Mismatch on U=1 R-only VU lw in Test Case 4!\""
test5_urw_str:      .string "\"Mismatch on U=1 R/W VU lw in Test Case 5!\""
test6_urx_str:      .string "\"Mismatch on U=1 R/X VU lw in Test Case 6!\""
test7_s_lw_str:     .string "\"Mismatch on U=0 VU lw (expect fault) in Test Case 7!\""
test8_uv_lw_str:    .string "\"Mismatch on U=1 V-only VU lw (expect fault) in Test Case 8!\""
test9_s_sw_str:     .string "\"Mismatch on U=0 VU sw (expect fault) in Test Case 9!\""
test10_sv_lw_str:   .string "\"Mismatch on U=0 V-only VU lw (expect fault) in Test Case 10!\""
test11_sv_sw_str:   .string "\"Mismatch on U=0 V-only VU sw (expect fault) in Test Case 11!\""
test12_uv_sw_str:   .string "\"Mismatch on U=1 V-only VU sw (expect fault) in Test Case 12!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
