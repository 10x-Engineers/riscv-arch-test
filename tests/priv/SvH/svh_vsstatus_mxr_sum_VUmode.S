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
//
// Total Expected Faults :: 4
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vsstatus_mxr_sum_VUmode.S"
#define SIGUPD_COUNT 8
#define TRAP_SIGUPD_COUNT 128
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

RVTEST_DATA_END
RVTEST_SIG_SETUP
