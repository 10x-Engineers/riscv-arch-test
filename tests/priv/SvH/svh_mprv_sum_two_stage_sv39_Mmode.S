// --------------------------------------------------------------------------------------------------------------------------------
// svh_mprv_sum_two_stage_sv39_Mmode.S
// Config: sail-rv64-max | both stages ON; MPRV×SUM×U-page
// Pair:   svh_mprv_sum_two_stage_Mmode.S
// Coverpoints mapped (SvH_cg): mprv_sum_effect_hs_two_stage
// What this proves (one line):
//   MPRV load through both stages honors vsstatus.SUM on U=1 pages.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. MPRV=1 MPP=S MPV=1 SUM=0 U-page: lw → Expected Fault (a3 stays 0)
//  2. MPRV=1 MPP=S MPV=1 SUM=1 U-page: lw → Successful (0x257A0C02)
//  3. MPRV=1 MPP=S MPV=1 SUM=1 U-page: sw+lw → Successful (0x257A0C03)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_mprv_sum_two_stage_sv39_Mmode.S"
#define SIGUPD_COUNT 3
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_u,                    0x008001000
  .set gpa_data,                0x00C002000
  .set gpa_rvtest_Vroot_pg_tbl, 0x01000A000
  .set gpa_rvtest_vlvl1_pg_tbl, 0x000000001000C000 // GPA of VS mid (LEVEL1) table
  .set gpa_rvtest_vlvl0_pg_tbl, 0x01000B000

  // G maps VS PT + data (identity-ish GPA→PA for code not needed — stay in M)
  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL2)
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL1)
  G_PTE_SETUP(sv39x4, rvtest_Vroot_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL0)
  G_PTE_SETUP(sv39x4, rvtest_vlvl1_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl1_pg_tbl, LEVEL0)
  G_PTE_SETUP(sv39x4, rvtest_vlvl0_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl0_pg_tbl, LEVEL0)
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)

  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, (PTE_V), va_u, LEVEL2)
  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl0_pg_tbl, (PTE_V), va_u, LEVEL1)
  VS_PTE_SETUP(sv39, GPA, gpa_data, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), va_u, LEVEL0)

  VSATP_SETUP(sv39, GPA)
  HGATP_SETUP(sv39x4)
  csrw satp, x0
  hfence.vvma
  hfence.gvma

  LI(t0, 0x257A0C02)
  la t1, test_region
  sw t0, 0(t1)

  // MPRV=1, MPP=S, MPV=1
  LI(t0, MSTATUS_MPP)
  csrc mstatus, t0
  LI(t0, MPP_SMODE)
  csrs mstatus, t0
  LI(t0, MSTATUS_MPV)
  csrs mstatus, t0
  LI(t0, MSTATUS_MPRV)
  csrs mstatus, t0

  LI(t0, SSTATUS_SUM)
  csrc sstatus, t0
  csrc vsstatus, t0
  hfence.vvma

  LI(a5, va_u)
  LI(a3, 0)
  lw   a3, 0(a5)
  nop
  // clear MPRV before SIGUPD
  LI(t0, MSTATUS_MPRV)
  csrc mstatus, t0
  test1_sum0:
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_sum0, test1_sum0_str)

  LI(t0, SSTATUS_SUM)
  csrs sstatus, t0
  csrs vsstatus, t0
  hfence.vvma

  LI(t0, MSTATUS_MPRV)
  csrs mstatus, t0
  LI(a5, va_u)
  lw   a4, 0(a5)
  nop
  LI(t0, MSTATUS_MPRV)
  csrc mstatus, t0
  test2_sum1:
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_sum1, test2_sum1_str)

  // Case 3: SUM=1 store through both stages (scores write_acc on mprv_sum cross)
  LI(t0, MSTATUS_MPRV)
  csrs mstatus, t0
  LI(a5, va_u)
  LI(t0, 0x257A0C03)
  sw   t0, 0(a5)
  nop
  lw   a6, 0(a5)
  nop
  LI(t0, MSTATUS_MPRV)
  csrc mstatus, t0
  test3_sum1_sw:
  RVTEST_SIGUPD(x2, x5, x4, a6, test3_sum1_sw, test3_sum1_sw_str)

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
test1_sum0_str: .string "\"Mismatch on MPRV two-stage SUM=0 U-page (expect fault) in Test Case 1!\""
test2_sum1_str: .string "\"Mismatch on MPRV two-stage SUM=1 U-page lw in Test Case 2!\""
test3_sum1_sw_str: .string "\"Mismatch on MPRV two-stage SUM=1 U-page sw+lw in Test Case 3!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
