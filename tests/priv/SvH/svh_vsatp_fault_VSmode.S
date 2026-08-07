// --------------------------------------------------------------------------------------------------------------------------------
// svh_vsatp_fault_VSmode.S
// Config: sail-rv32-max | VS=Sv32 ON, hgatp=Bare
// Coverpoints mapped (SvH_cg): cp_vsatp_invalid_pte, cp_vsatp_nonleaf_lvl0
// What this proves (one line):
//   VS faults on V=0/nonleaf lw+sw; HS HLV/HSV with SPVP=1 fault invalid PTE.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. VS lw of V=0 leaf at va_inv → Expected Fault (a3 stays 0)
//  2. VS sw of V=0 leaf at va_inv → Expected Fault (s2 stays 0)
//  3. VS lw of L0 non-leaf at va_nleaf → Expected Fault (a4 stays 0)
//  4. VS sw of L0 non-leaf at va_nleaf → Expected Fault (s3 stays 0)
//  5. HS hlv.w with SPVP=1 on V=0 leaf → Expected Fault (a6 stays 0)
//  6. HS hsv.w with SPVP=1 on V=0 leaf → Expected Fault (s4 stays 0)
//  7. Restore valid leaf at va_ok; VS lw → Successful (0x257A0310)
//
// Total Expected Faults :: 6
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vsatp_fault_VSmode.S"
#define SIGUPD_COUNT 7
#define TRAP_SIGUPD_COUNT 128
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VSMODE / _SMODE (ecall a0=4/2)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE (mret + PA↔VA relocate)
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_ok,     0x008001000                    // GVA for valid R/W leaf (case 7 baseline)
  .set va_inv,    0x008002000                    // GVA for V=0 invalid leaf
  .set va_nleaf,  0x008003000                    // GVA for L0 non-leaf PTE
  .set va_code,   0x90000000                     // GVA where VS executes this code

  // ---- VS-stage (vsatp Sv32): GVA -> PA  (hgatp Bare ⇒ PTE PPN fields are real PAs) ----
  SUPERPAGE_VS_PTE_SETUP(sv32, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // leaf: va_code -> PA(code)

  csrr a0, mscratch                             // a0 = Msave_area (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: VS entry PC is under va_code

  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_ok, LEVEL1)  // non-leaf: data VPN1 -> VS L0 table PA

  VS_PTE_SETUP(sv32, PA, test_region_ok, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V), va_ok, LEVEL0)  // valid R/W leaf
  VS_PTE_SETUP(sv32, PA, test_region_inv, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R), va_inv, LEVEL0)  // V=0 invalid
  VS_PTE_SETUP(sv32, PA, test_region_nleaf, (PTE_V), va_nleaf, LEVEL0)  // L0 non-leaf (XWR=000)

  VSATP_SETUP(sv32, PA)                         // vsatp = Sv32, PPN = PA of VS root
  csrw hgatp, x0                                // hgatp = Bare (no G-stage)
  hfence.vvma                                   // invalidate VS-stage TLB entries
  hfence.gvma                                   // invalidate G-stage TLB entries (harmless with Bare)

  LI(t0, 0x257A0310)                            // payload for successful case 7
  la t1, test_region_ok                         // t1 = SPA of valid leaf
  sw t0, 0(t1)                                  // preload SPA so case 7 has known data

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: VS lw of V=0 leaf | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_inv)                                // a5 = GVA of V=0 leaf
  LI(a3, 0)                                     // a3 stays 0 if lw is skipped by trap handler
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode mret + PA↔VA relocate
  lw   a3, 0(a5)                                // V=0 leaf → load-page-fault
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M

  test1_v0_lw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_v0_lw, test1_v0_lw_str)  // record case 1 fault sentinel

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: VS sw of V=0 leaf | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_inv)                                // a5 = GVA of V=0 leaf
  LI(s2, 0)                                     // sentinel for signature (store must fault)
  LI(t0, 0xDEADBEEF)                            // store payload (must not land)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode
  sw   t0, 0(a5)                                // V=0 leaf → store-page-fault
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M

  test2_v0_sw:
  RVTEST_SIGUPD(x2, x5, x4, s2, test2_v0_sw, test2_v0_sw_str)  // record case 2 fault sentinel

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: VS lw of L0 non-leaf | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_nleaf)                              // a5 = GVA pointing at L0 non-leaf PTE
  LI(a4, 0)                                     // a4 stays 0 if lw is skipped
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode
  lw   a4, 0(a5)                                // non-leaf at L0 → load-page-fault
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M

  test3_nleaf_lw:
  RVTEST_SIGUPD(x2, x5, x4, a4, test3_nleaf_lw, test3_nleaf_lw_str)  // record case 3 fault sentinel

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: VS sw of L0 non-leaf | Expected: Expected Fault
// cp_vsatp_nonleaf_lvl0_rw bin: write_acc
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_nleaf)                              // a5 = GVA of L0 non-leaf
  LI(s3, 0)                                     // sentinel for signature
  LI(t0, 0xCAFEBABE)                            // store payload (must not land)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode
  sw   t0, 0(a5)                                // non-leaf at L0 → store-page-fault
  nop                                           // trap-skip padding after store
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M

  test4_nleaf_sw:
  RVTEST_SIGUPD(x2, x5, x4, s3, test4_nleaf_sw, test4_nleaf_sw_str)  // record case 4 fault sentinel

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: HS hlv.w on V=0 leaf with SPVP=1 | Expected: Expected Fault
// cp_vsatp_invalid_pte_rw bin: priv_mode HS, read_acc
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, HSTATUS_SPVP)                          // t0 = SPVP bit mask (hstatus[8])
  csrs hstatus, t0                              // SPVP=1 → HLV uses VS-stage translation
  LI(a5, va_inv)                                // a5 = GVA of V=0 leaf
  LI(a6, 0)                                     // a6 stays 0 if hlv.w is skipped
  RVTEST_GOTO_LOWER_MODE HSmode                 // M→HSmode
  hlv.w a6, (a5)                                // HS load through vsatp → invalid PTE fault
  nop                                           // trap-skip padding after hlv.w
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M

  test5_hlv:
  RVTEST_SIGUPD(x2, x5, x4, a6, test5_hlv, test5_hlv_str)  // record case 5 fault sentinel

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: HS hsv.w on V=0 leaf with SPVP=1 | Expected: Expected Fault
// cp_vsatp_invalid_pte_rw bin: priv_mode HS, write_acc
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_inv)                                // a5 = GVA of V=0 leaf
  LI(s4, 0)                                     // sentinel for signature
  LI(t0, 0xBADCAFE)                             // store payload (must not land)
  RVTEST_GOTO_LOWER_MODE HSmode                 // M→HSmode
  hsv.w t0, (a5)                                // HS store through vsatp → invalid PTE fault
  nop                                           // trap-skip padding after hsv.w
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M

  LI(t0, HSTATUS_SPVP)                          // t0 = SPVP bit mask
  csrc hstatus, t0                              // clear SPVP (tidy for harness)

  test6_hsv:
  RVTEST_SIGUPD(x2, x5, x4, s4, test6_hsv, test6_hsv_str)  // record case 6 fault sentinel

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: Valid leaf VS lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_ok)                                  // a5 = GVA of valid R/W leaf
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VSmode
  lw   a7, 0(a5)                                // valid leaf → load succeeds; expect 0x257A0310
  nop                                           // trap-skip padding after load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M

  test7_ok:
  RVTEST_SIGUPD(x2, x5, x4, a7, test7_ok, test7_ok_str)  // record case 7 lw result

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

.align 12                                       // 4 KiB page align
test_region_ok:                                 // real PA backing va_ok (valid R/W leaf)
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
test_region_inv:                                // real PA behind V=0 leaf
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
test_region_nleaf:                              // PTE storage misused as L0 non-leaf target
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
rvtest_vlvl0_pg_tbl:                            // VS-stage level-0 PTE storage
  .zero(4096)

test1_v0_lw_str:    .string "\"Mismatch on VS lw of V=0 leaf (expect fault) in Test Case 1!\""
test2_v0_sw_str:    .string "\"Mismatch on VS sw of V=0 leaf (expect fault) in Test Case 2!\""
test3_nleaf_lw_str: .string "\"Mismatch on VS lw of L0 non-leaf (expect fault) in Test Case 3!\""
test4_nleaf_sw_str: .string "\"Mismatch on VS sw of L0 non-leaf (expect fault) in Test Case 4!\""
test5_hlv_str:      .string "\"Mismatch on HS hlv.w of V=0 leaf (expect fault) in Test Case 5!\""
test6_hsv_str:      .string "\"Mismatch on HS hsv.w of V=0 leaf (expect fault) in Test Case 6!\""
test7_ok_str:       .string "\"Mismatch on VS lw of valid leaf in Test Case 7!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
