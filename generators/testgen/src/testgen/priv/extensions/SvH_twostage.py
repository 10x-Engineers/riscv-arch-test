##################################
# priv/extensions/SvH_twostage.py
#
# SvH two-stage family — VS/G paging on/off, ifetch, MXR.
# SPDX-License-Identifier: Apache-2.0
##################################

"""Two-stage address-translation tests for SvH_cg.

Each generate_* function builds one tests/priv/SvH/*.S file.
build_twins() puts an Sv32 copy and an Sv39 copy in the same file under
#ifdef SV32_SUPPORTED / #ifdef SV39_SUPPORTED (only one is live per XLEN).

Typical assembly order inside one twin:
  symbols → page tables → enable paging → enter VS/VU → access
  → return to M → SIGUPD → .data section
"""

from __future__ import annotations  # postpone annotation evaluation for forward refs

from testgen.asm.csr import gen_csr_read_sigupd  # emit csrr + SIGUPD for CSR checks
from testgen.asm.helpers import comment_banner, write_sigupd  # file header banner + signature dump
from testgen.data.state import TestData  # per-test metadata (names, coverpoint bins)
from testgen.priv.extensions.SvHCommon import (  # shared SvH generator helpers and PTE constants
    CG,  # covergroup name for SvH two-stage bins
    PTE_CODE_G,  # G-stage code leaf: V|X (execute, supervisor at G walk)
    PTE_CODE_VS,  # VS-stage code leaf: V|X|R|W (guest code page)
    PTE_DATA_VS,  # VS-stage data leaf: V|R|W|A|D (guest read/write data)
    PTE_RW_U_V0,  # G-stage deny leaf: V only (no R/W — guest-page fault on access)
    PTE_X_ONLY_S,  # execute-only VS leaf for supervisor (U=0)
    PTE_X_ONLY_U,  # execute-only leaf for user (U=1)
    Paging,  # "sv32" | "sv39" twin selector passed into each _asm_* builder
    build_twins,  # wrap Sv32/Sv39 twins under #ifdef guards in one .S file
    build_two_stage_maps,  # emit G-stage + VS-stage page-table macros
    disable_paging,  # csrw vsatp/hgatp, x0 + fences (both stages Bare)
    enable_two_stage,  # enable vsatp then hgatp with fences
    enable_vs_only,  # enable vsatp only (hgatp stays Bare)
    fence_both_stages,  # SFENCE.VVMA + HFENCE.GVMA after PT edits
    GOTO_MMODE,  # trap return from VS/VU back to M-mode harness
    GOTO_VS,  # T-SBI hop into VS-mode (uses va_code when paging on)
    GOTO_VU,  # T-SBI hop into VU-mode (uses va_code when paging on)
    load_guest_va,  # la a5, va_data — guest VA for load/store under paging
    mode_names,  # map paging string to G/VS satp mode symbol names
    preload_spa,  # store pattern at test_region PA before guest runs
    set_va_gpa_symbols,  # .set va_*/gpa_* address constants for this twin
    twin_data,  # .data section bytes (test_region backing store)
    two_stage_setup,  # symbols + both-stage maps + enable vsatp/hgatp + fences
)


def _vs_only_page_tables(paging: Paging) -> list[str]:  # VS maps only; hgatp remains Bare
    """VS-stage maps with hgatp Bare (leaf PPNs are PAs, not GPAs)."""
    vs_mode, _ = mode_names(paging)  # e.g. SATP32_MODE vs SATP64_MODE for vsatp write
    lines: list[str] = []  # assembly lines accumulated for this twin
    if paging == "sv39":  # three-level Sv39 VS walk
        # Three-level VS walk; PPNs are supervisor physical addresses.
        lines.append(f"  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)")  # map guest code VA via VS superpage
        lines.append("  csrr a0, mscratch")  # read mscratch (holds relocated save-area pointer)
        lines.append("  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)")  # relocate trap save area to va_code (paging on)
        lines.append("  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_data, LEVEL2)")  # L2 pointer PTE toward data VA
        lines.append("  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)")  # L1 pointer PTE toward data VA
        lines.append(f"  VS_PTE_SETUP(sv39, PA, test_region, {PTE_DATA_VS}, va_data, LEVEL0)")  # L0 leaf: va_data → PA test_region
    else:  # two-level Sv32 VS walk
        # Two-level Sv32 walk.
        lines.append(f"  SUPERPAGE_VS_PTE_SETUP(sv32, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)")  # map guest code VA via VS superpage
        lines.append("  csrr a0, mscratch")  # read mscratch (holds relocated save-area pointer)
        lines.append("  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)")  # relocate trap save area to va_code (paging on)
        lines.append("  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)")  # L1 pointer PTE toward data VA
        lines.append(f"  VS_PTE_SETUP(sv32, PA, test_region, {PTE_DATA_VS}, va_data, LEVEL0)")  # L0 leaf: va_data → PA test_region
    lines.extend(enable_vs_only(vs_mode))  # csrw vsatp + SFENCE.VVMA (G-stage still Bare)
    return lines  # VS-only page-table + enable sequence


def _asm_two_stage_rw(test_data: TestData, paging: Paging) -> list[str]:  # one Sv32/Sv39 twin body
    """One twin: VS store/load through both stages, then SPA check from M."""
    lines = two_stage_setup(paging)  # .set symbols, G+VS maps, enable vsatp+hgatp, fences
    lines.extend(preload_spa(test_data, 0xDEADBEEF))  # seed test_region PA before guest write
    lines.extend(load_guest_va())  # la a5, va_data — guest VA for VS access (needs relocation)
    lines.extend(GOTO_VS)  # T-SBI into VS; trap vectors use va_code (paging on, not identity)
    lines.extend(
        [
            "  LI(a2, 0x257A0005)",  # store pattern into a2 before guest write
            "  sw   a2, 0(a5)",  # VS store through VS-stage then G-stage to SPA
            "  nop",  # pipeline bubble after store
            "  lw   a3, 0(a5)",  # VS load back through both stages; a3 must match a2
            "  nop",  # pipeline bubble after load
        ]
    )
    lines.extend(GOTO_MMODE)  # return to M-mode harness for signature checks
    lines.extend(
        [
            test_data.add_testcase("test1_vs", "two_stage_read", CG),  # cp_two_stage_rw: VS load result bin
            write_sigupd(13, test_data),  # dump a3 (x13) — guest load value
        ]
    )
    lines.extend(
        [
            "  la t1, test_region",  # M-mode PA pointer to backing store (bypass guest translation)
            "  lw t2, 0(t1)",  # read SPA directly to confirm store landed in physical memory
        ]
    )
    lines.extend(
        [
            test_data.add_testcase("test2_spa", "two_stage_write", CG),  # cp_two_stage_rw: SPA write bin
            write_sigupd(7, test_data),  # dump t2 (x7) — physical memory contents
        ]
    )
    lines.extend(twin_data(paging))  # .data section for test_region
    return lines  # complete twin assembly for two_stage_rw


def generate_two_stage_rw_VSmode(test_data: TestData) -> list[str]:  # top-level generator entry point
    """Write SvH_two_stage_rw_VSmode-00.S (cp_two_stage_rw)."""
    return [
        comment_banner("two_stage_rw_VSmode", "VS sw/lw through both stages"),  # file header comment block
        *build_twins(test_data, _asm_two_stage_rw),  # Sv32 + Sv39 twins via _asm_two_stage_rw
    ]


def _asm_two_stage_ifetch(test_data: TestData, paging: Paging) -> list[str]:  # one Sv32/Sv39 twin body
    """One twin: VS instruction fetch through both stages (no data leaf)."""
    lines = set_va_gpa_symbols(paging, with_data=False)  # code VA/GPA symbols only (no va_data)
    lines.extend(build_two_stage_maps(paging, with_data=False))  # G+VS maps for code only; no data leaf
    lines.extend(enable_two_stage(paging))  # enable vsatp + hgatp with fences
    lines.extend(GOTO_VS)  # enter VS; fetch uses va_code through both stages (relocation required)
    lines.extend(
        [
            "  LI(a2, 0x257A00FE)",  # marker value written by VS code reached via two-stage ifetch
            "  nop",  # align / pipeline spacing
            "  nop",  # align / pipeline spacing
        ]
    )
    lines.extend(GOTO_MMODE)  # return to M-mode to read signature register
    lines.extend(
        [
            test_data.add_testcase("test1_ifetch", "two_stage_ifetch", CG),  # cp_two_stage_ifetch bin
            write_sigupd(12, test_data),  # dump a2 (x12) — proves ifetch executed in VS
        ]
    )
    lines.extend(twin_data(paging))  # .data section (minimal; no data page in this test)
    return lines  # complete twin assembly for two_stage_ifetch


def generate_two_stage_ifetch_VSmode(test_data: TestData) -> list[str]:  # top-level generator entry point
    """Write SvH_two_stage_ifetch_VSmode-00.S (cp_two_stage_ifetch)."""
    return [
        comment_banner("two_stage_ifetch_VSmode", "VS instruction fetch through both stages"),  # file header
        *build_twins(test_data, _asm_two_stage_ifetch),  # Sv32 + Sv39 twins via _asm_two_stage_ifetch
    ]


def _asm_both_bare(test_data: TestData, paging: Paging) -> list[str]:  # one Sv32/Sv39 twin body
    """One twin: vsatp and hgatp Bare (identity addressing)."""
    lines = disable_paging()  # csrw vsatp/hgatp, x0 + fences — both stages identity/Bare
    lines.extend(preload_spa(test_data, 0xDEADBEEF))  # seed test_region PA before guest access
    lines.extend(
        [
            "  la a5, test_region",  # guest uses PA directly (Bare — no VA relocation needed)
            "  RVTEST_TSBI_GOTO_VSMODE",  # T-SBI hop to VS; identity addressing, not va_code path
        ]
    )
    lines.extend(
        [
            "  LI(a2, 0x257A0005)",  # store pattern into a2
            "  sw   a2, 0(a5)",  # Bare VS store — address used as-is (no translation)
            "  nop",  # pipeline bubble after store
            "  lw   a3, 0(a5)",  # Bare VS load; a3 must match a2
            "  nop",  # pipeline bubble after load
        ]
    )
    lines.extend(
        [
            test_data.add_testcase("test1_vs", "stage_both_bare", CG),  # cp_stage_both_bare: VS access bin
            write_sigupd(13, test_data),  # dump a3 (x13) — guest load under Bare paging
        ]
    )
    lines.extend(GOTO_MMODE)  # return to M-mode for SPA check (trap path after VS segment)
    lines.extend(
        [
            "  la t1, test_region",  # M-mode PA pointer (same as guest used under Bare)
            "  lw t2, 0(t1)",  # confirm store visible at SPA
        ]
    )
    lines.extend(
        [
            test_data.add_testcase("test2_spa", "stage_both_bare", CG),  # cp_stage_both_bare: SPA bin
            write_sigupd(7, test_data),  # dump t2 (x7) — physical memory contents
        ]
    )
    lines.extend(twin_data(paging))  # .data section for test_region
    return lines  # complete twin assembly for stage_both_bare


def generate_stage_both_bare_VSmode(test_data: TestData) -> list[str]:  # top-level generator entry point
    """Write SvH_stage_both_bare_VSmode-00.S (cp_stage_both_bare)."""
    return [
        comment_banner("stage_both_bare_VSmode", "VS access with vsatp=Bare and hgatp=Bare"),  # file header
        *build_twins(test_data, _asm_both_bare),  # Sv32 + Sv39 twins via _asm_both_bare
    ]


def _asm_hgatp_bare(test_data: TestData, paging: Paging) -> list[str]:  # one Sv32/Sv39 twin body
    """One twin: VS-stage on, G-stage Bare."""
    lines = set_va_gpa_symbols(paging)  # va_code, va_data, gpa_* symbols for VS-only maps
    lines.extend(_vs_only_page_tables(paging))  # VS maps with PA leaf PPNs (hgatp Bare — no G walk)
    lines.extend(preload_spa(test_data, 0xDEADBEEF))  # seed test_region PA before guest write
    lines.extend(load_guest_va())  # la a5, va_data — VS paging on, VA relocation required
    lines.extend(GOTO_VS)  # T-SBI into VS via va_code (VS paging on; G-stage identity)
    lines.extend(
        [
            "  LI(a2, 0x257A0005)",  # store pattern into a2
            "  sw   a2, 0(a5)",  # VS store: VS-stage translate, G-stage Bare (PA = GPA)
            "  nop",  # pipeline bubble after store
            "  lw   a3, 0(a5)",  # VS load back; a3 must match a2
            "  nop",  # pipeline bubble after load
        ]
    )
    lines.extend(GOTO_MMODE)  # return to M-mode for signature and CSR checks
    lines.extend(
        [
            test_data.add_testcase("test1_vs", "cp_hgatp_bare_trans", CG),  # cp_hgatp_bare_trans: VS rw bin
            write_sigupd(13, test_data),  # dump a3 (x13) — guest load value
        ]
    )
    lines.extend(
        [
            "  la t1, test_region",  # M-mode PA pointer to backing store
            "  lw t2, 0(t1)",  # read SPA to confirm store under VS-only paging
        ]
    )
    lines.extend(
        [
            test_data.add_testcase("test2_spa", "cp_hgatp_bare_trans", CG),  # cp_hgatp_bare_trans: SPA write bin
            write_sigupd(7, test_data),  # dump t2 (x7) — physical memory contents
        ]
    )
    lines.extend(
        [
            test_data.add_testcase("test3_hgatp", "hgatp_bare", CG),  # cp_hgatp_bare: hgatp.MODE bin
            gen_csr_read_sigupd(14, ("hgatp", None), test_data),  # read hgatp into a4 (x14); expect MODE=Bare
        ]
    )
    lines.extend(twin_data(paging))  # .data section for test_region
    return lines  # complete twin assembly for hgatp_bare_trans


def generate_hgatp_bare_trans_VSmode(test_data: TestData) -> list[str]:  # top-level generator entry point
    """Write SvH_hgatp_bare_trans_VSmode-00.S (VS paging, hgatp Bare)."""
    return [
        comment_banner("hgatp_bare_trans_VSmode", "VS paging with hgatp=Bare"),  # file header
        *build_twins(test_data, _asm_hgatp_bare),  # Sv32 + Sv39 twins via _asm_hgatp_bare
    ]


def _asm_g_walk_vs_pt(test_data: TestData, paging: Paging) -> list[str]:  # one Sv32/Sv39 twin body
    """One twin: G-stage walk of VS page-table GPAs (allow then deny)."""
    _, g_mode = mode_names(paging)  # G-stage satp mode symbol for G_PTE_SETUP macro
    lines = two_stage_setup(paging)  # symbols, maps (includes G leaf of VS L0 table), enable both stages
    lines.extend(preload_spa(test_data, 0x257A0041))  # seed test_region; distinct pattern for allow path
    lines.extend(load_guest_va())  # la a5, va_data — guest VA for load under two-stage paging
    lines.extend(GOTO_VS)  # enter VS; G-stage must walk VS PT GPAs to reach data
    lines.extend(
        [
            "  lw   a3, 0(a5)",  # load succeeds — G-stage allows R/W on VS PT GPA leaf
            "  nop",  # pipeline bubble after load
        ]
    )
    lines.extend(GOTO_MMODE)  # return to M-mode before rewriting G PTE
    lines.extend(
        [
            test_data.add_testcase("test1_allow", "cp_h_vm_gstagetrans", CG),  # cp_h_vm_gstagetrans: allow bin
            write_sigupd(13, test_data),  # dump a3 (x13) — preload pattern when G walk allowed
        ]
    )
    deny = PTE_RW_U_V0  # V-only G leaf — guest-page fault on data access through VS PT
    lines.append(f"  G_PTE_SETUP({g_mode}, rvtest_vlvl0_pg_tbl, {deny}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)")  # deny R/W on VS L0 table GPA
    lines.extend(fence_both_stages())  # SFENCE.VVMA + HFENCE.GVMA after G PTE change
    lines.extend(
        [
            "  LI(a4, 0)",  # fault sentinel — a4 stays 0 if guest-page fault traps load
        ]
    )
    lines.extend(GOTO_VS)  # re-enter VS for deny-path load (va relocation still required)
    lines.extend(
        [
            "  lw   a4, 0(a5)",  # expect guest-page fault; handler leaves a4 at sentinel 0
            "  nop",  # pipeline bubble after load attempt
        ]
    )
    lines.extend(GOTO_MMODE)  # return to M-mode for deny-path signature
    lines.extend(
        [
            test_data.add_testcase("test2_deny", "VM_permission_invalid_g_rw", CG),  # guest-page fault deny bin
            write_sigupd(14, test_data),  # dump a4 (x14) — should remain 0 on fault
        ]
    )
    lines.extend(twin_data(paging))  # .data section for test_region
    return lines  # complete twin assembly for g_walk_vs_pt


def generate_g_walk_vs_pt_VSmode(test_data: TestData) -> list[str]:  # top-level generator entry point
    """Write SvH_g_walk_vs_pt_VSmode-00.S (G-stage walk of VS page tables)."""
    return [
        comment_banner("g_walk_vs_pt_VSmode", "G-stage maps vs PT GPAs; deny → guest-page fault"),  # file header
        *build_twins(test_data, _asm_g_walk_vs_pt),  # Sv32 + Sv39 twins via _asm_g_walk_vs_pt
    ]


def _asm_mxr(test_data: TestData, paging: Paging, *, vu: bool) -> list[str]:  # one Sv32/Sv39 twin body
    """One twin: execute-only data leaf with MXR=0 then MXR=1.

    vu=False → VS-mode, VS leaf U=0.
    vu=True  → VU-mode, VS leaf U=1.
    """
    xonly_g = PTE_X_ONLY_U  # G-stage data leaf: execute-only (no R/W at G walk)
    xonly_vs = PTE_X_ONLY_U if vu else PTE_X_ONLY_S  # VS leaf U=1 for VU, U=0 for VS
    code_vs = PTE_CODE_G if vu else PTE_CODE_VS  # VU uses U=1 code leaf; VS uses supervisor code leaf
    lines = set_va_gpa_symbols(paging)  # va_code, va_data, gpa_* for MXR load target
    lines.extend(
        build_two_stage_maps(  # both stages with X-only data leaves at VS and G
            paging,
            code_pte=code_vs,  # VS-stage code mapping PTE flags
            data_pte=xonly_vs,  # VS-stage data leaf — no R/W unless MXR set
            g_data_pte=xonly_g,  # G-stage data leaf — X-only at G walk
            g_code_pte=PTE_CODE_G,  # G-stage code leaf
        )
    )
    lines.extend(enable_two_stage(paging))  # enable vsatp + hgatp with fences
    lines.extend(preload_spa(test_data, 0x257A0101))  # seed test_region; expect visible only when MXR=1
    lines.extend(load_guest_va())  # la a5, va_data — guest VA for MXR load tests
    lines.extend(
        [
            "  LI(t0, SSTATUS_MXR)",  # MXR bit mask into t0 for sstatus/vsstatus
            "  csrc sstatus, t0",  # clear MXR in HS-visible sstatus (MXR=0 path)
            "  csrc vsstatus, t0",  # clear MXR in guest vsstatus
            "  LI(a3, 0)",  # fault sentinel — a3 stays 0 if load faults with MXR=0
        ]
    )
    lines.extend(GOTO_VU if vu else GOTO_VS)  # enter VU or VS; va_code relocation required (paging on)
    lines.extend(
        [
            "  lw   a3, 0(a5)",  # load from X-only page — expect fault when MXR=0
            "  nop",  # pipeline bubble after load attempt
        ]
    )
    lines.extend(GOTO_MMODE)  # return to M-mode before enabling MXR
    lines.extend(
        [
            test_data.add_testcase("test1_mxr0", "cp_two_stage_mxr", CG),  # cp_two_stage_mxr: MXR=0 fault bin
            write_sigupd(13, test_data),  # dump a3 (x13) — sentinel 0 if faulted
        ]
    )
    lines.extend(
        [
            "  LI(t0, SSTATUS_MXR)",  # MXR bit mask into t0
            "  csrs sstatus, t0",  # set MXR in HS-visible sstatus (MXR=1 path)
            "  csrs vsstatus, t0",  # set MXR in guest vsstatus
            "  LI(a4, 0)",  # clear a4 before MXR=1 load (will hold preload if success)
        ]
    )
    lines.extend(GOTO_VU if vu else GOTO_VS)  # re-enter guest mode for MXR=1 load attempt
    lines.extend(
        [
            "  lw   a4, 0(a5)",  # load from X-only page — expect preload pattern when MXR=1
            "  nop",  # pipeline bubble after load
        ]
    )
    lines.extend(GOTO_MMODE)  # return to M-mode for MXR=1 signature
    lines.extend(
        [
            test_data.add_testcase("test2_mxr1", "cp_two_stage_mxr", CG),  # cp_two_stage_mxr: MXR=1 success bin
            write_sigupd(14, test_data),  # dump a4 (x14) — preload value when MXR allows read
        ]
    )
    lines.extend(twin_data(paging))  # .data section for test_region
    return lines  # complete twin assembly for two_stage_mxr


def generate_two_stage_mxr_VSmode(test_data: TestData) -> list[str]:  # top-level generator entry point
    """Write SvH_two_stage_mxr_VSmode-00.S (cp_two_stage_mxr, VS)."""

    def asm_for_paging(td: TestData, paging: Paging) -> list[str]:  # twin callback for build_twins
        return _asm_mxr(td, paging, vu=False)  # VS-mode, U=0 leaves

    return [
        comment_banner("two_stage_mxr_VSmode", "VS MXR on X-only pages"),  # file header
        *build_twins(test_data, asm_for_paging),  # Sv32 + Sv39 twins with VS-mode MXR test
    ]


def generate_two_stage_mxr_VUmode(test_data: TestData) -> list[str]:  # top-level generator entry point
    """Write SvH_two_stage_mxr_VUmode-00.S (cp_two_stage_mxr, VU, U=1 leaves)."""

    def asm_for_paging(td: TestData, paging: Paging) -> list[str]:  # twin callback for build_twins
        return _asm_mxr(td, paging, vu=True)  # VU-mode, U=1 leaves

    return [
        comment_banner("two_stage_mxr_VUmode", "VU MXR on U=1 X-only pages"),  # file header
        *build_twins(test_data, asm_for_paging),  # Sv32 + Sv39 twins with VU-mode MXR test
    ]
