// --------------------------------------------------------------------------------------------------------------------------------
// svh_hfence_gvma_mode_sv39_HSmode.S
// Config: sail-rv64-max | Bare↔Sv39x4 + HFENCE.GVMA
// Pair:   svh_hfence_gvma_mode_HSmode.S
// Coverpoints mapped (SvH_cg): cp_hgatp_mode_change_hfence
// What this proves (one line):
//   Changing hgatp.MODE then HFENCE.GVMA keeps HS HLV coherent.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. hgatp Bare→Sv39x4 + HFENCE.GVMA x0,x0; HS HLV → Successful (0x257A0911)
//  2. hgatp Sv39x4→Bare + HFENCE.GVMA; HS HLV of SPA → Successful (0x257A0912)
//
// Total Expected Faults :: 0
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_hfence_gvma_mode_sv39_HSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set gpa_data, 0x00C002000
  .set gpa_code,                0x0000000080000000

  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL2)
  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_data, LEVEL2)
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)

  csrw vsatp, x0
  csrw hgatp, x0                                // start Bare
  hfence.gvma

  LI(t0, 0x257A0911)
  la t1, test_region
  sw t0, 0(t1)

//---------------------------------------------------------------------------------------------------------------------------------
  HGATP_SETUP(sv39x4)                           // Bare → paged
  RVTEST_TSBI_GOTO_SMODE
  hfence.gvma                                   // rs1=x0 after MODE change
  LI(t1, gpa_data)
  hlv.w a3, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test1_bare_to_paged:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_bare_to_paged, test1_bare_to_paged_str)

//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0x257A0912)
  la t1, test_region
  sw t0, 0(t1)

  csrw hgatp, x0                                // paged → Bare
  RVTEST_TSBI_GOTO_SMODE
  hfence.gvma
  la t1, test_region                            // SPA direct under Bare
  hlv.w a3, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test2_paged_to_bare:
  RVTEST_SIGUPD(x2, x5, x4, a3, test2_paged_to_bare, test2_paged_to_bare_str)

RVTEST_CODE_END
RVTEST_DATA_BEGIN
.align 12
test_region:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
rvtest_hlvl1_pg_tbl:
  .zero(4096)
.align 12
rvtest_hlvl0_pg_tbl:
  .zero(4096)
test1_bare_to_paged_str: .string "\"Mismatch on Bare→Paged HFENCE.GVMA HLV in Test Case 1!\""
test2_paged_to_bare_str: .string "\"Mismatch on Paged→Bare HFENCE.GVMA HLV in Test Case 2!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
