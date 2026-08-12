// --------------------------------------------------------------------------------------------------------------------------------
// svh_tvm_hgatp_RV64_HSmode.S
// Config: sail-rv64-max | HS hgatp access × mstatus.TVM
// Pair:   svh_tvm_hgatp_HSmode.S
// Coverpoints mapped (SvH_cg): cp_hgatp_tvm_effects
// What this proves (one line):
//   Same TVM×hgatp illegal-write check on RV64.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. TVM=0: HS write hgatp.MODE=Sv39x4 → Successful (readback)
//  2. TVM=1: HS write hgatp illegal → Expected Fault (marker unchanged)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_tvm_hgatp_RV64_HSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
  // ---- Setup: both stages Bare; traps stay in M (no delegation) ----
  csrw vsatp, x0                            // VS Bare
  csrw hgatp, x0                                // clear hgatp before the cases
  csrw medeleg, x0                              // keep traps in M (simpler TVM fault handling)
  csrw hedeleg, x0                              // do not delegate to HS/VS


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: TVM=0 write hgatp allowed | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // cp_hgatp_tvm_effects bin: TVM=0 allows HS to write hgatp
  LI(t0, MSTATUS_TVM)                           // t0 = TVM bit mask
  csrc mstatus, t0                              // clear TVM bit
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  LI(t0, (HGATP_MODE_SV39X4 << 60))             // t0 = MODE Sv39x4 only (RV64 MODE in [63:60])
  csrw hgatp, t0                                // should succeed under TVM=0
  test1_hgatp:                                      // SIGUPD label
  RVTEST_SIGUPD_CSR_READ(hgatp, a4, test1_hgatp, test1_hgatp_str) // SIGUPD
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: TVM=1 write hgatp illegal | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  // cp_hgatp_tvm_effects bin: TVM=1 makes HS hgatp write illegal (virtual instruction trap)
  LI(t0, MSTATUS_TVM)                           // t0 = TVM bit mask
  csrs mstatus, t0                              // set TVM
  LI(a4, 0x257A0131)                            // marker: stays 0x257A0131 if csrw is skipped by trap
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  csrw hgatp, x0                                // illegal; trap handler skips this insn
  nop                                           // pad after possible skip
  addi a4, a4, 1                                // if we continued → 0x257A0132
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  LI(t0, MSTATUS_TVM)                           // t0 = TVM bit mask
  csrc mstatus, t0                              // clear TVM again (tidy)

  test2_marker:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_marker, test2_marker_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data
// PASS/FAIL message strings for signature compares


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_hgatp_str:  .string "\"Mismatch on hgatp write with TVM=0 in Test Case 1!\""  // mismatch string
test2_marker_str: .string "\"Mismatch on TVM=1 illegal hgatp write marker in Test Case 2!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                Same TVM×hgatp illegal-write check on RV64.
  //                      │
  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 1                             Test 2
  //         │                         │
  //      TVM=0                      TVM=1
  //         │                         │
  //      HS write hgatp.MODE=S…     HS write hgatp illegal
  //         ▼                         ▼
  //      rdback                     FAULT marker
