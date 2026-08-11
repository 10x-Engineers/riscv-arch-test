// --------------------------------------------------------------------------------------------------------------------------------
// svh_csr_hgatp_fields_HSmode.S
// Config: sail-rv32-max | HS writes hgatp; vsatp=Bare
// Pair:   svh_csr_hgatp_fields_RV64_HSmode.S
// Coverpoints mapped (SvH_cg): cp_hgatp_mode_field, cp_hgatp_ppn_field, cp_hgatp_vmidlen_detect, cp_hgatp_vmid_scoping
// What this proves (one line):
//   From HS, hgatp MODE / PPN / VMID can be written and read back.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. Set hgatp.MODE=Bare (0) from HS → Successful (readback)
//  2. Set hgatp.MODE=Sv32x4 with PPN=0 from HS → Successful (readback)
//  3. hgatp.VMID = all ones with MODE=Sv32x4 → Successful (VMIDLEN + scoping readbacks)
//  4. hgatp.PPN = all ones with MODE=Sv32x4 → Successful
//  5. Walking ones on hgatp.PPN bits [21:2] with MODE=Sv32x4 → Successful
//
// Total Expected Faults :: 0
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_csr_hgatp_fields_HSmode.S"
#define SIGUPD_COUNT 25
#define TRAP_SIGUPD_COUNT 16
#define RVTEST_HYPERVISOR

// Mode hops (Sv-style GOTO_* plus H T-SBI):
//   Enter PA/identity → RVTEST_TSBI_GOTO_VSMODE / _SMODE / _VUMODE
//   Enter VA≠PA (V_SAVE_AREA) → RVTEST_GOTO_LOWER_MODE
//   Return to M → always RVTEST_TSBI_GOTO_MMODE
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  // Partner stage off (isolate hgatp field bins)
  csrw vsatp, x0                                // vsatp Bare (no VS walk; isolate hgatp field bins)
  hfence.vvma                                   // flush VS TLB after vsatp clear
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: Set hgatp.MODE=Bare | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // cp_hgatp_mode_field bin: MODE=Bare
  csrw hgatp, x0                                // write Bare MODE (rs1=0)
  test1_bare:                                       // SIGUPD label
  RVTEST_SIGUPD_CSR_READ(hgatp, a4, test1_bare, test1_bare_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: Set hgatp.MODE=Sv32x4, PPN=0 | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // cp_hgatp_mode_field bin: MODE=Sv32x4, PPN=0
  LI(t0, (HGATP_MODE_SV32X4 << 31))             // G-stage Sv32x4 MODE, PPN clear
  csrw hgatp, t0                                // write hgatp (G-stage CSR)
  test2_mode:                                       // SIGUPD label
  RVTEST_SIGUPD_CSR_READ(hgatp, a4, test2_mode, test2_mode_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: hgatp.VMID = all ones | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // cp_hgatp_vmidlen_detect + cp_hgatp_vmid_scoping bins: VMID all-1s (two readbacks)
  LI(t0, (HGATP_MODE_SV32X4 << 31) | HGATP32_VMID)  // MODE + VMID all-1s
  csrw hgatp, t0                                // write hgatp (G-stage CSR)
  test3_vmid1:                                      // SIGUPD label
  RVTEST_SIGUPD_CSR_READ(hgatp, a4, test3_vmid1, test3_vmid1_str) // SIGUPD
  test3_vmid2:                                      // SIGUPD label
  RVTEST_SIGUPD_CSR_READ(hgatp, a4, test3_vmid2, test3_vmid2_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: hgatp.PPN = all ones | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // cp_hgatp_ppn_field bin: PPN all-ones (22 bits on RV32)
  LI(t0, (HGATP_MODE_SV32X4 << 31) | 0x3FFFFF)  // MODE + PPN all-1s
  csrw hgatp, t0                                // write hgatp (G-stage CSR)
  test4_ppn_ones:                                   // SIGUPD label
  RVTEST_SIGUPD_CSR_READ(hgatp, a4, test4_ppn_ones, test4_ppn_ones_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: Walking ones on hgatp.PPN bits [21:2] | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // cp_hgatp_ppn_field bin: walking-1 on PPN[21:2] (PPN[1:0] WARL-0 for Sv*x4 root align)
  // PPN walking-1 from bit 2..21 (bits 1:0 often forced 0)
  LI(t3, 2)                                     // start PPN walk at bit 2 (bits 1:0 often WARL-0)
ppn_walk:                                       // loop: walking-1 across PPN bits
  LI(t0, (HGATP_MODE_SV32X4 << 31))             // t0 = MODE Sv32x4 only
  LI(t1, 1)                                     // t1 = 1 (will shift into one bit)
  sll t1, t1, t3                                // shift 1 into bit position t3
  or  t0, t0, t1                                // merge MODE with PPN/bit
  csrw hgatp, t0                                // write hgatp (G-stage CSR)
  test5_ppn_walk:                                   // SIGUPD label
  RVTEST_SIGUPD_CSR_READ(hgatp, a4, test5_ppn_walk, test5_ppn_walk_str) // SIGUPD
  addi t3, t3, 1                                // next bit/index
  LI(t4, 22)                                    // stop after bits 2..21 (20 iterations)
  blt t3, t4, ppn_walk                          // repeat until all PPN bits tried

  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVTEST_DATA_BEGIN
// PASS/FAIL message strings for signature compares


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_bare_str:     .string "\"Mismatch on setting hgatp.MODE=Bare in Test Case 1!\""
test2_mode_str:     .string "\"Mismatch on setting hgatp.MODE=Sv32x4 (PPN=0) in Test Case 2!\""
test3_vmid1_str:    .string "\"Mismatch on hgatp.VMID=all-ones (VMIDLEN) in Test Case 3!\""
test3_vmid2_str:    .string "\"Mismatch on hgatp.VMID scoping read in Test Case 3!\""
test4_ppn_ones_str: .string "\"Mismatch on hgatp.PPN=all-ones in Test Case 4!\""
test5_ppn_walk_str: .string "\"Mismatch on walking ones in hgatp.PPN in Test Case 5!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
