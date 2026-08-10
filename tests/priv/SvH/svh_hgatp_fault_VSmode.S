// --------------------------------------------------------------------------------------------------------------------------------
// svh_hgatp_fault_VSmode.S
// Config: sail-rv32-max | vsatp=Bare, hgatp=Sv32x4 ON
// Coverpoints mapped (SvH_cg): cp_hgatp_invalid_pte, cp_hgatp_nonleaf_lvl0
// What this proves (one line):
//   Invalid G PTE (V=0) and L0 non-leaf-only entry cause guest-page faults on HS HLV/HSV.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. G leaf V=0 (D|A|U|X|W|R set): VS Bare lw → Expected Fault (a3 stays 0)
//  2. G L0 PTE_V only (non-leaf XWR=000): VS Bare lw → Expected Fault (a4 stays 0)
//  3. HS HLV to V=0 GPA → Expected Fault (a6 stays 0)
//  4. HS HSV to V=0 GPA → Expected Fault (s2 stays 0)
//  5. HS HSV to L0 non-leaf GPA → Expected Fault (s3 stays 0)
//  5b. HS HLV to L0 non-leaf GPA → Expected Fault (s5 stays 0)  // nonleaf×read_acc
//  6. Restore valid U=1 R/W G leaf: VS Bare lw → Successful (0x257A0221)
//  7. VS Bare jalr to V=0 G leaf GPA → Expected Fault (fetch-guest-page-fault; s4 stays 0)
//  8. G leaf V=0: VS Bare sw → Expected Fault (SPA unchanged)  // exception_reporting write
//
// Total Expected Faults :: 7
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_hgatp_fault_VSmode.S"
#define SIGUPD_COUNT 9
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VSMODE / _SMODE (ecall a0=4/2)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE (mret + PA↔VA relocate)
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set gpa_data, 0x00C002000                     // GPA for data (vsatp Bare ⇒ address-as-GPA)
  .set gpa_code, 0x80000000                      // identity GPA superpage for code + G PTs at 0x8000_0000

  // ---- G-stage (hgatp Sv32x4 ON): GPA -> PA ----
  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)  // gpa_code -> PA(code)

  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // non-leaf: G VPN1 for data -> G L0 table
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_G), gpa_data, LEVEL0)  // valid baseline leaf (cases overwrite)

  // ---- vsatp Bare + hgatp ON ----
  csrw vsatp, x0                                // VS Bare
  HGATP_SETUP(sv32x4)                           // hgatp = Sv32x4, PPN = G root
  hfence.vvma                                   // flush VS TLB
  hfence.gvma                                   // flush G TLB so next access rewalks

  LI(t0, 0x257A0221)                            // known SPA pattern (read after restore in case 6)
  la t1, test_region                            // SPA of data page
  sw t0, 0(t1)                                  // preload known pattern at SPA before guest access

  LI(a5, gpa_data)                              // a5 = GPA pointer for VS Bare lw

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: G leaf V=0 | Expected: Expected Fault
// cp_hgatp_invalid_pte_rw bin: g_pte_d_inv — V=0 with other bits set still invalid
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R), gpa_data, LEVEL0)  // strip V bit; X set so invalid_pte_x matches
  hfence.gvma                                   // flush so walk sees V=0 PTE

  LI(a3, 0)                                     // sentinel: stays 0 if trap fires
  RVTEST_TSBI_GOTO_VSMODE                      // T-SBI: ecall a0=4 → VS (code at PA / identity)
  lw   a3, 0(a5)                                // invalid G leaf → fault before load completes
  nop                                           // trap-skip padding if previous access faults
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test1_v0:                                     // signature dump point for case 1
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_v0, test1_v0_str)  // dump a3 (expect 0)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: G L0 non-leaf PTE_V only | Expected: Expected Fault
// cp_hgatp_nonleaf_lvl0_rw bin: g_pte_nonleaf_lvl0_d — L0 entry with V=1 but XWR=000
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_V), gpa_data, LEVEL0)  // V only at L0 (non-leaf shape at leaf level)
  hfence.gvma                                   // flush G TLB so next access rewalks

  LI(a4, 0)                                     // sentinel: stays 0 if trap fires
  RVTEST_TSBI_GOTO_VSMODE                      // T-SBI: ecall a0=4 → VS (code at PA / identity)
  lw   a4, 0(a5)                                // walk stops at non-leaf L0 → guest-page fault
  nop                                           // trap-skip padding if previous access faults
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test2_nonleaf:                                // signature dump point for case 2
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_nonleaf, test2_nonleaf_str)  // dump a4 (expect 0)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: HS HLV to V=0 GPA | Expected: Expected Fault
// cp_hgatp_invalid_pte_rw bin: priv_mode HS, read_acc
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R), gpa_data, LEVEL0)  // V=0 leaf again
  hfence.gvma                                   // flush G TLB so next access rewalks

  RVTEST_TSBI_GOTO_SMODE                       // T-SBI: ecall a0=2 → HS/S (code at PA / identity)
  LI(a6, 0)                                     // sentinel: stays 0 if trap fires
  LI(t1, gpa_data)                              // t1 = GPA pointer for HLV/HSV
  hlv.w a6, (t1)                                // HS hypervisor load hits V=0 → guest-page fault
  nop                                           // trap-skip padding if previous access faults
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA relocate)

  test3_hlv_v0:                                 // signature dump point for case 3
  RVTEST_SIGUPD(x2, x5, x4, a6, test3_hlv_v0, test3_hlv_v0_str)  // dump a6 (expect 0)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: HS HSV to V=0 GPA | Expected: Expected Fault
// cp_hgatp_invalid_pte_rw bin: priv_mode HS, write_acc
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.gvma                                   // flush G TLB before HS write path

  RVTEST_TSBI_GOTO_SMODE                       // T-SBI: ecall a0=2 → HS/S
  LI(s2, 0)                                     // sentinel: stays 0 if trap fires
  LI(t0, 0xDEADBEEF)                            // store payload (must not land)
  LI(t1, gpa_data)                              // t1 = GPA pointer for HSV
  hsv.w t0, (t1)                                // HS hypervisor store hits V=0 → guest-page fault
  nop                                           // trap-skip padding if previous access faults
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M

  test4_hsv_v0:                                 // signature dump point for case 4
  RVTEST_SIGUPD(x2, x5, x4, s2, test4_hsv_v0, test4_hsv_v0_str)  // dump s2 (expect 0)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: HS HSV to L0 non-leaf GPA | Expected: Expected Fault
// cp_hgatp_nonleaf_lvl0_rw bin: priv_mode HS, write_acc
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_V), gpa_data, LEVEL0)  // V only at L0 again
  hfence.gvma                                   // flush G TLB so next access rewalks

  RVTEST_TSBI_GOTO_SMODE                       // T-SBI: ecall a0=2 → HS/S
  LI(s3, 0)                                     // sentinel: stays 0 if trap fires
  LI(t0, 0xCAFEBABE)                            // store payload (must not land)
  LI(t1, gpa_data)                              // t1 = GPA pointer for HSV
  hsv.w t0, (t1)                                // HS store through non-leaf L0 → guest-page fault
  nop                                           // trap-skip padding if previous access faults
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M

  test5_hsv_nonleaf:                            // signature dump point for case 5
  RVTEST_SIGUPD(x2, x5, x4, s3, test5_hsv_nonleaf, test5_hsv_nonleaf_str)  // dump s3 (expect 0)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5b: HS HLV to L0 non-leaf GPA | Expected: Expected Fault
// cp_hgatp_nonleaf_lvl0_rw bin: priv_mode HS, read_acc
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.gvma                                   // flush G TLB before HS read of non-leaf L0
  RVTEST_TSBI_GOTO_SMODE                       // T-SBI: ecall a0=2 → HS/S
  LI(s5, 0)                                     // sentinel — stays 0 if HLV guest-page-faults
  LI(t1, gpa_data)                              // t1 = GPA pointer for HLV
  hlv.w s5, (t1)                                // HS load through non-leaf L0 → guest-page fault
  nop                                           // trap-skip padding after faulting HLV
  RVTEST_TSBI_GOTO_MMODE                       // return to M

  test5b_hlv_nonleaf:                           // signature dump point for case 5b
  RVTEST_SIGUPD(x2, x5, x4, s5, test5b_hlv_nonleaf, test5b_hlv_nonleaf_str)  // dump s5 (expect 0)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: Restore valid U=1 R/W G leaf | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_G), gpa_data, LEVEL0)  // restore valid U=1 R/W+G leaf
  hfence.gvma                                   // force walk on restored leaf (G_PTE_D in .rvvi)

  LI(a7, 0)                                     // clear result register before load
  RVTEST_TSBI_GOTO_VSMODE                      // T-SBI: ecall a0=4 → VS
  lw   a7, 0(a5)                                // expect 0x257A0221
  nop                                           // trap-skip padding if previous access faults
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M

  test6_restore:                                // signature dump point for case 6
  RVTEST_SIGUPD(x2, x5, x4, a7, test6_restore, test6_restore_str)  // dump a7 (expect 0x257A0221)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 7: VS Bare jalr into V=0 G leaf | Expected: Expected Fault (cp_hgatp_invalid_pte_x)
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R), gpa_data, LEVEL0)  // V=0 again
  hfence.gvma                                   // flush G TLB so ifetch walk sees V=0

  LI(s4, 0)                                     // sentinel — stays 0 if target never runs
  LI(a5, gpa_data)                              // a5 = GPA fetch target (vsatp Bare)
  RVTEST_TSBI_GOTO_VSMODE                      // T-SBI: ecall a0=4 → VS (code at PA / identity)
  nop                                           // pad so priv_mode_vs samples prev=VS on jalr
  jalr ra, a5, 0                                // ifetch through invalid G leaf → fetch-guest-page-fault
  nop                                           // trap-skip padding (not reached)
  RVTEST_TSBI_GOTO_MMODE                       // return to M

  test7_v0_ifetch:                              // signature dump point for case 7
  RVTEST_SIGUPD(x2, x5, x4, s4, test7_v0_ifetch, test7_v0_ifetch_str)  // dump s4 (expect 0)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 8: VS Bare sw into V=0 G leaf | Expected: Expected Fault (exception_reporting write)
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R), gpa_data, LEVEL0)  // G leaf V=0 again (write path)
  hfence.gvma                                   // flush G TLB so store walk sees V=0

  LI(a5, gpa_data)                              // a5 = GPA to store
  LI(t0, 0xDEADBEEF)                            // payload that must not land at SPA
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS identity hop
  nop                                           // pad before faulting store
  sw   t0, 0(a5)                                // VS Bare store: G leaf V=0 → guest-page
  nop                                           // trap-skip padding after faulting store
  RVTEST_TSBI_GOTO_MMODE                       // return to M

  la t1, test_region                            // t1 = SPA
  lw a3, 0(t1)                                  // expect preload 0x257A0221 unchanged
  test8_v0_sw:                                  // signature dump point for case 8
  RVTEST_SIGUPD(x2, x5, x4, a3, test8_v0_sw, test8_v0_sw_str)  // dump SPA word (expect preload)

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

.align 12                                      // 4 KiB page align
test_region:                                  // SPA backing for GPA data leaf
  .word 0                                     // payload word (preloaded in M)
  .word 0                                     // padding in same page
  .word 0                                     // padding in same page
  .word 0                                     // padding in same page

.align 12                                      // 4 KiB page align
rvtest_hlvl0_pg_tbl:                          // G-stage L0 PTE storage (4 KiB)
  .zero(4096)                                  // reserve 4 KiB page-table storage

test1_v0_str:         .string "\"Mismatch on VS lw with G leaf V=0 (expect fault) in Test Case 1!\""
test2_nonleaf_str:    .string "\"Mismatch on VS lw with G L0 non-leaf only (expect fault) in Test Case 2!\""
test3_hlv_v0_str:     .string "\"Mismatch on HS HLV with G leaf V=0 (expect fault) in Test Case 3!\""
test4_hsv_v0_str:     .string "\"Mismatch on HS HSV with G leaf V=0 (expect fault) in Test Case 4!\""
test5_hsv_nonleaf_str:.string "\"Mismatch on HS HSV with G L0 non-leaf (expect fault) in Test Case 5!\""
test5b_hlv_nonleaf_str:.string "\"Mismatch on HS HLV with G L0 non-leaf (expect fault) in Test Case 5b!\""
test6_restore_str:    .string "\"Mismatch on VS lw after valid G leaf restore in Test Case 6!\""
test7_v0_ifetch_str:  .string "\"Mismatch on VS ifetch with G leaf V=0 (expect fault) in Test Case 7!\""
test8_v0_sw_str:      .string "\"Mismatch on VS sw with G leaf V=0 (expect fault) in Test Case 8!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
