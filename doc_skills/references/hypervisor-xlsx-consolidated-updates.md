# Hypervisor (10x) — Consolidated XLSX Update List

> **Primary source:** `riscv-spec.md` (Ch.5 Hypervisor, Ch.6 State Enable)
> **Merged from:** `hypervisor-10x-test-plan.md` + `hypervisor-norm-rules-missing-from-xlsx.md`
> **Target file:** `Hypervisor (10x).xlsx`

## Executive Summary

| Metric | Count |
|--------|------:|
| Hypervisor norm rules in scope | 281 |
| Covered in xlsx today | 238 |
| **Missing norm IDs (spec-required, not in xlsx)** | **43** |
| Update rows in this document | 66 |
| A: Add norm ID to existing test | 46 |
| B: New testplan coverpoints | 19 |
| C: New sheets | 1 |

### How to use this file

1. Go to the **Excel section** listed for each item.
2. For **ADD_NORM** rows: open the existing coverpoint row and append the norm rule ID to the **Normative Rule** column.
3. For **NEW_TEST** rows: insert a new row with Coverpoint, Goal, Feature, Expectation, and Normative Rule.
4. For **NEW_SHEET** rows: create a new tab following the naming pattern of existing sheets.

---

## Master Update Table

| Item Type | Item Name/ID | Related Norm Rule | Related RISC-V Spec Requirement | Excel Section | Insert Location | Status | Notes |
|-----------|--------------|-------------------|---------------------------------|---------------|-----------------|--------|-------|
| Norm Rule (add to existing test) | `cp_hideleg_hip_vs` | `norm:vsip_vsie_sei` | §5.2.12 hideleg[10]→SEIP (riscv-spec.md L29987–29988) | **InterruptsH-NC** | Normative Rule on hideleg alias coverpoints | PARTIAL — add norm ID to existing coverpoint | When bit 10 of hideleg is zero, vsip.SEIP and vsie.SEIE are read-only zeros. Else, vsip.SEIP and vsi |
| Norm Rule (add to existing test) | `cp_hideleg_hip_vs` | `norm:vsip_vsie_ssi` | §5.2.12 hideleg[2]→SSIP (riscv-spec.md L29991–29992) | **InterruptsH-NC** | Normative Rule on hideleg alias coverpoints | PARTIAL — add norm ID to existing coverpoint | When bit 2 of hideleg is zero, vsip.SSIP and vsie.SSIE are read-only zeros. Else, vsip.SSIP and vsie |
| Norm Rule (add to existing test) | `cp_hideleg_hip_vs` | `norm:vsip_vsie_sti` | §5.2.12 hideleg[6]→STIP (riscv-spec.md L29989–29990) | **InterruptsH-NC** | Normative Rule on hideleg alias coverpoints | PARTIAL — add norm ID to existing coverpoint | When bit 6 of hideleg is zero, vsip.STIP and vsie.STIE are read-only zeros. Else, vsip.STIP and vsie |
| Norm Rule (add to existing test) | `cp_hie` | `norm:hie_op` | §5.2.3 hie register (riscv-spec.md L29544–29546) | **InterruptsH-NC** | Normative Rule on cp_hie | PARTIAL — add norm ID to existing coverpoint | respectively. The hip register indicates pending VS-level and hypervisor-specific interrupts, while  |
| New Testplan Item | `cp_hie_img_format` | `norm:hie_img` | §5.2.3 Figure 79 — hie format | **InterruptsH-NC** | New row near cp_hie | MISSING — new coverpoint required | Standard portions (bits 15:0) of hie formatted per Figure 79. |
| New Testplan Item | `cp_hie_warl_writable` | `norm:hie_acc` | §5.2.3 hie writable bits (riscv-spec.md L29572–29573) | **InterruptsH-NC** | New row after cp_hie | MISSING — new coverpoint required | A bit in hie shall be writable if the corresponding interrupt can ever become pending in hip. Bits o |
| Norm Rule (add to existing test) | `cp_hip` | `norm:hip_op` | §5.2.3 hip register (riscv-spec.md L29543–29545) | **InterruptsH-NC** | Normative Rule on cp_hip_write / cp_hip | PARTIAL — add norm ID to existing coverpoint | Registers  hip  and  hie  are  HSXLEN-bit  read/write  registers  that  supplement  HS-level’s  sip  |
| New Testplan Item | `cp_hip_img_format` | `norm:hip_img` | §5.2.3 Figure 80 — hip format | **InterruptsH-NC** | New row near cp_hip | MISSING — new coverpoint required | Standard portions (bits 15:0) of hip formatted per Figure 80. |
| New Testplan Item | `cp_hip_warl_clear` | `norm:hip_acc` | §5.2.3 hip writable bits (riscv-spec.md L29567–29571) | **InterruptsH-NC** | New row after cp_hip_write | MISSING — new coverpoint required | If bit i of sie is read-only zero, the same bit in register hip may be writable or may be read-only. |
| Norm Rule (add to existing test) | `cp_hip_write` | `norm:hip_op` | §5.2.3 hip register (riscv-spec.md L29543–29545) | **InterruptsH-NC** | Normative Rule on cp_hip_write / cp_hip | PARTIAL — add norm ID to existing coverpoint | Registers  hip  and  hie  are  HSXLEN-bit  read/write  registers  that  supplement  HS-level’s  sip  |
| Norm Rule (add to existing test) | `cp_mie` | `norm:mip_mie_alias` | §5.4.3 Machine Interrupt Registers (riscv-spec.md L30312–30313) | **InterruptsH-NC** | Normative Rule on cp_mip and cp_mie | PARTIAL — add norm ID to existing coverpoint | Bits SGEIP, VSEIP, VSTIP, and VSSIP in mip are aliases for the same bits in hypervisor CSR hip, whil |
| Norm Rule (add to existing test) | `cp_mie` | `norm:mip_mie_vs` | §5.4.3 mip/mie VS bits (riscv-spec.md L30307–30311) | **InterruptsH-NC** | Normative Rule on cp_mip and cp_mie | PARTIAL — add norm ID to existing coverpoint | 5.4. Machine-Level CSRs | Page 778 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0 0 LCOFIE SGEIE MEIE VSEIE S |
| Norm Rule (add to existing test) | `cp_mip` | `norm:mip_mie_alias` | §5.4.3 Machine Interrupt Registers (riscv-spec.md L30312–30313) | **InterruptsH-NC** | Normative Rule on cp_mip and cp_mie | PARTIAL — add norm ID to existing coverpoint | Bits SGEIP, VSEIP, VSTIP, and VSSIP in mip are aliases for the same bits in hypervisor CSR hip, whil |
| Norm Rule (add to existing test) | `cp_mip` | `norm:mip_mie_vs` | §5.4.3 mip/mie VS bits (riscv-spec.md L30307–30311) | **InterruptsH-NC** | Normative Rule on cp_mip and cp_mie | PARTIAL — add norm ID to existing coverpoint | 5.4. Machine-Level CSRs | Page 778 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0 0 LCOFIE SGEIE MEIE VSEIE S |
| New Testplan Item | `cp_sie_hip_hie_mutex` | `norm:sie_hip_hie_mutex` | §5.2.3 sie/hip/hie mutual exclusion (riscv-spec.md L29557–29558) | **InterruptsH-NC** | New row in HS-mode interrupt section | MISSING — new coverpoint required | For each writable bit in sie, the corresponding bit shall be read-only zero in both hip and hie. Hen |
| Norm Rule (add to existing test) | `cp_trigger_vssi` | `norm:vsip_vsie_ssi` | §5.2.12 hideleg[2]→SSIP (riscv-spec.md L29991–29992) | **InterruptsH-NC** | Normative Rule on hideleg alias coverpoints | PARTIAL — add norm ID to existing coverpoint | When bit 2 of hideleg is zero, vsip.SSIP and vsie.SSIE are read-only zeros. Else, vsip.SSIP and vsie |
| Norm Rule (add to existing test) | `cp_trigger_vsti` | `norm:vsip_vsie_sti` | §5.2.12 hideleg[6]→STIP (riscv-spec.md L29989–29990) | **InterruptsH-NC** | Normative Rule on hideleg alias coverpoints | PARTIAL — add norm ID to existing coverpoint | When bit 6 of hideleg is zero, vsip.STIP and vsie.STIE are read-only zeros. Else, vsip.STIP and vsie |
| Norm Rule (add to existing test) | `cp_vsie_from_hie` | `norm:vsip_vsie_sei` | §5.2.12 hideleg[10]→SEIP (riscv-spec.md L29987–29988) | **InterruptsH-NC** | Normative Rule on hideleg alias coverpoints | PARTIAL — add norm ID to existing coverpoint | When bit 10 of hideleg is zero, vsip.SEIP and vsie.SEIE are read-only zeros. Else, vsip.SEIP and vsi |
| New Testplan Item | `cp_vsie_img_format` | `norm:vsie_img` | §5.2.12 Figure 96 — vsie format | **InterruptsH-NC** | New row near cp_vsie_from_hie | MISSING — new coverpoint required | Standard portions (bits 15:0) of vsie formatted per Figure 96. |
| New Testplan Item | `cp_vsip_img_format` | `norm:vsip_img` | §5.2.12 Figure 95 — vsip format | **InterruptsH-NC** | New row near cp_vsip | MISSING — new coverpoint required | Standard portions (bits 15:0) of vsip formatted per Figure 95. |
| Norm Rule (add to existing test) | `cp_hcsr_access` | `norm:hip_hie_sz_acc` | §5.2.3 hip/hie size (riscv-spec.md L29543–29546) | **H - US** | Normative Rule on cp_hcsr_access (M/HS sections) | PARTIAL — add norm ID to existing coverpoint | Registers  hip  and  hie  are  HSXLEN-bit  read/write  registers  that  supplement  HS-level’s  sip  |
| Norm Rule (add to existing test) | `cp_hcsr_access` | `norm:vsip_vsie_sz_acc_op` | §5.2.12 vsip/vsie size (riscv-spec.md L29959–29963) | **H - US** | Normative Rule on CSR access coverpoints | PARTIAL — add norm ID to existing coverpoint | 5.2.12. Virtual Supervisor Interrupt (vsip and vsie) Registers The vsip and vsie registers are VSXLE |
| Norm Rule (add to existing test) | `cp_hcsr_access` | `norm:vspec_sz_acc_op` | §5.2.15 vsepc WARL (riscv-spec.md L30014–30019) | **H - US** | Normative Rule on cp_hcsr_access | PARTIAL — add norm ID to existing coverpoint | 5.2.15. Virtual Supervisor Exception Program Counter (vsepc) Register The vsepc register is a VSXLEN |
| Norm Rule (add to existing test) | `cp_hlv` | `norm:hlsv_op` | §5.3.1 HLV/HSV instructions (riscv-spec.md L30109–30112) | **H - US** | Normative Rule on Instructions (H_inst_cg) section | PARTIAL — add norm ID to existing coverpoint | For every RV32I or RV64I load instruction, LB, LBU, LH, LHU, LW, LWU, and LD, there is a correspondi |
| Norm Rule (add to existing test) | `cp_hlv` | `norm:hlsv_priv` | §5.3.1 effective privilege (riscv-spec.md L30103–30105) | **H - US** | Also cross-ref ExceptionsH-SN cp_loadstore_priv | PARTIAL — add norm ID to existing coverpoint | mode when hstatus.HU=1. Each instruction performs an explicit memory access with an effective privil |
| Norm Rule (add to existing test) | `cp_hlv` | `norm:hlsv_trans` | §5.3.1 two-stage translation (riscv-spec.md L30105–30108) | **H - US** | Normative Rule on cp_hlv / cp_hlvx | PARTIAL — add norm ID to existing coverpoint | and VS when hstatus.SPVP=1. As usual for VS-mode and VU-mode, two-stage address translation is appli |
| Norm Rule (add to existing test) | `cp_hlvx` | `norm:hlsv_trans` | §5.3.1 two-stage translation (riscv-spec.md L30105–30108) | **H - US** | Normative Rule on cp_hlv / cp_hlvx | PARTIAL — add norm ID to existing coverpoint | and VS when hstatus.SPVP=1. As usual for VS-mode and VU-mode, two-stage address translation is appli |
| Norm Rule (add to existing test) | `cp_hlvx` | `norm:hlsv_u_op` | §5.3.1 HLVX execute permission (riscv-spec.md L30114–30119) | **H - US** | Normative Rule on cp_hlvx | PARTIAL — add norm ID to existing coverpoint | Instructions HLVX.HU and HLVX.WU are the same as HLV.HU and HLV.WU, except that execute permission t |
| New Testplan Item | `cp_hstatus_vsxl_ro` | `norm:vsxl_ro` | §5.2.1 hstatus.VSXL (riscv-spec.md L29397–29403) | **H - US** | New row in H_hscsr_cg section | MISSING — new coverpoint required | The VSXL field controls the effective XLEN for VS-mode (known as VSXLEN), which may differ from the  |
| Norm Rule (add to existing test) | `cp_hsv` | `norm:hlsv_op` | §5.3.1 HLV/HSV instructions (riscv-spec.md L30109–30112) | **H - US** | Normative Rule on Instructions (H_inst_cg) section | PARTIAL — add norm ID to existing coverpoint | For every RV32I or RV64I load instruction, LB, LBU, LH, LHU, LW, LWU, and LD, there is a correspondi |
| New Testplan Item | `cp_hsxlen_impldef` | `norm:hsxlen` | §5.2 intro — HSXLEN (riscv-spec.md L29375–29376) | **H - US** | New row in H_mcsr_cg section | MISSING — new coverpoint required | HSXLEN is the effective XLEN when executing in HS-mode. |
| Norm Rule (add to existing test) | `cp_loadstore_priv` | `norm:hlsv_priv` | §5.3.1 effective privilege (riscv-spec.md L30103–30105) | **H - US** | Also cross-ref ExceptionsH-SN cp_loadstore_priv | PARTIAL — add norm ID to existing coverpoint | mode when hstatus.HU=1. Each instruction performs an explicit memory access with an effective privil |
| New Testplan Item | `cp_misa_h_enable` | `norm:misa_h_op` | §5.1 Hypervisor Extension intro (riscv-spec.md L29305–29307) | **H - US** | New row in H_mcsr_cg section | MISSING — new coverpoint required | The hypervisor extension is enabled by setting bit 7 in the misa CSR, which corresponds to the lette |
| Norm Rule (add to existing test) | `cp_mret_m` | `norm:mret_h` | §5.6.4 Trap Return — MRET (riscv-spec.md L30896–30899) | **H - US** | Normative Rule on cp_mret_m | PARTIAL — add norm ID to existing coverpoint | The MRET instruction is used to return from a trap taken into M-mode. MRET first determines what the |
| Norm Rule (add to existing test) | `cp_replica` | `norm:vsip_vsie_sz_acc_op` | §5.2.12 vsip/vsie size (riscv-spec.md L29959–29963) | **H - US** | Normative Rule on CSR access coverpoints | PARTIAL — add norm ID to existing coverpoint | 5.2.12. Virtual Supervisor Interrupt (vsip and vsie) Registers The vsip and vsie registers are VSXLE |
| Norm Rule (add to existing test) | `cp_sret_hs` | `norm:sret_h` | §5.6.4 Trap Return — SRET (riscv-spec.md L30900–30901) | **H - US** | Normative Rule on SRET coverpoints | PARTIAL — add norm ID to existing coverpoint | The SRET instruction is used to return from a trap taken into HS-mode or VS-mode. Its behavior depen |
| Norm Rule (add to existing test) | `cp_sret_hs` | `norm:sret_v0` | §5.6.4 SRET when V=0 (riscv-spec.md L30902–30905) | **H - US** | Normative Rule on cp_sret_hs / cp_sret_m | PARTIAL — add norm ID to existing coverpoint | When executed in M-mode or HS-mode (i.e., V=0), SRET first determines what the new privilege mode wi |
| Norm Rule (add to existing test) | `cp_sret_m` | `norm:sret_h` | §5.6.4 Trap Return — SRET (riscv-spec.md L30900–30901) | **H - US** | Normative Rule on SRET coverpoints | PARTIAL — add norm ID to existing coverpoint | The SRET instruction is used to return from a trap taken into HS-mode or VS-mode. Its behavior depen |
| Norm Rule (add to existing test) | `cp_sret_m` | `norm:sret_v0` | §5.6.4 SRET when V=0 (riscv-spec.md L30902–30905) | **H - US** | Normative Rule on cp_sret_hs / cp_sret_m | PARTIAL — add norm ID to existing coverpoint | When executed in M-mode or HS-mode (i.e., V=0), SRET first determines what the new privilege mode wi |
| Norm Rule (add to existing test) | `cp_sret_vs` | `norm:sret_h` | §5.6.4 Trap Return — SRET (riscv-spec.md L30900–30901) | **H - US** | Normative Rule on SRET coverpoints | PARTIAL — add norm ID to existing coverpoint | The SRET instruction is used to return from a trap taken into HS-mode or VS-mode. Its behavior depen |
| Norm Rule (add to existing test) | `cp_sret_vs` | `norm:sret_v1` | §5.6.4 SRET when V=1 (riscv-spec.md L30906–30907) | **H - US** | Normative Rule on cp_sret_vs | PARTIAL — add norm ID to existing coverpoint | When executed in VS-mode (i.e., V=1), SRET sets the privilege mode according to Table 126, in vsstat |
| New Testplan Item | `cp_vsxlen_hstatus_vsxl` | `norm:vsxlen` | §5.2 intro — VSXLEN (riscv-spec.md L29375–29376) | **H - US** | New row after cp_hstatus_vgein | MISSING — new coverpoint required | VSXLEN is the effective XLEN when executing in VS-mode. |
| Norm Rule (add to existing test) | `cp_hgatp_mode_field` | `norm:H_vm_gpa_g` | §5.5.1 Guest Physical Address Translation (riscv-spec.md L30365–30367) | **SvH-US** | Normative Rule on hgatp G-stage coverpoints | PARTIAL — add norm ID to existing coverpoint | 5.5.1. Guest Physical Address Translation The mapping of guest physical addresses to supervisor phys |
| New Testplan Item | `cp_vs_stage_speculative_a_bit` | `norm:vs_stage_speculative_a_bit` | §5.5 VS-stage speculative A bit (riscv-spec.md L28990–28998) | **SvH-US** | New row in SvH-US VM section | MISSING — new coverpoint required | When two-stage address translation is in use, an explicit access may cause both VS-stage and G-stage |
| Norm Rule (add to existing test) | `cp_vsatp_ppn_field` | `norm:satp_ppn_sv48_sz` | §4.4 Sv48 PPN field width | **SvH-US** | Normative Rule on cp_vsatp_ppn_field | PARTIAL — add norm ID to existing coverpoint | satp PPN field size for Sv48 mode. |
| Norm Rule (add to existing test) | `cp_vsatp_ppn_field` | `norm:satp_ppn_sv57_sz` | §4.5 Sv57 PPN field width | **SvH-US** | Normative Rule on cp_vsatp_ppn_field | PARTIAL — add norm ID to existing coverpoint | satp PPN field size for Sv57 mode. |
| Norm Rule (add to existing test) | `hgatp_pte_g_bit` | `norm:H_vm_gpa_g` | §5.5.1 Guest Physical Address Translation (riscv-spec.md L30365–30367) | **SvH-US** | Normative Rule on hgatp G-stage coverpoints | PARTIAL — add norm ID to existing coverpoint | 5.5.1. Guest Physical Address Translation The mapping of guest physical addresses to supervisor phys |
| Norm Rule (add to existing test) | `stage_both_bare` | `norm:H_vm_twostage` | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) | **SvH-US** | Normative Rule on two-stage translation coverpoints | PARTIAL — add norm ID to existing coverpoint | Whenever the current virtualization mode V is 1, two-stage address translation and protection is in  |
| Norm Rule (add to existing test) | `two_stage_ifetch` | `norm:H_vm_twostage` | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) | **SvH-US** | Normative Rule on two-stage translation coverpoints | PARTIAL — add norm ID to existing coverpoint | Whenever the current virtualization mode V is 1, two-stage address translation and protection is in  |
| Norm Rule (add to existing test) | `two_stage_read` | `norm:H_vm_twostage` | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) | **SvH-US** | Normative Rule on two-stage translation coverpoints | PARTIAL — add norm ID to existing coverpoint | Whenever the current virtualization mode V is 1, two-stage address translation and protection is in  |
| Norm Rule (add to existing test) | `two_stage_write` | `norm:H_vm_twostage` | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) | **SvH-US** | Normative Rule on two-stage translation coverpoints | PARTIAL — add norm ID to existing coverpoint | Whenever the current virtualization mode V is 1, two-stage address translation and protection is in  |
| Norm Rule (add to existing test) | `cp_pmp_after_gstage` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) | **PMPH-US** | Normative Rule column on all PMPH-US coverpoints | PARTIAL — add norm ID to existing coverpoint | Machine-level physical memory protection applies to supervisor physical addresses and is in effect r |
| Norm Rule (add to existing test) | `cp_pmp_hlv_read` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) | **PMPH-US** | Normative Rule column on all PMPH-US coverpoints | PARTIAL — add norm ID to existing coverpoint | Machine-level physical memory protection applies to supervisor physical addresses and is in effect r |
| Norm Rule (add to existing test) | `cp_pmp_hs_mode_access` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) | **PMPH-US** | Normative Rule column on all PMPH-US coverpoints | PARTIAL — add norm ID to existing coverpoint | Machine-level physical memory protection applies to supervisor physical addresses and is in effect r |
| Norm Rule (add to existing test) | `cp_pmp_hsv_write` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) | **PMPH-US** | Normative Rule column on all PMPH-US coverpoints | PARTIAL — add norm ID to existing coverpoint | Machine-level physical memory protection applies to supervisor physical addresses and is in effect r |
| Norm Rule (add to existing test) | `cp_pmp_vs_mode_access` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) | **PMPH-US** | Normative Rule column on all PMPH-US coverpoints | PARTIAL — add norm ID to existing coverpoint | Machine-level physical memory protection applies to supervisor physical addresses and is in effect r |
| Norm Rule (add to existing test) | `cp_pmp_vu_mode_access` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) | **PMPH-US** | Normative Rule column on all PMPH-US coverpoints | PARTIAL — add norm ID to existing coverpoint | Machine-level physical memory protection applies to supervisor physical addresses and is in effect r |
| Norm Rule (add to existing test) | `pmp_twostage_interaction` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) | **PMPH-US** | Normative Rule column on all PMPH-US coverpoints | PARTIAL — add norm ID to existing coverpoint | Machine-level physical memory protection applies to supervisor physical addresses and is in effect r |
| New Testplan Item | `cp_xtinst_cbo_transform` | `norm:h_trans_cache` | §5.6.3 Trap Handling — mtinst/htinst transform (riscv-spec.md + ch-6 Cache) | **SvHCBO-US** | New row in SvHCBO-US; also tag ExceptionsH-SN xtinst coverpoints | MISSING — new coverpoint required | Standard transformation for cache-block management instructions written to mtinst/htinst on trap. |
| New Testplan Item | `cp_guest_page_fault_straddle` | `norm:H_straddle` | §5.5.2 Guest-Page Faults (riscv-spec.md L30456–30460) | **Shtvala** | New row after cp_instr_guest_page_fault | MISSING — new coverpoint required | When an instruction fetch or a misaligned memory access straddles a page boundary, two different add |
| New Testplan Item | `cp_vsip_vsie_lcofi` | `norm:vsip_vsie_lcofi` | §5.2.12 hideleg[13]→LCOFIP (riscv-spec.md L29983–29986) | **Shlcofideleg** | Replace 'Develop after baseline' placeholder | MISSING — new coverpoint required | Extension Shlcofideleg supports delegating LCOFI interrupts to VS-mode. If the Shlcofideleg extensio |
| New Testplan Item | `cp_mstateen0_p1p13` | `norm:mstateen0_p1p13_op` | §6.1.2 mstateen0 P1P13 field (riscv-spec.md L31038+) | **SsstateenH** | New row in SsstateenH | MISSING — new coverpoint required | mstateen0 P1P13 controls access to pointer-masking and related features. |
| New Testplan Item | `cp_mstateen_bit63_hypervisor` | `norm:mstateen_bit_63_roz` | §6.1.2 mstateen bit 63 (riscv-spec.md L31034–31037) | **SsstateenH** | Replace placeholder row | MISSING — new coverpoint required | Bit 63 of each mstateen CSR may be read-only zero only if the hypervisor extension is not implemente |
| New Testplan Item | `cp_sret_dt_ssdbltrp` | `norm:sret_dt` | §5.6.4 SRET + Ssdbltrp (riscv-spec.md L30908–30912) | **SsdbltrpH** | Replace placeholder row | MISSING — new coverpoint required | If the Ssdbltrp extension is implemented, when SRET is executed in HS-mode, if the new privilege mod |
| New Testplan Item | `cp_ssnpm_hypervisor` | `norm:ssnpm_definition` | §Pointer Masking Extensions | **SsnpmH** | Replace placeholder row | MISSING — new coverpoint required | Ssnpm definition for supervisor pointer masking in virtualized environments. |
| New Sheet + Testplan Item | `cp_ssqosid_hypervisor` | `norm:Ssqosid_shared_resource_need_management` | §8.1 Ssqosid Extension (riscv-spec.md L33179+) | **NEW: SsqosidH** | Create new sheet after SmnpmH | NO TEST — new sheet required | Shared resources that require QoS management when hypervisor is implemented. |

---

## Updates by Excel Section

### InterruptsH-NC

**A. Add missing norm rule IDs to existing coverpoints:**

| Coverpoint | Add Norm Rule | Spec Reference (riscv-spec.md) |
|------------|---------------|-------------------------------|
| `cp_hie` | `norm:hie_op` | §5.2.3 hie register (riscv-spec.md L29544–29546) |
| `cp_hip_write` | `norm:hip_op` | §5.2.3 hip register (riscv-spec.md L29543–29545) |
| `cp_hip` | `norm:hip_op` | §5.2.3 hip register (riscv-spec.md L29543–29545) |
| `cp_mip` | `norm:mip_mie_alias` | §5.4.3 Machine Interrupt Registers (riscv-spec.md L30312–30313) |
| `cp_mie` | `norm:mip_mie_alias` | §5.4.3 Machine Interrupt Registers (riscv-spec.md L30312–30313) |
| `cp_mip` | `norm:mip_mie_vs` | §5.4.3 mip/mie VS bits (riscv-spec.md L30307–30311) |
| `cp_mie` | `norm:mip_mie_vs` | §5.4.3 mip/mie VS bits (riscv-spec.md L30307–30311) |
| `cp_hideleg_hip_vs` | `norm:vsip_vsie_sei` | §5.2.12 hideleg[10]→SEIP (riscv-spec.md L29987–29988) |
| `cp_vsie_from_hie` | `norm:vsip_vsie_sei` | §5.2.12 hideleg[10]→SEIP (riscv-spec.md L29987–29988) |
| `cp_hideleg_hip_vs` | `norm:vsip_vsie_ssi` | §5.2.12 hideleg[2]→SSIP (riscv-spec.md L29991–29992) |
| `cp_trigger_vssi` | `norm:vsip_vsie_ssi` | §5.2.12 hideleg[2]→SSIP (riscv-spec.md L29991–29992) |
| `cp_hideleg_hip_vs` | `norm:vsip_vsie_sti` | §5.2.12 hideleg[6]→STIP (riscv-spec.md L29989–29990) |
| `cp_trigger_vsti` | `norm:vsip_vsie_sti` | §5.2.12 hideleg[6]→STIP (riscv-spec.md L29989–29990) |

**B. Add new testplan coverpoints:**

| New Coverpoint | Norm Rule | Spec Reference | Insert Location |
|----------------|-----------|----------------|-----------------|
| `cp_hie_warl_writable` | `norm:hie_acc` | §5.2.3 hie writable bits (riscv-spec.md L29572–29573) | New row after cp_hie |
| `cp_hie_img_format` | `norm:hie_img` | §5.2.3 Figure 79 — hie format | New row near cp_hie |
| `cp_hip_warl_clear` | `norm:hip_acc` | §5.2.3 hip writable bits (riscv-spec.md L29567–29571) | New row after cp_hip_write |
| `cp_hip_img_format` | `norm:hip_img` | §5.2.3 Figure 80 — hip format | New row near cp_hip |
| `cp_sie_hip_hie_mutex` | `norm:sie_hip_hie_mutex` | §5.2.3 sie/hip/hie mutual exclusion (riscv-spec.md L29557–29558) | New row in HS-mode interrupt section |
| `cp_vsie_img_format` | `norm:vsie_img` | §5.2.12 Figure 96 — vsie format | New row near cp_vsie_from_hie |
| `cp_vsip_img_format` | `norm:vsip_img` | §5.2.12 Figure 95 — vsip format | New row near cp_vsip |

---

### H - US

**A. Add missing norm rule IDs to existing coverpoints:**

| Coverpoint | Add Norm Rule | Spec Reference (riscv-spec.md) |
|------------|---------------|-------------------------------|
| `cp_hcsr_access` | `norm:hip_hie_sz_acc` | §5.2.3 hip/hie size (riscv-spec.md L29543–29546) |
| `cp_hlv` | `norm:hlsv_op` | §5.3.1 HLV/HSV instructions (riscv-spec.md L30109–30112) |
| `cp_hsv` | `norm:hlsv_op` | §5.3.1 HLV/HSV instructions (riscv-spec.md L30109–30112) |
| `cp_hlv` | `norm:hlsv_priv` | §5.3.1 effective privilege (riscv-spec.md L30103–30105) |
| `cp_loadstore_priv` | `norm:hlsv_priv` | §5.3.1 effective privilege (riscv-spec.md L30103–30105) |
| `cp_hlv` | `norm:hlsv_trans` | §5.3.1 two-stage translation (riscv-spec.md L30105–30108) |
| `cp_hlvx` | `norm:hlsv_trans` | §5.3.1 two-stage translation (riscv-spec.md L30105–30108) |
| `cp_hlvx` | `norm:hlsv_u_op` | §5.3.1 HLVX execute permission (riscv-spec.md L30114–30119) |
| `cp_mret_m` | `norm:mret_h` | §5.6.4 Trap Return — MRET (riscv-spec.md L30896–30899) |
| `cp_sret_hs` | `norm:sret_h` | §5.6.4 Trap Return — SRET (riscv-spec.md L30900–30901) |
| `cp_sret_vs` | `norm:sret_h` | §5.6.4 Trap Return — SRET (riscv-spec.md L30900–30901) |
| `cp_sret_m` | `norm:sret_h` | §5.6.4 Trap Return — SRET (riscv-spec.md L30900–30901) |
| `cp_sret_hs` | `norm:sret_v0` | §5.6.4 SRET when V=0 (riscv-spec.md L30902–30905) |
| `cp_sret_m` | `norm:sret_v0` | §5.6.4 SRET when V=0 (riscv-spec.md L30902–30905) |
| `cp_sret_vs` | `norm:sret_v1` | §5.6.4 SRET when V=1 (riscv-spec.md L30906–30907) |
| `cp_hcsr_access` | `norm:vsip_vsie_sz_acc_op` | §5.2.12 vsip/vsie size (riscv-spec.md L29959–29963) |
| `cp_replica` | `norm:vsip_vsie_sz_acc_op` | §5.2.12 vsip/vsie size (riscv-spec.md L29959–29963) |
| `cp_hcsr_access` | `norm:vspec_sz_acc_op` | §5.2.15 vsepc WARL (riscv-spec.md L30014–30019) |

**B. Add new testplan coverpoints:**

| New Coverpoint | Norm Rule | Spec Reference | Insert Location |
|----------------|-----------|----------------|-----------------|
| `cp_hsxlen_impldef` | `norm:hsxlen` | §5.2 intro — HSXLEN (riscv-spec.md L29375–29376) | New row in H_mcsr_cg section |
| `cp_misa_h_enable` | `norm:misa_h_op` | §5.1 Hypervisor Extension intro (riscv-spec.md L29305–29307) | New row in H_mcsr_cg section |
| `cp_hstatus_vsxl_ro` | `norm:vsxl_ro` | §5.2.1 hstatus.VSXL (riscv-spec.md L29397–29403) | New row in H_hscsr_cg section |
| `cp_vsxlen_hstatus_vsxl` | `norm:vsxlen` | §5.2 intro — VSXLEN (riscv-spec.md L29375–29376) | New row after cp_hstatus_vgein |

---

### SvH-US

**A. Add missing norm rule IDs to existing coverpoints:**

| Coverpoint | Add Norm Rule | Spec Reference (riscv-spec.md) |
|------------|---------------|-------------------------------|
| `cp_hgatp_mode_field` | `norm:H_vm_gpa_g` | §5.5.1 Guest Physical Address Translation (riscv-spec.md L30365–30367) |
| `hgatp_pte_g_bit` | `norm:H_vm_gpa_g` | §5.5.1 Guest Physical Address Translation (riscv-spec.md L30365–30367) |
| `two_stage_read` | `norm:H_vm_twostage` | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) |
| `two_stage_write` | `norm:H_vm_twostage` | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) |
| `two_stage_ifetch` | `norm:H_vm_twostage` | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) |
| `stage_both_bare` | `norm:H_vm_twostage` | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) |
| `cp_vsatp_ppn_field` | `norm:satp_ppn_sv48_sz` | §4.4 Sv48 PPN field width |
| `cp_vsatp_ppn_field` | `norm:satp_ppn_sv57_sz` | §4.5 Sv57 PPN field width |

**B. Add new testplan coverpoints:**

| New Coverpoint | Norm Rule | Spec Reference | Insert Location |
|----------------|-----------|----------------|-----------------|
| `cp_vs_stage_speculative_a_bit` | `norm:vs_stage_speculative_a_bit` | §5.5 VS-stage speculative A bit (riscv-spec.md L28990–28998) | New row in SvH-US VM section |

---

### PMPH-US

**A. Add missing norm rule IDs to existing coverpoints:**

| Coverpoint | Add Norm Rule | Spec Reference (riscv-spec.md) |
|------------|---------------|-------------------------------|
| `cp_pmp_hs_mode_access` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| `cp_pmp_vs_mode_access` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| `cp_pmp_vu_mode_access` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| `cp_pmp_after_gstage` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| `cp_pmp_hlv_read` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| `cp_pmp_hsv_write` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| `pmp_twostage_interaction` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |

---

### SvHCBO-US

**B. Add new testplan coverpoints:**

| New Coverpoint | Norm Rule | Spec Reference | Insert Location |
|----------------|-----------|----------------|-----------------|
| `cp_xtinst_cbo_transform` | `norm:h_trans_cache` | §5.6.3 Trap Handling — mtinst/htinst transform (riscv-spec.md + ch-6 Cache) | New row in SvHCBO-US; also tag ExceptionsH-SN xtinst coverpoints |

---

### Shtvala

**B. Add new testplan coverpoints:**

| New Coverpoint | Norm Rule | Spec Reference | Insert Location |
|----------------|-----------|----------------|-----------------|
| `cp_guest_page_fault_straddle` | `norm:H_straddle` | §5.5.2 Guest-Page Faults (riscv-spec.md L30456–30460) | New row after cp_instr_guest_page_fault |

---

### Shlcofideleg

**B. Add new testplan coverpoints:**

| New Coverpoint | Norm Rule | Spec Reference | Insert Location |
|----------------|-----------|----------------|-----------------|
| `cp_vsip_vsie_lcofi` | `norm:vsip_vsie_lcofi` | §5.2.12 hideleg[13]→LCOFIP (riscv-spec.md L29983–29986) | Replace 'Develop after baseline' placeholder |

---

### SsstateenH

**B. Add new testplan coverpoints:**

| New Coverpoint | Norm Rule | Spec Reference | Insert Location |
|----------------|-----------|----------------|-----------------|
| `cp_mstateen0_p1p13` | `norm:mstateen0_p1p13_op` | §6.1.2 mstateen0 P1P13 field (riscv-spec.md L31038+) | New row in SsstateenH |
| `cp_mstateen_bit63_hypervisor` | `norm:mstateen_bit_63_roz` | §6.1.2 mstateen bit 63 (riscv-spec.md L31034–31037) | Replace placeholder row |

---

### SsdbltrpH

**B. Add new testplan coverpoints:**

| New Coverpoint | Norm Rule | Spec Reference | Insert Location |
|----------------|-----------|----------------|-----------------|
| `cp_sret_dt_ssdbltrp` | `norm:sret_dt` | §5.6.4 SRET + Ssdbltrp (riscv-spec.md L30908–30912) | Replace placeholder row |

---

### SsnpmH

**B. Add new testplan coverpoints:**

| New Coverpoint | Norm Rule | Spec Reference | Insert Location |
|----------------|-----------|----------------|-----------------|
| `cp_ssnpm_hypervisor` | `norm:ssnpm_definition` | §Pointer Masking Extensions | Replace placeholder row |

---

### NEW: SsqosidH

**B. Add new testplan coverpoints:**

| New Coverpoint | Norm Rule | Spec Reference | Insert Location |
|----------------|-----------|----------------|-----------------|
| `cp_ssqosid_hypervisor` | `norm:Ssqosid_shared_resource_need_management` | §8.1 Ssqosid Extension (riscv-spec.md L33179+) | Create new sheet after SmnpmH |

---

## Complete List of Missing Norm Rules

| Norm Rule ID | Spec Reference | Excel Section | Action |
|--------------|----------------|---------------|--------|
| `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) | PMPH-US | ADD_NORM |
| `norm:H_straddle` | §5.5.2 Guest-Page Faults (riscv-spec.md L30456–30460) | Shtvala | NEW_TEST |
| `norm:H_vm_gpa_g` | §5.5.1 Guest Physical Address Translation (riscv-spec.md L30365–30367) | SvH-US | ADD_NORM |
| `norm:H_vm_twostage` | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) | SvH-US | ADD_NORM |
| `norm:Ssqosid_shared_resource_need_management` | §8.1 Ssqosid Extension (riscv-spec.md L33179+) | NEW: SsqosidH | NEW_SHEET |
| `norm:h_trans_cache` | §5.6.3 Trap Handling — mtinst/htinst transform (riscv-spec.md + ch-6 Cache) | SvHCBO-US | NEW_TEST |
| `norm:hie_acc` | §5.2.3 hie writable bits (riscv-spec.md L29572–29573) | InterruptsH-NC | NEW_TEST |
| `norm:hie_img` | §5.2.3 Figure 79 — hie format | InterruptsH-NC | NEW_TEST |
| `norm:hie_op` | §5.2.3 hie register (riscv-spec.md L29544–29546) | InterruptsH-NC | ADD_NORM |
| `norm:hip_acc` | §5.2.3 hip writable bits (riscv-spec.md L29567–29571) | InterruptsH-NC | NEW_TEST |
| `norm:hip_hie_sz_acc` | §5.2.3 hip/hie size (riscv-spec.md L29543–29546) | H - US | ADD_NORM |
| `norm:hip_img` | §5.2.3 Figure 80 — hip format | InterruptsH-NC | NEW_TEST |
| `norm:hip_op` | §5.2.3 hip register (riscv-spec.md L29543–29545) | InterruptsH-NC | ADD_NORM |
| `norm:hlsv_op` | §5.3.1 HLV/HSV instructions (riscv-spec.md L30109–30112) | H - US | ADD_NORM |
| `norm:hlsv_priv` | §5.3.1 effective privilege (riscv-spec.md L30103–30105) | H - US | ADD_NORM |
| `norm:hlsv_trans` | §5.3.1 two-stage translation (riscv-spec.md L30105–30108) | H - US | ADD_NORM |
| `norm:hlsv_u_op` | §5.3.1 HLVX execute permission (riscv-spec.md L30114–30119) | H - US | ADD_NORM |
| `norm:hsxlen` | §5.2 intro — HSXLEN (riscv-spec.md L29375–29376) | H - US | NEW_TEST |
| `norm:mip_mie_alias` | §5.4.3 Machine Interrupt Registers (riscv-spec.md L30312–30313) | InterruptsH-NC | ADD_NORM |
| `norm:mip_mie_vs` | §5.4.3 mip/mie VS bits (riscv-spec.md L30307–30311) | InterruptsH-NC | ADD_NORM |
| `norm:misa_h_op` | §5.1 Hypervisor Extension intro (riscv-spec.md L29305–29307) | H - US | NEW_TEST |
| `norm:mret_h` | §5.6.4 Trap Return — MRET (riscv-spec.md L30896–30899) | H - US | ADD_NORM |
| `norm:mstateen0_p1p13_op` | §6.1.2 mstateen0 P1P13 field (riscv-spec.md L31038+) | SsstateenH | NEW_TEST |
| `norm:mstateen_bit_63_roz` | §6.1.2 mstateen bit 63 (riscv-spec.md L31034–31037) | SsstateenH | NEW_TEST |
| `norm:satp_ppn_sv48_sz` | §4.4 Sv48 PPN field width | SvH-US | ADD_NORM |
| `norm:satp_ppn_sv57_sz` | §4.5 Sv57 PPN field width | SvH-US | ADD_NORM |
| `norm:sie_hip_hie_mutex` | §5.2.3 sie/hip/hie mutual exclusion (riscv-spec.md L29557–29558) | InterruptsH-NC | NEW_TEST |
| `norm:sret_dt` | §5.6.4 SRET + Ssdbltrp (riscv-spec.md L30908–30912) | SsdbltrpH | NEW_TEST |
| `norm:sret_h` | §5.6.4 Trap Return — SRET (riscv-spec.md L30900–30901) | H - US | ADD_NORM |
| `norm:sret_v0` | §5.6.4 SRET when V=0 (riscv-spec.md L30902–30905) | H - US | ADD_NORM |
| `norm:sret_v1` | §5.6.4 SRET when V=1 (riscv-spec.md L30906–30907) | H - US | ADD_NORM |
| `norm:ssnpm_definition` | §Pointer Masking Extensions | SsnpmH | NEW_TEST |
| `norm:vs_stage_speculative_a_bit` | §5.5 VS-stage speculative A bit (riscv-spec.md L28990–28998) | SvH-US | NEW_TEST |
| `norm:vsie_img` | §5.2.12 Figure 96 — vsie format | InterruptsH-NC | NEW_TEST |
| `norm:vsip_img` | §5.2.12 Figure 95 — vsip format | InterruptsH-NC | NEW_TEST |
| `norm:vsip_vsie_lcofi` | §5.2.12 hideleg[13]→LCOFIP (riscv-spec.md L29983–29986) | Shlcofideleg | NEW_TEST |
| `norm:vsip_vsie_sei` | §5.2.12 hideleg[10]→SEIP (riscv-spec.md L29987–29988) | InterruptsH-NC | ADD_NORM |
| `norm:vsip_vsie_ssi` | §5.2.12 hideleg[2]→SSIP (riscv-spec.md L29991–29992) | InterruptsH-NC | ADD_NORM |
| `norm:vsip_vsie_sti` | §5.2.12 hideleg[6]→STIP (riscv-spec.md L29989–29990) | InterruptsH-NC | ADD_NORM |
| `norm:vsip_vsie_sz_acc_op` | §5.2.12 vsip/vsie size (riscv-spec.md L29959–29963) | H - US | ADD_NORM |
| `norm:vspec_sz_acc_op` | §5.2.15 vsepc WARL (riscv-spec.md L30014–30019) | H - US | ADD_NORM |
| `norm:vsxl_ro` | §5.2.1 hstatus.VSXL (riscv-spec.md L29397–29403) | H - US | NEW_TEST |
| `norm:vsxlen` | §5.2 intro — VSXLEN (riscv-spec.md L29375–29376) | H - US | NEW_TEST |

## Testplan → Norm Rule → Spec Mapping

| Testplan Item | Norm Rule | RISC-V Spec (riscv-spec.md) |
|---------------|-----------|----------------------------|
| `cp_pmp_hs_mode_access` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| `cp_pmp_vs_mode_access` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| `cp_pmp_vu_mode_access` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| `cp_pmp_after_gstage` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| `cp_pmp_hlv_read` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| `cp_pmp_hsv_write` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| `pmp_twostage_interaction` | `norm:H_pmp` | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| `cp_guest_page_fault_straddle` | `norm:H_straddle` | §5.5.2 Guest-Page Faults (riscv-spec.md L30456–30460) |
| `cp_hgatp_mode_field` | `norm:H_vm_gpa_g` | §5.5.1 Guest Physical Address Translation (riscv-spec.md L30365–30367) |
| `hgatp_pte_g_bit` | `norm:H_vm_gpa_g` | §5.5.1 Guest Physical Address Translation (riscv-spec.md L30365–30367) |
| `two_stage_read` | `norm:H_vm_twostage` | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) |
| `two_stage_write` | `norm:H_vm_twostage` | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) |
| `two_stage_ifetch` | `norm:H_vm_twostage` | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) |
| `stage_both_bare` | `norm:H_vm_twostage` | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) |
| `cp_ssqosid_hypervisor` | `norm:Ssqosid_shared_resource_need_management` | §8.1 Ssqosid Extension (riscv-spec.md L33179+) |
| `cp_xtinst_cbo_transform` | `norm:h_trans_cache` | §5.6.3 Trap Handling — mtinst/htinst transform (riscv-spec.md + ch-6 Cache) |
| `cp_hie_warl_writable` | `norm:hie_acc` | §5.2.3 hie writable bits (riscv-spec.md L29572–29573) |
| `cp_hie_img_format` | `norm:hie_img` | §5.2.3 Figure 79 — hie format |
| `cp_hie` | `norm:hie_op` | §5.2.3 hie register (riscv-spec.md L29544–29546) |
| `cp_hip_warl_clear` | `norm:hip_acc` | §5.2.3 hip writable bits (riscv-spec.md L29567–29571) |
| `cp_hcsr_access` | `norm:hip_hie_sz_acc` | §5.2.3 hip/hie size (riscv-spec.md L29543–29546) |
| `cp_hip_img_format` | `norm:hip_img` | §5.2.3 Figure 80 — hip format |
| `cp_hip_write` | `norm:hip_op` | §5.2.3 hip register (riscv-spec.md L29543–29545) |
| `cp_hip` | `norm:hip_op` | §5.2.3 hip register (riscv-spec.md L29543–29545) |
| `cp_hlv` | `norm:hlsv_op` | §5.3.1 HLV/HSV instructions (riscv-spec.md L30109–30112) |
| `cp_hsv` | `norm:hlsv_op` | §5.3.1 HLV/HSV instructions (riscv-spec.md L30109–30112) |
| `cp_hlv` | `norm:hlsv_priv` | §5.3.1 effective privilege (riscv-spec.md L30103–30105) |
| `cp_loadstore_priv` | `norm:hlsv_priv` | §5.3.1 effective privilege (riscv-spec.md L30103–30105) |
| `cp_hlv` | `norm:hlsv_trans` | §5.3.1 two-stage translation (riscv-spec.md L30105–30108) |
| `cp_hlvx` | `norm:hlsv_trans` | §5.3.1 two-stage translation (riscv-spec.md L30105–30108) |
| `cp_hlvx` | `norm:hlsv_u_op` | §5.3.1 HLVX execute permission (riscv-spec.md L30114–30119) |
| `cp_hsxlen_impldef` | `norm:hsxlen` | §5.2 intro — HSXLEN (riscv-spec.md L29375–29376) |
| `cp_mip` | `norm:mip_mie_alias` | §5.4.3 Machine Interrupt Registers (riscv-spec.md L30312–30313) |
| `cp_mie` | `norm:mip_mie_alias` | §5.4.3 Machine Interrupt Registers (riscv-spec.md L30312–30313) |
| `cp_mip` | `norm:mip_mie_vs` | §5.4.3 mip/mie VS bits (riscv-spec.md L30307–30311) |
| `cp_mie` | `norm:mip_mie_vs` | §5.4.3 mip/mie VS bits (riscv-spec.md L30307–30311) |
| `cp_misa_h_enable` | `norm:misa_h_op` | §5.1 Hypervisor Extension intro (riscv-spec.md L29305–29307) |
| `cp_mret_m` | `norm:mret_h` | §5.6.4 Trap Return — MRET (riscv-spec.md L30896–30899) |
| `cp_mstateen0_p1p13` | `norm:mstateen0_p1p13_op` | §6.1.2 mstateen0 P1P13 field (riscv-spec.md L31038+) |
| `cp_mstateen_bit63_hypervisor` | `norm:mstateen_bit_63_roz` | §6.1.2 mstateen bit 63 (riscv-spec.md L31034–31037) |
| `cp_vsatp_ppn_field` | `norm:satp_ppn_sv48_sz` | §4.4 Sv48 PPN field width |
| `cp_vsatp_ppn_field` | `norm:satp_ppn_sv57_sz` | §4.5 Sv57 PPN field width |
| `cp_sie_hip_hie_mutex` | `norm:sie_hip_hie_mutex` | §5.2.3 sie/hip/hie mutual exclusion (riscv-spec.md L29557–29558) |
| `cp_sret_dt_ssdbltrp` | `norm:sret_dt` | §5.6.4 SRET + Ssdbltrp (riscv-spec.md L30908–30912) |
| `cp_sret_hs` | `norm:sret_h` | §5.6.4 Trap Return — SRET (riscv-spec.md L30900–30901) |
| `cp_sret_vs` | `norm:sret_h` | §5.6.4 Trap Return — SRET (riscv-spec.md L30900–30901) |
| `cp_sret_m` | `norm:sret_h` | §5.6.4 Trap Return — SRET (riscv-spec.md L30900–30901) |
| `cp_sret_hs` | `norm:sret_v0` | §5.6.4 SRET when V=0 (riscv-spec.md L30902–30905) |
| `cp_sret_m` | `norm:sret_v0` | §5.6.4 SRET when V=0 (riscv-spec.md L30902–30905) |
| `cp_sret_vs` | `norm:sret_v1` | §5.6.4 SRET when V=1 (riscv-spec.md L30906–30907) |
| `cp_ssnpm_hypervisor` | `norm:ssnpm_definition` | §Pointer Masking Extensions |
| `cp_vs_stage_speculative_a_bit` | `norm:vs_stage_speculative_a_bit` | §5.5 VS-stage speculative A bit (riscv-spec.md L28990–28998) |
| `cp_vsie_img_format` | `norm:vsie_img` | §5.2.12 Figure 96 — vsie format |
| `cp_vsip_img_format` | `norm:vsip_img` | §5.2.12 Figure 95 — vsip format |
| `cp_vsip_vsie_lcofi` | `norm:vsip_vsie_lcofi` | §5.2.12 hideleg[13]→LCOFIP (riscv-spec.md L29983–29986) |
| `cp_hideleg_hip_vs` | `norm:vsip_vsie_sei` | §5.2.12 hideleg[10]→SEIP (riscv-spec.md L29987–29988) |
| `cp_vsie_from_hie` | `norm:vsip_vsie_sei` | §5.2.12 hideleg[10]→SEIP (riscv-spec.md L29987–29988) |
| `cp_hideleg_hip_vs` | `norm:vsip_vsie_ssi` | §5.2.12 hideleg[2]→SSIP (riscv-spec.md L29991–29992) |
| `cp_trigger_vssi` | `norm:vsip_vsie_ssi` | §5.2.12 hideleg[2]→SSIP (riscv-spec.md L29991–29992) |
| `cp_hideleg_hip_vs` | `norm:vsip_vsie_sti` | §5.2.12 hideleg[6]→STIP (riscv-spec.md L29989–29990) |
| `cp_trigger_vsti` | `norm:vsip_vsie_sti` | §5.2.12 hideleg[6]→STIP (riscv-spec.md L29989–29990) |
| `cp_hcsr_access` | `norm:vsip_vsie_sz_acc_op` | §5.2.12 vsip/vsie size (riscv-spec.md L29959–29963) |
| `cp_replica` | `norm:vsip_vsie_sz_acc_op` | §5.2.12 vsip/vsie size (riscv-spec.md L29959–29963) |
| `cp_hcsr_access` | `norm:vspec_sz_acc_op` | §5.2.15 vsepc WARL (riscv-spec.md L30014–30019) |
| `cp_hstatus_vsxl_ro` | `norm:vsxl_ro` | §5.2.1 hstatus.VSXL (riscv-spec.md L29397–29403) |
| `cp_vsxlen_hstatus_vsxl` | `norm:vsxlen` | §5.2 intro — VSXLEN (riscv-spec.md L29375–29376) |