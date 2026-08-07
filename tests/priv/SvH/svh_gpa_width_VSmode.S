// --------------------------------------------------------------------------------------------------------------------------------
// svh_gpa_width_VSmode.S
// Config: sail-rv64-max | vsatp=Bare, hgatp=Sv39x4, non-canonical GPA
// Coverpoints mapped (SvH_cg): cp_hgatp_gpa_width_checks
// What this proves (one line):
//   Non-canonical high GPA bits under Sv39x4 raise guest-page-fault.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. GPA with bit 41 set (beyond Sv39x4): VS Bare lw → Expected Fault (a3 stays 0)
//  2. Canonical GPA: VS Bare lw → Successful (0x257A0E02)
//  3. GPA with bit 41 set: VS Bare sw → Expected Fault (SPA stays 0x257A0E02)
//
// Total Expected Faults :: 2
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_gpa_width_VSmode.S"
#define SIGUPD_COUNT 3
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set gpa_ok,   0x00000000C002000
  .set gpa_wide, 0x00000200C002000              // bit 41 set — non-canonical for Sv39x4
  .set gpa_code, 0x0000000080000000

  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL2)
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_ok, LEVEL2)
  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_ok, LEVEL1)
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_ok, LEVEL0)

  csrw vsatp, x0
  HGATP_SETUP(sv39x4)
  hfence.gvma

  LI(t0, 0x257A0E02)
  la t1, test_region
  sd t0, 0(t1)

  LI(a5, gpa_wide)
  LI(a3, 0)
  RVTEST_TSBI_GOTO_VSMODE
  ld   a3, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test1_wide:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_wide, test1_wide_str)

  LI(a5, gpa_ok)
  RVTEST_TSBI_GOTO_VSMODE
  ld   a4, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test2_ok:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_ok, test2_ok_str)

  // Case 3: non-canonical GPA store (scores write_acc×trap on gpa_width)
  LI(a5, gpa_wide)
  LI(t0, 0xBAD00FAD)
  RVTEST_TSBI_GOTO_VSMODE
  sd   t0, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  la t1, test_region
  ld a6, 0(t1)                                  // SPA must still be 0x257A0E02
  test3_wide_sw:
  RVTEST_SIGUPD(x2, x5, x4, a6, test3_wide_sw, test3_wide_sw_str)

RVTEST_CODE_END
RVTEST_DATA_BEGIN
.align 12
test_region:
  .dword 0
  .dword 0
.align 12
rvtest_hlvl1_pg_tbl:
  .zero(4096)
.align 12
rvtest_hlvl0_pg_tbl:
  .zero(4096)
test1_wide_str: .string "\"Mismatch on non-canonical GPA lw (expect fault) in Test Case 1!\""
test2_ok_str:   .string "\"Mismatch on canonical GPA lw in Test Case 2!\""
test3_wide_sw_str: .string "\"Mismatch on non-canonical GPA sw (SPA must stay) in Test Case 3!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
