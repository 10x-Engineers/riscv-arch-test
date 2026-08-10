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
  .set va_u,                    0x008001000     // GVA of U=1 data page (MPRV target)
  .set gpa_data,                0x00C002000     // GPA behind va_u
  .set gpa_rvtest_Vroot_pg_tbl, 0x01000A000     // GPA of VS root page table
  .set gpa_rvtest_vlvl1_pg_tbl, 0x000000001000C000 // GPA of VS mid (LEVEL1) table
  .set gpa_rvtest_vlvl0_pg_tbl, 0x01000B000     // GPA of VS L0 page table

  // G maps VS PT + data (identity-ish GPA→PA for code not needed — stay in M)
  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL2)  // G non-leaf: VS-root GPA VPN2 → G L1
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL1)  // G non-leaf: VS-root GPA VPN1 → G L0
  G_PTE_SETUP(sv39x4, rvtest_Vroot_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL0)  // G leaf: VS-root GPA → PA(VS root) R/W U=1
  G_PTE_SETUP(sv39x4, rvtest_vlvl1_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl1_pg_tbl, LEVEL0)  // G leaf: VS-L1 GPA → PA(VS L1) R/W U=1
  G_PTE_SETUP(sv39x4, rvtest_vlvl0_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl0_pg_tbl, LEVEL0)  // G leaf: VS-L0 GPA → PA(VS L0) R/W U=1
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf: data GPA VPN1 → G L0
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf: gpa_data → PA(test_region) R/W U=1

  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, (PTE_V), va_u, LEVEL2)  // VS non-leaf: va_u VPN2 → VS L1 table GPA
  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl0_pg_tbl, (PTE_V), va_u, LEVEL1)  // VS non-leaf: va_u VPN1 → VS L0 table GPA
  VS_PTE_SETUP(sv39, GPA, gpa_data, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), va_u, LEVEL0)  // VS leaf: va_u → gpa_data U=1 R/W (needs SUM)

  VSATP_SETUP(sv39, GPA)                        // vsatp = Sv39, PPN = GPA of VS root
  HGATP_SETUP(sv39x4)                           // hgatp = Sv39x4, PPN = G root
  csrw satp, x0                                 // HS satp Bare (only vsatp+hgatp translate)
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB

  LI(t0, 0x257A0C02)                            // known SPA preload
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // write preload so success cases have a known value

  // MPRV=1, MPP=S, MPV=1
  LI(t0, MSTATUS_MPP)                           // mask for MPP field
  csrc mstatus, t0                              // clear MPP
  LI(t0, MPP_SMODE)                             // MPP = S encoding
  csrs mstatus, t0                              // set MPP=S (MPRV uses S privilege)
  LI(t0, MSTATUS_MPV)                           // MPV bit (virtualized previous)
  csrs mstatus, t0                              // set MPV=1 so MPRV walks as VS
  LI(t0, MSTATUS_MPRV)                          // MPRV bit mask
  csrs mstatus, t0                              // MPRV=1: loads/stores use MPP/MPV translation

  LI(t0, SSTATUS_SUM)                           // SUM bit mask
  csrc sstatus, t0                              // clear HS SUM
  csrc vsstatus, t0                             // clear VS SUM — U=1 pages forbidden
  hfence.vvma                                   // flush TLB after SUM clear

  LI(a5, va_u)                                  // a5 = GVA of U=1 page
  LI(a3, 0)                                     // sentinel — stays 0 if load faults
  lw   a3, 0(a5)                                // MPRV two-stage load SUM=0 U=1 → fault
  nop                                           // trap-skip padding after faulting load
  // clear MPRV before SIGUPD
  LI(t0, MSTATUS_MPRV)                          // MPRV bit mask
  csrc mstatus, t0                              // clear MPRV before SIGUPD
  test1_sum0:                                   // signature dump point for case 1
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_sum0, test1_sum0_str)  // dump a3 (expect 0)

  LI(t0, SSTATUS_SUM)                           // SUM bit mask
  csrs sstatus, t0                              // set HS SUM
  csrs vsstatus, t0                             // set VS SUM — U=1 R/W allowed
  hfence.vvma                                   // flush TLB after SUM set

  LI(t0, MSTATUS_MPRV)                          // MPRV bit mask
  csrs mstatus, t0                              // re-enable MPRV for case 2 load
  LI(a5, va_u)                                  // a5 = GVA of U=1 page
  lw   a4, 0(a5)                                // MPRV two-stage load SUM=1 → expect preload
  nop                                           // trap-skip padding
  LI(t0, MSTATUS_MPRV)                          // MPRV bit mask
  csrc mstatus, t0                              // clear MPRV before SIGUPD
  test2_sum1:                                   // signature dump point for case 2
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_sum1, test2_sum1_str)  // dump a4 (expect 0x257A0C02)

  // Case 3: SUM=1 store through both stages (scores write_acc on mprv_sum cross)
  LI(t0, MSTATUS_MPRV)                          // MPRV bit mask
  csrs mstatus, t0                              // re-enable MPRV for case 3 store
  LI(a5, va_u)                                  // a5 = GVA of U=1 page
  LI(t0, 0x257A0C03)                            // new payload for SUM=1 store
  sw   t0, 0(a5)                                // MPRV two-stage store SUM=1 U=1 → success
  nop                                           // trap-skip padding after store
  lw   a6, 0(a5)                                // MPRV two-stage load back; expect 0x257A0C03
  nop                                           // trap-skip padding after load
  LI(t0, MSTATUS_MPRV)                          // MPRV bit mask
  csrc mstatus, t0                              // clear MPRV before SIGUPD
  test3_sum1_sw:                                // signature dump point for case 3
  RVTEST_SIGUPD(x2, x5, x4, a6, test3_sum1_sw, test3_sum1_sw_str)  // dump a6 (expect 0x257A0C03)

RVTEST_CODE_END
RVTEST_DATA_BEGIN
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing gpa_data
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)
.align 12                                       // 4 KiB page align
rvtest_vlvl1_pg_tbl:                            // VS-stage L1 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage L0 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage
.align 12                                       // 4 KiB page align
rvtest_hlvl1_pg_tbl:                            // G-stage L1 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L0 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage
test1_sum0_str: .string "\"Mismatch on MPRV two-stage SUM=0 U-page (expect fault) in Test Case 1!\""
test2_sum1_str: .string "\"Mismatch on MPRV two-stage SUM=1 U-page lw in Test Case 2!\""
test3_sum1_sw_str: .string "\"Mismatch on MPRV two-stage SUM=1 U-page sw+lw in Test Case 3!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
