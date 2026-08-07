// --------------------------------------------------------------------------------------------------------------------------------
// svh_xonly_mxr0_gstage_sv39_HSmode.S
// Config: sail-rv64-max | vsatp=Bare, hgatp=Sv39x4, HS HLV, MXR=0
// Pair:   svh_xonly_mxr0_gstage_HSmode.S
// Coverpoints mapped (SvH_cg): xonly_mxr0_g_hs
// What this proves (one line):
//   HS HLV of G-stage X-only leaf with MXR=0 raises guest-page-fault.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. G X-only U=1, MXR=0: HS hlv.w → Expected Fault (a3 stays 0)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_xonly_mxr0_gstage_sv39_HSmode.S"
#define SIGUPD_COUNT 1
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set gpa_data, 0x00C002000
  .set gpa_code,                0x0000000080000000

  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL2)
  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_data, LEVEL2)
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V), gpa_data, LEVEL0)

  csrw vsatp, x0
  HGATP_SETUP(sv39x4)
  hfence.vvma
  hfence.gvma

  LI(t0, SSTATUS_MXR)
  csrc sstatus, t0
  csrc vsstatus, t0

  LI(t0, 0x257A0821)
  la t1, test_region
  sw t0, 0(t1)

  LI(t1, gpa_data)
  LI(a3, 0)
  RVTEST_TSBI_GOTO_SMODE
  hlv.w a3, (t1)
  nop
  RVTEST_TSBI_GOTO_MMODE

  test1_g_xonly:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_g_xonly, test1_g_xonly_str)

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
test1_g_xonly_str: .string "\"Mismatch on HS HLV G X-only MXR=0 (expect fault) in Test Case 1!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
