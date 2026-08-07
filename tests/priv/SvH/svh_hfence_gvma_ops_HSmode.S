// --------------------------------------------------------------------------------------------------------------------------------
// svh_hfence_gvma_ops_HSmode.S
// Config: sail-rv32-max | HS HFENCE.GVMA rs1/rs2 variants
// Coverpoints mapped (SvH_cg): cp_hfence_gvma_operand
// What this proves (one line):
//   HS HFENCE.GVMA with GPA/VMID operand forms retires legally.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. HFENCE.GVMA a5,x0 (GPA) then HLV → Successful (0x257A0921)
//  2. HFENCE.GVMA x0,a6 (VMID) then HLV → Successful (0x257A0922)
//  3. HFENCE.GVMA a5,a6 then HLV → Successful (0x257A0923)
//
// Total Expected Faults :: 0
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_hfence_gvma_ops_HSmode.S"
#define SIGUPD_COUNT 3
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set gpa_data, 0x00C002000
  .set gpa_code, 0x80000000

  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)
  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)

  csrw vsatp, x0
  HGATP_SETUP(sv32x4)

  LI(t0, 0x257A0921)
  la t1, test_region
  sw t0, 0(t1)

  LI(a5, gpa_data)
  LI(a6, 0)

  RVTEST_TSBI_GOTO_SMODE
  hfence.gvma a5, x0
  hlv.w a3, (a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test1_gpa:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_gpa, test1_gpa_str)

  LI(t0, 0x257A0922)
  la t1, test_region
  sw t0, 0(t1)

  LI(a5, gpa_data)
  LI(a6, 0)
  RVTEST_TSBI_GOTO_SMODE
  hfence.gvma x0, a6
  hlv.w a3, (a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test2_vmid:
  RVTEST_SIGUPD(x2, x5, x4, a3, test2_vmid, test2_vmid_str)

  LI(t0, 0x257A0923)
  la t1, test_region
  sw t0, 0(t1)

  LI(a5, gpa_data)
  LI(a6, 0)
  RVTEST_TSBI_GOTO_SMODE
  hfence.gvma a5, a6
  hlv.w a3, (a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test3_both:
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_both, test3_both_str)

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
test1_gpa_str:  .string "\"Mismatch on HFENCE.GVMA GPA + HLV in Test Case 1!\""
test2_vmid_str: .string "\"Mismatch on HFENCE.GVMA VMID + HLV in Test Case 2!\""
test3_both_str: .string "\"Mismatch on HFENCE.GVMA GPA+VMID + HLV in Test Case 3!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
