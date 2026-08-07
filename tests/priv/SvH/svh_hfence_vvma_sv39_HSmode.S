// --------------------------------------------------------------------------------------------------------------------------------
// svh_hfence_vvma_sv39_HSmode.S
// Config: sail-rv64-max | HS legal HFENCE.VVMA
// Pair:   svh_hfence_vvma_HSmode.S
// Coverpoints mapped (SvH_cg): cp_hfence_functionality, cp_hfence_vvma_operand
// What this proves (one line):
//   HS HFENCE.VVMA with rs1/rs2 variants retires; stale VS map refreshed after fence.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. HFENCE.VVMA x0,x0 then VS lw → Successful (0x257A0901)
//  2. HFENCE.VVMA a5,x0 (GVA) then VS lw → Successful (0x257A0902)
//  3. HFENCE.VVMA x0,a6 (ASID) then VS lw → Successful (0x257A0903)
//
// Total Expected Faults :: 0
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_hfence_vvma_sv39_HSmode.S"
#define SIGUPD_COUNT 3
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_data, 0x008001000
  .set va_code,                 0x0000000090000000

  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)
  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)
  csrr a0, mscratch
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)

  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_data, LEVEL2)
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)
  VS_PTE_SETUP(sv39, PA, test_region, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)

  VSATP_SETUP(sv39, PA)
  csrw hgatp, x0

  LI(t0, 0x257A0901)
  la t1, test_region
  sw t0, 0(t1)

//---------------------------------------------------------------------------------------------------------------------------------
  RVTEST_TSBI_GOTO_SMODE
  hfence.vvma                                   // rs1=x0 rs2=x0
  RVTEST_TSBI_GOTO_MMODE

  LI(a5, va_data)
  RVTEST_GOTO_LOWER_MODE VSmode
  lw   a3, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test1_all:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_all, test1_all_str)

//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0x257A0902)
  la t1, test_region
  sw t0, 0(t1)

  LI(a5, va_data)
  RVTEST_TSBI_GOTO_SMODE
  hfence.vvma a5, x0                            // GVA operand
  RVTEST_TSBI_GOTO_MMODE

  RVTEST_GOTO_LOWER_MODE VSmode
  lw   a3, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test2_gva:
  RVTEST_SIGUPD(x2, x5, x4, a3, test2_gva, test2_gva_str)

//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0x257A0903)
  la t1, test_region
  sw t0, 0(t1)

  LI(a5, va_data)
  LI(a6, 0)                                     // ASID=0
  RVTEST_TSBI_GOTO_SMODE
  hfence.vvma x0, a6                            // ASID operand
  RVTEST_TSBI_GOTO_MMODE

  RVTEST_GOTO_LOWER_MODE VSmode
  lw   a3, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test3_asid:
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_asid, test3_asid_str)

RVTEST_CODE_END
RVTEST_DATA_BEGIN
.align 12
test_region:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
rvtest_vlvl1_pg_tbl:
  .zero(4096)
.align 12
rvtest_vlvl0_pg_tbl:
  .zero(4096)
test1_all_str: .string "\"Mismatch on HFENCE.VVMA all + VS lw in Test Case 1!\""
test2_gva_str: .string "\"Mismatch on HFENCE.VVMA GVA + VS lw in Test Case 2!\""
test3_asid_str:.string "\"Mismatch on HFENCE.VVMA ASID + VS lw in Test Case 3!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
