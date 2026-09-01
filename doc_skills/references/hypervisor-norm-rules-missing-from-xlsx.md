# Hypervisor Norm Rules — Spec Golden Reference vs Test Plan Gaps

> **Golden reference:** `riscv-spec.md` (Privileged Architecture Ch.5–6)
> **Norm catalog:** `norm-rules.html`
> **Test plan:** `Hypervisor (10x).xlsx`

## Summary

| Metric | Count |
|--------|------:|
| Hypervisor norm rules in scope | 281 |
| Covered in xlsx (norm ID referenced) | 238 |
| **Missing norm ID in xlsx** | **43** |
| Missing with **no test item at all** | 6 |
| Missing with **partial/indirect test** | 37 |

### Coverage status legend

| Status | Meaning |
|--------|---------|
| **MISSING** | Norm rule ID not referenced in any xlsx coverpoint |
| **PARTIAL** | Related coverpoint exists but norm ID not linked |
| **NO TEST** | No coverpoint exercises this requirement |

---

## 1. `norm:H_pmp`

| Field | Value |
|-------|-------|
| Rule name | `H_pmp` |
| Norm chapter | H Extension |
| Spec golden ref | §5.5 Two-Stage Address Translation (riscv-spec.md L30363–30364) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** Machine-level physical memory protection applies to supervisor physical addresses and is in effect regardless of virtualization mode.

**Spec golden text (riscv-spec.md):**
> Machine-level physical memory protection applies to supervisor physical addresses and is in effect regardless of virtualization mode.

**Related test items (partial — norm ID not linked):**

- `cp_pmp_hs_mode_access` — sheet **PMPH-US**
  - Goal: Verify PMP applies in HS-mode
  - Current norms: `norm:pmp_check_priv_modes`, `norm:pmp_with_paging`
- `cp_pmp_vs_mode_access` — sheet **PMPH-US**
  - Goal: Verify PMP applies in VS-mode
  - Current norms: `norm:pmp_check_priv_modes`, `norm:pmp_with_paging`
- `cp_pmp_vu_mode_access` — sheet **PMPH-US**
  - Goal: Verify PMP applies in VU-mode
  - Current norms: `norm:pmp_check_priv_modes`, `norm:pmp_with_paging`
- `cp_pmp_after_gstage` — sheet **PMPH-US**
  - Goal: Verify PMP checked after G-stage
  - Current norms: `norm:pmp_with_paging`
- `cp_pmp_hlv_read` — sheet **PMPH-US**
  - Goal: Verify HLV obeys PMP.R
  - Current norms: `norm:pmp_load_fault`, `norm:pmp_rwx_check`
- `cp_pmp_hsv_write` — sheet **PMPH-US**
  - Goal: Verify HSV obeys PMP.W
  - Current norms: `norm:pmp_store_fault`

**Gap analysis:** PMPH-US tests PMP in hypervisor modes but does NOT reference norm:H_pmp.

**Suggested action:** `add norm:H_pmp to PMPH-US coverpoints`

---

## 2. `norm:H_straddle`

| Field | Value |
|-------|-------|
| Rule name | `H_straddle` |
| Norm chapter | H Extension |
| Spec golden ref | §5.5.2 Guest-Page Faults (riscv-spec.md L30456–30460) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** When an instruction fetch or a misaligned memory access straddles a page boundary, two different address translations are involved. When a guest-page fault occurs in such a circumstance, the faulting virtual address written to mtval/stval is the same as would be required for a regular page fault. Thus, the faulting virtual address may be a page-boundary address that is higher than the instruction&#8217;s original virtual address, if the byte at that page boundary is among the accessed bytes.

**Spec golden text (riscv-spec.md):**
> When an instruction fetch or a misaligned memory access straddles a page boundary, two different address translations are involved. When a guest-page fault occurs in such a circumstance, the faulting virtual address written to mtval/stval is the same as would be required for a regular page fault. Thus, the faulting virtual address may be a page-boundary address that is higher than the instruction’s original virtual address, if the byte at that pa

**Related test items (partial — norm ID not linked):**

- `cp_load_guest_page_fault` — sheet **Shtvala**
  - Goal: Fault writes GPA >> 2 to htval
- `cp_store_guest_page_fault` — sheet **Shtvala**
  - Goal: Fault writes GPA >> 2 to htval
- `cp_instr_guest_page_fault` — sheet **Shtvala**
  - Goal: Fault writes GPA >> 2 to htval

**Gap analysis:** Shtvala tests htval on guest-page faults but NOT straddling misaligned/multi-page case.

**Suggested action:** `cp_guest_page_fault_straddle`

---

## 3. `norm:H_vm_gpa_g`

| Field | Value |
|-------|-------|
| Rule name | `H_vm_gpa_g` |
| Norm chapter | H Extension |
| Spec golden ref | §5.5.1 Guest Physical Address Translation (riscv-spec.md L30365–30367) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** The G bit in all G-stage PTEs is currently not used. Until its use is defined by a standard extension, it should be cleared by software for forward compatibility, and must be ignored by hardware.

**Spec golden text (riscv-spec.md):**
> 5.5.1. Guest Physical Address Translation The mapping of guest physical addresses to supervisor physical addresses is controlled by CSR hgatp (Section 5.2.10). When the address translation scheme selected by the MODE field of hgatp is Bare, guest physical addresses are equal to supervisor physical addresses without modification, and no memory protection applies in the trivial translation of guest physical addresses to supervisor physical addresse

**Related test items (partial — norm ID not linked):**

- `cp_hgatp_mode_field` — sheet **SvH-US**
  - Goal: supported/unsupported MODE encodings for hgatp
- `cp_hgatp_gpa_width_checks` — sheet **SvH-US**
  - Goal: guest-physical address width limits
- `cp_hgatp_ppn_field` — sheet **SvH-US**
  - Goal: programmability of PPN in hgatp

**Gap analysis:** Shgatpa tests G-stage but norm:H_vm_gpa_g not referenced.

**Suggested action:** `add norm:H_vm_gpa_g to cp_hgatp_mode_field`

---

## 4. `norm:H_vm_twostage`

| Field | Value |
|-------|-------|
| Rule name | `H_vm_twostage` |
| Norm chapter | H Extension |
| Spec golden ref | §5.5 Two-Stage Translation (riscv-spec.md L30350–30356) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** Whenever the current virtualization mode V is 1, two-stage address translation and protection is in effect. For any virtual memory access, the original virtual address is converted in the first stage by VS-level address translation, as controlled by the vsatp register, into a guest physical address. The guest physical address is then converted in the second stage by guest physical address translation, as controlled by the hgatp register, into a supervisor physical address. The two stages are kno

**Spec golden text (riscv-spec.md):**
> Whenever the current virtualization mode V is 1, two-stage address translation and protection is in effect. For any virtual memory access, the original virtual address is converted in the first stage by VS-level address translation, as controlled by the vsatp register, into a guest physical address. The guest physical address is then converted in the second stage by guest physical address translation, as controlled by the hgatp register, into a s

**Related test items (partial — norm ID not linked):**

- `two_stage_read` — *(planned name, no cp_ row in xlsx)*
- `two_stage_write` — *(planned name, no cp_ row in xlsx)*
- `two_stage_ifetch` — *(planned name, no cp_ row in xlsx)*
- `cp_vsatp_mode_field` — sheet **SvH-US**
  - Goal: supported/unsupported MODE encodings

**Gap analysis:** SvH-US two-stage tests exist but norm:H_vm_twostage not tagged.

**Suggested action:** `add norm:H_vm_twostage to two_stage_read`

---

## 5. `norm:Ssqosid_shared_resource_need_management`

| Field | Value |
|-------|-------|
| Rule name | `Ssqosid_shared_resource_need_management` |
| Norm chapter | Supervisor Mode |
| Spec golden ref | §8.1 Ssqosid Extension (riscv-spec.md L33179+) |
| Coverage status | **NO TEST** — norm ID **MISSING** in xlsx |

**Norm requirement:** When multiple workloads execute concurrently on modern processors—equipped with large core counts, multiple cache hierarchies, and multiple memory controllers— the performance of any given workload becomes less deterministic, or even non-deterministic, due to shared resource contention.

**Spec golden text (riscv-spec.md):**
> Shared resources that require QoS management when hypervisor is implemented.

**Related test items:** None — **NO TEST ITEM**

**Gap analysis:** NO TEST — no Ssqosid sheet in Hypervisor (10x).xlsx.

**Suggested action:** `cp_ssqosid_hypervisor (new sheet)`

---

## 6. `norm:h_trans_cache`

| Field | Value |
|-------|-------|
| Rule name | `h_trans_cache` |
| Norm chapter | Cache Manage Ops |
| Spec golden ref | §5.6.3 Trap Handling — mtinst/htinst transform (riscv-spec.md + ch-6 Cache) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Spec golden text (riscv-spec.md):**
> Standard transformation for cache-block management instructions written to mtinst/htinst on trap.

**Related test items (partial — norm ID not linked):**

- `vs_invalid_pte_cbo` — *(planned name, no cp_ row in xlsx)*
- `g_invalid_pte_cbo` — *(planned name, no cp_ row in xlsx)*
- `hfence_interaction` — *(planned name, no cp_ row in xlsx)*

**Gap analysis:** SvHCBO-US tests CBO faults but NOT htinst/mtinst transform on CBO trap.

**Suggested action:** `cp_xtinst_cbo_transform`

---

## 7. `norm:hie_acc`

| Field | Value |
|-------|-------|
| Rule name | `hie_acc` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.3 hie writable bits (riscv-spec.md L29572–29573) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** A bit in hie shall be writable if the corresponding interrupt can ever become pending in hip. Bits of hie that are not writable shall be read-only zero.

**Spec golden text (riscv-spec.md):**
> A bit in hie shall be writable if the corresponding interrupt can ever become pending in hip. Bits of hie that are not writable shall be read-only zero.

**Related test items (partial — norm ID not linked):**

- `cp_hie` — sheet **InterruptsH-NC**
  - Goal: hie.VS*IE bits are alias of mie
- `cp_trigger_vsei` — sheet **InterruptsH-NC**
  - Goal: trigger HS-mode VSEI
- `cp_trigger_vsti` — sheet **InterruptsH-NC**
  - Goal: trigger HS-mode VSTI
- `cp_trigger_vssi` — sheet **InterruptsH-NC**
  - Goal: trigger HS-mode VSSI

**Gap analysis:** InterruptsH-NC tests hie aliases but not per-interrupt WARL writable rules.

**Suggested action:** `cp_hie_warl_writable`

---

## 8. `norm:hie_img`

| Field | Value |
|-------|-------|
| Rule name | `hie_img` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.3 Figure 79 — hie format |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** hie contains enable bits for the same interrupts

**Spec golden text (riscv-spec.md):**
> Standard portions (bits 15:0) of hie formatted per Figure 79.

**Related test items (partial — norm ID not linked):**

- `cp_hie` — sheet **InterruptsH-NC**
  - Goal: hie.VS*IE bits are alias of mie

**Gap analysis:** Register image/format not explicitly tested.

**Suggested action:** `cp_hie_img_format`

---

## 9. `norm:hie_op`

| Field | Value |
|-------|-------|
| Rule name | `hie_op` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.3 hie register (riscv-spec.md L29544–29546) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** hie contains enable bits for the same interrupts

**Spec golden text (riscv-spec.md):**
> respectively. The hip register indicates pending VS-level and hypervisor-specific interrupts, while hie contains enable bits for the same interrupts. The RISC-V Instruction Set Manual | © RISC-V International

**Related test items (partial — norm ID not linked):**

- `cp_hie` — sheet **InterruptsH-NC**
  - Goal: hie.VS*IE bits are alias of mie
- `cp_mie` — sheet **InterruptsH-NC**
  - Goal: mie.VS*IE bits are alias of hie

**Gap analysis:** hie existence not norm-tagged.

**Suggested action:** `add norm:hie_op to cp_hie`

---

## 10. `norm:hip_acc`

| Field | Value |
|-------|-------|
| Rule name | `hip_acc` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.3 hip writable bits (riscv-spec.md L29567–29571) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** If bit i of sie is read-only zero, the same bit in register hip may be writable or may be read-only. When bit i in hip is writable, a pending interrupt i can be cleared by writing 0 to this bit. If interrupt i can become pending in hip but bit i in hip is read-only, then either the interrupt can be cleared by clearing bit i of hvip, or the implementation must provide some other mechanism for clearing the pending interrupt (which may involve a call to the execution environment).

**Spec golden text (riscv-spec.md):**
> If bit i of sie is read-only zero, the same bit in register hip may be writable or may be read-only. When bit i in hip is writable, a pending interrupt i can be cleared by writing 0 to this bit. If interrupt i can become pending in hip but bit i in hip is read-only, then either the interrupt can be cleared by clearing bit i of hvip, or the implementation must provide some other mechanism for clearing the pending interrupt (which may involve a cal

**Related test items (partial — norm ID not linked):**

- `cp_hip_write` — sheet **InterruptsH-NC**
  - Goal: only hip.vssip is writable, and aliases to hvip
- `cp_mip` — sheet **InterruptsH-NC**
  - Goal: mip.VS*IP bits are alias of hip
- `cp_trigger_vsei` — sheet **InterruptsH-NC**
  - Goal: trigger HS-mode VSEI

**Gap analysis:** hip writable-bit rules per interrupt not fully covered.

**Suggested action:** `cp_hip_warl_clear`

---

## 11. `norm:hip_hie_sz_acc`

| Field | Value |
|-------|-------|
| Rule name | `hip_hie_sz` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.3 hip/hie size (riscv-spec.md L29543–29546) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** Registers hip and hie are HSXLEN-bit read/write registers that supplement HS-level’s sip and sie respectively.

**Spec golden text (riscv-spec.md):**
> Registers  hip  and  hie  are  HSXLEN-bit  read/write  registers  that  supplement  HS-level’s  sip  and  sie respectively. The hip register indicates pending VS-level and hypervisor-specific interrupts, while hie contains enable bits for the same interrupts. The RISC-V Instruction Set Manual | © RISC-V International

**Related test items (partial — norm ID not linked):**

- `cp_hcsr_access` — sheet **H - US**
  - Goal: All H-extension CSRs are able to read, write, set, and clear
  - Current norms: `norm:csr:hstatus:reg`, `norm:csr:hedeleg:reg`, `norm:csr:hideleg:reg`, `norm:csr:hie:reg`, `norm:csr:htimedelta:reg`, `norm:csr:hcounteren:reg`

**Gap analysis:** Size/access tested generically; norm ID missing.

**Suggested action:** `add norm:hip_hie_sz_acc to cp_hcsr_access`

---

## 12. `norm:hip_img`

| Field | Value |
|-------|-------|
| Rule name | `hip_img` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.3 Figure 80 — hip format |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** hie contains enable bits for the same interrupts

**Spec golden text (riscv-spec.md):**
> Standard portions (bits 15:0) of hip formatted per Figure 80.

**Related test items (partial — norm ID not linked):**

- `cp_hip_write` — sheet **InterruptsH-NC**
  - Goal: only hip.vssip is writable, and aliases to hvip

**Gap analysis:** Figure bit layout not explicitly verified.

**Suggested action:** `cp_hip_img_format`

---

## 13. `norm:hip_op`

| Field | Value |
|-------|-------|
| Rule name | `hip_op` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.3 hip register (riscv-spec.md L29543–29545) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** The hip register indicates pending VS-level and hypervisor-specific interrupts

**Spec golden text (riscv-spec.md):**
> Registers  hip  and  hie  are  HSXLEN-bit  read/write  registers  that  supplement  HS-level’s  sip  and  sie respectively. The hip register indicates pending VS-level and hypervisor-specific interrupts, while hie contains enable bits for the same interrupts.

**Related test items (partial — norm ID not linked):**

- `cp_mip` — sheet **InterruptsH-NC**
  - Goal: mip.VS*IP bits are alias of hip
- `cp_hip_write` — sheet **InterruptsH-NC**
  - Goal: only hip.vssip is writable, and aliases to hvip

**Gap analysis:** hip pending semantics not norm-tagged.

**Suggested action:** `add norm:hip_op to cp_hip_write`

---

## 14. `norm:hlsv_op`

| Field | Value |
|-------|-------|
| Rule name | `hlsv_op` |
| Norm chapter | H Extension |
| Spec golden ref | §5.3.1 HLV/HSV instructions (riscv-spec.md L30109–30112) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** For every RV32I or RV64I load instruction, LB, LBU, LH, LHU, LW, LWU, and LD, there is a corresponding virtual-machine load instruction: HLV.B, HLV.BU, HLV.H, HLV.HU, HLV.W, HLV.WU, and HLV.D. For every RV32I or RV64I store instruction, SB, SH, SW, and SD, there is a corresponding virtual-machine store instruction: HSV.B, HSV.H, HSV.W, and HSV.D. Instructions HLV.WU, HLV.D, and HSV.D are not valid for RV32, of course.

**Spec golden text (riscv-spec.md):**
> For every RV32I or RV64I load instruction, LB, LBU, LH, LHU, LW, LWU, and LD, there is a corresponding virtual-machine load instruction: HLV.B, HLV.BU, HLV.H, HLV.HU, HLV.W, HLV.WU, and HLV.D. For every RV32I or RV64I store instruction, SB, SH, SW, and SD, there is a corresponding virtual-machine store instruction: HSV.B, HSV.H, HSV.W, and HSV.D. Instructions HLV.WU, HLV.D, and HSV.D are not valid for

**Related test items (partial — norm ID not linked):**

- `cp_hlv` — sheet **H - US**
  - Goal: Basic load
- `cp_hsv` — sheet **H - US**
  - Goal: Basic store
- `cp_hlvx` — sheet **H - US**
  - Goal: Basic load
- `cp_loadstore_priv` — sheet **ExceptionsH-SN**
  - Goal: Valid privilege modes of hypervisor load/store

**Gap analysis:** H-US tests HLV/HSV but norm:hlsv_op not referenced.

**Suggested action:** `add norm:hlsv_op to cp_hlv/cp_hsv`

---

## 15. `norm:hlsv_priv`

| Field | Value |
|-------|-------|
| Rule name | `hlsv_priv` |
| Norm chapter | H Extension |
| Spec golden ref | §5.3.1 effective privilege (riscv-spec.md L30103–30105) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** Each instruction performs an explicit memory access with an effective privilege mode of VS or VU. The effective privilege mode of the explicit memory access is VU when hstatus.SPVP=0, and VS when hstatus.SPVP=1.

**Spec golden text (riscv-spec.md):**
> mode when hstatus.HU=1. Each instruction performs an explicit memory access with an effective privilege mode of VS or VU. The effective privilege mode of the explicit memory access is VU when hstatus.SPVP=0, and VS when hstatus.SPVP=1. As usual for VS-mode and VU-mode, two-stage address translation is

**Related test items (partial — norm ID not linked):**

- `cp_hlv` — sheet **H - US**
  - Goal: Basic load
- `cp_loadstore_priv` — sheet **ExceptionsH-SN**
  - Goal: Valid privilege modes of hypervisor load/store
- `cp_ecall_to_hs` — sheet **ExceptionsH-SN**
  - Goal: ecall to HS sets status bits

**Gap analysis:** SPVP effective privilege for HLV not norm-tagged.

**Suggested action:** `cp_hlsv_spvp_effective_priv`

---

## 16. `norm:hlsv_trans`

| Field | Value |
|-------|-------|
| Rule name | `hlsv_trans` |
| Norm chapter | H Extension |
| Spec golden ref | §5.3.1 two-stage translation (riscv-spec.md L30105–30108) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** As usual for VS-mode and VU-mode, two-stage address translation is applied, and the HS-level sstatus.SUM is ignored.

**Spec golden text (riscv-spec.md):**
> and VS when hstatus.SPVP=1. As usual for VS-mode and VU-mode, two-stage address translation is applied, and the HS-level sstatus.SUM is ignored. HS-level sstatus.MXR makes execute-only pages readable by explicit loads for both stages of address translation (VS-stage and G-stage), whereas vsstatus.MXR affects only the first translation stage (VS-stage).

**Related test items (partial — norm ID not linked):**

- `cp_hlv` — sheet **H - US**
  - Goal: Basic load
- `two_stage_read` — *(planned name, no cp_ row in xlsx)*
- `two_stage_write` — *(planned name, no cp_ row in xlsx)*

**Gap analysis:** Two-stage + SUM ignored for HLV not norm-tagged.

**Suggested action:** `cp_hlsv_twostage_sum`

---

## 17. `norm:hlsv_u_op`

| Field | Value |
|-------|-------|
| Rule name | `hlsv_u_op` |
| Norm chapter | H Extension |
| Spec golden ref | §5.3.1 HLVX execute permission (riscv-spec.md L30114–30119) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** Instructions HLVX.HU and HLVX.WU are the same as HLV.HU and HLV.WU, except that execute permission takes the place of read permission during address translation. That is, the memory being read must be executable in both stages of address translation, but read permission is not required. For the supervisor physical address that results from address translation, the supervisor physical memory attributes must grant both execute and read permissions. (The supervisor physical memory attributes are th

**Spec golden text (riscv-spec.md):**
> Instructions HLVX.HU and HLVX.WU are the same as HLV.HU and HLV.WU, except that execute permission takes the place of read permission during address translation. That is, the memory being read must be executable in both stages of address translation, but read permission is not required. For the supervisor physical address that results from address translation, the supervisor physical memory attributes must grant both execute and read permissions.

**Related test items (partial — norm ID not linked):**

- `cp_hlvx` — sheet **H - US**
  - Goal: Basic load
- `cp_hlv_access_fault` — sheet **ExceptionsH-SN**
  - Goal: Hypervisor Load Access Fault

**Gap analysis:** HLVX execute-permission semantics not norm-tagged.

**Suggested action:** `add norm:hlsv_u_op to cp_hlvx`

---

## 18. `norm:hsxlen`

| Field | Value |
|-------|-------|
| Rule name | `hsxlen` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2 intro — HSXLEN (riscv-spec.md L29375–29376) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** Some standard supervisor CSRs (senvcfg, scounteren, and scontext, possibly others) have no matching VS CSR. These supervisor CSRs continue to have their usual function and accessibility even when V=1, except with VS-mode and VU-mode substituting for HS-mode and U-mode. Hypervisor software is expected to manually swap the contents of these registers as needed.

**Spec golden text (riscv-spec.md):**
> HSXLEN is the effective XLEN when executing in HS-mode.

**Related test items (partial — norm ID not linked):**

- `cp_hcsr_access` — sheet **H - US**
  - Goal: All H-extension CSRs are able to read, write, set, and clear
  - Current norms: `norm:csr:hstatus:reg`, `norm:csr:hedeleg:reg`, `norm:csr:hideleg:reg`, `norm:csr:hie:reg`, `norm:csr:htimedelta:reg`, `norm:csr:hcounteren:reg`

**Gap analysis:** HSXLEN implementation-defined behavior not explicitly tested.

**Suggested action:** `cp_hsxlen_impldef`

---

## 19. `norm:mip_mie_alias`

| Field | Value |
|-------|-------|
| Rule name | `mip_mie_alias` |
| Norm chapter | H Extension |
| Spec golden ref | §5.4.3 Machine Interrupt Registers (riscv-spec.md L30312–30313) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** Bits SGEIP, VSEIP, VSTIP, and VSSIP in mip are aliases for the same bits in hypervisor CSR hip, while SGEIE, VSEIE, VSTIE, and VSSIE in mie are aliases for the same bits in hie.

**Spec golden text (riscv-spec.md):**
> Bits SGEIP, VSEIP, VSTIP, and VSSIP in mip are aliases for the same bits in hypervisor CSR hip, while SGEIE, VSEIE, VSTIE, and VSSIE in mie are aliases for the same bits in hie.

**Related test items (partial — norm ID not linked):**

- `cp_mip` — sheet **InterruptsH-NC**
  - Goal: mip.VS*IP bits are alias of hip
- `cp_mie` — sheet **InterruptsH-NC**
  - Goal: mie.VS*IE bits are alias of hie
- `cp_mie_gilen` — sheet **InterruptsH-NC**
  - Goal: mie.SGEIE is read-only zero if GILEN = 0

**Gap analysis:** Alias tested behaviorally but norm ID missing.

**Suggested action:** `add norm:mip_mie_alias to cp_mip/cp_mie`

---

## 20. `norm:mip_mie_vs`

| Field | Value |
|-------|-------|
| Rule name | `mip_mie_vs` |
| Norm chapter | H Extension |
| Spec golden ref | §5.4.3 mip/mie VS bits (riscv-spec.md L30307–30311) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** The hypervisor extension gives registers mip and mie additional active bits for the hypervisor-added interrupts. and show the standard portions (bits 15:0) of registers mip and mie when the hypervisor extension is implemented.

**Spec golden text (riscv-spec.md):**
> 5.4. Machine-Level CSRs | Page 778 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0 0 LCOFIE SGEIE MEIE VSEIE SEIE 0 MTIE VSTIE STIE 0 MSIE VSSIE SSIE 0 2 1 1 1 1 1 1 1 1 1 1 1 1 1 1 Figure 107. Standard portion (bits 15:0) of mie.

**Related test items (partial — norm ID not linked):**

- `cp_mip` — sheet **InterruptsH-NC**
  - Goal: mip.VS*IP bits are alias of hip
- `cp_mie` — sheet **InterruptsH-NC**
  - Goal: mie.VS*IE bits are alias of hie

**Gap analysis:** VS interrupt bits in mip/mie format not norm-tagged.

**Suggested action:** `add norm:mip_mie_vs to cp_mip`

---

## 21. `norm:misa_h_op`

| Field | Value |
|-------|-------|
| Rule name | `misa_h_op` |
| Norm chapter | H Extension |
| Spec golden ref | §5.1 Hypervisor Extension intro (riscv-spec.md L29305–29307) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** The hypervisor extension is enabled by setting bit 7 in the misa CSR

**Spec golden text (riscv-spec.md):**
> The hypervisor extension is enabled by setting bit 7 in the misa CSR, which corresponds to the letter H. RISC-V harts that implement the hypervisor extension are encouraged not to hardwire misa[7], so that the extension may be disabled.

**Related test items (partial — norm ID not linked):**

- `cp_hcsr_access` — sheet **H - US**
  - Goal: All H-extension CSRs are able to read, write, set, and clear
  - Current norms: `norm:csr:hstatus:reg`, `norm:csr:hedeleg:reg`, `norm:csr:hideleg:reg`, `norm:csr:hie:reg`, `norm:csr:htimedelta:reg`, `norm:csr:hcounteren:reg`

**Gap analysis:** misa[7] H extension enable/disable not tested.

**Suggested action:** `cp_misa_h_enable`

---

## 22. `norm:mret_h`

| Field | Value |
|-------|-------|
| Rule name | `mret_h` |
| Norm chapter | H Extension |
| Spec golden ref | §5.6.4 Trap Return — MRET (riscv-spec.md L30896–30899) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** The MRET instruction is used to return from a trap taken into M-mode. MRET first determines what the new privilege mode will be according to the values of MPP and MPV in mstatus or mstatush, as encoded in . MRET then in mstatus/mstatush sets MPV=0, MPP=0, MIE=MPIE, and MPIE=1. Lastly, MRET sets the privilege mode as previously determined, and sets pc=mepc.

**Spec golden text (riscv-spec.md):**
> The MRET instruction is used to return from a trap taken into M-mode. MRET first determines what the new privilege mode will be according to the values of MPP and MPV in mstatus or mstatush, as encoded in Table 124. MRET then in mstatus/mstatush sets MPV=0, MPP=0, MIE=MPIE, and MPIE=1. Lastly, MRET sets the privilege mode as previously determined, and sets pc=mepc.

**Related test items (partial — norm ID not linked):**

- `cp_mret_m` — sheet **H - US**
  - Goal: mret uses MPV

**Gap analysis:** cp_mret_m tests behavior but norm:mret_h not referenced.

**Suggested action:** `add norm:mret_h to cp_mret_m`

---

## 23. `norm:mstateen0_p1p13_op`

| Field | Value |
|-------|-------|
| Rule name | `mstateen0_p1p13_op` |
| Norm chapter | State Enable Extension |
| Spec golden ref | §6.1.2 mstateen0 P1P13 field (riscv-spec.md L31038+) |
| Coverage status | **NO TEST** — norm ID **MISSING** in xlsx |

**Norm requirement:** The P1P13 bit in mstateen0 controls access to the hedelegh introduced by Privileged Specification Version 1.13.

**Spec golden text (riscv-spec.md):**
> mstateen0 P1P13 controls access to pointer-masking and related features.

**Related test items:** None — **NO TEST ITEM**

**Gap analysis:** NO TEST — SsstateenH sheet is placeholder.

**Suggested action:** `cp_mstateen0_p1p13 (new sheet SsstateenH)`

---

## 24. `norm:mstateen_bit_63_roz`

| Field | Value |
|-------|-------|
| Rule name | `mstateen_bit_63_roz` |
| Norm chapter | State Enable Extension |
| Spec golden ref | §6.1.2 mstateen bit 63 (riscv-spec.md L31034–31037) |
| Coverage status | **NO TEST** — norm ID **MISSING** in xlsx |

**Norm requirement:** Bit 63 of each mstateen CSR may be read-only zero only if the hypervisor extension is not implemented and the matching supervisor-level sstateen CSR is all read-only zeros.

**Spec golden text (riscv-spec.md):**
> Bit 63 of each mstateen CSR may be read-only zero only if the hypervisor extension is not implemented and the matching supervisor-level sstateen CSR is all read-only zeros. In that case, machine-level software should emulate attempts to access the affected sstateen CSR from S-mode, ignoring writes and returning zero for reads. Bit 63 of each hstateen CSR is always writable (not read-only).

**Related test items:** None — **NO TEST ITEM**

**Gap analysis:** NO TEST — SsstateenH sheet is placeholder.

**Suggested action:** `cp_mstateen_bit63_hypervisor (new sheet SsstateenH)`

---

## 25. `norm:satp_ppn_sv48_sz`

| Field | Value |
|-------|-------|
| Rule name | `satp_ppn_sv48_sz` |
| Norm chapter | H Extension |
| Spec golden ref | §4.4 Sv48 PPN field width |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** The vsatp register is a VSXLEN-bit read/write register that is VS-mode’s version of supervisor register satp, formatted as shown in for VSXLEN=32 and for VSXLEN=64. When V=1, vsatp substitutes for the usual satp, so instructions that normally read or modify satp actually access vsatp instead. vsatp controls VS-stage address translation, the first stage of two-stage translation for guest virtual addresses (see ).

**Spec golden text (riscv-spec.md):**
> satp PPN field size for Sv48 mode.

**Related test items (partial — norm ID not linked):**

- `cp_satp_mode_field` — sheet **SvH-US**
  - Goal: supported/unsupported MODE encodings
- `cp_vsatp_ppn_field` — sheet **SvH-US**
  - Goal: programmability of PPN field

**Gap analysis:** PPN width for Sv48 not norm-tagged in hypervisor context.

**Suggested action:** `add norm:satp_ppn_sv48_sz to cp_vsatp_ppn_field`

---

## 26. `norm:satp_ppn_sv57_sz`

| Field | Value |
|-------|-------|
| Rule name | `satp_ppn_sv57_sz` |
| Norm chapter | H Extension |
| Spec golden ref | §4.5 Sv57 PPN field width |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** The vsatp register is a VSXLEN-bit read/write register that is VS-mode’s version of supervisor register satp, formatted as shown in for VSXLEN=32 and for VSXLEN=64. When V=1, vsatp substitutes for the usual satp, so instructions that normally read or modify satp actually access vsatp instead. vsatp controls VS-stage address translation, the first stage of two-stage translation for guest virtual addresses (see ).

**Spec golden text (riscv-spec.md):**
> satp PPN field size for Sv57 mode.

**Related test items (partial — norm ID not linked):**

- `cp_satp_mode_field` — sheet **SvH-US**
  - Goal: supported/unsupported MODE encodings
- `cp_vsatp_ppn_field` — sheet **SvH-US**
  - Goal: programmability of PPN field

**Gap analysis:** PPN width for Sv57 not norm-tagged.

**Suggested action:** `add norm:satp_ppn_sv57_sz to cp_vsatp_ppn_field`

---

## 27. `norm:sie_hip_hie_mutex`

| Field | Value |
|-------|-------|
| Rule name | `sie_hip_hie_mutex` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.3 sie/hip/hie mutual exclusion (riscv-spec.md L29557–29558) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** For each writable bit in sie, the corresponding bit shall be read-only zero in both hip and hie. Hence, the nonzero bits in sie and hie are always mutually exclusive, and likewise for sip and hip.

**Spec golden text (riscv-spec.md):**
> For each writable bit in sie, the corresponding bit shall be read-only zero in both hip and hie. Hence, the nonzero bits in sie and hie are always mutually exclusive, and likewise for sip and hip.

**Related test items (partial — norm ID not linked):**

- `cp_hie` — sheet **InterruptsH-NC**
  - Goal: hie.VS*IE bits are alias of mie
- `cp_hip_write` — sheet **InterruptsH-NC**
  - Goal: only hip.vssip is writable, and aliases to hvip
- `cp_mie` — sheet **InterruptsH-NC**
  - Goal: mie.VS*IE bits are alias of hie

**Gap analysis:** sie/hip/hie mutual exclusion not norm-tagged.

**Suggested action:** `cp_sie_hip_hie_mutex`

---

## 28. `norm:sret_dt`

| Field | Value |
|-------|-------|
| Rule name | `sret_dt` |
| Norm chapter | H Extension |
| Spec golden ref | §5.6.4 SRET + Ssdbltrp (riscv-spec.md L30908–30912) |
| Coverage status | **NO TEST** — norm ID **MISSING** in xlsx |

**Norm requirement:** If the Ssdbltrp extension is implemented, when SRET is executed in HS-mode, if the new privilege mode is VU, the SRET instruction sets vsstatus.SDT to 0. When executed in VS-mode, vsstatus.SDT is set to 0.

**Spec golden text (riscv-spec.md):**
> If the Ssdbltrp extension is implemented, when SRET is executed in HS-mode, if the new privilege mode is The RISC-V Instruction Set Manual | © RISC-V International  5.6. Traps | Page 792 VU, the SRET instruction sets vsstatus.SDT to 0. When executed in VS-mode, vsstatus.SDT is set to 0.

**Related test items:** None — **NO TEST ITEM**

**Gap analysis:** NO TEST — SsdbltrpH sheet is placeholder only.

**Suggested action:** `cp_sret_dt_ssdbltrp (new sheet SsdbltrpH)`

---

## 29. `norm:sret_h`

| Field | Value |
|-------|-------|
| Rule name | `sret_h` |
| Norm chapter | H Extension |
| Spec golden ref | §5.6.4 Trap Return — SRET (riscv-spec.md L30900–30901) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** The SRET instruction is used to return from a trap taken into HS-mode or VS-mode. Its behavior depends on the current virtualization mode.

**Spec golden text (riscv-spec.md):**
> The SRET instruction is used to return from a trap taken into HS-mode or VS-mode. Its behavior depends on the current virtualization mode.

**Related test items (partial — norm ID not linked):**

- `cp_sret_hs` — sheet **H - US**
  - Goal: sret from HS mode
- `cp_sret_vs` — sheet **H - US**
  - Goal: sret from VS mode
- `cp_sret_m` — sheet **H - US**
  - Goal: sret from M mode

**Gap analysis:** SRET V-dependent behavior tested but norm not tagged.

**Suggested action:** `add norm:sret_h to cp_sret_hs/cp_sret_vs`

---

## 30. `norm:sret_v0`

| Field | Value |
|-------|-------|
| Rule name | `sret_v0` |
| Norm chapter | H Extension |
| Spec golden ref | §5.6.4 SRET when V=0 (riscv-spec.md L30902–30905) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** When executed in M-mode or HS-mode (i.e., V=0), SRET first determines what the new privilege mode will be according to the values in hstatus.SPV and sstatus.SPP, as encoded in . SRET then sets hstatus.SPV=0, and in sstatus sets SPP=0, SIE=SPIE, and SPIE=1. Lastly, SRET sets the privilege mode as previously determined, and sets pc=sepc.

**Spec golden text (riscv-spec.md):**
> When executed in M-mode or HS-mode (i.e., V=0), SRET first determines what the new privilege mode will be according to the values in hstatus.SPV and sstatus.SPP, as encoded in Table 125. SRET then sets hstatus.SPV=0, and in sstatus sets SPP=0, SIE=SPIE, and SPIE=1. Lastly, SRET sets the privilege mode as previously determined, and sets pc=sepc.

**Related test items (partial — norm ID not linked):**

- `cp_sret_hs` — sheet **H - US**
  - Goal: sret from HS mode
- `cp_sret_m` — sheet **H - US**
  - Goal: sret from M mode

**Gap analysis:** SRET when V=0 path not norm-tagged separately.

**Suggested action:** `add norm:sret_v0 to cp_sret_hs`

---

## 31. `norm:sret_v1`

| Field | Value |
|-------|-------|
| Rule name | `sret_v1` |
| Norm chapter | H Extension |
| Spec golden ref | §5.6.4 SRET when V=1 (riscv-spec.md L30906–30907) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** When executed in VS-mode (i.e., V=1), SRET sets the privilege mode according to , in vsstatus sets SPP=0, SIE=SPIE, and SPIE=1, and lastly sets pc=vsepc.

**Spec golden text (riscv-spec.md):**
> When executed in VS-mode (i.e., V=1), SRET sets the privilege mode according to Table 126, in vsstatus sets SPP=0, SIE=SPIE, and SPIE=1, and lastly sets pc=vsepc.

**Related test items (partial — norm ID not linked):**

- `cp_sret_vs` — sheet **H - US**
  - Goal: sret from VS mode

**Gap analysis:** SRET when V=1 uses vsepc — tested but norm missing.

**Suggested action:** `add norm:sret_v1 to cp_sret_vs`

---

## 32. `norm:ssnpm_definition`

| Field | Value |
|-------|-------|
| Rule name | `ssnpm_definition` |
| Norm chapter | Pointer Masking Extensions |
| Spec golden ref | §Pointer Masking Extensions |
| Coverage status | **NO TEST** — norm ID **MISSING** in xlsx |

**Norm requirement:** A supervisor-level extension that provides pointer masking for the next lower privilege mode (U-mode), and for VS- and VU-modes if the H extension is present.

**Spec golden text (riscv-spec.md):**
> Ssnpm definition for supervisor pointer masking in virtualized environments.

**Related test items:** None — **NO TEST ITEM**

**Gap analysis:** NO TEST — no SsnpmH sheet in test plan.

**Suggested action:** `cp_ssnpm_hypervisor (new sheet)`

---

## 33. `norm:vs_stage_speculative_a_bit`

| Field | Value |
|-------|-------|
| Rule name | `vs_stage_speculative_a_bit` |
| Norm chapter | H Extension |
| Spec golden ref | §5.5 VS-stage speculative A bit (riscv-spec.md L28990–28998) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** when vsatp is active, VS-stage page-table entries’ A bits must not be set as a result of speculative execution, unless the effective privilege mode is VS or VU.

**Spec golden text (riscv-spec.md):**
> When two-stage address translation is in use, an explicit access may cause both VS-stage and G-stage PTEs to be updated. The following rules apply to all PTE updates caused by an explicit or an implicit memory accesses. The PTE update must be atomic with respect to other accesses to the PTE, and must atomically perform all page-table walk checks for that leaf PTE as part of, and before, conditionally updating the PTE value. Updates of the A bit m

**Related test items (partial — norm ID not linked):**

- `cp_vsatp_invalid_pte` — sheet **SvH-US**
  - Goal: invalid PTE behavior
- `cp_hgatp_adbit_behavior` — sheet **SvH-US**
  - Goal: Verify that A/D bits in G-stage PTEs are updated for implicit page table accesses (not the original access type)

**Gap analysis:** A/D bit behavior partially tested but VS-stage speculative A-bit rule not norm-tagged.

**Suggested action:** `cp_vs_stage_speculative_a_bit`

---

## 34. `norm:vsie_img`

| Field | Value |
|-------|-------|
| Rule name | `vsie_img` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.12 Figure 96 — vsie format |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** The vsip and vsie registers are VSXLEN-bit read/write registers that are VS-mode’s versions of supervisor CSRs sip and sie, formatted as shown in and respectively. When V=1, vsip and vsie substitute for the usual sip and sie, so instructions that normally read or modify sip/sie actually access vsip/vsie instead. However, interrupts directed to HS-level continue to be indicated in the HS-level sip register, not in vsip, when V=1.

**Spec golden text (riscv-spec.md):**
> Standard portions (bits 15:0) of vsie formatted per Figure 96.

**Related test items (partial — norm ID not linked):**

- `cp_vsie_from_hie` — sheet **InterruptsH-NC**
  - Goal: hie is alias of vsie when delegated

**Gap analysis:** vsie bit image not explicitly tested.

**Suggested action:** `cp_vsie_img_format`

---

## 35. `norm:vsip_img`

| Field | Value |
|-------|-------|
| Rule name | `vsip_img` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.12 Figure 95 — vsip format |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** The vsip and vsie registers are VSXLEN-bit read/write registers that are VS-mode’s versions of supervisor CSRs sip and sie, formatted as shown in and respectively. When V=1, vsip and vsie substitute for the usual sip and sie, so instructions that normally read or modify sip/sie actually access vsip/vsie instead. However, interrupts directed to HS-level continue to be indicated in the HS-level sip register, not in vsip, when V=1.

**Spec golden text (riscv-spec.md):**
> Standard portions (bits 15:0) of vsip formatted per Figure 95.

**Related test items (partial — norm ID not linked):**

- `cp_hideleg_hip_vs` — sheet **InterruptsH-NC**

**Gap analysis:** vsip bit image not explicitly tested.

**Suggested action:** `cp_vsip_img_format`

---

## 36. `norm:vsip_vsie_lcofi`

| Field | Value |
|-------|-------|
| Rule name | `vsip_vsie_lcofi` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.12 hideleg[13]→LCOFIP (riscv-spec.md L29983–29986) |
| Coverage status | **NO TEST** — norm ID **MISSING** in xlsx |

**Norm requirement:** Extension Shlcofideleg supports delegating LCOFI interrupts to VS-mode. If the Shlcofideleg extension is implemented, hideleg bit 13 is writable; otherwise, it is read-only zero. When bit 13 of hideleg is zero, vsip.LCOFIP and vsie.LCOFIE are read-only zeros. Else, vsip.LCOFIP and vsie.LCOFIE are aliases of sip.LCOFIP and sie.LCOFIE.

**Spec golden text (riscv-spec.md):**
> Extension Shlcofideleg supports delegating LCOFI interrupts to VS-mode. If the Shlcofideleg extension is implemented, hideleg bit 13 is writable; otherwise, it is read-only zero. When bit 13 of hideleg is zero, vsip.LCOFIP and vsie.LCOFIE are read-only zeros. Else, vsip.LCOFIP and vsie.LCOFIE are aliases of sip.LCOFIP and sie.LCOFIE.

**Related test items:** None — **NO TEST ITEM**

**Gap analysis:** NO TEST — Shlcofideleg sheet says 'Develop after baseline'.

**Suggested action:** `cp_vsip_vsie_lcofi (new sheet Shlcofideleg)`

---

## 37. `norm:vsip_vsie_sei`

| Field | Value |
|-------|-------|
| Rule name | `vsip_vsie_sei` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.12 hideleg[10]→SEIP (riscv-spec.md L29987–29988) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** When bit 10 of hideleg is zero, vsip.SEIP and vsie.SEIE are read-only zeros. Else, vsip.SEIP and vsie.SEIE are aliases of hip.VSEIP and hie.VSEIE.

**Spec golden text (riscv-spec.md):**
> When bit 10 of hideleg is zero, vsip.SEIP and vsie.SEIE are read-only zeros. Else, vsip.SEIP and vsie.SEIE are aliases of hip.VSEIP and hie.VSEIE.

**Related test items (partial — norm ID not linked):**

- `cp_hideleg_hip_vs` — sheet **InterruptsH-NC**
- `cp_vsie_from_hie` — sheet **InterruptsH-NC**
  - Goal: hie is alias of vsie when delegated
- `cp_trigger_vsei` — sheet **InterruptsH-NC**
  - Goal: trigger HS-mode VSEI

**Gap analysis:** hideleg[10]→SEIP alias rule not norm-tagged.

**Suggested action:** `add norm:vsip_vsie_sei to cp_hideleg_hip_vs`

---

## 38. `norm:vsip_vsie_ssi`

| Field | Value |
|-------|-------|
| Rule name | `vsip_vsie_ssi` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.12 hideleg[2]→SSIP (riscv-spec.md L29991–29992) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** When bit 2 of hideleg is zero, vsip.SSIP and vsie.SSIE are read-only zeros. Else, vsip.SSIP and vsie.SSIE are aliases of hip.VSSIP and hie.VSSIE.

**Spec golden text (riscv-spec.md):**
> When bit 2 of hideleg is zero, vsip.SSIP and vsie.SSIE are read-only zeros. Else, vsip.SSIP and vsie.SSIE are aliases of hip.VSSIP and hie.VSSIE.

**Related test items (partial — norm ID not linked):**

- `cp_hideleg_hip_vs` — sheet **InterruptsH-NC**
- `cp_trigger_vssi` — sheet **InterruptsH-NC**
  - Goal: trigger HS-mode VSSI

**Gap analysis:** hideleg[2]→SSIP alias not norm-tagged.

**Suggested action:** `add norm:vsip_vsie_ssi to cp_hideleg_hip_vs`

---

## 39. `norm:vsip_vsie_sti`

| Field | Value |
|-------|-------|
| Rule name | `vsip_vsie_sti` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.12 hideleg[6]→STIP (riscv-spec.md L29989–29990) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** When bit 6 of hideleg is zero, vsip.STIP and vsie.STIE are read-only zeros. Else, vsip.STIP and vsie.STIE are aliases of hip.VSTIP and hie.VSTIE.

**Spec golden text (riscv-spec.md):**
> When bit 6 of hideleg is zero, vsip.STIP and vsie.STIE are read-only zeros. Else, vsip.STIP and vsie.STIE are aliases of hip.VSTIP and hie.VSTIE.

**Related test items (partial — norm ID not linked):**

- `cp_hideleg_hip_vs` — sheet **InterruptsH-NC**
- `cp_trigger_vsti` — sheet **InterruptsH-NC**
  - Goal: trigger HS-mode VSTI

**Gap analysis:** hideleg[6]→STIP alias not norm-tagged.

**Suggested action:** `add norm:vsip_vsie_sti to cp_hideleg_hip_vs`

---

## 40. `norm:vsip_vsie_sz_acc_op`

| Field | Value |
|-------|-------|
| Rule name | `vsip_vsie_sz` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.12 vsip/vsie size (riscv-spec.md L29959–29963) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** The vsip and vsie registers are VSXLEN-bit read/write registers that are VS-mode’s versions of supervisor CSRs sip and sie, formatted as shown in and respectively. When V=1, vsip and vsie substitute for the usual sip and sie, so instructions that normally read or modify sip/sie actually access vsip/vsie instead. However, interrupts directed to HS-level continue to be indicated in the HS-level sip register, not in vsip, when V=1.

**Spec golden text (riscv-spec.md):**
> 5.2.12. Virtual Supervisor Interrupt (vsip and vsie) Registers The vsip and vsie registers are VSXLEN-bit read/write registers that are VS-mode’s versions of supervisor CSRs sip and sie, formatted as shown in Figure 93 and Figure 94 respectively. When V=1, vsip and vsie substitute for the usual sip and sie, so instructions that normally read or modify sip/sie actually access vsip/vsie instead. However, interrupts directed to HS-level continue to

**Related test items (partial — norm ID not linked):**

- `cp_hcsr_access` — sheet **H - US**
  - Goal: All H-extension CSRs are able to read, write, set, and clear
  - Current norms: `norm:csr:hstatus:reg`, `norm:csr:hedeleg:reg`, `norm:csr:hideleg:reg`, `norm:csr:hie:reg`, `norm:csr:htimedelta:reg`, `norm:csr:hcounteren:reg`
- `cp_replica` — sheet **H - US**
  - Goal: In VS, writing to S-mode CSRs affects replica instead
  - Current norms: `norm:ext:H:vscsrs-v0`, `norm:ext:H:vscsrs-v0`, `norm:ext:H:vscsrs-v0`

**Gap analysis:** vsip/vsie size and substitution not norm-tagged.

**Suggested action:** `add norm:vsip_vsie_sz_acc_op to cp_hcsr_access`

---

## 41. `norm:vspec_sz_acc_op`

| Field | Value |
|-------|-------|
| Rule name | `vspec_sz` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.15 vsepc WARL (riscv-spec.md L30014–30019) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** The vsepc register is a VSXLEN-bit read/write register that is VS-mode’s version of supervisor register sepc, formatted as shown in . When V=1, vsepc substitutes for the usual sepc, so instructions that normally read or modify sepc actually access vsepc instead. When V=0, vsepc does not directly affect the behavior of the machine.

**Spec golden text (riscv-spec.md):**
> 5.2.15. Virtual Supervisor Exception Program Counter (vsepc) Register The vsepc register is a VSXLEN-bit read/write register that is VS-mode’s version of supervisor register sepc, formatted as shown in Figure 99. When V=1, vsepc substitutes for the usual sepc, so instructions that normally read or modify sepc actually access vsepc instead. When V=0, vsepc does not directly affect the behavior of the machine. vsepc is a WARL register that must be

**Related test items (partial — norm ID not linked):**

- `cp_hcsr_access` — sheet **H - US**
  - Goal: All H-extension CSRs are able to read, write, set, and clear
  - Current norms: `norm:csr:hstatus:reg`, `norm:csr:hedeleg:reg`, `norm:csr:hideleg:reg`, `norm:csr:hie:reg`, `norm:csr:htimedelta:reg`, `norm:csr:hcounteren:reg`

**Gap analysis:** vsepc WARL/size not norm-tagged.

**Suggested action:** `add norm:vspec_sz_acc_op to cp_hcsr_access`

---

## 42. `norm:vsxl_ro`

| Field | Value |
|-------|-------|
| Rule name | `vsxl_ro` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2.1 hstatus.VSXL (riscv-spec.md L29397–29403) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** When HSXLEN=32, the VSXL field does not exist, and VSXLEN=32.

**Spec golden text (riscv-spec.md):**
> The VSXL field controls the effective XLEN for VS-mode (known as VSXLEN), which may differ from the XLEN for HS-mode (HSXLEN). When HSXLEN=32, the VSXL field does not exist, and VSXLEN=32. When HSXLEN=64, VSXL is a WARL field that is encoded the same as the MXL field of misa, shown in Table 96. In particular, an implementation may make VSXL be a read-only field whose value always ensures that VSXLEN=HSXLEN. If HSXLEN is changed from 32 to a wider

**Related test items (partial — norm ID not linked):**

- `cp_hcsrwalk` — sheet **H - US**
  - Goal: Exercise each bit of H-extension CSRs
  - Current norms: `norm:csr:hedeleg:reg`, `norm:csr:hideleg:reg`, `norm:csr:hie:reg`, `norm:csr:htimedelta:reg`, `norm:csr:hcounteren:reg`, `norm:csr:hgeie:reg`

**Gap analysis:** VSXL read-only restriction not isolated.

**Suggested action:** `cp_hstatus_vsxl_ro`

---

## 43. `norm:vsxlen`

| Field | Value |
|-------|-------|
| Rule name | `VSXLEN` |
| Norm chapter | H Extension |
| Spec golden ref | §5.2 intro — VSXLEN (riscv-spec.md L29375–29376) |
| Coverage status | **PARTIAL** — norm ID **MISSING** in xlsx |

**Norm requirement:** Some standard supervisor CSRs (senvcfg, scounteren, and scontext, possibly others) have no matching VS CSR. These supervisor CSRs continue to have their usual function and accessibility even when V=1, except with VS-mode and VU-mode substituting for HS-mode and U-mode. Hypervisor software is expected to manually swap the contents of these registers as needed.

**Spec golden text (riscv-spec.md):**
> VSXLEN is the effective XLEN when executing in VS-mode.

**Related test items (partial — norm ID not linked):**

- `cp_hstatus_vgein` — sheet **H - US**
  - Goal: VGEIN can hold values between 0 and GEILEN
  - Current norms: `norm:csrfld:hstatus:vgein:op`, `norm:csrfld:hstatus:vgein:op`, `norm:csrfld:hstatus:vgein:op`
- `cp_hcsr_access` — sheet **H - US**
  - Goal: All H-extension CSRs are able to read, write, set, and clear
  - Current norms: `norm:csr:hstatus:reg`, `norm:csr:hedeleg:reg`, `norm:csr:hideleg:reg`, `norm:csr:hie:reg`, `norm:csr:htimedelta:reg`, `norm:csr:hcounteren:reg`

**Gap analysis:** VSXLEN via hstatus.VSXL not norm-tagged.

**Suggested action:** `cp_vsxlen_hstatus_vsxl`

---

## Quick Reference — All Missing Norms

| # | Norm Rule | Spec § | Coverage | Test Item(s) | Suggested Action |
|--:|-----------|--------|----------|--------------|------------------|
| 1 | `norm:H_pmp` | §5.5 Two-Stage Address Translation | PARTIAL | `cp_pmp_hs_mode_access`, `cp_pmp_vs_mode_access` (+4) | `add norm:H_pmp to PMPH-US coverpoints` |
| 2 | `norm:H_straddle` | §5.5.2 Guest-Page Faults | PARTIAL | `cp_load_guest_page_fault`, `cp_store_guest_page_fault` (+1) | `cp_guest_page_fault_straddle` |
| 3 | `norm:H_vm_gpa_g` | §5.5.1 Guest Physical Address Translation | PARTIAL | `cp_hgatp_mode_field`, `cp_hgatp_gpa_width_checks` (+1) | `add norm:H_vm_gpa_g to cp_hgatp_mode_field` |
| 4 | `norm:H_vm_twostage` | §5.5 Two-Stage Translation | PARTIAL | `two_stage_read`, `two_stage_write` (+2) | `add norm:H_vm_twostage to two_stage_read` |
| 5 | `norm:Ssqosid_shared_resource_need_management` | §8.1 Ssqosid Extension | NO TEST | — | `cp_ssqosid_hypervisor (new sheet)` |
| 6 | `norm:h_trans_cache` | §5.6.3 Trap Handling — mtinst/htinst transform | PARTIAL | `vs_invalid_pte_cbo`, `g_invalid_pte_cbo` (+1) | `cp_xtinst_cbo_transform` |
| 7 | `norm:hie_acc` | §5.2.3 hie writable bits | PARTIAL | `cp_hie`, `cp_trigger_vsei` (+2) | `cp_hie_warl_writable` |
| 8 | `norm:hie_img` | §5.2.3 Figure 79 — hie format | PARTIAL | `cp_hie` | `cp_hie_img_format` |
| 9 | `norm:hie_op` | §5.2.3 hie register | PARTIAL | `cp_hie`, `cp_mie` | `add norm:hie_op to cp_hie` |
| 10 | `norm:hip_acc` | §5.2.3 hip writable bits | PARTIAL | `cp_hip_write`, `cp_mip` (+1) | `cp_hip_warl_clear` |
| 11 | `norm:hip_hie_sz_acc` | §5.2.3 hip/hie size | PARTIAL | `cp_hcsr_access` | `add norm:hip_hie_sz_acc to cp_hcsr_access` |
| 12 | `norm:hip_img` | §5.2.3 Figure 80 — hip format | PARTIAL | `cp_hip_write` | `cp_hip_img_format` |
| 13 | `norm:hip_op` | §5.2.3 hip register | PARTIAL | `cp_mip`, `cp_hip_write` | `add norm:hip_op to cp_hip_write` |
| 14 | `norm:hlsv_op` | §5.3.1 HLV/HSV instructions | PARTIAL | `cp_hlv`, `cp_hsv` (+2) | `add norm:hlsv_op to cp_hlv/cp_hsv` |
| 15 | `norm:hlsv_priv` | §5.3.1 effective privilege | PARTIAL | `cp_hlv`, `cp_loadstore_priv` (+1) | `cp_hlsv_spvp_effective_priv` |
| 16 | `norm:hlsv_trans` | §5.3.1 two-stage translation | PARTIAL | `cp_hlv`, `two_stage_read` (+1) | `cp_hlsv_twostage_sum` |
| 17 | `norm:hlsv_u_op` | §5.3.1 HLVX execute permission | PARTIAL | `cp_hlvx`, `cp_hlv_access_fault` | `add norm:hlsv_u_op to cp_hlvx` |
| 18 | `norm:hsxlen` | §5.2 intro — HSXLEN | PARTIAL | `cp_hcsr_access` | `cp_hsxlen_impldef` |
| 19 | `norm:mip_mie_alias` | §5.4.3 Machine Interrupt Registers | PARTIAL | `cp_mip`, `cp_mie` (+1) | `add norm:mip_mie_alias to cp_mip/cp_mie` |
| 20 | `norm:mip_mie_vs` | §5.4.3 mip/mie VS bits | PARTIAL | `cp_mip`, `cp_mie` | `add norm:mip_mie_vs to cp_mip` |
| 21 | `norm:misa_h_op` | §5.1 Hypervisor Extension intro | PARTIAL | `cp_hcsr_access` | `cp_misa_h_enable` |
| 22 | `norm:mret_h` | §5.6.4 Trap Return — MRET | PARTIAL | `cp_mret_m` | `add norm:mret_h to cp_mret_m` |
| 23 | `norm:mstateen0_p1p13_op` | §6.1.2 mstateen0 P1P13 field | NO TEST | — | `cp_mstateen0_p1p13 (new sheet SsstateenH)` |
| 24 | `norm:mstateen_bit_63_roz` | §6.1.2 mstateen bit 63 | NO TEST | — | `cp_mstateen_bit63_hypervisor (new sheet SsstateenH)` |
| 25 | `norm:satp_ppn_sv48_sz` | §4.4 Sv48 PPN field width | PARTIAL | `cp_satp_mode_field`, `cp_vsatp_ppn_field` | `add norm:satp_ppn_sv48_sz to cp_vsatp_ppn_field` |
| 26 | `norm:satp_ppn_sv57_sz` | §4.5 Sv57 PPN field width | PARTIAL | `cp_satp_mode_field`, `cp_vsatp_ppn_field` | `add norm:satp_ppn_sv57_sz to cp_vsatp_ppn_field` |
| 27 | `norm:sie_hip_hie_mutex` | §5.2.3 sie/hip/hie mutual exclusion | PARTIAL | `cp_hie`, `cp_hip_write` (+1) | `cp_sie_hip_hie_mutex` |
| 28 | `norm:sret_dt` | §5.6.4 SRET + Ssdbltrp | NO TEST | — | `cp_sret_dt_ssdbltrp (new sheet SsdbltrpH)` |
| 29 | `norm:sret_h` | §5.6.4 Trap Return — SRET | PARTIAL | `cp_sret_hs`, `cp_sret_vs` (+1) | `add norm:sret_h to cp_sret_hs/cp_sret_vs` |
| 30 | `norm:sret_v0` | §5.6.4 SRET when V=0 | PARTIAL | `cp_sret_hs`, `cp_sret_m` | `add norm:sret_v0 to cp_sret_hs` |
| 31 | `norm:sret_v1` | §5.6.4 SRET when V=1 | PARTIAL | `cp_sret_vs` | `add norm:sret_v1 to cp_sret_vs` |
| 32 | `norm:ssnpm_definition` | §Pointer Masking Extensions | NO TEST | — | `cp_ssnpm_hypervisor (new sheet)` |
| 33 | `norm:vs_stage_speculative_a_bit` | §5.5 VS-stage speculative A bit | PARTIAL | `cp_vsatp_invalid_pte`, `cp_hgatp_adbit_behavior` | `cp_vs_stage_speculative_a_bit` |
| 34 | `norm:vsie_img` | §5.2.12 Figure 96 — vsie format | PARTIAL | `cp_vsie_from_hie` | `cp_vsie_img_format` |
| 35 | `norm:vsip_img` | §5.2.12 Figure 95 — vsip format | PARTIAL | `cp_hideleg_hip_vs` | `cp_vsip_img_format` |
| 36 | `norm:vsip_vsie_lcofi` | §5.2.12 hideleg[13]→LCOFIP | NO TEST | — | `cp_vsip_vsie_lcofi (new sheet Shlcofideleg)` |
| 37 | `norm:vsip_vsie_sei` | §5.2.12 hideleg[10]→SEIP | PARTIAL | `cp_hideleg_hip_vs`, `cp_vsie_from_hie` (+1) | `add norm:vsip_vsie_sei to cp_hideleg_hip_vs` |
| 38 | `norm:vsip_vsie_ssi` | §5.2.12 hideleg[2]→SSIP | PARTIAL | `cp_hideleg_hip_vs`, `cp_trigger_vssi` | `add norm:vsip_vsie_ssi to cp_hideleg_hip_vs` |
| 39 | `norm:vsip_vsie_sti` | §5.2.12 hideleg[6]→STIP | PARTIAL | `cp_hideleg_hip_vs`, `cp_trigger_vsti` | `add norm:vsip_vsie_sti to cp_hideleg_hip_vs` |
| 40 | `norm:vsip_vsie_sz_acc_op` | §5.2.12 vsip/vsie size | PARTIAL | `cp_hcsr_access`, `cp_replica` | `add norm:vsip_vsie_sz_acc_op to cp_hcsr_access` |
| 41 | `norm:vspec_sz_acc_op` | §5.2.15 vsepc WARL | PARTIAL | `cp_hcsr_access` | `add norm:vspec_sz_acc_op to cp_hcsr_access` |
| 42 | `norm:vsxl_ro` | §5.2.1 hstatus.VSXL | PARTIAL | `cp_hcsrwalk` | `cp_hstatus_vsxl_ro` |
| 43 | `norm:vsxlen` | §5.2 intro — VSXLEN | PARTIAL | `cp_hstatus_vgein`, `cp_hcsr_access` | `cp_vsxlen_hstatus_vsxl` |