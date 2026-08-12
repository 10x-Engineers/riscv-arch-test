// --------------------------------------------------------------------------------------------------------------------------------
// svh_hfence_vvma_sv39_HSmode.S
// Config: sail-rv64-max | HS legal HFENCE.VVMA
// Pair:   svh_hfence_vvma_HSmode.S
// Coverpoints mapped (SvH_cg): cp_hfence_functionality, cp_hfence_vvma_operand
// What this proves (one line):
//   HS HFENCE.VVMA with rs1/rs2 variants retires; stale VS map refreshed after fence.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. HFENCE.VVMA x0,x0 then VS lw → Successful (0x257A0901)
//  2. HFENCE.VVMA a5,x0 (GVA) then VS lw → Successful (0x257A0902)
//  3. HFENCE.VVMA x0,a6 (ASID) then VS lw → Successful (0x257A0903)
//
// Total Expected Faults :: 0
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_hfence_vvma_sv39_HSmode.S"
#define SIGUPD_COUNT 3
#define TRAP_SIGUPD_COUNT 64
#define RVTEST_HYPERVISOR

#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set va_data, 0x008001000                     // GVA VS lw will use (data)
  .set va_code,                 0x0000000090000000  // GVA where VS executes this code (VA≠PA)


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)  // VS non-leaf: va_code VPN2 → VS L1 table PA
  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // VS leaf: va_code → PA(code) X/R A=D=1; LEVEL1 = 2 MiB
  csrr a0, mscratch                         // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // VA≠PA code entry

  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_data, LEVEL2)  // VS non-leaf: va_data VPN2 → VS L1 table PA
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)  // VS non-leaf: va_data VPN1 → VS L0 table PA
  VS_PTE_SETUP(sv39, PA, test_region, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)  // VS leaf: va_data → PA(test_region) W/R A=D=1 U=0


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv39, PA)                         // vsatp = Sv39, PPN = PA of VS root (single-stage)
  csrw hgatp, x0                                // hgatp Bare — GVA→PA only (no G-stage)

  LI(t0, 0x257A0901)                        // preload SPA
  la t1, test_region                        // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: HFENCE.VVMA x0,x0 then VS lw | Expected: Successful (0x257A0901)
//---------------------------------------------------------------------------------------------------------------------------------
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  hfence.vvma                                   // HS HFENCE.VVMA x0,x0: flush all VS-stage TLB (all ASIDs + GVAs)
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  LI(a5, va_data)                               // a5 = GVA pointer for VS load
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a3, 0(a5)                                // VS load after all-ASID fence: GVA→PA; expect 0x257A0901
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test1_all:                                        // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_all, test1_all_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: HFENCE.VVMA a5,x0 (GVA) then VS lw | Expected: Successful (0x257A0902)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0x257A0902)                        // preload SPA
  la t1, test_region                        // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)

  LI(a5, va_data)                               // a5 = GVA operand for HFENCE.VVMA rs1 and later VS lw
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  hfence.vvma a5, x0                            // HS HFENCE.VVMA GVA=a5, ASID=all: flush that GVA in VS TLB
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a3, 0(a5)                                // VS load after GVA-operand fence: expect 0x257A0902
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test2_gva:                                        // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test2_gva, test2_gva_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: HFENCE.VVMA x0,a6 (ASID) then VS lw | Expected: Successful (0x257A0903)
//---------------------------------------------------------------------------------------------------------------------------------
  LI(t0, 0x257A0903)                        // preload SPA
  la t1, test_region                        // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)

  LI(a5, va_data)                               // a5 = GVA pointer for VS load
  LI(a6, 0)                                     // a6 = ASID 0 (matches vsatp ASID)
  RVTEST_TSBI_GOTO_SMODE                       // M→HS (T-SBI)
  hfence.vvma x0, a6                            // HS HFENCE.VVMA GVA=all, ASID=a6: flush that ASID in VS TLB
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)

  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS (VA≠PA relocate)
  lw   a3, 0(a5)                                // VS load after ASID-operand fence: expect 0x257A0903
  nop                                           // trap-skip pad
  RVTEST_TSBI_GOTO_MMODE                       // →M (T-SBI)
  test3_asid:                                       // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test3_asid, test3_asid_str) // SIGUPD

RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data
// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing va_data (VS leaf → this PA)
  .word 0                                       // data word (preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_vlvl1_pg_tbl:                            // VS-stage L1 (mid) PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_all_str: .string "\"Mismatch on HFENCE.VVMA all + VS lw in Test Case 1!\""  // mismatch string
test2_gva_str: .string "\"Mismatch on HFENCE.VVMA GVA + VS lw in Test Case 2!\""  // mismatch string
test3_asid_str:.string "\"Mismatch on HFENCE.VVMA ASID + VS lw in Test Case 3!\""  // mismatch string
RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                HS HFENCE.VVMA with rs1/rs2 variants retires; sta...
  //                      │
  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 1                      Test 2                      Test 3          
  //                │                           │                           │             
  //      HFENCE.VVMA x0,x0 then     HFENCE.VVMA a5,x0 (GVA)     HFENCE.VVMA x0,a6 (ASID) 
  //                ▼                           ▼                           ▼             
  //            0x257A0901                  0x257A0902                  0x257A0903        
