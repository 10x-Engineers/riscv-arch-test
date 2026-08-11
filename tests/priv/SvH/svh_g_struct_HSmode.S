// --------------------------------------------------------------------------------------------------------------------------------
// svh_g_struct_HSmode.S
// Config: sail-rv32-max | hgatp Sv32x4 structural faults
// Coverpoints mapped (SvH_cg): hgatp_misaligned_superpage, hgatp_root_table_alignment_and_size
// What this proves (one line):
//   Misaligned G superpage PPN faults; HFENCE.GVMA after root setup retires in HS.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. LEVEL1 leaf with misaligned PPN (not 4MiB-aligned): HS HLV → Expected Fault (a3 stays 0)
//  2. Restore aligned root + HFENCE.GVMA; HS HLV valid → Successful (0x257A0D02)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_g_struct_HSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

// Mode hops (Sv-style GOTO_* plus H T-SBI):
//   Enter PA/identity → RVTEST_TSBI_GOTO_VSMODE / _SMODE / _VUMODE
//   Enter VA≠PA (V_SAVE_AREA) → RVTEST_GOTO_LOWER_MODE
//   Return to M → always RVTEST_TSBI_GOTO_MMODE
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set gpa_data, 0x00C000000                     // 4MiB-aligned GPA for superpage attempt
  .set gpa_code, 0x80000000                     // identity GPA superpage for HS ifetch


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------
  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)  // gpa_code → PA(code); LEVEL1 = 4 MiB leaf

  // Misaligned LEVEL1 leaf: point at test_region which is only 4KiB-aligned (not 4MiB).
  // Sail should fault guest-page on walk (PPN[9:0] nonzero for Sv32x4 megapage).
  SUPERPAGE_G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL1)  // misaligned LEVEL1 leaf: PPN not 4 MiB aligned


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  csrw vsatp, x0                                // vsatp Bare (HS HLV uses G-stage only)
  HGATP_SETUP(sv32x4)                           // hgatp = Sv32x4, PPN = G root
  hfence.gvma                                   // flush G-stage TLB

  LI(t0, 0x257A0D02)                            // known SPA preload
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // write preload at SPA

// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: LEVEL1 leaf with misaligned PPN (not 4MiB-aligned): HS HLV | Expected: Expected Fault (a3 stays 0)
//---------------------------------------------------------------------------------------------------------------------------------

  LI(t1, gpa_data)                              // t1 = GPA for HS HLV
  LI(a3, 0)                                     // sentinel — stays 0 if HLV faults
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  hlv.w a3, (t1)                                // HS hyper-load of misaligned G superpage → fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test1_misalign:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_misalign, test1_misalign_str) // SIGUPD

  // Restore valid 4KiB leaf path + HFENCE (root alignment cover via hfence after setup)
  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf: data GPA VPN1 → G L0 (aligned path)
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf: gpa_data → PA(test_region) R/W U=1
  HGATP_SETUP(sv32x4)                           // rewrite hgatp after PTE restore
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  hfence.gvma                                   // scores root_alignment cross via fence after root write
  LI(t1, gpa_data)                              // t1 = GPA for HS HLV
  hlv.w a4, (t1)                                // HS hyper-load of aligned G leaf → success
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test2_ok:                                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_ok, test2_ok_str) // SIGUPD

RVTEST_CODE_END
RVTEST_DATA_BEGIN
// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing gpa_data
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)
  .word 0                                       // data word (initially 0)

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L0 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_misalign_str: .string "\"Mismatch on misaligned G superpage HLV (expect fault) in Test Case 1!\""
test2_ok_str:       .string "\"Mismatch on restored G leaf HLV in Test Case 2!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
