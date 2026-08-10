// --------------------------------------------------------------------------------------------------------------------------------
// svh_xonly_mxr0_sv39_VUmode.S
// Config: sail-rv64-max | VS=Sv39 ON, hgatp=Bare, MXR=0, VU
// Pair:   svh_xonly_mxr0_VUmode.S
// Coverpoints mapped (SvH_cg): xonly_mxr0_vs_vu
// What this proves (one line):
//   VU load of U=1 X-only page with MXR=0 raises load-page-fault.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. MXR=0, U-page X-only: VU lw → Expected Fault (a3 stays 0)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_xonly_mxr0_sv39_VUmode.S"
#define SIGUPD_COUNT 1
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_x_u,  0x008002000                     // GVA of U=1 X-only data page (VU lw target)
  .set va_code,                 0x0000000090000000  // GVA where VU executes this code (VA≠PA; U=1 X/R)

  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)  // VS non-leaf: va_code VPN2 → VS L1 table PA
  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // VS leaf: va_code → PA(code) U=1 X/R; LEVEL1 = 2 MiB
  csrr a0, mscratch                             // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: VU entry PC is under va_code (VA≠PA)

  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_x_u, LEVEL2)  // VS non-leaf: va_x_u VPN2 → VS L1 table PA
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_x_u, LEVEL1)  // VS non-leaf: va_x_u VPN1 → VS L0 table PA
  VS_PTE_SETUP(sv39, PA, test_region_x, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_V), va_x_u, LEVEL0)  // VS leaf: va_x_u → PA(test_region_x) U=1 X-only (R=0 W=0)

  VSATP_SETUP(sv39, PA)                         // vsatp = Sv39, PPN = PA of VS root
  csrw hgatp, x0                                // hgatp Bare — GVA→PA only
  hfence.vvma                                   // flush VS-stage TLB after PTE install
  hfence.gvma                                   // flush G-stage TLB (none, but keep walks coherent)

  LI(t0, SSTATUS_MXR | SSTATUS_SUM)             // bits to clear: MXR (X-as-R) and SUM
  csrc sstatus, t0                              // HS sstatus: MXR=0 SUM=0
  csrc vsstatus, t0                             // vsstatus: MXR=0 so VU cannot read X-only

  LI(t0, 0xDEADBEEF)                            // poison at SPA — successful lw would copy this into a3
  la t1, test_region_x                          // t1 = SPA of X-only U page
  sw t0, 0(t1)                                  // M can store via PA (no VS perms)

  LI(a5, va_x_u)                                // a5 = GVA of U=1 X-only page
  LI(a3, 0)                                     // sentinel — stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU mret + PA↔VA relocate (guest code VA≠PA)
  lw   a3, 0(a5)                                // VU load X-only U-page with MXR=0 → load page-fault (a3 stays 0)
  nop                                           // trap-skip padding after faulting load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA)
  test1_mxr0_vu:                                // signature dump point for case 1
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_mxr0_vu, test1_mxr0_vu_str)  // dump a3 (expect 0)

RVTEST_CODE_END
RVTEST_DATA_BEGIN
.align 12                                       // 4 KiB page align
test_region_x:                                  // SPA backing va_x_u (U=1 X-only VS leaf)
  .word 0                                       // payload word (preloaded in M; VU must not read)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
rvtest_vlvl1_pg_tbl:                            // VS-stage L1 (mid) PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
test1_mxr0_vu_str: .string "\"Mismatch on VU X-only MXR=0 lw (expect fault) in Test Case 1!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
