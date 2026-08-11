// --------------------------------------------------------------------------------------------------------------------------------
// svh_g_struct_sv39_HSmode.S
// Config: sail-rv64-max | hgatp Sv39x4 structural (twin of RV32)
// Coverpoints mapped (SvH_cg): hgatp_misaligned_superpage, hgatp_root_table_alignment_and_size
// What this proves (one line):
//   RV64 twin: misaligned G megapage faults; HFENCE.GVMA after root setup.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. Misaligned LEVEL2 leaf PPN: HS HLV → Expected Fault (a3 stays 0)
//  2. Valid 4KiB leaf + HFENCE.GVMA: HS HLV → Successful (0x257A0D12)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_g_struct_sv39_HSmode.S"
#define SIGUPD_COUNT 2
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set gpa_data, 0x00000000C0000000             // 1 GiB-aligned GPA for superpage attempt
  .set gpa_code, 0x0000000080000000             // identity GPA superpage for HS ifetch


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------
  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL2)  // gpa_code → PA(code); LEVEL2 = 1 GiB leaf
  // Misaligned: LEVEL2 leaf pointing at 4KiB-aligned test_region (needs 1GiB align for Sv39)
  SUPERPAGE_G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL2)  // misaligned LEVEL2 leaf: PPN not 1 GiB aligned


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  csrw vsatp, x0                                // vsatp Bare (HS HLV uses G-stage only)
  HGATP_SETUP(sv39x4)                           // hgatp = Sv39x4, PPN = G root
  hfence.gvma                               // flush G-stage TLB (must be M or HS — illegal in VS/VU)

  LI(t0, 0x257A0D12)                            // known SPA preload
  la t1, test_region                            // t1 = SPA of data page
  sd t0, 0(t1)                                  // write preload at SPA (64-bit)

// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: Misaligned LEVEL2 leaf PPN: HS HLV | Expected: Expected Fault (a3 stays 0)
//---------------------------------------------------------------------------------------------------------------------------------

  LI(t1, gpa_data)                              // t1 = GPA for HS HLV
  LI(a3, 0)                                     // sentinel — stays 0 if HLV faults
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  hlv.d a3, (t1)                                // HS hyper-load of misaligned G megapage → fault
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test1_misalign:                                   // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_misalign, test1_misalign_str) // SIGUPD

  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_data, LEVEL2)  // G non-leaf: data GPA VPN2 → G L1
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf: data GPA VPN1 → G L0
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf: gpa_data → PA(test_region) R/W U=1
  HGATP_SETUP(sv39x4)                           // rewrite hgatp after PTE restore
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  hfence.gvma                                   // flush G TLB after root rewrite (scores root alignment)
  LI(t1, gpa_data)                              // t1 = GPA for HS HLV
  hlv.d a4, (t1)                                // HS hyper-load of aligned G leaf → success
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test2_ok:                                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_ok, test2_ok_str) // SIGUPD

RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data
// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing gpa_data
  .dword 0                                      // data dword (initially 0)
  .dword 0                                      // data dword (initially 0)

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_hlvl1_pg_tbl:                            // G-stage L1 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L0 PTE storage
  .zero(4096)                                   // 4 KiB page-table storage

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_misalign_str: .string "\"Mismatch on RV64 misaligned G superpage (expect fault) in Test Case 1!\""  // mismatch string
test2_ok_str:       .string "\"Mismatch on RV64 restored G leaf HLV in Test Case 2!\""  // mismatch string
RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                RV64 twin: misaligned G megapage faults; HFENCE.G...
  //                      │
  //         ┌────────────┴────────────┐
  //         │                         │
  //      Test 1                             Test 2
  //         │                         │
  //      Misaligned LEVEL2          Valid 4KiB leaf +
  //         │                         │
  //      HS HLV                     HS HLV
  //         ▼                         ▼
  //      FAULT a3=0                 0x257A0D12
