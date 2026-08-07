// --------------------------------------------------------------------------------------------------------------------------------
// svh_g_struct_HSmode.S
// Config: sail-rv32-max | hgatp Sv32x4 structural faults
// Coverpoints mapped (SvH_cg): hgatp_misaligned_superpage, hgatp_root_table_alignment_and_size
// What this proves (one line):
//   Misaligned G superpage PPN faults; HFENCE.GVMA after root setup retires in HS.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. LEVEL1 leaf with misaligned PPN (not 4MiB-aligned): HS HLV → Expected Fault (a3 stays 0)
//  2. Restore aligned root + HFENCE.GVMA; HS HLV valid → Successful (0x257A0D02)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_g_struct_HSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set gpa_data, 0x00C000000                     // 4MiB-aligned GPA for superpage attempt
  .set gpa_code, 0x80000000

  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)

  // Misaligned LEVEL1 leaf: point at test_region which is only 4KiB-aligned (not 4MiB).
  // Sail should fault guest-page on walk (PPN[9:0] nonzero for Sv32x4 megapage).
  SUPERPAGE_G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL1)

  csrw vsatp, x0
  HGATP_SETUP(sv32x4)
  hfence.gvma

  LI(t0, 0x257A0D02)
  la t1, test_region
  sw t0, 0(t1)

  LI(t1, gpa_data)
  LI(a3, 0)
  RVTEST_TSBI_GOTO_SMODE
  hlv.w a3, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test1_misalign:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_misalign, test1_misalign_str)

  // Restore valid 4KiB leaf path + HFENCE (root alignment cover via hfence after setup)
  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)
  HGATP_SETUP(sv32x4)
  RVTEST_TSBI_GOTO_SMODE
  hfence.gvma                                   // scores root_alignment cross via fence after root write
  LI(t1, gpa_data)
  hlv.w a4, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test2_ok:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_ok, test2_ok_str)

RVTEST_CODE_END
RVTEST_DATA_BEGIN
.align 12
test_region:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
rvtest_hlvl0_pg_tbl:
  .zero(4096)
test1_misalign_str: .string "\"Mismatch on misaligned G superpage HLV (expect fault) in Test Case 1!\""
test2_ok_str:       .string "\"Mismatch on restored G leaf HLV in Test Case 2!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
