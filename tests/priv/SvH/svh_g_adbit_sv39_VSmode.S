// --------------------------------------------------------------------------------------------------------------------------------
// svh_g_adbit_sv39_VSmode.S
// Config: sail-rv64-max | VS=Sv39 + G=Sv39x4 (both ON), Svade (ADUE=0)
// Pair:   svh_g_adbit_VSmode.S
// Coverpoints mapped (SvH_cg): cp_hgatp_adbit_behavior, cp_hgatp_adbit_behavior_x,
//   cp_hgatp_adbit_vs_ad_rw, cp_hgatp_adbit_vs_ad_x
// What this proves (one line):
//   G A/D on implicit VS page-table walks: A=D=0 → guest-page; VS leaf A=D=00 → page fault.
// --------------------------------------------------------------------------------------------------------------------------------
// Environment: G PTE that maps VS L0 table has A=D=0 R/W U=1. VS leaf A=D={11,00} XWR=111.
// Test: VS lw / sw / jalr so hardware implicitly reads VS PTEs through that G PTE.
// Svade + menvcfg/henvcfg.ADUE=0 → fault (type follows original access). ADUE=1 would update A/D.
// --------------------------------------------------------------------------------------------------------------------------------
//  1. G-for-VS-L0 A=D=0, VS leaf A=D=11: VS lw  → Expected Fault (guest-page; a3 stays 0)
//  2. Same PTEs:                          VS sw  → Expected Fault (SPA stays 0x257A0251)
//  3. Same PTEs:                          VS jalr → Expected Fault (s4 stays 0)
//  4. G-for-VS-L0 A=D=1, VS leaf A=D=00: VS lw  → Expected Fault (page-fault; a4 stays 0)
//  5. Same PTEs:                          VS sw  → Expected Fault (SPA stays 0x257A0251)
//  6. Same PTEs:                          VS jalr → Expected Fault (s5 stays 0)
//
// Total Expected Faults :: 6
// --------------------------------------------------------------------------------------------------------------------------------

##### START_TEST_CONFIG #####
# REQUIRED_EXTENSIONS: [I, H, Sv39]
# MARCH: rv64ih_zicsr_zifencei
##### END_TEST_CONFIG #####

#define TEST_FILE "svh_g_adbit_sv39_VSmode.S"
#define SIGUPD_COUNT 6
#define TRAP_SIGUPD_COUNT 256
#define RVTEST_HYPERVISOR

// Mode hops (T-SBI) — return-to-M always uses RVTEST_TSBI_GOTO_MMODE (ecall a0=1;
//   handler rtn2mmode relocates EPC VA→PA). Enter:
//   • Code at PA / identity: RVTEST_TSBI_GOTO_VSMODE / _SMODE (ecall a0=4/2)
//   • Guest code VA≠PA (V_SAVE_AREA_*): RVTEST_GOTO_LOWER_MODE (mret + PA↔VA relocate)
#include "riscv_arch_test.h"

RVTEST_BEGIN

main:
  .set va_data,                 0x008001000     // GVA VS lw/sw/jalr will use (data + fetch target)
  .set va_code,                 0x0000000090000000  // GVA where VS executes this test code (VA≠PA)
  .set gpa_data,                0x00C002000     // GPA behind va_data (G leaf → test_region SPA)
  .set gpa_code,                0x012000000     // GPA behind va_code (2 MiB aligned for LEVEL1 superpage)
  .set gpa_rvtest_Vroot_pg_tbl, 0x01000A000     // GPA of VS root (LEVEL2) page table
  .set gpa_rvtest_vlvl1_pg_tbl, 0x000000001000C000  // GPA of VS mid (LEVEL1) page table
  .set gpa_rvtest_vlvl0_pg_tbl, 0x01000B000     // GPA of VS L0 table (implicit G A/D target)

  // Keep faults in M so trap-sig mode matches reference (mode=3).
  csrw medeleg, x0                              // clear M delegation — page/guest-page stay in M
  csrw hedeleg, x0                              // clear HS delegation so they do not land in HS

  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_code, LEVEL2)  // G non-leaf: shared VPN2 → G L1 table
  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, (PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V), gpa_code, LEVEL1)  // gpa_code → PA(code); LEVEL1 = 2 MiB leaf U=1 X/R
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL1)  // G non-leaf: VPN1 for VS-root GPA → G L0
  G_PTE_SETUP(sv39x4, rvtest_Vroot_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_Vroot_pg_tbl, LEVEL0)  // G leaf: VS-root GPA → PA(VS root) R/W A=D=1
  G_PTE_SETUP(sv39x4, rvtest_vlvl1_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl1_pg_tbl, LEVEL0)  // G leaf: VS L1 GPA → PA(VS L1) R/W A=D=1
  // Implicit G access: A=D=0 R/W U=1 (no X) — hardware reads VS L0 PTEs through this leaf
  G_PTE_SETUP(sv39x4, rvtest_vlvl0_pg_tbl, (PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl0_pg_tbl, LEVEL0)  // G leaf: VS-L0 GPA → PA(VS L0); A=D=0 R/W (Svade must fault)
  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_data, LEVEL1)  // G non-leaf: VPN1 for data GPA → G L0
  G_PTE_SETUP(sv39x4, test_region, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_data, LEVEL0)  // G leaf: gpa_data → PA(test_region) R/W A=D=1

  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)  // VS non-leaf: va_code VPN2 → VS L1 table GPA
  VS_PTE_SETUP(sv39, GPA, gpa_code, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_V), va_code, LEVEL1)  // VS leaf: va_code → gpa_code X/R A=D=1 so VS can fetch
  csrr a0, mscratch                             // a0 = M save-area pointer (required by next macro)
  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)  // framework: VS entry PC is under va_code (VA≠PA)

  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, (PTE_V), va_data, LEVEL2)  // VS non-leaf: va_data VPN2 → VS L1 table GPA
  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)  // VS non-leaf: va_data VPN1 → VS L0 table GPA
  VS_PTE_SETUP(sv39, GPA, gpa_data, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)  // VS leaf: va_data → gpa_data XWR=111 A=D=1 U=0

  csrw satp, x0                                 // HS satp Bare (only vsatp+hgatp translate)
  VSATP_SETUP(sv39, GPA)                        // vsatp = Sv39, PPN = GPA of VS root
  HGATP_SETUP(sv39x4)                           // hgatp = Sv39x4, PPN = G root
  hfence.vvma                                   // flush VS-stage TLB (must be M or HS)
  hfence.gvma                                   // flush G-stage TLB (illegal in VS/VU)
  sfence.vma                                    // extra TLB clear (sheet asks sfence.vma)

  LI(t0, 0x257A0251)                            // known SPA preload for store-fault check
  la t1, test_region                            // t1 = SPA of data page
  sw t0, 0(t1)                                  // write preload so a successful store would change it

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 1: implicit G A=D=0 on VS-PT map — VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_data)                               // a5 = GVA to load (walk reads VS L0 via G A=0)
  LI(a3, 0)                                     // sentinel — stays 0 if load guest-page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate (guest code VA≠PA)
  lw   a3, 0(a5)                                // VS load: implicit G read of VS L0 PTE A=0 → guest-page
  nop                                           // trap-skip padding after faulting load
  RVTEST_TSBI_GOTO_MMODE                       // T-SBI: ecall a0=1 → M (rtn2mmode VA→PA)
  test1_impl_g_lw:                              // signature dump point for case 1
  RVTEST_SIGUPD(x2, x5, x4, a3, test1_impl_g_lw, test1_impl_g_lw_str)  // dump a3 (expect 0)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 2: implicit G A=D=0 on VS-PT map — VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS TLB before next hop
  hfence.gvma                                   // flush G TLB so A=0 G-for-PT is not cached
  sfence.vma                                    // clear any leftover translations
  LI(a5, va_data)                               // a5 = GVA to store
  LI(t0, 0xBAD00FAD)                            // payload that must not land at SPA
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS mret + PA↔VA relocate
  sw   t0, 0(a5)                                // VS store: implicit G read of VS L0 PTE A=0 → guest-page
  nop                                           // trap-skip padding after faulting store
  RVTEST_TSBI_GOTO_MMODE                       // return to M
  la t3, test_region                            // t3 = SPA
  lw s3, 0(t3)                                  // expect preload 0x257A0251 unchanged
  test2_impl_g_sw:                              // signature dump point for case 2
  RVTEST_SIGUPD(x2, x5, x4, s3, test2_impl_g_sw, test2_impl_g_sw_str)  // dump SPA word

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 3: implicit G A=D=0 on VS-PT map — VS jalr | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS TLB
  hfence.gvma                                   // flush G TLB
  sfence.vma                                    // clear leftover translations
  LI(a5, va_data)                               // a5 = GVA fetch target (same data page, X on VS leaf)
  LI(s4, 0)                                     // sentinel — stays 0 if target never runs
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS
  nop                                           // pad so priv_mode_vs samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch of va_data: implicit G A=0 → fetch guest-page
  nop                                           // trap-skip padding (not reached)
  RVTEST_TSBI_GOTO_MMODE                       // return to M
  test3_impl_g_jalr:                            // signature dump point for case 3
  RVTEST_SIGUPD(x2, x5, x4, s4, test3_impl_g_jalr, test3_impl_g_jalr_str)  // dump s4 (expect 0)

//---------------------------------------------------------------------------------------------------------------------------------
// Restore G-for-VS-L0 A=D=1; set VS leaf A=D=00 (Svade → page fault on original access)
//---------------------------------------------------------------------------------------------------------------------------------
  G_PTE_SETUP(sv39x4, rvtest_vlvl0_pg_tbl, (PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V), gpa_rvtest_vlvl0_pg_tbl, LEVEL0)  // G-for-VS-L0 now A=D=1 R/W (implicit walk OK)
  VS_PTE_SETUP(sv39, GPA, gpa_data, (PTE_X | PTE_W | PTE_R | PTE_V), va_data, LEVEL0)  // VS leaf A=D=00 XWR=111 V=1 (Svade → page fault)
  hfence.vvma                                   // flush VS TLB after PTE rewrite
  hfence.gvma                                   // flush G TLB after G PTE rewrite
  sfence.vma                                    // clear leftover translations

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 4: VS leaf A=D=00 — VS lw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  LI(a5, va_data)                               // a5 = GVA to load
  LI(a4, 0)                                     // sentinel — stays 0 if load page-faults
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS
  lw   a4, 0(a5)                                // VS load: VS leaf A=0 → load page-fault (not guest-page)
  nop                                           // trap-skip padding
  RVTEST_TSBI_GOTO_MMODE                       // return to M
  test4_vs_ad00_lw:                             // signature dump point for case 4
  RVTEST_SIGUPD(x2, x5, x4, a4, test4_vs_ad00_lw, test4_vs_ad00_lw_str)  // dump a4 (expect 0)

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 5: VS leaf A=D=00 — VS sw | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS TLB
  hfence.gvma                                   // flush G TLB
  sfence.vma                                    // clear leftover translations
  LI(a5, va_data)                               // a5 = GVA to store
  LI(t0, 0xBAD00FAD)                            // payload that must not land
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS
  sw   t0, 0(a5)                                // VS store: VS leaf A=0 D=0 → store page-fault
  nop                                           // trap-skip padding
  RVTEST_TSBI_GOTO_MMODE                       // return to M
  la t3, test_region                            // t3 = SPA
  lw s3, 0(t3)                                  // expect preload 0x257A0251 unchanged
  test5_vs_ad00_sw:                             // signature dump point for case 5
  RVTEST_SIGUPD(x2, x5, x4, s3, test5_vs_ad00_sw, test5_vs_ad00_sw_str)  // dump SPA word

//---------------------------------------------------------------------------------------------------------------------------------
// Test case 6: VS leaf A=D=00 — VS jalr | Expected: Expected Fault
//---------------------------------------------------------------------------------------------------------------------------------
  hfence.vvma                                   // flush VS TLB
  hfence.gvma                                   // flush G TLB
  sfence.vma                                    // clear leftover translations
  LI(a5, va_data)                               // a5 = GVA fetch target
  LI(s5, 0)                                     // sentinel — stays 0 if target never runs
  RVTEST_GOTO_LOWER_MODE VSmode                 // M→VS
  nop                                           // pad so priv_mode_vs samples prev=VS on jalr
  jalr ra, a5, 0                                // VS ifetch: VS leaf A=0 → fetch page-fault
  nop                                           // trap-skip padding (not reached)
  RVTEST_TSBI_GOTO_MMODE                       // return to M
  test6_vs_ad00_jalr:                           // signature dump point for case 6
  RVTEST_SIGUPD(x2, x5, x4, s5, test6_vs_ad00_jalr, test6_vs_ad00_jalr_str)  // dump s5 (expect 0)

RVTEST_CODE_END
RVTEST_DATA_BEGIN

.align 12                                       // 4 KiB page align
test_region:                                    // SPA backing gpa_data
  .word 0                                       // payload word (preloaded in M)
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page
  .word 0                                       // padding in same page

.align 12                                       // 4 KiB page align
rvtest_hlvl1_pg_tbl:                            // G-stage L1 PTE storage (Sv39x4)
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_hlvl0_pg_tbl:                            // G-stage L0 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_vlvl1_pg_tbl:                            // VS-stage L1 PTE storage
  .zero(4096)                                   // reserve 4 KiB page-table page
.align 12                                       // 4 KiB page align
rvtest_vlvl0_pg_tbl:                            // VS-stage L0 PTE storage (implicit G maps this GPA)
  .zero(4096)                                   // reserve 4 KiB page-table page

test1_impl_g_lw_str:    .string "\"Mismatch on implicit G A=0 VS lw (expect fault) in Test Case 1!\""
test2_impl_g_sw_str:    .string "\"Mismatch on implicit G A=0 VS sw (SPA must stay) in Test Case 2!\""
test3_impl_g_jalr_str:  .string "\"Mismatch on implicit G A=0 VS jalr (expect fault) in Test Case 3!\""
test4_vs_ad00_lw_str:   .string "\"Mismatch on VS A=D=00 lw (expect fault) in Test Case 4!\""
test5_vs_ad00_sw_str:   .string "\"Mismatch on VS A=D=00 sw (SPA must stay) in Test Case 5!\""
test6_vs_ad00_jalr_str: .string "\"Mismatch on VS A=D=00 jalr (expect fault) in Test Case 6!\""

RVTEST_DATA_END
RVTEST_SIG_SETUP
