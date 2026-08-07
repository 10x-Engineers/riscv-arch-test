// --------------------------------------------------------------------------------------------------------------------------------
// svh_g_struct_sv39_HSmode.S
// Config: sail-rv64-max | hgatp Sv39x4 structural (twin of RV32)
// Coverpoints mapped (SvH_cg): hgatp_misaligned_superpage, hgatp_root_table_alignment_and_size
// What this proves (one line):
//   RV64 twin: misaligned G megapage faults; HFENCE.GVMA after root setup.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. Misaligned LEVEL2 leaf PPN: HS HLV → Expected Fault (a3 stays 0)
//  2. Valid 4KiB leaf + HFENCE.GVMA: HS HLV → Successful (0x257A0D12)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_g_struct_sv39_HSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set gpa_data, 0x00000000C0000000
  .set gpa_code, 0x0000000080000000

  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL2)
  // Misaligned: LEVEL2 leaf pointing at 4KiB-aligned test_region (needs 1GiB align for Sv39)
  SUPERPAGE_G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL2)

  csrw vsatp, x0
  HGATP_SETUP(sv39x4)
  hfence.gvma

  LI(t0, 0x257A0D12)
  la t1, test_region
  sd t0, 0(t1)

  LI(t1, gpa_data)
  LI(a3, 0)
  RVTEST_TSBI_GOTO_SMODE
  hlv.d a3, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test1_misalign:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_misalign, test1_misalign_str)

  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_data, LEVEL2)
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)
  HGATP_SETUP(sv39x4)
  RVTEST_TSBI_GOTO_SMODE
  hfence.gvma
  LI(t1, gpa_data)
  hlv.d a4, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test2_ok:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_ok, test2_ok_str)

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
test1_misalign_str: .string "\"Mismatch on RV64 misaligned G superpage (expect fault) in Test Case 1!\""
test2_ok_str:       .string "\"Mismatch on RV64 restored G leaf HLV in Test Case 2!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
