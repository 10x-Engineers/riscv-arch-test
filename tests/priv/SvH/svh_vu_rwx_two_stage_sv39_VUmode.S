// --------------------------------------------------------------------------------------------------------------------------------
// svh_vu_rwx_two_stage_sv39_VUmode.S
// Config: sail-rv64-max | VS=Sv39 + G=Sv39x4, VU U=1 both stages
// Pair:   svh_vu_rwx_two_stage_VUmode.S
// Coverpoints mapped (SvH_cg): rwx_umode_pages_umode
// What this proves (one line):
//   VU R/W/X through both-stage U=1 pages; U=0 VS leaf denies.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. Both U=1 XWR=111: VU sw+lw → Successful (0x257A0B01)
//  2. VS leaf U=0: VU lw → Expected Fault (a4 stays 0)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vu_rwx_two_stage_sv39_VUmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_data,                 0x008001000
  .set va_deny,                 0x008002000
  .set va_code,                 0x0000000090000000
  .set gpa_data,                0x00C002000
  .set gpa_deny,                0x00C003000
  .set gpa_code,                0x012000000
  .set gpa_rvtest_Vroot_pg_tbl, 0x01000A000
  .set gpa_rvtest_vlvl1_pg_tbl, 0x000000001000C000 // GPA of VS mid (LEVEL1) table
  .set gpa_rvtest_vlvl0_pg_tbl, 0x01000B000

  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_code, LEVEL2)
  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL1)
  G_PTE_SETUP(sv39x4, rvtest_Vroot_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL0)
  G_PTE_SETUP(sv39x4, rvtest_vlvl1_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl1_pg_tbl, LEVEL0)
  G_PTE_SETUP(sv39x4, rvtest_vlvl0_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl0_pg_tbl, LEVEL0)
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)
  G_PTE_SETUP(sv39x4, test_region_deny, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), gpa_deny, LEVEL0)

  // VU code leaf needs U=1
  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)
  VS_PTE_SETUP(sv39, GPA, gpa_code, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)
  csrr a0, mscratch
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)

  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, (PTE_V), va_data, LEVEL2)
  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)
  VS_PTE_SETUP(sv39, GPA, gpa_data, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)
  VS_PTE_SETUP(sv39, GPA, gpa_deny, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V), va_deny, LEVEL0)  // U=0 deny for VU

  VSATP_SETUP(sv39, GPA)
  HGATP_SETUP(sv39x4)
  hfence.vvma
  hfence.gvma

  LI(t0, 0x257A0B01)
  la t1, test_region
  sw t0, 0(t1)

  LI(a5, va_data)
  LI(t0, 0x257A0B01)
  RVTEST_GOTO_LOWER_MODE VUmode
  sw   t0, 0(a5)
  nop
  lw   a3, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test1_allow:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_allow, test1_allow_str)

  LI(a5, va_deny)
  LI(a4, 0)
  RVTEST_GOTO_LOWER_MODE VUmode
  lw   a4, 0(a5)
  nop
  RVTEST_TSBI_GOTO_MMODE
  test2_deny:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_deny, test2_deny_str)

RVTEST_CODE_END
RVTEST_DATA_BEGIN
.align 12
test_region:
  .word 0
  .word 0
  .word 0
  .word 0
.align 12
test_region_deny:
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
test1_allow_str: .string "\"Mismatch on VU two-stage U=1 RWX in Test Case 1!\""
test2_deny_str:  .string "\"Mismatch on VU two-stage U=0 deny in Test Case 2!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
