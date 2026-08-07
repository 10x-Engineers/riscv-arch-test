// --------------------------------------------------------------------------------------------------------------------------------
// svh_g_u_bit_sv39_HSmode.S
// Config: sail-rv64-max | vsatp=Bare, hgatp=Sv39x4 ON, HS HLV/HSV
// Pair:   svh_g_u_bit_HSmode.S
// Coverpoints mapped (SvH_cg): cp_hgatp_u_mode_access
// What this proves (one line):
//   G-stage walks as U-mode; HS HLV/HSV need G leaf U=1 (XWR=111); U=0 faults.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. G leaf U=1 XWR=111: HS hlv.w → Successful (0x257A0231)
//  2. G leaf U=1 XWR=111: HS hsv.w + hlv.w → Successful (0x257A0232)
//  3. G leaf U=0 XWR=111: HS hlv.w → Expected Fault (a4 stays 0)
//  4. G leaf U=0 XWR=111: HS hsv.w → Expected Fault (s3 stays 0)
//  5. Restore G leaf U=1 XWR=111: HS hlv.w → Successful (0x257A0232)
//
// Total Expected Faults :: 2
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_g_u_bit_sv39_HSmode.S"
#define SIGUPD_COUNT 5
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VSMODE / _SMODE (ecall a0=4/2)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE (mret + PA↔VA relocate)
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set gpa_data, 0x00C002000                     // GPA for data (vsatp Bare ⇒ HLV uses GPA directly)
  .set gpa_code,                0x0000000080000000                      // identity GPA superpage for code + G PTs at 0x8000_0000

  // ---- G-stage (hgatp Sv39x4 ON): GPA -> PA ----
  // g_pte_d_u bins need XWR=111 (???x1111); G walks as U-mode → U=1 required for success.
  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL2)  // G-stage superpage: code/data GPA → PA

  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_data, LEVEL2)
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // non-leaf: G VPN1 for data -> G L0 table
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // U=1 XWR=111

  // ---- vsatp Bare + hgatp ON ----
  csrw vsatp, x0                                // VS Bare (all cases run in HS)
  HGATP_SETUP(sv39x4)                           // hgatp = Sv39x4, PPN = G root
  hfence.vvma                                   // flush VS TLB
  hfence.gvma                                   // flush G TLB so next access rewalks

  LI(t0, 0x257A0231)                            // known SPA pattern
  la t1, test_region                            // SPA of data page
  sw t0, 0(t1)                                  // preload known pattern at SPA

  LI(t1, gpa_data)                              // t1 = GPA pointer for all HS HLV/HSV cases

  RVTEST_TSBI_GOTO_SMODE                       // T-SBI: ecall a0=2 → HS/S

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: G leaf U=1 XWR=111 HS HLV | Expected: Successful
// cp_hgatp_u_mode_access_rw bin: g_pte_d_u=1, priv_mode HS, vsatp_bare, read_acc
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.gvma                                   // force walk so G_PTE_D appears in .rvvi
  LI(a3, 0)                                     // clear result register before load
  hlv.w a3, (t1)                                // G walk as U-mode sees U=1 → load succeeds
  nop                                           // trap-skip padding if previous access faults
  test1_u1_hlv:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_u1_hlv, test1_u1_hlv_str)  // record result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: G leaf U=1 XWR=111 HS HSV + HLV | Expected: Successful
// cp_hgatp_u_mode_access_rw bin: write_acc then read_acc with U=1
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.gvma                                   // force walk before scored store
  LI(t0, 0x257A0232)                            // new payload for HSV
  hsv.w t0, (t1)                                // U=1 XWR=111 → store succeeds
  nop                                           // trap-skip padding if previous access faults
  hfence.gvma                                   // flush so following HLV rewalks leaf
  LI(a6, 0)                                     // clear result register before load
  hlv.w a6, (t1)                                // expect 0x257A0232
  nop                                           // trap-skip padding if previous access faults
  test2_u1_hsv:
  RVTEST_SIGUPD(x2, x5, x4, a6, test2_u1_hsv, test2_u1_hsv_str)  // record result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: G leaf U=0 XWR=111 HS HLV | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // strip U; keep XWR=111
  hfence.gvma                                   // flush G TLB before HS retries HLV
  RVTEST_TSBI_GOTO_SMODE                       // T-SBI: ecall a0=2 → HS/S

  LI(a4, 0)                                     // sentinel: stays 0 if trap fires
  LI(t1, gpa_data)                              // reload GPA pointer
  hlv.w a4, (t1)                                // U=0 G leaf → fault (G walk as U-mode)
  nop                                           // trap-skip padding if previous access faults
  test3_u0_hlv:
  RVTEST_SIGUPD(x2, x5, x4, a4, test3_u0_hlv, test3_u0_hlv_str)  // record result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: G leaf U=0 XWR=111 HS HSV | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.gvma                                   // force walk before scored store
  LI(s3, 0)                                     // sentinel: stays 0 if trap fires
  LI(t0, 0xDEADBEEF)                            // store payload (must not land)
  LI(t1, gpa_data)                              // reload GPA pointer
  hsv.w t0, (t1)                                // U=0 G leaf → store fault
  nop                                           // trap-skip padding if previous access faults
  test4_u0_hsv:
  RVTEST_SIGUPD(x2, x5, x4, s3, test4_u0_hsv, test4_u0_hsv_str)  // record result in signature

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: Restore G leaf U=1 XWR=111 HS HLV | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // restore U=1
  hfence.gvma                                   // flush G TLB so next access rewalks
  RVTEST_TSBI_GOTO_SMODE                       // T-SBI: ecall a0=2 → HS/S

  LI(a7, 0)                                     // clear result register before load
  LI(t1, gpa_data)                              // reload GPA pointer
  hlv.w a7, (t1)                                // expect 0x257A0232 (from case 2 HSV)
  nop                                           // trap-skip padding if previous access faults
  test5_restore:
  RVTEST_SIGUPD(x2, x5, x4, a7, test5_restore, test5_restore_str)  // record result in signature

  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

.align 12                                      // 4 KiB page align
test_region:                                  // SPA backing for GPA data leaf
  .word 0
  .word 0
  .word 0
  .word 0

.align 12
.align 12
rvtest_hlvl1_pg_tbl:
  .zero(4096)
rvtest_hlvl0_pg_tbl:                          // G-stage L0 PTE storage (4 KiB)
  .zero(4096)

test1_u1_hlv_str:  .string "\"Mismatch on HS HLV with G U=1 XWR=111 in Test Case 1!\""
test2_u1_hsv_str:  .string "\"Mismatch on HS HSV/HLV with G U=1 XWR=111 in Test Case 2!\""
test3_u0_hlv_str:  .string "\"Mismatch on HS HLV with G U=0 XWR=111 (expect fault) in Test Case 3!\""
test4_u0_hsv_str:  .string "\"Mismatch on HS HSV with G U=0 XWR=111 (expect fault) in Test Case 4!\""
test5_restore_str: .string "\"Mismatch on HS HLV after G U-bit restore in Test Case 5!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
