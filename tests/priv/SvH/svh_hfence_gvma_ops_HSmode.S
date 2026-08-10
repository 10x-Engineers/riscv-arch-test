// --------------------------------------------------------------------------------------------------------------------------------
// svh_hfence_gvma_ops_HSmode.S
// Config: sail-rv32-max | HS HFENCE.GVMA rs1/rs2 variants
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
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_hfence_gvma_ops_HSmode.S"
#define SIGUPD_COUNT 3
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set gpa_data, 0x00C002000                    // GPA HS HLV will use (G leaf → test_region SPA)
  .set gpa_code, 0x80000000                     // GPA of code identity superpage (4 MiB aligned)

  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)  // G superpage: gpa_code → PA(code) U=1 X/R; LEVEL1 = 4 MiB
  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf: VPN1 for data GPA → G L0
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf: gpa_data → PA(test_region) U=1 R/W A=D=1

  csrw vsatp, x0                                // vsatp Bare — HLV address is a GPA (G-stage only)
  HGATP_SETUP(sv32x4)                           // hgatp = Sv32x4, PPN = G root

  LI(t0, 0x257A0921)                            // known SPA preload for case 1
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // SPA starts as 0x257A0921

  LI(a5, gpa_data)                              // a5 = GPA operand for HFENCE.GVMA rs1 and HLV
  LI(a6, 0)                                     // a6 = VMID 0 (matches hgatp VMID)

  RVTEST_TSBI_GOTO_SMODE                       // T-SBI: ecall a0=2 → HS (HFENCE.GVMA + HLV legal in HS)
  hfence.gvma a5, x0                            // HS HFENCE.GVMA GPA=a5, VMID=all: flush that GPA in G TLB
  hlv.w a3, (a5)                                // HS hypervisor load of GPA: G-stage walk → SPA; expect 0x257A0921
  nop                                           // trap-skip padding after HLV
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M
  test1_gpa:                                    // signature dump point for case 1
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_gpa, test1_gpa_str)  // record case 1 HLV result (expect 0x257A0921)

  LI(t0, 0x257A0922)                            // known SPA preload for case 2
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // SPA now 0x257A0922

  LI(a5, gpa_data)                              // a5 = GPA for HLV
  LI(a6, 0)                                     // a6 = VMID 0
  RVTEST_TSBI_GOTO_SMODE                       // M→HS
  hfence.gvma x0, a6                            // HS HFENCE.GVMA GPA=all, VMID=a6: flush that VMID in G TLB
  hlv.w a3, (a5)                                // HS HLV after VMID fence: expect 0x257A0922
  nop                                           // trap-skip padding after HLV
  RVTEST_TSBI_GOTO_MMODE                       // return to M
  test2_vmid:                                   // signature dump point for case 2
  RVTEST_SIGUPD(x2, x5, x4, a3, test2_vmid, test2_vmid_str)  // record case 2 HLV result (expect 0x257A0922)

  LI(t0, 0x257A0923)                            // known SPA preload for case 3
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // SPA now 0x257A0923

  LI(a5, gpa_data)                              // a5 = GPA operand + HLV address
  LI(a6, 0)                                     // a6 = VMID 0
  RVTEST_TSBI_GOTO_SMODE                       // M→HS
  hfence.gvma a5, a6                            // HS HFENCE.GVMA GPA=a5 + VMID=a6: flush that (GPA,VMID) pair
  hlv.w a3, (a5)                                // HS HLV after combined fence: expect 0x257A0923
  nop                                           // trap-skip padding after HLV
  RVTEST_TSBI_GOTO_MMODE                       // return to M
  test3_both:                                   // signature dump point for case 3
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_both, test3_both_str)  // record case 3 HLV result (expect 0x257A0923)

RVTEST_CODE_END
RVTEST_DATA_BEGIN
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing gpa_data
  .word 0                                       // data word (preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
test1_gpa_str:  .string "\"Mismatch on HFENCE.GVMA GPA + HLV in Test Case 1!\""
test2_vmid_str: .string "\"Mismatch on HFENCE.GVMA VMID + HLV in Test Case 2!\""
test3_both_str: .string "\"Mismatch on HFENCE.GVMA GPA+VMID + HLV in Test Case 3!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
