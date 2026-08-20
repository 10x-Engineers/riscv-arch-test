##################################
# priv/extensions/SvH_twostage.py
#
# SvH two-stage family — VS/G paging on/off, ifetch, MXR.
# SPDX-License-Identifier: Apache-2.0
##################################

"""Two-stage address-translation stimulus for ``SvH_cg``.

Each public ``generate_*`` function is one output file. ``emit_twin`` emits
an Sv32 body and an Sv39 body under ``#ifdef SV32_SUPPORTED`` /
``#ifdef SV39_SUPPORTED``. Only one ifdef is compiled per XLEN.

Typical body sequence:
  page-table setup → enable vsatp/hgatp → enter VS/VU → access →
  return to M-mode → ``RVTEST_SIGUPD`` → ``.pushsection .data``.
"""

from __future__ import annotations  # postpone evaluation of type hints

from testgen.asm.helpers import comment_banner  # file-level assembly banner
from testgen.data.state import TestData  # open TestChunk
from testgen.priv.extensions.SvHCommon import (
    PTE_CODE_G,  # G-stage code leaf (U=1 X R V)
    PTE_CODE_VS,  # VS-stage code leaf
    PTE_DATA_VS,  # VS-stage data leaf
    Paging,  # "sv32" | "sv39"
    emit_both_bare,  # vsatp=0, hgatp=0
    emit_enable_paging,  # two-stage enable + fences
    emit_enable_vs_hgatp_bare,  # vsatp ON, hgatp Bare
    emit_goto_mmode,  # return to M before SIGUPD
    emit_goto_vs,  # GOTO_LOWER_MODE VSmode
    emit_goto_vu,  # GOTO_LOWER_MODE VUmode
    emit_hfence_both,  # hfence.vvma + hfence.gvma
    emit_load_va_ptr,  # LI(a5, va_data)
    emit_manual_sigupd,  # RVTEST_SIGUPD with a label
    emit_mismatch_string,  # .string for mismatch text
    emit_spa_preload,  # M-mode store to test_region
    emit_standard_prologue,  # .set + two-stage maps + enable
    emit_twin,  # Sv32/Sv39 ifdef wrap + max SIGUPD
    emit_two_stage_maps,  # G_PTE_SETUP / VS_PTE_SETUP
    emit_va_gpa_sets,  # .set va_* / gpa_*
    paging_modes,  # MODE name pair
    pte_flags,  # build (PTE_D | …) text
    twin_data_section,  # .pushsection .data for one twin
)


def _bump(test_data: TestData, n: int) -> None:
    """Add ``n`` to ``sigupd_count`` and ``num_testcases`` for the current chunk.

    The writer uses ``sigupd_count`` to size ``#define SIGUPD_COUNT``.
    """
    assert test_data.test_chunk is not None  # generate_* always runs inside make_svh
    test_data.test_chunk.sigupd_count += n  # n RVTEST_SIGUPD sites in this body
    test_data.test_chunk.num_testcases += n  # one testcase string per SIGUPD here


def _emit_vs_only_maps(paging: Paging) -> list[str]:
    """Emit VS-stage maps with hgatp Bare.

    Leaf PPNs are supervisor physical addresses (``PA``), not GPAs.
    ``V_SAVE_AREA_SETUP`` relocates the save area because ``va_code`` != PA.
    """
    vs_mode, _ = paging_modes(paging)  # "sv32" or "sv39" for VSATP_SETUP
    lines: list[str] = []  # VS maps then enable
    if paging == "sv39":  # three-level VS walk
        # Code superpage at LEVEL1; data through L2/L1/L0; PPNs are PAs.
        lines.append(f"  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)")
        lines.append("  csrr a0, mscratch")  # M save-area pointer required by V_SAVE_AREA_SETUP
        lines.append("  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)")  # relocate save area
        lines.append("  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_data, LEVEL2)")  # L2 ptr
        lines.append("  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)")  # L1 ptr
        lines.append(f"  VS_PTE_SETUP(sv39, PA, test_region, {PTE_DATA_VS}, va_data, LEVEL0)")  # data leaf
    else:  # two-level Sv32 walk
        lines.append(f"  SUPERPAGE_VS_PTE_SETUP(sv32, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)")
        lines.append("  csrr a0, mscratch")  # save-area pointer
        lines.append("  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)")
        lines.append("  VS_PTE_SETUP(sv32, PA, rvtest_vlvl0_pg_tbl, (PTE_V), va_data, LEVEL1)")  # L1 ptr
        lines.append(f"  VS_PTE_SETUP(sv32, PA, test_region, {PTE_DATA_VS}, va_data, LEVEL0)")  # data leaf
    lines.extend(emit_enable_vs_hgatp_bare(vs_mode))  # vsatp ON, hgatp=0, both fences
    return lines


def _body_two_stage_rw(test_data: TestData, paging: Paging) -> list[str]:
    """Sv32 or Sv39 body: VS store/load through both stages, then SPA check from M."""
    lines = emit_standard_prologue(paging)  # .set, G+VS maps, vsatp+hgatp, fences
    lines.extend(emit_spa_preload(0xDEADBEEF))  # known pattern in the physical page
    lines.extend(emit_load_va_ptr())  # a5 = va_data
    lines.extend(emit_goto_vs())  # enter VS (VA != PA relocate)
    lines.extend(
        [
            "  LI(a2, 0x257A0005)",  # store payload
            "  sw   a2, 0(a5)",  # VS store: VS-stage then G-stage
            "  nop",  # retire padding
            "  lw   a3, 0(a5)",  # VS load; a3 must match a2
            "  nop",
        ]
    )
    lines.extend(emit_goto_mmode())  # signature is not guest-mapped
    lines.extend(emit_manual_sigupd("test1_vs", "a3"))  # dump guest load result
    lines.extend(["  la t1, test_region", "  lw t2, 0(t1)"])  # SPA readback of the same page
    lines.extend(emit_manual_sigupd("test2_spa", "t2"))  # dump SPA word
    _bump(test_data, 2)  # two SIGUPD sites
    lines.extend(
        twin_data_section(
            paging,
            mismatch_strings=[
                emit_mismatch_string("test1_vs", "Mismatch on VS lw after two-stage sw"),
                emit_mismatch_string("test2_spa", "Mismatch on SPA readback after two-stage store"),
            ],
        )
    )
    return lines


def generate_two_stage_rw_VSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_two_stage_rw_VSmode-00.S`` (``cp_two_stage_rw``)."""
    return [
        comment_banner("two_stage_rw_VSmode", "VS sw/lw through both stages"),
        *emit_twin(test_data, _body_two_stage_rw),  # Sv32 + Sv39 ifdefs
    ]


def _body_two_stage_ifetch(test_data: TestData, paging: Paging) -> list[str]:
    """Sv32 or Sv39 body: VS instruction fetch through both stages. No data leaf."""
    lines = emit_va_gpa_sets(paging, with_data=False)  # code VA/GPA only
    lines.extend(emit_two_stage_maps(paging, with_data=False))  # no data walks
    lines.extend(emit_enable_paging(paging))  # vsatp + hgatp
    lines.extend(emit_goto_vs())  # execute at va_code
    lines.extend(["  LI(a2, 0x257A00FE)", "  nop", "  nop"])  # retired VS insn samples mem_i PTE
    lines.extend(emit_goto_mmode())
    lines.extend(emit_manual_sigupd("test1_ifetch", "a2"))  # dump a2
    _bump(test_data, 1)  # one SIGUPD
    lines.extend(
        twin_data_section(
            paging,
            mismatch_strings=[
                emit_mismatch_string("test1_ifetch", "Mismatch on VS ifetch through two-stage"),
            ],
        )
    )
    return lines


def generate_two_stage_ifetch_VSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_two_stage_ifetch_VSmode-00.S`` (``cp_two_stage_ifetch``)."""
    return [
        comment_banner("two_stage_ifetch_VSmode", "VS instruction fetch through both stages"),
        *emit_twin(test_data, _body_two_stage_ifetch),
    ]


def _body_both_bare(test_data: TestData, paging: Paging) -> list[str]:
    """Sv32 or Sv39 body: vsatp and hgatp Bare (identity addressing)."""
    lines = emit_both_bare()  # csrw vsatp/hgatp, x0 + fences
    lines.extend(emit_spa_preload(0xDEADBEEF))  # pattern in test_region
    lines.extend(["  la a5, test_region", "  RVTEST_TSBI_GOTO_VSMODE"])  # identity: T-SBI hop
    lines.extend(
        [
            "  LI(a2, 0x257A0005)",  # store payload
            "  sw   a2, 0(a5)",  # VS store at SPA
            "  nop",
            "  lw   a3, 0(a5)",  # VS load
            "  nop",
        ]
    )
    lines.extend(emit_manual_sigupd("test1_vs", "a3"))  # Bare identity: dump before M return
    lines.extend(emit_goto_mmode())
    lines.extend(["  la t1, test_region", "  lw t2, 0(t1)"])  # SPA check from M
    lines.extend(emit_manual_sigupd("test2_spa", "t2"))
    _bump(test_data, 2)
    lines.extend(
        twin_data_section(
            paging,
            mismatch_strings=[
                emit_mismatch_string("test1_vs", "Mismatch on VS lw after sw (both Bare)"),
                emit_mismatch_string("test2_spa", "Mismatch on SPA readback (both Bare)"),
            ],
        )
    )
    return lines


def generate_stage_both_bare_VSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_stage_both_bare_VSmode-00.S`` (``cp_stage_both_bare``)."""
    return [
        comment_banner("stage_both_bare_VSmode", "VS access with vsatp=Bare and hgatp=Bare"),
        *emit_twin(test_data, _body_both_bare),
    ]


def _body_hgatp_bare(test_data: TestData, paging: Paging) -> list[str]:
    """Sv32 or Sv39 body: VS-stage on, G-stage Bare."""
    lines = emit_va_gpa_sets(paging)  # .set va_* / gpa_* (gpa unused for G maps)
    lines.extend(_emit_vs_only_maps(paging))  # VS maps with PA PPNs
    lines.extend(emit_spa_preload(0xDEADBEEF))
    lines.extend(emit_load_va_ptr())  # a5 = va_data
    lines.extend(emit_goto_vs())
    lines.extend(
        [
            "  LI(a2, 0x257A0005)",
            "  sw   a2, 0(a5)",  # VS-stage only (hgatp Bare)
            "  nop",
            "  lw   a3, 0(a5)",
            "  nop",
        ]
    )
    lines.extend(emit_goto_mmode())
    lines.extend(emit_manual_sigupd("test1_vs", "a3"))
    lines.extend(["  la t1, test_region", "  lw t2, 0(t1)"])  # SPA check
    lines.extend(emit_manual_sigupd("test2_spa", "t2"))
    lines.extend(
        [
            "  test3_hgatp:",  # CSR SIGUPD label
            "  RVTEST_SIGUPD_CSR_READ(hgatp, a4, test3_hgatp, test3_hgatp_str)",  # hgatp still Bare
        ]
    )
    _bump(test_data, 3)  # lw + SPA + hgatp
    lines.extend(
        twin_data_section(
            paging,
            mismatch_strings=[
                emit_mismatch_string("test1_vs", "Mismatch on VS lw (hgatp Bare)"),
                emit_mismatch_string("test2_spa", "Mismatch on SPA readback (hgatp Bare)"),
                emit_mismatch_string("test3_hgatp", "Mismatch on hgatp still Bare"),
            ],
        )
    )
    return lines


def generate_hgatp_bare_trans_VSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_hgatp_bare_trans_VSmode-00.S`` (VS translation, hgatp Bare)."""
    return [
        comment_banner("hgatp_bare_trans_VSmode", "VS paging with hgatp=Bare"),
        *emit_twin(test_data, _body_hgatp_bare),
    ]


def _body_g_walk(test_data: TestData, paging: Paging) -> list[str]:
    """Sv32 or Sv39 body: G-stage walk of VS page-table GPAs.

    Case 1: G leaf valid for the VS L0 table GPA; VS load succeeds.
    Case 2: that G leaf V=0; VS load takes a guest-page fault (sentinel 0).
    """
    _, g_mode = paging_modes(paging)  # sv32x4 / sv39x4 for G_PTE_SETUP
    lines = emit_standard_prologue(paging)  # two-stage maps including G leaf of VS L0 table
    lines.extend(emit_spa_preload(0x257A0041))  # pattern for the successful load
    lines.extend(emit_load_va_ptr())
    lines.extend(emit_goto_vs())
    lines.extend(["  lw   a3, 0(a5)", "  nop"])  # G allows walk of VS PT → load completes
    lines.extend(emit_goto_mmode())
    lines.extend(emit_manual_sigupd("test1_allow", "a3"))
    deny = pte_flags(x=False, w=True, r=True, u=True, v=False)  # G leaf V=0 on VS L0 table page
    lines.append(f"  G_PTE_SETUP({g_mode}, rvtest_vlvl0_pg_tbl, {deny}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)")
    lines.extend(emit_hfence_both())  # publish the V=0 G leaf
    lines.extend(["  LI(a4, 0)"])  # fault sentinel if the load does not complete
    lines.extend(emit_goto_vs())
    lines.extend(["  lw   a4, 0(a5)", "  nop"])  # guest-page fault; a4 stays 0
    lines.extend(emit_goto_mmode())
    lines.extend(emit_manual_sigupd("test2_deny", "a4"))
    _bump(test_data, 2)
    lines.extend(
        twin_data_section(
            paging,
            mismatch_strings=[
                emit_mismatch_string("test1_allow", "Mismatch on VS lw with G allowing VS-PT walk"),
                emit_mismatch_string("test2_deny", "Mismatch on VS lw with G denying VS-PT walk"),
            ],
        )
    )
    return lines


def generate_g_walk_vs_pt_VSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_g_walk_vs_pt_VSmode-00.S`` (G-stage walk of VS page tables)."""
    return [
        comment_banner("g_walk_vs_pt_VSmode", "G-stage maps vs PT GPAs; deny → guest-page fault"),
        *emit_twin(test_data, _body_g_walk),
    ]


def _body_mxr(test_data: TestData, paging: Paging, *, vu: bool) -> list[str]:
    """Sv32 or Sv39 body: execute-only data leaf with MXR=0 then MXR=1.

    ``vu=False``: VS-mode, VS leaf U=0.
    ``vu=True``: VU-mode, VS leaf U=1.
    G-stage data leaf is U=1 execute-only in both cases.
    """
    xonly_g = pte_flags(x=True, w=False, r=False, u=True, v=True)  # G X-only, U=1 (G walks as U)
    xonly_vs = pte_flags(x=True, w=False, r=False, u=vu, v=True)  # VS X-only; U=1 iff VU
    code_vs = pte_flags(x=True, w=False, r=True, u=vu, v=True)  # VS code; U=1 iff VU
    lines = emit_va_gpa_sets(paging)
    lines.extend(
        emit_two_stage_maps(
            paging,
            code_pte=code_vs,  # VS code leaf
            data_pte=xonly_vs,  # VS data is execute-only
            g_data_pte=xonly_g,  # G data is execute-only
            g_code_pte=PTE_CODE_G,  # G code stays R+X U=1
        )
    )
    lines.extend(emit_enable_paging(paging))
    lines.extend(emit_spa_preload(0x257A0101))  # pattern visible only if the load is allowed
    lines.extend(emit_load_va_ptr())
    lines.extend(
        [
            "  LI(t0, SSTATUS_MXR)",  # MXR bit mask
            "  csrc sstatus, t0",  # MXR=0 in sstatus
            "  csrc vsstatus, t0",  # MXR=0 in vsstatus
            "  LI(a3, 0)",  # fault sentinel
        ]
    )
    lines.extend(emit_goto_vu() if vu else emit_goto_vs())  # VU or VS
    lines.extend(["  lw   a3, 0(a5)", "  nop"])  # expect fault when MXR=0
    lines.extend(emit_goto_mmode())
    lines.extend(emit_manual_sigupd("test1_mxr0", "a3"))
    lines.extend(
        [
            "  LI(t0, SSTATUS_MXR)",
            "  csrs sstatus, t0",  # MXR=1: execute-only may be read
            "  csrs vsstatus, t0",
            "  LI(a4, 0)",  # sentinel if the second load still faults
        ]
    )
    lines.extend(emit_goto_vu() if vu else emit_goto_vs())
    lines.extend(["  lw   a4, 0(a5)", "  nop"])  # expect the preload pattern
    lines.extend(emit_goto_mmode())
    lines.extend(emit_manual_sigupd("test2_mxr1", "a4"))
    _bump(test_data, 2)
    who = "VU" if vu else "VS"  # mismatch text
    lines.extend(
        twin_data_section(
            paging,
            mismatch_strings=[
                emit_mismatch_string("test1_mxr0", f"Mismatch on {who} MXR=0 X-only load"),
                emit_mismatch_string("test2_mxr1", f"Mismatch on {who} MXR=1 X-only load"),
            ],
        )
    )
    return lines


def generate_two_stage_mxr_VSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_two_stage_mxr_VSmode-00.S`` (``cp_two_stage_mxr``, VS)."""

    def body(td: TestData, paging: Paging) -> list[str]:
        return _body_mxr(td, paging, vu=False)  # VS, U=0 VS leaves

    return [
        comment_banner("two_stage_mxr_VSmode", "VS MXR on X-only pages"),
        *emit_twin(test_data, body),
    ]


def generate_two_stage_mxr_VUmode(test_data: TestData) -> list[str]:
    """Output ``SvH_two_stage_mxr_VUmode-00.S`` (``cp_two_stage_mxr``, VU, U=1 leaves)."""

    def body(td: TestData, paging: Paging) -> list[str]:
        return _body_mxr(td, paging, vu=True)  # VU, U=1 VS leaves

    return [
        comment_banner("two_stage_mxr_VUmode", "VU MXR on U=1 X-only pages"),
        *emit_twin(test_data, body),
    ]


# SvH.py iterates this list. File order follows the list order.
ALL_GENERATORS = [
    generate_g_walk_vs_pt_VSmode,  # G leaf of VS PT page
    generate_hgatp_bare_trans_VSmode,  # VS on, G Bare
    generate_stage_both_bare_VSmode,  # both Bare
    generate_two_stage_ifetch_VSmode,  # VS ifetch both stages
    generate_two_stage_mxr_VSmode,  # MXR VS
    generate_two_stage_mxr_VUmode,  # MXR VU
    generate_two_stage_rw_VSmode,  # VS sw/lw both stages
]
