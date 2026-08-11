// --------------------------------------------------------------------------------------------------------------------------------
// svh_mprv_vsatp_sv39_Mmode.S
// Config: sail-rv64-max | M-mode MPRV×MPV×vsatp Sv39; hgatp/satp Bare
// Pair:   svh_mprv_vsatp_Mmode.S
// Coverpoints mapped (SvH_cg): cp_vsatp_mprv_effects
// What this proves (one line):
//   Same MPRV×vsatp effects on RV64 with Sv39 VS-stage.
// --------------------------------------------------------------------------------------------------------------------------------
// Test cases are as follows:
// --------------------------------------------------------------------------------------------------------------------------------
//  1. MPRV=0: M-mode lw of GVA without vsatp → Expected Fault (a3 stays 0)
//  2. MPRV=1, MPP=S, MPV=1: lw through vsatp S-page → Successful (0x257A0141)
//  3. MPRV=1, MPP=U, MPV=1: lw through vsatp U-page → Successful (0x257A0142)
//
// Total Expected Faults :: 1
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_mprv_vsatp_sv39_Mmode.S"
#define SIGUPD_COUNT 3
#define TRAP_SIGUPD_COUNT 16
#define RVTEST_HYPERVISOR

// Mode hops: none — stimulus stays in M. MPRV×MPP×MPV make M loads walk vsatp
// as if they were VS S/U; clear MPRV before every SIGUPD (signature not guest-mapped).
#include "riscv_arch_test.h"
RVTEST_BEGIN                                // framework: start code

main:                                       // test entry
// --------------------------------------------------------------------------------------------------------------------------------
//                                   Virtual addresses / GPA definitions
// --------------------------------------------------------------------------------------------------------------------------------
  .set va_s, 0x0000000080010000                 // guest VA for supervisor-style page (U=0)
  .set va_u, 0x0000000080020000                 // guest VA for user-style page (U=1)

// --------------------------------------------------------------------------------------------------------------------------------
//                                   Page-table setup (G-stage and/or VS-stage)
// --------------------------------------------------------------------------------------------------------------------------------

  // ---- VS-stage (vsatp Sv39): two pages — S (U=0) and U (U=1) for MPP matrix ----
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_s, LEVEL2)  // va_s VPN2 points at VS L1 table
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_s, LEVEL1)  // va_s VPN1 points at VS L0 table
  VS_PTE_SETUP(sv39, PA, test_region_s, (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V), va_s, LEVEL0)  // S leaf: R/W, U=0
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_u, LEVEL2)  // va_u VPN2 points at VS L1 table
  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_u, LEVEL1)  // va_u VPN1 points at VS L0 table
  VS_PTE_SETUP(sv39, PA, test_region_u, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), va_u, LEVEL0)  // U leaf: R/W, U=1


// --------------------------------------------------------------------------------------------------------------------------------
//                                   Enable translation / TLB fences / preloads
// --------------------------------------------------------------------------------------------------------------------------------
  VSATP_SETUP(sv39, PA)                         // write vsatp so VS-stage Sv39 translation can be used
  csrw hgatp, x0                                // G Bare — isolate vsatp MPRV effects
  csrw satp, x0                                 // S Bare — no HS satp walk during M-mode loads
  hfence.vvma                                   // flush VS TLB after vsatp setup
  hfence.gvma                                   // flush G TLB (hgatp Bare)

  LI(t0, 0x257A0141)                        // preload SPA
  la t1, test_region_s                      // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)
  LI(t0, 0x257A0142)                        // preload SPA
  la t1, test_region_u                      // t1 = SPA of data page
  sw t0, 0(t1)                              // SPA preload (known pattern before guest access)


// --------------------------------------------------------------------------------------------------------------------------------
//                                               Test Cases Start from here
// --------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: MPRV=0 load without vsatp | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  // MPRV matrix case: MPRV=0, MPV=0 → M-mode uses address as SPA (no vsatp walk) → fault
  LI(t0, MSTATUS_MPRV)                          // t0 = bit mask for MPRV
  csrc mstatus, t0                              // clear MPRV so M-mode uses raw addresses
  LI(t0, MSTATUS_MPV)                           // t0 = bit mask for MPV (RV64: in mstatus)
  csrc mstatus, t0                              // clear MPV so memory is not virtualized
  LI(a3, 0)                                     // a3 stays 0 if raw-address load is skipped by trap
  LI(a5, va_s)                                  // a5 = virtual-looking address, not a real PA
  lw   a3, 0(a5)                                // try M-mode load without vsatp translation
  nop                                           // trap-skip pad
  test1_mprv0:                                      // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_mprv0, test1_mprv0_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: MPRV=1, MPP=S, MPV=1 load S-page | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // MPRV matrix case: MPRV=1, MPP=S, MPV=1 → load walks vsatp as virtualized VS S-mode
  LI(t0, MSTATUS_MPP)                           // t0 = bit mask for MPP field
  csrc mstatus, t0                              // clear old MPP bits
  LI(t0, MPP_SMODE)                             // t0 = value that selects S-mode memory rules
  csrs mstatus, t0                              // set MPP=S in mstatus
  LI(t0, MSTATUS_MPV)                           // t0 = bit mask for MPV
  csrs mstatus, t0                              // set MPV so the lower-mode access is virtual (VS)
  LI(t0, MSTATUS_MPRV)                          // t0 = bit mask for MPRV
  csrs mstatus, t0                              // set MPRV so M-mode load uses MPP/MPV rules
  LI(a4, 0)                                     // a4 should receive the supervisor-page value
  LI(a5, va_s)                                  // a5 = supervisor-page guest virtual address
  lw   a4, 0(a5)                                // load through vsatp as virtualized S-mode
  nop                                           // trap-skip pad
  LI(t0, MSTATUS_MPRV)                          // t0 = bit mask for MPRV
  csrc mstatus, t0                              // MPRV off: vsatp maps only va_s/va_u, so the
                                                // signature access below must stay untranslated
  test2_mprv_s:                                     // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a4, test2_mprv_s, test2_mprv_s_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: MPRV=1, MPP=U, MPV=1 load U-page | Expected: Successful
//---------------------------------------------------------------------------------------------------------------------------------
  // MPRV matrix case: MPRV=1, MPP=U, MPV=1 → load walks vsatp as virtualized VS U-mode (U=1 page)
  LI(t0, MSTATUS_MPP)                           // t0 = bit mask for MPP field
  csrc mstatus, t0                              // clear MPP → MPP=U (00)
  LI(t0, MSTATUS_MPRV)                          // t0 = bit mask for MPRV
  csrs mstatus, t0                              // re-enable MPRV (cleared before the Test Case 2 dump);
                                                // MPV is still set, so this load runs as virtualized U
  LI(a6, 0)                                     // a6 should receive the user-page value
  LI(a5, va_u)                                  // a5 = user-page guest virtual address
  lw   a6, 0(a5)                                // load through vsatp as virtualized U-mode
  nop                                           // trap-skip pad

  LI(t0, MSTATUS_MPRV)                          // t0 = bit mask for MPRV
  csrc mstatus, t0                              // clear MPRV before finishing
  LI(t0, MSTATUS_MPV)                           // t0 = bit mask for MPV
  csrc mstatus, t0                              // clear MPV before finishing

  test3_mprv_u:                                    // SIGUPD label
  RVTEST_SIGUPD(x2, x5, x4, a6, test3_mprv_u, test3_mprv_u_str) // SIGUPD

//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END                             // framework: end code
RVTEST_DATA_BEGIN                           // framework: start data
// --------------------------------------------------------------------------------------------------------------------------------
//                                            PHYSICAL ADDRESS REGION FOR TESTING
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
test_region_s:                                  // real PA backing the supervisor-style page
  .word 0                                       // data slot for va_s
  .word 0                                       // padding in the same page
  .word 0                                       // padding in the same page
  .word 0                                       // padding in the same page
.align 12                                       // 4 KiB page align
test_region_u:                                  // real PA backing the user-style page
  .word 0                                       // data slot for va_u
  .word 0                                       // padding in the same page
  .word 0                                       // padding in the same page
  .word 0                                       // padding in the same page

// --------------------------------------------------------------------------------------------------------------------------------
//                                            Page-table storage
// --------------------------------------------------------------------------------------------------------------------------------
.align 12                                       // 4 KiB page align
rvtest_vlvl1_pg_tbl:                            // VS-stage level-1 PTE storage
  .zero(4096)                                   // reserve one page for VS L1 table
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage level-0 PTE storage
  .zero(4096)                                   // reserve one page for VS L0 table


// --------------------------------------------------------------------------------------------------------------------------------
//                                            Mismatch strings (SIGUPD)
// --------------------------------------------------------------------------------------------------------------------------------
test1_mprv0_str: .string "\"Mismatch on MPRV=0 load (expect fault) in Test Case 1!\""  // mismatch string
test2_mprv_s_str: .string "\"Mismatch on MPRV=1 MPP=S load in Test Case 2!\""  // mismatch string
test3_mprv_u_str: .string "\"Mismatch on MPRV=1 MPP=U load in Test Case 3!\""  // mismatch string

RVTEST_DATA_END                             // framework: end data
RVTEST_SIG_SETUP                            // framework: signature region



  //                Same MPRV×vsatp effects on RV64 with Sv39 VS-stage.
  //                      │
  //    ┌────────────────────────┬────────────────────────┬────────────────────────┐
  //                │                           │                           │             
  //              Test 1                      Test 2                      Test 3          
  //                │                           │                           │             
  //              MPRV=0               MPRV=1, MPP=S, MPV=1        MPRV=1, MPP=U, MPV=1   
  //                │                           │                           │             
  //     M-mode lw of GVA without    lw through vsatp S-page     lw through vsatp U-page  
  //                ▼                           ▼                           ▼             
  //            FAULT a3=0                  0x257A0141                  0x257A0142        
