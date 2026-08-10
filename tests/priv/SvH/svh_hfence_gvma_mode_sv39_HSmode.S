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
  .set gpa_data, 0x00C002000                    // GPA HS HLV uses after hgatp becomes Sv39x4
  .set gpa_code,                0x0000000080000000  // GPA of code identity superpage (1 GiB aligned for LEVEL2)

  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL2)  // G superpage: gpa_code → PA(code) U=1 X/R; LEVEL2 = 1 GiB
  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_data, LEVEL2)  // G non-leaf: VPN2 for data GPA → G L1
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf: VPN1 for data GPA → G L0
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf: gpa_data → PA(test_region) U=1 R/W A=D=1

  csrw vsatp, x0                                // vsatp Bare — HLV address is a GPA when G is on
  csrw hgatp, x0                                // start Bare (address used as-is until MODE switch)
  hfence.gvma                                   // flush G TLB after forcing Bare

  LI(t0, 0x257A0911)                            // known SPA preload for case 1
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // SPA starts as 0x257A0911

//---------------------------------------------------------------------------------------------------------------------------------
  HGATP_SETUP(sv39x4)                           // Bare → Sv39x4 (G paging now on)
  RVTEST_TSBI_GOTO_SMODE                       // T-SBI: ecall a0=2 → HS (fence + HLV legal in HS)
  hfence.gvma                                   // HS HFENCE.GVMA x0,x0 after MODE change: drop stale Bare G TLB
  LI(t1, gpa_data)                              // t1 = GPA (must walk G now, not treat as SPA)
  hlv.w a3, (t1)                                // HS HLV of GPA through new Sv39x4 map; expect 0x257A0911
  nop                                           // trap-skip padding after HLV
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M
  test1_bare_to_paged:                          // signature dump point for case 1
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_bare_to_paged, test1_bare_to_paged_str)  // record case 1 HLV (expect 0x257A0911)

//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0x257A0912)                            // known SPA preload for case 2
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // SPA now 0x257A0912

  csrw hgatp, x0                                // Sv39x4 → Bare (HLV address is now SPA)
  RVTEST_TSBI_GOTO_SMODE                       // M→HS
  hfence.gvma                                   // HS HFENCE.GVMA after MODE change: drop stale paged G TLB
  la t1, test_region                            // t1 = SPA (Bare: HLV uses address as-is)
  hlv.w a3, (t1)                                // HS HLV of SPA under Bare; expect 0x257A0912
  nop                                           // trap-skip padding after HLV
  RVTEST_TSBI_GOTO_MMODE                       // return to M
  test2_paged_to_bare:                          // signature dump point for case 2
  RVTEST_SIGUPD(x2, x5, x4, a3, test2_paged_to_bare, test2_paged_to_bare_str)  // record case 2 HLV (expect 0x257A0912)

RVTEST_CODE_END
RVTEST_DATA_BEGIN
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing gpa_data (and Bare HLV target)
  .word 0                                       // data word (preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
rvtest_hlvl1_pg_tbl:                            // G-stage L1 (mid) PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
test1_bare_to_paged_str: .string "\"Mismatch on Bare→Paged HFENCE.GVMA HLV in Test Case 1!\""
test2_paged_to_bare_str: .string "\"Mismatch on Paged→Bare HFENCE.GVMA HLV in Test Case 2!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
