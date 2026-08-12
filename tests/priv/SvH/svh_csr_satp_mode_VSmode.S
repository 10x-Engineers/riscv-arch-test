// --------------------------------------------------------------------------------------------------------------------------------
// svh_csr_satp_mode_VSmode.S
// Config: sail-rv64-max | VS writes satp MODE; hgatp=Bare
// Coverpoints mapped (SvH_cg): cp_satp_mode_field
// What this proves (one line):
//   In VS, satp.MODE is WARL; satp and vsatp stay aliases.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. Read satp/vsatp alias with MODE=Sv39 in VS → Successful
//  2. Walk satp.MODE 0..15 starting Bare (identity map) → Successful (each readback)
//  3. Walk satp.MODE 0..15 starting Sv39 → Successful (each readback)
//  4. Final satp read after MODE walks → Successful
//
// Total Expected Faults :: 0
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_csr_satp_mode_VSmode.S"
#define SIGUPD_COUNT 35
#define TRAP_SIGUPD_COUNT 32
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
  // ---- VS-stage map: keep code reachable while satp.MODE is flipped in VS ----
  // Keep PC mapped while we change MODE: VA 0x80000000 → real code PA
  .set va_code, 0x0000000080000000              // GVA where VS executes this test code


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv39, PA, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_W | PTE_V), va_code, LEVEL2)  // map code so MODE flips cannot unmap us
  csrr a0, mscratch                         // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL2)  // VA≠PA code entry

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv39, PA)                     // vsatp ON (PPN = PA of VS root)
  csrw hgatp, x0                            // hgatp Bare
  hfence.vvma                               // flush VS-stage TLB
  hfence.gvma                               // flush G-stage TLB (legal in M)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: Read satp/vsatp alias with MODE=Sv39 | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // cp_satp_mode_field bin: satp and vsatp are aliases in VS (both must read Sv39)
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  csrr a3, satp                                 // guest sees satp (should be Sv39)
  csrr a4, vsatp                                // vsatp must match (alias)
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test1_satp:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_satp, test1_satp_str) // SIGUPD
  test1_vsatp:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test1_vsatp, test1_vsatp_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: Walk satp.MODE 0..15 starting Bare | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  csrw satp, x0                                 // Bare starting MODE (va_code=PA identity still fetches)
  LI(t3, 0)                                     // bit/index = 0
bare_mode_walk:                                 // loop: try each MODE from Bare
  csrw satp, x0                                 // force prev=Bare every iter (encodings 9..15)
  sll  t0, t3, 60                               // candidate MODE
  csrw satp, t0                                 // try that MODE
  csrr a5, satp                                 // readback for SIGUPD
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test2_bare_walk:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a5, test2_bare_walk, test2_bare_walk_str) // SIGUPD
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS for next iter
  addi t3, t3, 1                                // next encoding
  LI(t4, 16)                                    // loop until 16 MODE values tried
  blt  t3, t4, bare_mode_walk                    // repeat
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: Walk satp.MODE 0..15 starting Sv39 | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  csrr t2, satp                                 // save current satp (PPN/ASID)
  li   t0, ~((0xF) << 60)                       // mask to clear MODE nibble
  and  t2, t2, t0                               // strip MODE; keep PPN/ASID
  li   t0, (SATP_MODE_SV39 << 60)               // Sv39 MODE nibble
  or   t1, t2, t0                               // restore Sv39 before each write
  csrw satp, t1                                 // Sv39 starting MODE
  LI(t3, 0)                                     // bit/index = 0
sv39_mode_walk:                                 // loop: try each MODE from Sv39
  sll  t0, t3, 60                               // candidate MODE
  or   t1, t2, t0                               // combine kept PPN/ASID with MODE
  csrw satp, t1                                 // write (SAMPLE_PREV=Sv39 from restore below)
  csrr a5, satp                                 // readback for SIGUPD
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test3_sv39_walk:                               // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a5, test3_sv39_walk, test3_sv39_walk_str) // SIGUPD
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS for next iter
  li   t0, (SATP_MODE_SV39 << 60)               // restore Sv39 for next iteration prev
  or   t1, t2, t0                               // combine kept PPN/ASID with MODE
  csrw satp, t1                                 // keep Sv39 before next encoding
  addi t3, t3, 1                                // next encoding
  LI(t4, 16)                                    // loop until 16 MODE values tried
  blt  t3, t4, sv39_mode_walk                    // repeat
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: Final satp read after MODE walks | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  csrr a6, satp                                 // final satp after loop
  RVTEST_GOTO_MMODE                       // →M (T-SBI)

  test4_final:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test4_final, test4_final_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data
// PASS/FAIL message strings for signature compares


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_satp_str:       .string "\"Mismatch on satp read (Sv39) in Test Case 1!\""  // mismatch string
test1_vsatp_str:      .string "\"Mismatch on vsatp alias read in Test Case 1!\""  // mismatch string
test2_bare_walk_str:  .string "\"Mismatch on satp.MODE Bare-start walk in Test Case 2!\""  // mismatch string
test3_sv39_walk_str:  .string "\"Mismatch on satp.MODE Sv39-start walk in Test Case 3!\""  // mismatch string
test4_final_str:      .string "\"Mismatch on final satp read in Test Case 4!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                In VS, satp.MODE is WARL; satp and vsatp stay ali...
  //                      │
  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 1                      Test 2                      Test 3          
  //                │                           │                           │             
  //      Read satp/vsatp alias        Walk satp.MODE 0..15       Final satp read after   
  //                │                           │                           │             
  //               PASS               dump last WARL sample                PASS           
  //                                            ▼                                         
  //                                           PASS                                       
