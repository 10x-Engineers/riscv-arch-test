// --------------------------------------------------------------------------------------------------------------------------------
// svh_xonly_mxr0_VSmode.S
// Config: sail-rv32-max | VS=Sv32 ON, hgatp=Bare, MXR=0
// Coverpoints mapped (SvH_cg): xonly_mxr0_vs_vs
// What this proves (one line):
//   VS load of X-only page with MXR=0 raises load-page-fault.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. MXR=0 SUM=0, S-page X-only: VS lw → Expected Fault (a3 stays 0)
//  2. MXR=0 SUM=0, S-page X-only: VS ifetch OK on code (control) → Successful (a4=0x257A0802)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_xonly_mxr0_VSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_x,    0x008001000
  .set va_code, 0x90000000

  SUPERPAGE_VS_PTE_SETUP(sv32, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)
  csrr a0, mscratch
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)

  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_x, LEVEL1)
  VS_PTE_SETUP(sv32, PA, test_region_x, (PTE_D | PTE_A | PTE_X | PTE_V), va_x, LEVEL0)

  VSATP_SETUP(sv32, PA)
  csrw hgatp, x0
  hfence.vvma
  hfence.gvma

  LI(t0, SSTATUS_MXR | SSTATUS_SUM)
  csrc sstatus, t0
  csrc vsstatus, t0

  LI(t0, 0x257A0801)
  la t1, test_region_x
  sw t0, 0(t1)

//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_x)
  LI(a3, 0)
  RVTEST_GOTO_LOWER_MODE VSmode
  lw   a3, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test1_mxr0_lw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_mxr0_lw, test1_mxr0_lw_str)

//---------------------------------------------------------------------------------------------------------------------------------
  LI(a4, 0x257A0801)
  addi a4, a4, 1
  test2_ctrl:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_ctrl, test2_ctrl_str)

RVTEST_CODE_END
RVTEST_DATA_BEGIN
.align 12
test_region_x:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
rvtest_vlvl0_pg_tbl:
  .zero(4096)
test1_mxr0_lw_str: .string "\"Mismatch on VS X-only MXR=0 lw (expect fault) in Test Case 1!\""
test2_ctrl_str:    .string "\"Mismatch on control addi in Test Case 2!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
