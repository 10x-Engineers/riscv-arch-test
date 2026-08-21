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

from __future__ import annotations  # postpone evaluation of type hints

from testgen.asm.helpers import comment_banner  # file-level assembly banner
from testgen.data.state import TestData  # open TestChunk (SIGUPD / testcase counters)
from testgen.priv.extensions.SvHCommon import (  # shared SvH page-table / mode helpers
    PTE_CODE_G,  # G-stage code leaf flags (X+R, U=1)
    PTE_CODE_VS,  # VS-stage code leaf flags (X+R, U=0)
    PTE_DATA_VS,  # VS-stage data leaf flags (W+R, U=0)
    Paging,  # "sv32" | "sv39" twin selector
    build_twins,  # wrap asm builder in Sv32 + Sv39 ifdefs
    build_two_stage_maps,  # emit G + VS page-table macros
    count_sigupds,  # bump TestData SIGUPD counter
    disable_paging,  # csrw vsatp/hgatp, x0 + fences
    enable_two_stage,  # program vsatp + hgatp and fence both
    enable_vs_only,  # vsatp ON, hgatp Bare, both fences
    fence_both_stages,  # SFENCE.VMA + HFENCE.GVMA
    goto_mmode,  # return from VS/VU to M-mode
    goto_vs,  # enter VS-mode (VA-relocated code)
    goto_vu,  # enter VU-mode (U=1 leaves)
    load_guest_va,  # a5 = va_data guest VA
    mismatch_string,  # .asciz label for fail message
    mode_names,  # (vsatp MODE name, hgatp MODE name)
    preload_spa,  # write known pattern into physical page
    pte_bits,  # build PTE flag string from X/W/R/U/V
    set_va_gpa_symbols,  # .set va_* / gpa_* for this twin
    sigupd_labeled,  # dump one GPR into the signature
    twin_data,  # .data section with mismatch strings
    two_stage_setup,  # symbols + maps + enable both stages
)  # end SvHCommon imports


def _vs_only_page_tables(paging: Paging) -> list[str]:  # define _vs_only_page_tables
    """VS-stage maps with hgatp Bare (leaf PPNs are PAs, not GPAs)."""
    vs_mode, _ = mode_names(paging)  # "sv32" or "sv39" for VSATP_SETUP
    lines: list[str] = []  # assembly lines for this twin
    if paging == "sv39":  # RV64 three-level VS walk
        # Three-level VS walk; PPNs are supervisor physical addresses.
        lines.append(f"  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)")  # map code VA as megapage
        lines.append("  csrr a0, mscratch")  # save-area base for V_SAVE_AREA_SETUP
        lines.append("  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)")  # relocate trap save area
        lines.append("  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_data, LEVEL2)")  # L2 → L1 table
        lines.append("  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)")  # L1 → L0 table
        lines.append(f"  VS_PTE_SETUP(sv39, PA, test_region, {PTE_DATA_VS}, va_data, LEVEL0)")  # L0 data leaf → PA
    else:  # RV32 two-level Sv32 walk
        # Two-level Sv32 walk.
        lines.append(f"  SUPERPAGE_VS_PTE_SETUP(sv32, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)")  # map code VA as megapage
        lines.append("  csrr a0, mscratch")  # save-area base for V_SAVE_AREA_SETUP
        lines.append("  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)")  # relocate trap save area
        lines.append("  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)")  # L1 → L0 table
        lines.append(f"  VS_PTE_SETUP(sv32, PA, test_region, {PTE_DATA_VS}, va_data, LEVEL0)")  # L0 data leaf → PA
    lines.extend(enable_vs_only(vs_mode))  # vsatp ON, hgatp=0, both fences
    return lines  # VS-only page-table + enable sequence


def _asm_two_stage_rw(test_data: TestData, paging: Paging) -> list[str]:  # define _asm_two_stage_rw
    """One twin: VS store/load through both stages, then SPA check from M."""
    lines = two_stage_setup(paging)  # .set, G+VS maps, vsatp+hgatp, fences
    lines.extend(preload_spa(0xDEADBEEF))  # known pattern in the physical page
    lines.extend(load_guest_va())  # a5 = va_data
    lines.extend(goto_vs())  # enter VS (VA != PA relocate)
    lines.extend(
        [
            "  LI(a2, 0x257A0005)",  # store payload
            "  sw   a2, 0(a5)",  # VS store: VS-stage then G-stage
            "  nop",  # retire padding
            "  lw   a3, 0(a5)",  # VS load; a3 must match a2
            "  nop",  # retire padding
        ]
    )
    lines.extend(goto_mmode())  # signature is not guest-mapped
    lines.extend(sigupd_labeled("test1_vs", "a3"))  # dump guest load result
    lines.extend(
        [
            "  la t1, test_region",  # SPA address of physical page
            "  lw t2, 0(t1)",  # SPA readback of stored word
        ]
    )
    lines.extend(sigupd_labeled("test2_spa", "t2"))  # dump SPA word
    count_sigupds(test_data, 2)  # two SIGUPD sites
    lines.extend(
        twin_data(
            paging,  # which twin's .data symbols
            mismatch_strings=[  # fail messages for each SIGUPD
                mismatch_string("test1_vs", "Mismatch on VS lw after two-stage sw"),  # guest load fail text
                mismatch_string("test2_spa", "Mismatch on SPA readback after two-stage store"),  # SPA fail text
            ],
        )
    )
    return lines  # full twin asm for two-stage sw/lw


def generate_two_stage_rw_VSmode(test_data: TestData) -> list[str]:  # define generate_two_stage_rw_VSmode
    """Write SvH_two_stage_rw_VSmode-00.S (cp_two_stage_rw)."""
    return [
        comment_banner("two_stage_rw_VSmode", "VS sw/lw through both stages"),  # top-of-file banner
        *build_twins(test_data, _asm_two_stage_rw),  # Sv32 + Sv39 twins
    ]


def _asm_two_stage_ifetch(test_data: TestData, paging: Paging) -> list[str]:  # define _asm_two_stage_ifetch
    """One twin: VS instruction fetch through both stages (no data leaf)."""
    lines = set_va_gpa_symbols(paging, with_data=False)  # code VA/GPA only
    lines.extend(build_two_stage_maps(paging, with_data=False))  # no data walks
    lines.extend(enable_two_stage(paging))  # vsatp + hgatp
    lines.extend(goto_vs())  # execute at va_code
    lines.extend(
        [
            "  LI(a2, 0x257A00FE)",  # marker value proving VS ifetch ran
            "  nop",  # retire padding
            "  nop",  # retire padding
        ]
    )
    lines.extend(goto_mmode())  # back to M for signature
    lines.extend(sigupd_labeled("test1_ifetch", "a2"))  # dump ifetch marker GPR
    count_sigupds(test_data, 1)  # one SIGUPD site
    lines.extend(
        twin_data(
            paging,  # which twin's .data symbols
            mismatch_strings=[  # fail messages for each SIGUPD
                mismatch_string("test1_ifetch", "Mismatch on VS ifetch through two-stage"),  # ifetch fail text
            ],
        )
    )
    return lines  # full twin asm for two-stage ifetch


def generate_two_stage_ifetch_VSmode(test_data: TestData) -> list[str]:  # define generate_two_stage_ifetch_VSmode
    """Write SvH_two_stage_ifetch_VSmode-00.S (cp_two_stage_ifetch)."""
    return [
        comment_banner("two_stage_ifetch_VSmode", "VS instruction fetch through both stages"),  # top-of-file banner
        *build_twins(test_data, _asm_two_stage_ifetch),  # Sv32 + Sv39 twins
    ]


def _asm_both_bare(test_data: TestData, paging: Paging) -> list[str]:  # define _asm_both_bare
    """One twin: vsatp and hgatp Bare (identity addressing)."""
    lines = disable_paging()  # csrw vsatp/hgatp, x0 + fences
    lines.extend(preload_spa(0xDEADBEEF))  # known pattern in the physical page
    lines.extend(
        [
            "  la a5, test_region",  # Bare: VA == PA of data page
            "  RVTEST_TSBI_GOTO_VSMODE",  # hop to VS without VA relocate
        ]
    )
    lines.extend(
        [
            "  LI(a2, 0x257A0005)",  # store payload
            "  sw   a2, 0(a5)",  # Bare VS store (identity)
            "  nop",  # retire padding
            "  lw   a3, 0(a5)",  # Bare VS load; a3 must match a2
            "  nop",  # retire padding
        ]
    )
    lines.extend(sigupd_labeled("test1_vs", "a3"))  # Bare: dump before M return
    lines.extend(goto_mmode())  # back to M for SPA check
    lines.extend(
        [
            "  la t1, test_region",  # SPA address of physical page
            "  lw t2, 0(t1)",  # SPA readback of stored word
        ]
    )
    lines.extend(sigupd_labeled("test2_spa", "t2"))  # dump SPA word
    count_sigupds(test_data, 2)  # two SIGUPD sites
    lines.extend(
        twin_data(
            paging,  # which twin's .data symbols
            mismatch_strings=[  # fail messages for each SIGUPD
                mismatch_string("test1_vs", "Mismatch on VS lw after sw (both Bare)"),  # guest load fail text
                mismatch_string("test2_spa", "Mismatch on SPA readback (both Bare)"),  # SPA fail text
            ],
        )
    )
    return lines  # full twin asm for both Bare


def generate_stage_both_bare_VSmode(test_data: TestData) -> list[str]:  # define generate_stage_both_bare_VSmode
    """Write SvH_stage_both_bare_VSmode-00.S (cp_stage_both_bare)."""
    return [
        comment_banner("stage_both_bare_VSmode", "VS access with vsatp=Bare and hgatp=Bare"),  # top-of-file banner
        *build_twins(test_data, _asm_both_bare),  # Sv32 + Sv39 twins
    ]


def _asm_hgatp_bare(test_data: TestData, paging: Paging) -> list[str]:  # define _asm_hgatp_bare
    """One twin: VS-stage on, G-stage Bare."""
    lines = set_va_gpa_symbols(paging)  # .set va_* / gpa_* for this twin
    lines.extend(_vs_only_page_tables(paging))  # VS maps with PA PPNs
    lines.extend(preload_spa(0xDEADBEEF))  # known pattern in the physical page
    lines.extend(load_guest_va())  # a5 = va_data
    lines.extend(goto_vs())  # enter VS (VA-relocated)
    lines.extend(
        [
            "  LI(a2, 0x257A0005)",  # store payload
            "  sw   a2, 0(a5)",  # VS-stage only (hgatp Bare)
            "  nop",  # retire padding
            "  lw   a3, 0(a5)",  # VS load; a3 must match a2
            "  nop",  # retire padding
        ]
    )
    lines.extend(goto_mmode())  # back to M for signature
    lines.extend(sigupd_labeled("test1_vs", "a3"))  # dump guest load result
    lines.extend(
        [
            "  la t1, test_region",  # SPA address of physical page
            "  lw t2, 0(t1)",  # SPA readback of stored word
        ]
    )
    lines.extend(sigupd_labeled("test2_spa", "t2"))  # dump SPA word
    lines.extend(
        [
            "  test3_hgatp:",  # label for hgatp SIGUPD case
            "  RVTEST_SIGUPD_CSR_READ(hgatp, a4, test3_hgatp, test3_hgatp_str)",  # dump hgatp (expect Bare)
        ]
    )
    count_sigupds(test_data, 3)  # lw + SPA + hgatp
    lines.extend(
        twin_data(
            paging,  # which twin's .data symbols
            mismatch_strings=[  # fail messages for each SIGUPD
                mismatch_string("test1_vs", "Mismatch on VS lw (hgatp Bare)"),  # guest load fail text
                mismatch_string("test2_spa", "Mismatch on SPA readback (hgatp Bare)"),  # SPA fail text
                mismatch_string("test3_hgatp", "Mismatch on hgatp still Bare"),  # hgatp fail text
            ],
        )
    )
    return lines  # full twin asm for VS-on / G-Bare


def generate_hgatp_bare_trans_VSmode(test_data: TestData) -> list[str]:  # define generate_hgatp_bare_trans_VSmode
    """Write SvH_hgatp_bare_trans_VSmode-00.S (VS paging, hgatp Bare)."""
    return [
        comment_banner("hgatp_bare_trans_VSmode", "VS paging with hgatp=Bare"),  # top-of-file banner
        *build_twins(test_data, _asm_hgatp_bare),  # Sv32 + Sv39 twins
    ]


def _asm_g_walk_vs_pt(test_data: TestData, paging: Paging) -> list[str]:  # define _asm_g_walk_vs_pt
    """One twin: G-stage walk of VS page-table GPAs (allow then deny)."""
    _, g_mode = mode_names(paging)  # hgatp MODE name (sv32x4 / sv39x4)
    lines = two_stage_setup(paging)  # includes G leaf of VS L0 table
    lines.extend(preload_spa(0x257A0041))  # known pattern for allow-path load
    lines.extend(load_guest_va())  # a5 = va_data
    lines.extend(goto_vs())  # enter VS for allow-path lw
    lines.extend(
        [
            "  lw   a3, 0(a5)",  # G allows VS-PT walk → load completes
            "  nop",  # retire padding
        ]
    )
    lines.extend(goto_mmode())  # back to M after allow path
    lines.extend(sigupd_labeled("test1_allow", "a3"))  # dump allow-path load
    deny = pte_bits(x=False, w=True, r=True, u=True, v=False)  # G leaf V=0 on VS L0 page
    lines.append(f"  G_PTE_SETUP({g_mode}, rvtest_vlvl0_pg_tbl, {deny}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)")  # invalidate G leaf over VS L0
    lines.extend(fence_both_stages())  # flush both TLBs after PTE change
    lines.extend(
        [
            "  LI(a4, 0)",  # fault sentinel before deny-path load
        ]
    )
    lines.extend(goto_vs())  # re-enter VS for deny-path lw
    lines.extend(
        [
            "  lw   a4, 0(a5)",  # guest-page fault; a4 stays 0
            "  nop",  # retire padding
        ]
    )
    lines.extend(goto_mmode())  # back to M after deny path
    lines.extend(sigupd_labeled("test2_deny", "a4"))  # dump deny-path sentinel
    count_sigupds(test_data, 2)  # two SIGUPD sites
    lines.extend(
        twin_data(
            paging,  # which twin's .data symbols
            mismatch_strings=[  # fail messages for each SIGUPD
                mismatch_string("test1_allow", "Mismatch on VS lw with G allowing VS-PT walk"),  # allow fail text
                mismatch_string("test2_deny", "Mismatch on VS lw with G denying VS-PT walk"),  # deny fail text
            ],
        )
    )
    return lines  # full twin asm for G walk of VS PTs


def generate_g_walk_vs_pt_VSmode(test_data: TestData) -> list[str]:  # define generate_g_walk_vs_pt_VSmode
    """Write SvH_g_walk_vs_pt_VSmode-00.S (G-stage walk of VS page tables)."""
    return [
        comment_banner("g_walk_vs_pt_VSmode", "G-stage maps vs PT GPAs; deny → guest-page fault"),  # top-of-file banner
        *build_twins(test_data, _asm_g_walk_vs_pt),  # Sv32 + Sv39 twins
    ]


def _asm_mxr(test_data: TestData, paging: Paging, *, vu: bool) -> list[str]:  # define _asm_mxr
    """One twin: execute-only data leaf with MXR=0 then MXR=1.

    vu=False → VS-mode, VS leaf U=0.
    vu=True  → VU-mode, VS leaf U=1.
    """
    xonly_g = pte_bits(x=True, w=False, r=False, u=True, v=True)  # G X-only, U=1
    xonly_vs = pte_bits(x=True, w=False, r=False, u=vu, v=True)  # VS X-only; U=1 iff VU
    code_vs = pte_bits(x=True, w=False, r=True, u=vu, v=True)  # VS code; U=1 iff VU
    lines = set_va_gpa_symbols(paging)  # .set va_* / gpa_* for this twin
    lines.extend(
        build_two_stage_maps(
            paging,  # which twin's page sizes
            code_pte=code_vs,  # VS code leaf (U matches VS/VU)
            data_pte=xonly_vs,  # VS data leaf is execute-only
            g_data_pte=xonly_g,  # G data leaf is execute-only
            g_code_pte=PTE_CODE_G,  # G code leaf stays X+R U=1
        )
    )
    lines.extend(enable_two_stage(paging))  # vsatp + hgatp
    lines.extend(preload_spa(0x257A0101))  # pattern expected when MXR=1 load works
    lines.extend(load_guest_va())  # a5 = va_data
    lines.extend(
        [
            "  LI(t0, SSTATUS_MXR)",  # MXR bit mask into t0
            "  csrc sstatus, t0",  # MXR=0
            "  csrc vsstatus, t0",  # clear guest MXR too
            "  LI(a3, 0)",  # fault sentinel
        ]
    )
    lines.extend(goto_vu() if vu else goto_vs())  # enter VU or VS for MXR=0 load
    lines.extend(
        [
            "  lw   a3, 0(a5)",  # expect fault when MXR=0
            "  nop",  # retire padding
        ]
    )
    lines.extend(goto_mmode())  # back to M after MXR=0 path
    lines.extend(sigupd_labeled("test1_mxr0", "a3"))  # dump MXR=0 sentinel
    lines.extend(
        [
            "  LI(t0, SSTATUS_MXR)",  # MXR bit mask into t0
            "  csrs sstatus, t0",  # MXR=1: execute-only may be read
            "  csrs vsstatus, t0",  # set guest MXR too
            "  LI(a4, 0)",  # clear before MXR=1 load
        ]
    )
    lines.extend(goto_vu() if vu else goto_vs())  # enter VU or VS for MXR=1 load
    lines.extend(
        [
            "  lw   a4, 0(a5)",  # expect preload pattern
            "  nop",  # retire padding
        ]
    )
    lines.extend(goto_mmode())  # back to M after MXR=1 path
    lines.extend(sigupd_labeled("test2_mxr1", "a4"))  # dump MXR=1 load result
    count_sigupds(test_data, 2)  # two SIGUPD sites
    who = "VU" if vu else "VS"  # label text for mismatch strings
    lines.extend(
        twin_data(
            paging,  # which twin's .data symbols
            mismatch_strings=[  # fail messages for each SIGUPD
                mismatch_string("test1_mxr0", f"Mismatch on {who} MXR=0 X-only load"),  # MXR=0 fail text
                mismatch_string("test2_mxr1", f"Mismatch on {who} MXR=1 X-only load"),  # MXR=1 fail text
            ],
        )
    )
    return lines  # full twin asm for MXR X-only loads


def generate_two_stage_mxr_VSmode(test_data: TestData) -> list[str]:  # define generate_two_stage_mxr_VSmode
    """Write SvH_two_stage_mxr_VSmode-00.S (cp_two_stage_mxr, VS)."""

    def asm_for_paging(td: TestData, paging: Paging) -> list[str]:  # twin builder for VS MXR
        return _asm_mxr(td, paging, vu=False)  # VS-mode, U=0 leaves

    return [
        comment_banner("two_stage_mxr_VSmode", "VS MXR on X-only pages"),  # top-of-file banner
        *build_twins(test_data, asm_for_paging),  # Sv32 + Sv39 twins
    ]


def generate_two_stage_mxr_VUmode(test_data: TestData) -> list[str]:  # define generate_two_stage_mxr_VUmode
    """Write SvH_two_stage_mxr_VUmode-00.S (cp_two_stage_mxr, VU, U=1 leaves)."""

    def asm_for_paging(td: TestData, paging: Paging) -> list[str]:  # twin builder for VU MXR
        return _asm_mxr(td, paging, vu=True)  # VU-mode, U=1 leaves

    return [
        comment_banner("two_stage_mxr_VUmode", "VU MXR on U=1 X-only pages"),  # top-of-file banner
        *build_twins(test_data, asm_for_paging),  # Sv32 + Sv39 twins
    ]
