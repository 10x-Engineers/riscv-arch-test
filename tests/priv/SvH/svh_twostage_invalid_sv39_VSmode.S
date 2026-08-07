// --------------------------------------------------------------------------------------------------------------------------------
// svh_twostage_invalid_sv39_VSmode.S
// Config: sail-rv64-max | VS=Sv39 + G=Sv39x4 both ON
// Pair:   svh_twostage_invalid_VSmode.S
// Coverpoints mapped (SvH_cg): VM_permission_invalid
// What this proves (one line):
//   Two-stage V=0 at VS or G denies loads with traps.
// Harness note (2026-08-07): clear medeleg/hedeleg so load-PF stays in M —
//   trap-sig Vector+Mode expects M-mode word 0x0dc4c35b (got HS 0x0019c359
//   when medeleg bit13 left at platform default).
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. VS leaf V=0, G valid: VS lw → Expected Fault (a3 stays 0)
//  2. VS valid, G leaf V=0: VS lw → Expected Fault (a4 stays 0)
//
// Total Expected Faults :: 2
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_twostage_invalid_sv39_VSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_data,                 0x008001000
  .set va_code,                 0x0000000090000000
  .set gpa_data,                0x00C002000
  .set gpa_code,                0x012000000
  .set gpa_rvtest_Vroot_pg_tbl, 0x01000A000
  .set gpa_rvtest_vlvl1_pg_tbl, 0x000000001000C000 // GPA of VS mid (LEVEL1) table
  .set gpa_rvtest_vlvl0_pg_tbl, 0x01000B000

  // Keep load/store page faults in M so trap-sig mode matches reference (mode=3).
  csrw medeleg, x0
  csrw hedeleg, x0

  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_code, LEVEL2)
  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL1)
  G_PTE_SETUP(sv39x4, rvtest_Vroot_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL0)
  G_PTE_SETUP(sv39x4, rvtest_vlvl1_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl1_pg_tbl, LEVEL0)
  G_PTE_SETUP(sv39x4, rvtest_vlvl0_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl0_pg_tbl, LEVEL0)
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)

  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)
  VS_PTE_SETUP(sv39, GPA, gpa_code, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)
  csrr a0, mscratch
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)

  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, (PTE_V), va_data, LEVEL2)
  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)
  // Case 1: VS V=0 leaf (A/D/R/W set, V clear)
  VS_PTE_SETUP(sv39, GPA, gpa_data, (PTE_D | PTE_A | PTE_W | PTE_R), va_data, LEVEL0)

  VSATP_SETUP(sv39, GPA)
  HGATP_SETUP(sv39x4)
  hfence.vvma
  hfence.gvma

  LI(t0, 0x257A0A01)
  la t1, test_region
  sw t0, 0(t1)

//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_data)
  LI(a3, 0)
  RVTEST_GOTO_LOWER_MODE VSmode
  lw   a3, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test1_vs_v0_lw:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_vs_v0_lw, test1_vs_v0_lw_str)

//---------------------------------------------------------------------------------------------------------------------------------
  // Restore VS valid; invalidate G data leaf
  VS_PTE_SETUP(sv39, GPA, gpa_data, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R), gpa_data, LEVEL0)
  hfence.vvma
  hfence.gvma

  LI(a5, va_data)
  LI(a4, 0)
  RVTEST_GOTO_LOWER_MODE VSmode
  lw   a4, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test2_g_v0_lw:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_g_v0_lw, test2_g_v0_lw_str)

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
.align 12
rvtest_hlvl1_pg_tbl:
  .zero(4096)
.align 12
rvtest_hlvl0_pg_tbl:
  .zero(4096)
test1_vs_v0_lw_str: .string "\"Mismatch on two-stage VS V=0 lw in Test Case 1!\""
test2_g_v0_lw_str:  .string "\"Mismatch on two-stage G V=0 lw in Test Case 2!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
