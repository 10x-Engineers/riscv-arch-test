// --------------------------------------------------------------------------------------------------------------------------------
// svh_vu_rwx_two_stage_VUmode.S
// Config: sail-rv32-max | VS=Sv32 + G=Sv32x4, VU U=1 both stages
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
# REQUIRED_EXTENSIONS: [I, H, Sv32]
# MARCH: rv32ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_vu_rwx_two_stage_VUmode.S"
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
  .set va_data,                 0x008001000     // GVA VU sw/lw will use (allow path; U=1 both stages)
  .set va_deny,                 0x008002000     // GVA VU lw deny path (VS leaf U=0)
  .set va_code,                 0x90000000      // GVA where VU executes this code (VA≠PA)
  .set gpa_data,                0x00C002000     // GPA behind va_data (G leaf → test_region SPA)
  .set gpa_deny,                0x00C003000     // GPA behind va_deny (G leaf → test_region_deny SPA)
  .set gpa_code,                0x012000000     // GPA behind va_code (4 MiB aligned superpage)
  .set gpa_rvtest_Vroot_pg_tbl, 0x01000A000     // GPA of VS root page table
  .set gpa_rvtest_vlvl0_pg_tbl, 0x01000B000     // GPA of VS L0 table


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------
  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)  // G superpage: gpa_code → PA(code) U=1 X/R; LEVEL1 = 4 MiB
  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL1)  // G non-leaf: VPN1 for VS-root GPA → G L0
  G_PTE_SETUP(sv32x4, rvtest_Vroot_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL0)  // G leaf: VS-root GPA → PA(VS root) U=1 R/W
  G_PTE_SETUP(sv32x4, rvtest_vlvl0_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl0_pg_tbl, LEVEL0)  // G leaf: VS-L0 GPA → PA(VS L0) U=1 R/W
  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf: VPN1 for data/deny GPAs → G L0 (same 4 MiB)
  G_PTE_SETUP(sv32x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf: gpa_data → PA(test_region) U=1 XWR=111
  G_PTE_SETUP(sv32x4, test_region_deny, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), gpa_deny, LEVEL0)  // G leaf: gpa_deny → PA(test_region_deny) U=1 XWR=111 (G allows)

  VS_PTE_SETUP(sv32, GPA, gpa_code, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // VS superpage: va_code → gpa_code U=1 X/R (VU ifetch needs U=1)
  csrr a0, mscratch                             // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: VU entry PC is under va_code (VA≠PA)

  VS_PTE_SETUP(sv32, GPA, gpa_rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)  // VS non-leaf: va_data/va_deny VPN1 → VS L0 table GPA
  VS_PTE_SETUP(sv32, GPA, gpa_data, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)  // VS leaf: va_data → gpa_data U=1 XWR=111 (VU allow)
  VS_PTE_SETUP(sv32, GPA, gpa_deny, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V), va_deny, LEVEL0)  // VS leaf: va_deny → gpa_deny U=0 XWR=111 (VU must fault)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv32, GPA)                        // vsatp = Sv32, PPN = GPA of VS root
  HGATP_SETUP(sv32x4)                           // hgatp = Sv32x4, PPN = G root
  hfence.vvma                                   // flush VS-stage TLB
  hfence.gvma                                   // flush G-stage TLB

  LI(t0, 0x257A0B01)                            // known SPA preload / VU store payload
  la t1, test_region                            // t1 = SPA of allow page
  sw t0, 0(t1)                                  // SPA starts as 0x257A0B01

// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: Both U=1 XWR=111: VU sw+lw | Expected: Successful (0x257A0B01)
//---------------------------------------------------------------------------------------------------------------------------------

  LI(a5, va_data)                               // a5 = GVA allow pointer (U=1 both stages)
  LI(t0, 0x257A0B01)                            // payload VU will store (same as preload)
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  sw   t0, 0(a5)                                // VU store: GVA→GPA→SPA through U=1 XWR=111; expect success
  nop                                           // trap-skip pad
  lw   a3, 0(a5)                                // VU load same GVA; expect 0x257A0B01
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test1_allow:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_allow, test1_allow_str)  // record VU lw (expect 0x257A0B01)

  LI(a5, va_deny)                               // a5 = GVA deny pointer (VS leaf U=0)
  LI(a4, 0)                                     // sentinel — stays 0 if VU load page-faults
  RVTEST_GOTO_LOWER_MODE VUmode                 // M→VU (VA≠PA relocate)
  lw   a4, 0(a5)                                // VU load of U=0 VS leaf → page-fault (a4 stays 0)
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test2_deny:                                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_deny, test2_deny_str) // SIGUPD

RVTEST_CODE_END
RVTEST_DATA_BEGIN
// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing gpa_data (VU allow path)
  .word 0                                       // payload word (preloaded / stored by VU)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
.align 12                                       // 4 KiB page align
test_region_deny:                               // SPA backing gpa_deny (G allows; VS U=0 blocks VU)
  .word 0                                       // unused payload (VU must not reach here)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_allow_str: .string "\"Mismatch on VU two-stage U=1 RWX in Test Case 1!\""
test2_deny_str:  .string "\"Mismatch on VU two-stage U=0 deny in Test Case 2!\""
RVTEST_DATA_END
RVTEST_SIG_SETUP
