// --------------------------------------------------------------------------------------------------------------------------------
// svh_xonly_mxr0_sv39_HSmode.S
// Config: sail-rv64-max | vsatp=Sv39, hgatp=Bare, HS HLV SPVP=1, MXR=0
// Pair:   svh_xonly_mxr0_HSmode.S
// Coverpoints mapped (SvH_cg): xonly_mxr0_vs_hs
// What this proves (one line):
//   HS HLV through VS X-only leaf with MXR=0 raises load-page-fault.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. MXR=0, SPVP=1, VS X-only: HS hlv.w → Expected Fault (a3 stays 0)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_xonly_mxr0_sv39_HSmode.S"
#define SIGUPD_COUNT 1
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_x, 0x008001000

  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_x, LEVEL2)
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_x, LEVEL1)
  VS_PTE_SETUP(sv39, PA, test_region_x, (PTE_D | PTE_A | PTE_X | PTE_V), va_x, LEVEL0)

  VSATP_SETUP(sv39, PA)
  csrw hgatp, x0
  hfence.vvma
  hfence.gvma

  LI(t0, SSTATUS_MXR | SSTATUS_SUM)
  csrc sstatus, t0
  csrc vsstatus, t0

  LI(t0, HSTATUS_SPVP)
  csrs hstatus, t0

  LI(t0, 0x257A0811)
  la t1, test_region_x
  sw t0, 0(t1)

  LI(a5, va_x)
  LI(a3, 0)
  RVTEST_TSBI_GOTO_SMODE
  hlv.w a3, (a5)
  nop
  RVTEST_TSBI_GOTO_MMODE

  LI(t0, HSTATUS_SPVP)
  csrc hstatus, t0

  test1_hlv:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_hlv, test1_hlv_str)

RVTEST_CODE_END
RVTEST_DATA_BEGIN
.align 12
test_region_x:
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
test1_hlv_str: .string "\"Mismatch on HS HLV X-only MXR=0 (expect fault) in Test Case 1!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
