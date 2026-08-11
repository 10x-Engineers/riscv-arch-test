// --------------------------------------------------------------------------------------------------------------------------------
// svh_hfence_gvma_ops_sv39_HSmode.S
// Config: sail-rv64-max | HS HFENCE.GVMA rs1/rs2 variants
// Pair:   svh_hfence_gvma_ops_HSmode.S
// Coverpoints mapped (SvH_cg): cp_hfence_gvma_operand
// What this proves (one line):
//   HS HFENCE.GVMA with GPA/VMID operand forms retires legally.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. HFENCE.GVMA a5,x0 (GPA) then HLV → Successful (0x257A0921)
//  2. HFENCE.GVMA x0,a6 (VMID) then HLV → Successful (0x257A0922)
//  3. HFENCE.GVMA a5,a6 then HLV → Successful (0x257A0923)
//
// Total Expected Faults :: 0
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_hfence_gvma_ops_sv39_HSmode.S"
#define SIGUPD_COUNT 3
#define TRAP_SIGUPD_COUNT 64
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
  .set gpa_data, 0x00C002000                    // GPA HS HLV will use (G leaf → test_region SPA)
  .set gpa_code,                0x0000000080000000  // GPA of code identity superpage (1 GiB aligned for LEVEL2)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------
  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL2)  // G superpage: gpa_code → PA(code) U=1 X/R; LEVEL2 = 1 GiB
  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_data, LEVEL2)  // G non-leaf: VPN2 for data GPA → G L1
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf: VPN1 for data GPA → G L0
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf: gpa_data → PA(test_region) U=1 R/W A=D=1


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  csrw vsatp, x0                                // vsatp Bare — HLV address is a GPA (G-stage only)
  HGATP_SETUP(sv39x4)                           // hgatp = Sv39x4, PPN = G root

  LI(t0, 0x257A0921)                            // known SPA preload for case 1
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // SPA starts as 0x257A0921

  LI(a5, gpa_data)                              // a5 = GPA operand for HFENCE.GVMA rs1 and HLV
  LI(a6, 0)                                     // a6 = VMID 0 (matches hgatp VMID)

// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: HFENCE.GVMA a5,x0 (GPA) then HLV | Expected: Successful (0x257A0921)
//---------------------------------------------------------------------------------------------------------------------------------

  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  hfence.gvma a5, x0                            // HS HFENCE.GVMA GPA=a5, VMID=all: flush that GPA in G TLB
  hlv.w a3, (a5)                                // HS hypervisor load of GPA: G-stage walk → SPA; expect 0x257A0921
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test1_gpa:                                        // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_gpa, test1_gpa_str) // SIGUPD

  LI(t0, 0x257A0922)                            // known SPA preload for case 2
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // SPA now 0x257A0922

  LI(a5, gpa_data)                              // a5 = GPA for HLV
  LI(a6, 0)                                     // a6 = VMID 0
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  hfence.gvma x0, a6                            // HS HFENCE.GVMA GPA=all, VMID=a6: flush that VMID in G TLB
  hlv.w a3, (a5)                                // HS HLV after VMID fence: expect 0x257A0922
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test2_vmid:                                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test2_vmid, test2_vmid_str) // SIGUPD

  LI(t0, 0x257A0923)                            // known SPA preload for case 3
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // SPA now 0x257A0923

  LI(a5, gpa_data)                              // a5 = GPA operand + HLV address
  LI(a6, 0)                                     // a6 = VMID 0
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  hfence.gvma a5, a6                            // HS HFENCE.GVMA GPA=a5 + VMID=a6: flush that (GPA,VMID) pair
  hlv.w a3, (a5)                                // HS HLV after combined fence: expect 0x257A0923
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test3_both:                                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_both, test3_both_str) // SIGUPD

RVTEST_CODE_END
RVTEST_DATA_BEGIN
// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing gpa_data
  .word 0                                       // data word (preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_hlvl1_pg_tbl:                            // G-stage L1 (mid) PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_gpa_str:  .string "\"Mismatch on HFENCE.GVMA GPA + HLV in Test Case 1!\""
test2_vmid_str: .string "\"Mismatch on HFENCE.GVMA VMID + HLV in Test Case 2!\""
test3_both_str: .string "\"Mismatch on HFENCE.GVMA GPA+VMID + HLV in Test Case 3!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
