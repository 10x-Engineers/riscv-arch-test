// --------------------------------------------------------------------------------------------------------------------------------
// svh_gpa_width_VSmode.S
// Config: sail-rv64-max | vsatp=Bare, hgatp=Sv39x4, non-canonical GPA
// Coverpoints mapped (SvH_cg): cp_hgatp_gpa_width_checks
// What this proves (one line):
//   Non-canonical high GPA bits under Sv39x4 raise guest-page-fault.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. GPA with bit 41 set (beyond Sv39x4): VS Bare lw → Expected Fault (a3 stays 0)
//  2. Canonical GPA: VS Bare lw → Successful (0x257A0E02)
//  3. GPA with bit 41 set: VS Bare sw → Expected Fault (SPA stays 0x257A0E02)
//
// Total Expected Faults :: 2
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_gpa_width_VSmode.S"
#define SIGUPD_COUNT 3
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set gpa_ok,   0x00000000C002000              // canonical GPA (bits[63:41]=0) → test_region SPA
  .set gpa_wide, 0x00000200C002000              // bit 41 set — non-canonical for Sv39x4 (41-bit GPA)
  .set gpa_code, 0x0000000080000000             // identity GPA superpage for VS Bare ifetch


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------
  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL2)  // gpa_code → PA(code); LEVEL2 superpage U=1 X/R
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_ok, LEVEL2)  // G non-leaf: VPN2 for canonical GPA → G L1
  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_ok, LEVEL1)  // G non-leaf: VPN1 for canonical GPA → G L0
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_ok, LEVEL0)  // G leaf: gpa_ok → PA(test_region) R/W A=D=1 U=1


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  csrw vsatp, x0                                // VS Bare — address used as GPA (isolate G-stage width)
  HGATP_SETUP(sv39x4)                           // hgatp = Sv39x4, PPN = G root
  hfence.gvma                                   // flush G-stage TLB so next access rewalks

  LI(t0, 0x257A0E02)                            // known SPA pattern (success case 2 / store-fault check)
  la t1, test_region                            // t1 = SPA of data page
  sd t0, 0(t1)                                  // preload 64-bit pattern at SPA before guest access

// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: non-canonical GPA lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, gpa_wide)                              // a5 = non-canonical GPA (bit 41 set)
  LI(a3, 0)                                     // sentinel — stays 0 if load guest-page-faults
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  ld   a3, 0(a5)                                // VS Bare load of wide GPA → guest-page (a3 stays 0)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test1_wide:                                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_wide, test1_wide_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: canonical GPA lw | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, gpa_ok)                                // a5 = canonical GPA that the G leaf maps
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  ld   a4, 0(a5)                                // VS Bare load: GVA=GPA → SPA; expect 0x257A0E02
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  test2_ok:                                         // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_ok, test2_ok_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: non-canonical GPA sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, gpa_wide)                              // a5 = non-canonical GPA again
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA
  RVTEST_TSBI_GOTO_VSMODE                      // M→VS (T-SBI)
  sd   t0, 0(a5)                                // VS Bare store of wide GPA → guest-page (SPA unchanged)
  nop                                           // trap-skip pad
  RVTEST_GOTO_MMODE                       // →M (T-SBI)
  la t1, test_region                            // t1 = SPA
  ld a6, 0(t1)                                  // SPA must still be 0x257A0E02
  test3_wide_sw:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test3_wide_sw, test3_wide_sw_str) // SIGUPD

RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data
// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing canonical gpa_ok
  .dword 0                                      // 64-bit payload (preloaded in M)
  .dword 0                                      // padding in same page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_hlvl1_pg_tbl:                            // G-stage L0 PTE storage (LEVEL1 non-leaf points here)
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L1 PTE storage (LEVEL2 non-leaf points here)
  .zero(4096)                                   // reserve 4 KiB page-table page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_wide_str: .string "\"Mismatch on non-canonical GPA lw (expect fault) in Test Case 1!\""  // mismatch string
test2_ok_str:   .string "\"Mismatch on canonical GPA lw in Test Case 2!\""  // mismatch string
test3_wide_sw_str: .string "\"Mismatch on non-canonical GPA sw (SPA must stay) in Test Case 3!\""  // mismatch string
RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                Non-canonical high GPA bits under Sv39x4 raise gu...
  //                      │
  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 1                      Test 2                      Test 3          
  //                │                           │                           │             
  //       GPA with bit 41 set            Canonical GPA            GPA with bit 41 set    
  //                │                           │                           │             
  //            VS Bare lw                  VS Bare lw                  VS Bare sw        
  //                ▼                           ▼                           ▼             
  //            FAULT a3=0                  0x257A0E02            FAULT SPA 0x257A0E02)   
