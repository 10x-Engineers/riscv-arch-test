// --------------------------------------------------------------------------------------------------------------------------------
// svh_twostage_invalid_VSmode.S
// Config: sail-rv32-max | VS=Sv32 + G=Sv32x4 both ON
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
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_twostage_invalid_VSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_data,                 0x008001000     // GVA VS lw will use (data)
  .set va_code,                 0x90000000      // GVA where VS executes this code (VA≠PA)
  .set gpa_data,                0x00C002000     // GPA behind va_data (G leaf → test_region SPA)
  .set gpa_code,                0x012000000     // GPA behind va_code (4 MiB aligned superpage)
  .set gpa_rvtest_Vroot_pg_tbl, 0x01000A000     // GPA of VS root page table (G must map for walks)
  .set gpa_rvtest_vlvl0_pg_tbl, 0x01000B000     // GPA of VS level-0 page table

  // Keep load/store page faults in M so trap-sig mode matches reference (mode=3).
  csrw medeleg, x0                              // clear M delegation — page/guest-page stay in M
  csrw hedeleg, x0                              // clear HS delegation so they do not land in HS

  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)  // gpa_code → PA(code); U=1 A=D=1 X/R (VS ifetch)
  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL1)  // G non-leaf: VPN1 for VS-root GPA → G L0
  G_PTE_SETUP(sv32x4, rvtest_Vroot_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL0)  // G leaf: VS-root GPA → PA(VS root) R/W A=D=1
  G_PTE_SETUP(sv32x4, rvtest_vlvl0_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl0_pg_tbl, LEVEL0)  // G leaf: VS-L0 GPA → PA(VS L0) R/W A=D=1
  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf: VPN1 for data GPA → G L0
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf: gpa_data → PA(test_region) R/W A=D=1 U=1

  VS_PTE_SETUP(sv32, GPA, gpa_code, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // VS superpage: va_code → gpa_code (X/R A=D=1) so VS can fetch
  csrr a0, mscratch                             // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: VS entry PC is under va_code (VA≠PA)

  VS_PTE_SETUP(sv32, GPA, gpa_rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)  // VS non-leaf: va_data VPN1 → VS L0 table GPA
  // Case 1: VS V=0 leaf (A/D/R/W set, V clear)
  VS_PTE_SETUP(sv32, GPA, gpa_data, (PTE_D | PTE_A | PTE_W | PTE_R), va_data, LEVEL0)  // VS leaf: va_data → gpa_data R/W A=D=1 V=0 (must page-fault)

  VSATP_SETUP(sv32, GPA)                        // vsatp = Sv32, PPN = GPA of VS root
  HGATP_SETUP(sv32x4)                           // hgatp = Sv32x4, PPN = G root
  hfence.vvma                                   // flush VS-stage TLB (must be M or HS)
  hfence.gvma                                   // flush G-stage TLB (illegal in VS/VU)

  LI(t0, 0x257A0A01)                            // known SPA preload (must not be read on fault cases)
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // write preload so a successful load would see it

//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_data)                               // a5 = GVA to load (VS leaf V=0)
  LI(a3, 0)                                     // sentinel — stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   a3, 0(a5)                                // VS load: VS leaf V=0 → load page-fault (a3 stays 0)
  nop                                           // trap-skip padding after faulting load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA)
  test1_vs_v0_lw:                               // signature dump point for case 1
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_vs_v0_lw, test1_vs_v0_lw_str)  // dump a3 (expect 0)

//---------------------------------------------------------------------------------------------------------------------------------
  // Restore VS valid; invalidate G data leaf
  VS_PTE_SETUP(sv32, GPA, gpa_data, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)  // VS leaf now V=1 R/W A=D=1 (VS walk OK)
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R), gpa_data, LEVEL0)  // G leaf: strip V; U=1 R/W A=D=1 (guest-page)
  hfence.vvma                                   // flush VS TLB after PTE rewrite
  hfence.gvma                                   // flush G TLB so V=0 G leaf is not cached

  LI(a5, va_data)                               // a5 = GVA to load (G leaf V=0)
  LI(a4, 0)                                     // sentinel — stays 0 if load guest-page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate
  lw   a4, 0(a5)                                // VS load: G leaf V=0 → guest-page fault (a4 stays 0)
  nop                                           // trap-skip padding after faulting load
  RVTEST_TSBI_GOTO_MMODE                       // return to M
  test2_g_v0_lw:                                // signature dump point for case 2
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_g_v0_lw, test2_g_v0_lw_str)  // dump a4 (expect 0)

RVTEST_CODE_END
RVTEST_DATA_BEGIN
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing gpa_data
  .word 0                                       // payload word (preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
test1_vs_v0_lw_str: .string "\"Mismatch on two-stage VS V=0 lw in Test Case 1!\""
test2_g_v0_lw_str:  .string "\"Mismatch on two-stage G V=0 lw in Test Case 2!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
