// --------------------------------------------------------------------------------------------------------------------------------
// svh_stage_both_bare_VSmode.S
// Config: sail-rv32-max | vsatp=Bare + hgatp=Bare
// Pair:   svh_stage_both_bare_sv39_VSmode.S
// Coverpoints mapped (SvH_cg): stage_both_bare
// What this proves (one line):
//   With both stages Bare, the address VS uses is the real physical address.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. VS sw/lw with both stages Bare (VA==SPA) → Successful
//  2. M-mode SPA readback confirms VS store → Successful
//
// Total Expected Faults :: 0
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_stage_both_bare_VSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 16
#define RVTEST_HYPERVISOR

// Mode hops (Sv-style GOTO_* plus H T-SBI):
//   Enter PA/identity → RVTEST_TSBI_GOTO_VSMODE / _SMODE / _VUMODE
//   Enter VA≠PA (V_SAVE_AREA) → RVTEST_GOTO_LOWER_MODE
//   Return to M → always RVTEST_TSBI_GOTO_MMODE
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  // ---- Both stages Bare: no page tables; GVA/GPA used as real SPA ----
  csrw vsatp, x0                                // VS paging OFF (Bare)
  csrw hgatp, x0                                // G paging OFF (Bare)
  hfence.vvma                                   // flush stale VS TLB (safe even when Bare)
  hfence.gvma                                   // flush stale G TLB (safe even when Bare)

  LI(t0, 0xDEADBEEF)                            // poison pattern
  la t1, test_region                            // real address of data
  sw t0, 0(t1)                                  // SPA starts as DEADBEEF

  la a5, test_region                            // same address for VS (Bare ⇒ VA==SPA)
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: VS sw/lw with both stages Bare | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a2, 0x257A0021)                            // value to store
  sw   a2, 0(a5)                                // stage_both_bare: VA==SPA store (no translation)
  nop                                           // pad (trap handler may skip prior insn)
  lw   a3, 0(a5)                                // load back → a3
  nop                                           // pad (trap handler may skip prior insn)
  test1_vs:                                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_vs, test1_vs_str) // SIGUPD

  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: M-mode SPA readback | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  la t1, test_region                            // t1 = real address of test_region
  lw t2, 0(t1)                                  // M reads SPA; expect 0x257A0021
  test2_spa:                                        // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, t2, test2_spa, test2_spa_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN

// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB align
test_region:                                    // real memory used as VA and SPA
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_vs_str:  .string "\"Mismatch on VS lw after sw (both Bare) in Test Case 1!\""
test2_spa_str: .string "\"Mismatch on SPA readback after VS store in Test Case 2!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
