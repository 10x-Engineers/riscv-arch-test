// --------------------------------------------------------------------------------------------------------------------------------
// svh_vs_pte_attr_VSmode.S
// Config: sail-rv32-max | VS=Sv32 ON, hgatp=Bare
// Coverpoints mapped (SvH_cg): cp_vsatp_pte_rsw
// What this proves (one line):
//   VS-stage PTE RSW[9:8] is preserved; stores and loads succeed for all RSW encodings.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. RSW=00: VS sw → Successful (SPA 0x257A0301)
//  2. RSW=00: VS lw only (fresh hop + hfence) → Successful (0x257A0301)
//  3. RSW=01: VS sw → Successful (SPA 0x257A0302)
//  4. RSW=01: VS lw only → Successful (0x257A0302)   // clears auto[1]×read
//  5. RSW=10: VS sw → Successful (SPA 0x257A0303)
//  6. RSW=10: VS lw only → Successful (0x257A0303)   // clears auto[2]×read
//  7. RSW=11: VS sw → Successful (SPA 0x257A0304)
//  8. RSW=11: VS lw only → Successful (0x257A0304)
//
// Note: sw+lw in the same VS hop TLB-hits the load so VS_PTE_D is missing on
// the read sample; RSW read bins need a separate hop after hfence.vvma.
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vs_pte_attr_VSmode.S"
#define SIGUPD_COUNT 8
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VSMODE / _SMODE (ecall a0=4/2)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE (mret + PA↔VA relocate)
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_data,                 0x008001000     // GVA for R/W data leaf (same VA, varying RSW bits)
  .set va_code,                 0x90000000      // GVA where VS executes this code (VA≠PA)

  // ---- VS-stage (vsatp Sv32): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  SUPERPAGE_VS_PTE_SETUP(sv32, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // VS superpage: va_code → PA(code); X/R A=D=1

  csrr a0, mscratch                             // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: VS entry PC is under va_code (VA≠PA)

  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)  // VS non-leaf: va_data VPN1 → VS L0 table PA
  VS_PTE_SETUP(sv32, PA, test_region, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)  // VS leaf: va_data → PA(test_region) R/W A=D=1 RSW=00

  VSATP_SETUP(sv32, PA)                         // vsatp = Sv32, PPN = PA of VS root
  csrw hgatp, x0                                // hgatp = Bare (no G-stage; VS PPN is real PA)
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(a5, va_data)                               // a5 = GVA pointer for all RSW store/load cases

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: RSW=00 VS sw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0x257A0301)                            // payload for RSW=00 store
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  sw   t0, 0(a5)                                // VS store through RSW=00 leaf → SPA
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA)

  la t1, test_region                            // t1 = SPA of data page
  lw s2, 0(t1)                                  // expect 0x257A0301 in SPA
  test1_rsw00_sw:                               // signature dump point for case 1
  RVTEST_SIGUPD(x2, x5, x4, s2, test1_rsw00_sw, test1_rsw00_sw_str)  // dump SPA word (expect 0x257A0301)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: RSW=00 VS lw only | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS TLB so lw rewalks (RSW read bin)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate
  lw   a3, 0(a5)                                // VS load through RSW=00 leaf; expect 0x257A0301
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M

  test2_rsw00_lw:                               // signature dump point for case 2
  RVTEST_SIGUPD(x2, x5, x4, a3, test2_rsw00_lw, test2_rsw00_lw_str)  // dump a3 (expect 0x257A0301)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: RSW=01 VS sw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv32, PA, test_region, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | 0x100), va_data, LEVEL0)  // VS leaf RSW=01 (bit 8) R/W A=D=1
  hfence.vvma                                   // flush VS TLB after PTE rewrite

  LI(t0, 0x257A0302)                            // payload for RSW=01 store
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS
  sw   t0, 0(a5)                                // VS store through RSW=01 leaf → SPA
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // return to M

  la t1, test_region                            // t1 = SPA
  lw s3, 0(t1)                                  // expect 0x257A0302 in SPA
  test3_rsw01_sw:                               // signature dump point for case 3
  RVTEST_SIGUPD(x2, x5, x4, s3, test3_rsw01_sw, test3_rsw01_sw_str)  // dump SPA word (expect 0x257A0302)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: RSW=01 VS lw only | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS TLB so lw rewalks
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS
  lw   a4, 0(a5)                                // VS load through RSW=01 leaf; expect 0x257A0302
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M

  test4_rsw01_lw:                               // signature dump point for case 4
  RVTEST_SIGUPD(x2, x5, x4, a4, test4_rsw01_lw, test4_rsw01_lw_str)  // dump a4 (expect 0x257A0302)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: RSW=10 VS sw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv32, PA, test_region, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | 0x200), va_data, LEVEL0)  // VS leaf RSW=10 (bit 9) R/W A=D=1
  hfence.vvma                                   // flush VS TLB after PTE rewrite

  LI(t0, 0x257A0303)                            // payload for RSW=10 store
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS
  sw   t0, 0(a5)                                // VS store through RSW=10 leaf → SPA
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // return to M

  la t1, test_region                            // t1 = SPA
  lw s4, 0(t1)                                  // expect 0x257A0303 in SPA
  test5_rsw10_sw:                               // signature dump point for case 5
  RVTEST_SIGUPD(x2, x5, x4, s4, test5_rsw10_sw, test5_rsw10_sw_str)  // dump SPA word (expect 0x257A0303)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: RSW=10 VS lw only | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS TLB so lw rewalks
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS
  lw   a6, 0(a5)                                // VS load through RSW=10 leaf; expect 0x257A0303
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M

  test6_rsw10_lw:                               // signature dump point for case 6
  RVTEST_SIGUPD(x2, x5, x4, a6, test6_rsw10_lw, test6_rsw10_lw_str)  // dump a6 (expect 0x257A0303)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: RSW=11 VS sw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv32, PA, test_region, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V | PTE_SOFT), va_data, LEVEL0)  // VS leaf RSW=11 (PTE_SOFT bits 9:8) R/W
  hfence.vvma                                   // flush VS TLB after PTE rewrite

  LI(t0, 0x257A0304)                            // payload for RSW=11 store
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS
  sw   t0, 0(a5)                                // VS store through RSW=11 leaf → SPA
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                        // return to M

  la t1, test_region                            // t1 = SPA
  lw s5, 0(t1)                                  // expect 0x257A0304 in SPA
  test7_rsw11_sw:                               // signature dump point for case 7
  RVTEST_SIGUPD(x2, x5, x4, s5, test7_rsw11_sw, test7_rsw11_sw_str)  // dump SPA word (expect 0x257A0304)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: RSW=11 VS lw only | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS TLB so lw rewalks
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS
  lw   a7, 0(a5)                                // VS load through RSW=11 leaf; expect 0x257A0304
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                        // return to M

  test8_rsw11_lw:                               // signature dump point for case 8
  RVTEST_SIGUPD(x2, x5, x4, a7, test8_rsw11_lw, test8_rsw11_lw_str)  // dump a7 (expect 0x257A0304)

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing va_data (hgatp Bare)
  .word 0                                       // payload word (written by VS stores)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page

.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page

test1_rsw00_sw_str: .string "\"Mismatch on RSW=00 VS sw SPA in Test Case 1!\""
test2_rsw00_lw_str: .string "\"Mismatch on RSW=00 VS lw in Test Case 2!\""
test3_rsw01_sw_str: .string "\"Mismatch on RSW=01 VS sw SPA in Test Case 3!\""
test4_rsw01_lw_str: .string "\"Mismatch on RSW=01 VS lw in Test Case 4!\""
test5_rsw10_sw_str: .string "\"Mismatch on RSW=10 VS sw SPA in Test Case 5!\""
test6_rsw10_lw_str: .string "\"Mismatch on RSW=10 VS lw in Test Case 6!\""
test7_rsw11_sw_str: .string "\"Mismatch on RSW=11 VS sw SPA in Test Case 7!\""
test8_rsw11_lw_str: .string "\"Mismatch on RSW=11 VS lw in Test Case 8!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
