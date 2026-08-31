##################################
# priv/extensions/SvH_perm.py
#
# SvH permission-family emitters - true Python, no runtime seed I/O.
# SPDX-License-Identifier: Apache-2.0
##################################

"""VS-stage and G-stage permission stimulus for ``SvH_cg``.

Each ``generate_*`` is one output file. ``build_twins`` emits Sv32 and Sv39 under
ifdefs. Case tables in ``_asm_vs_perm`` / ``_asm_g_perm`` match directed-test
counts (not a full XWR cartesian product).

Helpers:
  ``_asm_load_case`` / ``_asm_store_case`` / ``_asm_store_load_case`` / ``_asm_jalr_case``
      enter guest, perform the access, return to M, SIGUPD.
  ``_vs_only_setup``     vsatp on, hgatp Bare.
  ``_g_only_setup`` vsatp Bare, hgatp on (identity code GPA).
"""

from __future__ import annotations  # postponed annotation eval

from dataclasses import dataclass  # immutable case record helper
from typing import Literal, cast  # guest mode + access cast

from testgen.asm.helpers import comment_banner, write_sigupd  # file banner + SIGUPD emit
from testgen.data.state import TestData  # testcase counter state
from testgen.priv.extensions.SvHCommon import (  # shared SvH paging/mode helpers
    ABI_TO_INT,  # GPR name → sig index
    CG,  # covergroup tag for add_testcase
    PTE_CODE_G,  # SvHCommon.PTE_CODE_G
    PTE_CODE_VS,  # SvHCommon.PTE_CODE_VS
    PTE_DATA_G,  # SvHCommon.PTE_DATA_G
    PTE_DATA_VS,  # SvHCommon.PTE_DATA_VS
    PTE_PT_G,  # SvHCommon.PTE_PT_G
    PTE_R_ONLY_S,  # SvHCommon.PTE_R_ONLY_S
    PTE_R_ONLY_U,  # SvHCommon.PTE_R_ONLY_U
    PTE_RW_U,  # SvHCommon.PTE_RW_U
    PTE_V_ONLY,  # SvHCommon.PTE_V_ONLY
    PTE_V_S,  # SvHCommon.PTE_V_S
    PTE_V_S_G,  # SvHCommon.PTE_V_S_G
    PTE_V_U,  # SvHCommon.PTE_V_U
    PTE_V_U_G,  # SvHCommon.PTE_V_U_G
    PTE_X_ONLY_S,  # SvHCommon.PTE_X_ONLY_S
    PTE_X_ONLY_U,  # SvHCommon.PTE_X_ONLY_U
    PTE_X_ONLY_U_G,  # SvHCommon.PTE_X_ONLY_U_G
    PTE_XR_S,  # SvHCommon.PTE_XR_S
    PTE_XR_U,  # SvHCommon.PTE_XR_U
    PTE_XWR_S,  # SvHCommon.PTE_XWR_S
    PTE_XWR_S_G,  # SvHCommon.PTE_XWR_S_G
    PTE_XWR_U,  # SvHCommon.PTE_XWR_U
    PTE_XWR_U_G,  # SvHCommon.PTE_XWR_U_G
    build_twins,  # Sv32+Sv39 twin wrapper
    data_section,  # .data pages/tables
    enable_two_stage,  # turn on vsatp+hgatp
    enable_vs_only,  # vsatp on, hgatp Bare
    fence_both_stages,  # TLB shootdown both stages
    GOTO_HS,  # relocated hop M→HS (GOTO)
    GOTO_MMODE,  # return trap path to M
    GOTO_VS,  # relocated hop M→VS
    GOTO_VU,  # relocated hop M→VU
    load_guest_va,  # load guest VA into a5
    mode_names,  # vsatp/hgatp MODE strings
    preload_spa,  # M-mode store pattern into SPA
    set_g_data_leaf,  # rewrite G-stage data PTE
    set_vs_data_leaf,  # rewrite VS-stage data PTE
    twin_data,  # .data section for twin
)  # end SvHCommon import list

Paging = Literal["sv32", "sv39"]  # type alias for emitter APIs
Guest = Literal["VS", "VU", "HS"]  # type alias for emitter APIs
Access = Literal["lw", "sw", "jalr", "swlw", "hlv", "hsvhlv"]  # type alias for emitter APIs


@dataclass(frozen=True)  # immutable per-case metadata
class SigCase:  # testcase banner + SIGUPD register
    """One numbered permission case: banner metadata + which GPR to dump."""

    num: str  # SigCase.num
    title: str  # SigCase.title
    label: str  # SigCase.label
    check_reg: str  # SigCase.check_reg
    coverpoint: str  # SigCase.coverpoint
    expected: str = "Expected Fault"  # SigCase.expected


def _case_banner(case: SigCase) -> list[str]:  # per-case // header lines
    """Emit the per-case header: number, title, expected result, coverpoint ids."""
    return [
        "//" + "-" * 128,  # top rule
        f"// Test case {case.num}: {case.title} | Expected: {case.expected}",  # title line
        f"// Coverpoints: {case.coverpoint}",  # coverpoint id line
        "//" + "-" * 128,  # bottom rule
    ]


def _sig(test_data: TestData, case: SigCase) -> list[str]:  # ExceptionsSm-style SIGUPD pair
    """ACT4 testcase record + GPR SIGUPD (same pattern as ExceptionsSm)."""
    return [
        test_data.add_testcase(case.label, case.coverpoint, CG),  # record testcase label/coverpoint
        write_sigupd(ABI_TO_INT[case.check_reg], test_data),  # dump check_reg to signature
    ]


def _write_mxr_sum(mxr: int, sum_: int) -> list[str]:  # program MXR/SUM on sstatus+vsstatus
    """Set vsstatus/sstatus MXR and SUM to the requested combination.

    When both bits are 1, OR them in with a single csrs (seed case 24 style) so we
    do not clear SUM between related cases. Otherwise clear both then set the ones
    that should be 1.
    """
    if mxr and sum_:
        return [
            "  LI(t0, SSTATUS_MXR | SSTATUS_SUM)",  # both bit masks
            "  csrs sstatus, t0",  # set in sstatus
            "  csrs vsstatus, t0",  # set in vsstatus (guest view)
            "  hfence.vvma",  # publish status-bit effect on TLB/perms
        ]
    lines = ["  LI(t0, SSTATUS_MXR | SSTATUS_SUM)", "  csrc sstatus, t0", "  csrc vsstatus, t0"]
    if mxr:
        lines.extend(["  LI(t0, SSTATUS_MXR)", "  csrs sstatus, t0", "  csrs vsstatus, t0"])  # set MXR only
    if sum_:
        lines.extend(["  LI(t0, SSTATUS_SUM)", "  csrs sstatus, t0", "  csrs vsstatus, t0"])  # set SUM only
    lines.append("  hfence.vvma")  # publish
    return lines


def _enter_guest(mode: Guest, *, relocated: bool) -> list[str]:  # GOTO_* if relocated else TSBI identity
    """Enter VS, VU, or HS. ``relocated=True`` uses GOTO_LOWER_MODE (VA != PA)."""
    if relocated:  # VA!=PA: use GOTO_* trap hops
        if mode == "VU":
            return GOTO_VU  # GOTO_VU relocated hop
        if mode == "VS":
            return GOTO_VS  # GOTO_VS relocated hop
        return GOTO_HS  # GOTO_HS relocated hop
    # identity GPA: TSBI keeps PA==VA (not GOTO_*)
    if mode == "VU":
        return ["  RVTEST_TSBI_GOTO_VUMODE"]  # TSBI VU (identity map)
    if mode == "VS":
        return ["  RVTEST_TSBI_GOTO_VSMODE"]  # TSBI VS (identity map)
    return ["  RVTEST_TSBI_GOTO_SMODE"]  # TSBI HS (identity map)


def _leave_guest() -> list[str]:  # GOTO_MMODE before signature
    """Return to M-mode before SIGUPD."""
    return GOTO_MMODE  # trap return to M-mode


def _map_vs_code(paging: Paging, *, code_u: bool) -> list[str]:  # VS code superpage + save area
    """VS-stage code superpage plus ``V_SAVE_AREA_SETUP``. ``code_u`` sets PTE_U."""
    vs_mode, _ = mode_names(paging)  # local setup variable
    code_flags = PTE_XR_U if code_u else PTE_CODE_VS  # local setup variable
    if paging == "sv39":
        return [
            f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_code, LEVEL2)",  # paging macro emission
            f"  SUPERPAGE_VS_PTE_SETUP({vs_mode}, rvtest_code_begin, {code_flags}, va_code, LEVEL1)",  # paging macro emission
            "  csrr a0, mscratch",  # a0 = trap save-area base
            "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate save area
        ]
    return [
        f"  SUPERPAGE_VS_PTE_SETUP({vs_mode}, rvtest_code_begin, {code_flags}, va_code, LEVEL1)",  # paging macro emission
        "  csrr a0, mscratch",  # a0 = save-area base
        "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate save area
    ]


def _vs_leaf_map(paging: Paging, *, va: str, pa: str, flags: str) -> list[str]:  # VS data walk to va→pa leaf
    """VS-stage data walk to ``va`` with leaf PPN ``pa`` (PA, hgatp Bare)."""
    vs_mode, _ = mode_names(paging)  # local setup variable
    if paging == "sv39":
        return [
            f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL2)",  # paging macro emission
            f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL1)",  # paging macro emission
            f"  VS_PTE_SETUP({vs_mode}, PA, {pa}, {flags}, {va}, LEVEL0)",  # paging macro emission
        ]
    return [
        f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL1)",  # paging macro emission
        f"  VS_PTE_SETUP({vs_mode}, PA, {pa}, {flags}, {va}, LEVEL0)",  # paging macro emission
    ]


def _g_only_setup(paging: Paging, *, g_flags: str = PTE_DATA_G) -> list[str]:  # vsatp Bare + hgatp ON maps
    """vsatp Bare + hgatp ON: code GPA must identity-map PA (~0x80000000) for TSBI hops."""
    _, g_mode = mode_names(paging)  # expression/ call
    gpa_data = "0x0000000000C002000" if paging == "sv39" else "0x00C002000"  # data GPA constant
    lines = [  # asm output buffer
        "  .set gpa_code, 0x80000000",  # code GPA symbol
        f"  .set gpa_data, {gpa_data}",  # data GPA symbol
        "  csrw vsatp, x0",  # Bare vsatp (G-only)
    ]
    if paging == "sv39":
        lines.extend(  # extend with following list
            [  # list begin
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_code, LEVEL2)",  # paging macro emission
                f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {PTE_CODE_G}, gpa_code, LEVEL2)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL2)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)",  # paging macro emission
            ]
        )  # end SvHCommon import list
    else:
        lines.extend(  # extend with following list
            [  # list begin
                f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {PTE_CODE_G}, gpa_code, LEVEL1)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)",  # paging macro emission
            ]
        )  # end SvHCommon import list
    lines.extend([f"  G_PTE_SETUP({g_mode}, test_region, {g_flags}, gpa_data, LEVEL0)", f"  HGATP_SETUP({g_mode})"])  # splice more asm into output
    lines.extend(fence_both_stages())  # splice more asm into output
    return lines


def _vs_only_setup(paging: Paging, *, code_u: bool, data_flags: str) -> list[str]:  # vsatp ON + hgatp Bare maps
    """VS-stage on, hgatp Bare: code map, data leaf, enable vsatp."""
    vs_mode, _ = mode_names(paging)  # local setup variable
    va_data = "0x0000000080010000" if paging == "sv39" else "0x08001000"  # data VA constant
    return [
        "  .set va_code, 0x90000000",  # code VA symbol
        f"  .set va_data, {va_data}",  # data VA symbol
        *_map_vs_code(paging, code_u=code_u),  # unpack/splice helper output
        *_vs_leaf_map(paging, va="va_data", pa="test_region", flags=data_flags),  # unpack/splice helper output
        *enable_vs_only(vs_mode),  # unpack/splice helper output
    ]


def _asm_load_case(
    test_data: TestData,  # test counters / chunk
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    va: str,
    check_reg: str,  # GPR dumped by SIGUPD
    relocated: bool = True,  # use VA!=PA hops
) -> list[str]:
    return [
        *_case_banner(case),  # unpack/splice helper output
        *load_guest_va("a5", va),
        f"  LI({check_reg}, 0)",  # load immediate
        *_enter_guest(mode, relocated=relocated),
        f"  lw {check_reg}, 0(a5)",  # load word
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        *_sig(test_data, case),  # SIGUPD
        "",  # asm/data line in output list
    ]


def _asm_store_case(
    test_data: TestData,  # test counters / chunk
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    va: str,
    spa: str,
    check_reg: str,  # GPR dumped by SIGUPD
    payload: int = 0xBAD00FAD,
    relocated: bool = True,  # use VA!=PA hops
) -> list[str]:
    return [
        *_case_banner(case),  # unpack/splice helper output
        *load_guest_va("a5", va),
        f"  LI(t0, {hex(payload)})",  # load immediate
        *_enter_guest(mode, relocated=relocated),
        "  sw t0, 0(a5)",  # store at guest VA
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        f"  la t1, {spa}",
        f"  lw {check_reg}, 0(t1)",  # load word
        *_sig(test_data, case),  # SIGUPD
        "",  # asm/data line in output list
    ]


def _asm_store_load_case(
    test_data: TestData,  # test counters / chunk
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    va: str,
    check_reg: str,  # GPR dumped by SIGUPD
    payload: int,  # store/preload pattern
    relocated: bool = True,  # use VA!=PA hops
) -> list[str]:
    return [
        *_case_banner(case),  # unpack/splice helper output
        *load_guest_va("a5", va),
        f"  LI(t0, {hex(payload)})",  # load immediate
        *_enter_guest(mode, relocated=relocated),
        "  sw t0, 0(a5)",  # store at guest VA
        "  nop",  # delay slot / pad
        f"  lw {check_reg}, 0(a5)",  # load word
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        *_sig(test_data, case),  # SIGUPD
        "",  # asm/data line in output list
    ]


def _asm_jalr_case(
    test_data: TestData,  # test counters / chunk
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    va: str,
    check_reg: str,  # GPR dumped by SIGUPD
    marker: int,  # success marker immediate
    relocated: bool = True,  # use VA!=PA hops
) -> list[str]:
    return [
        *_case_banner(case),  # unpack/splice helper output
        *load_guest_va("a5", va),
        f"  LI({check_reg}, 0)",  # load immediate
        *_enter_guest(mode, relocated=relocated),
        "  nop",  # delay slot / pad
        "  jalr ra, a5, 0",  # ifetch via jalr
        f"  LI({check_reg}, {hex(marker)})",  # load immediate
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        *_sig(test_data, case),  # SIGUPD
        "",  # asm/data line in output list
    ]


def _jalr_fault_case(
    test_data: TestData,  # test counters / chunk
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    va: str,
    check_reg: str,  # GPR dumped by SIGUPD
    relocated: bool = True,  # use VA!=PA hops
) -> list[str]:
    return [
        *_case_banner(case),  # unpack/splice helper output
        *load_guest_va("a5", va),
        f"  LI({check_reg}, 0)",  # load immediate
        *_enter_guest(mode, relocated=relocated),
        "  nop",  # delay slot / pad
        "  jalr ra, a5, 0",  # ifetch via jalr
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        *_sig(test_data, case),  # SIGUPD
        "",  # asm/data line in output list
    ]


def _regions(names: list[str], *, xonly_exec: bool = False) -> list[str]:  # extra aligned data pages
    lines: list[str] = []  # asm output buffer
    for name in names:  # iterate cases/specs
        lines.extend([".p2align 12", f"{name}:", "  .word 0", "  .word 0", "  .word 0", "  .word 0"])  # splice more asm into output
    if xonly_exec:
        lines.extend(  # extend with following list
            [  # list begin
                ".p2align 12",  # 4KiB align
                "xonly_exec_page:",  # label
                "  LI(a3, 0x257A040E)",  # load immediate
                "  jalr x0, ra, 0",  # return from xonly exec stub
                "  nop",  # delay slot / pad
                "  nop",  # delay slot / pad
            ]
        )  # end SvHCommon import list
    return lines


def _data(paging: Paging, *, regions: list[str] | None = None, xonly_exec: bool = False) -> list[str]:  # twin or custom data_section
    if regions is None:
        return twin_data(paging)
    return data_section(
        need_test_region=False,  # include test_region?
        need_hlvl0=False,
        need_vlvl0=True,
        need_hlvl1=False,
        need_vlvl1=paging == "sv39",
        extra_regions=_regions(regions, xonly_exec=xonly_exec),  # extra named regions
    )  # end SvHCommon import list


def _asm_vs_seed_case(
    test_data: TestData,  # test counters / chunk
    paging: Paging,  # Sv32 or Sv39
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    flags: str,
    access: Access,  # lw / sw / jalr / …
    mxr: int = 0,  # MXR bit (0/1)
    sum_: int = 0,  # SUM bit (0/1)
    payload: int = 0x257A0400,  # signature pattern
    exec_page: bool = False,  # map xonly exec page
    va: str = "va_data",
    pa: str | None = None,
) -> list[str]:
    if pa is None:
        pa = "xonly_exec_page" if exec_page else "test_region"  # physical page name
    lines = [*_write_mxr_sum(mxr, sum_), *set_vs_data_leaf(paging, flags, ppn_kind="PA", ppn=pa, va=va)]
    lines.extend(fence_both_stages())  # splice more asm into output
    lines.extend(preload_spa(test_data, 0x00008067 if access == "jalr" else payload, dest=pa))  # splice more asm into output
    if access == "lw":
        lines.extend(_asm_load_case(test_data, case=case, mode=mode, va=va, check_reg=case.check_reg))  # splice more asm into output
    elif access == "sw":
        lines.extend(_asm_store_case(test_data, case=case, mode=mode, va=va, spa=pa, check_reg=case.check_reg))  # splice more asm into output
    elif access == "swlw":
        lines.extend(_asm_store_load_case(test_data, case=case, mode=mode, va=va, check_reg=case.check_reg, payload=payload))  # splice more asm into output
    else:
        if case.expected == "Successful":
            lines.extend(_asm_jalr_case(test_data, case=case, mode=mode, va=va, check_reg=case.check_reg, marker=payload))  # splice more asm into output
        else:
            lines.extend(_jalr_fault_case(test_data, case=case, mode=mode, va=va, check_reg=case.check_reg))  # splice more asm into output
    return lines


def _asm_g_seed_case(
    test_data: TestData,  # test counters / chunk
    paging: Paging,  # Sv32 or Sv39
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    flags: str,
    access: Access,  # lw / sw / jalr / …
    payload: int,  # store/preload pattern
) -> list[str]:
    lines = [*set_g_data_leaf(paging, flags), "  hfence.gvma"]
    lines.extend(preload_spa(test_data, payload))  # splice more asm into output
    if access == "lw":
        lines.extend(_asm_load_case(test_data, case=case, mode=mode, va="gpa_data", check_reg=case.check_reg, relocated=False))  # splice more asm into output
    elif access == "sw":
        lines.extend(_asm_store_case(test_data, case=case, mode=mode, va="gpa_data", spa="test_region", check_reg=case.check_reg, relocated=False))  # splice more asm into output
    else:
        lines.extend(_asm_store_load_case(test_data, case=case, mode=mode, va="gpa_data", check_reg=case.check_reg, payload=payload, relocated=False))  # splice more asm into output
    return lines


def _asm_g_perm(test_data: TestData, paging: Paging, *, mode: Guest) -> list[str]:  # G-stage perm matrix for VS/VU
    lines = [*_g_only_setup(paging, g_flags=PTE_XWR_U_G)]
    if mode == "VS":
        specs = [  # packed case table
            ("1", "G leaf U=1 XWR=111+G VS sw/lw", "test1_u1_rwx", "a3", "Mismatch on VS sw/lw with G U=1 XWR=111+G in Test Case 1!", PTE_XWR_U_G, "swlw", "Successful"),  # case 1: G U=1 RWX+G sw+lw expect ok
            ("2", "G leaf U=0 XWR=111+G VS lw", "test2_u0_lw", "a4", "Mismatch on VS lw with G U=0 XWR=111 (expect fault) in Test Case 2!", PTE_XWR_S_G, "lw", "Expected Fault"),  # case 2: G U=0 RWX+G lw expect fault
            ("3", "G leaf U=0 XWR=111+G VS sw", "test3_u0_sw", "s2", "Mismatch on VS sw with G U=0 XWR=111 (expect SPA unchanged) in Test Case 3!", PTE_XWR_S_G, "sw", "Expected Fault"),  # case 3: G U=0 RWX+G sw expect fault
            ("4", "G leaf U=1 X-only", "test4_xonly", "a6", "Mismatch on VS lw with G X-only (expect fault) in Test Case 4!", PTE_X_ONLY_U_G, "lw", "Expected Fault"),  # case 4: G U=1 X-only+G lw expect fault
            ("5", "G leaf U=1 V-only (XWR=000)", "test5_vonly_u1", "s3", "Mismatch on VS lw with G U=1 V-only (expect fault) in Test Case 5!", PTE_V_U_G, "lw", "Expected Fault"),  # case 5: G U=1 V-only+G lw expect fault
            ("6", "Restore U=1 XWR=111+G VS lw", "test6_restore", "a7", "Mismatch on VS lw after G perm restore in Test Case 6!", PTE_XWR_U_G, "lw", "Successful"),  # case 6: G U=1 RWX+G lw expect ok
            ("9", "G leaf U=1 V-only VS sw", "test9_vonly_u1_sw", "s6", "Mismatch on VS sw with G U=1 V-only (expect SPA unchanged) in Test Case 9!", PTE_V_U_G, "sw", "Expected Fault"),  # case 9: G U=1 V-only+G sw expect fault
            ("10", "G leaf U=0 V-only VS sw", "test10_vonly_u0_sw", "s7", "Mismatch on VS sw with G U=0 V-only (expect SPA unchanged) in Test Case 10!", PTE_V_S_G, "sw", "Expected Fault"),  # case 10: G U=0 V-only+G sw expect fault
        ]
    else:
        specs = [  # packed case table
            ("1", "G leaf U=1 XWR=111+G VU sw/lw", "test1_u1_rwx", "a3", "Mismatch on VU sw/lw with G U=1 XWR=111+G in Test Case 1!", PTE_XWR_U_G, "swlw", "Successful"),  # case 1: G U=1 RWX+G sw+lw expect ok
            ("2", "G leaf U=0 XWR=111+G VU lw", "test2_u0_lw", "a4", "Mismatch on VU lw with G U=0 XWR=111 (expect fault) in Test Case 2!", PTE_XWR_S_G, "lw", "Expected Fault"),  # case 2: G U=0 RWX+G lw expect fault
            ("3", "G leaf U=0 XWR=111+G VU sw", "test3_u0_sw", "s2", "Mismatch on VU sw with G U=0 XWR=111 (expect SPA unchanged) in Test Case 3!", PTE_XWR_S_G, "sw", "Expected Fault"),  # case 3: G U=0 RWX+G sw expect fault
            ("4", "G leaf U=1 X-only", "test4_xonly", "a6", "Mismatch on VU lw with G X-only (expect fault) in Test Case 4!", PTE_X_ONLY_U_G, "lw", "Expected Fault"),  # case 4: G U=1 X-only+G lw expect fault
            ("5", "G leaf U=1 V-only", "test5_vonly_u1", "s3", "Mismatch on VU lw with G U=1 V-only (expect fault) in Test Case 5!", PTE_V_U_G, "lw", "Expected Fault"),  # case 5: G U=1 V-only+G lw expect fault
            ("6", "Restore U=1 XWR=111+G VU lw", "test6_restore", "a7", "Mismatch on VU lw after G perm restore in Test Case 6!", PTE_XWR_U_G, "lw", "Successful"),  # case 6: G U=1 RWX+G lw expect ok
            ("7", "G leaf U=1 V-only VU sw", "test7_vonly_u1_sw", "s6", "Mismatch on VU sw with G U=1 V-only (expect SPA unchanged) in Test Case 7!", PTE_V_U_G, "sw", "Expected Fault"),  # case 7: G U=1 V-only+G sw expect fault
            ("8", "G leaf U=0 V-only VU sw", "test8_vonly_u0_sw", "s7", "Mismatch on VU sw with G U=0 V-only (expect SPA unchanged) in Test Case 8!", PTE_V_S_G, "sw", "Expected Fault"),  # case 8: G U=0 V-only+G sw expect fault
            ("9", "G leaf U=0 V-only VU lw", "test9_vonly_u0_lw", "s4", "Mismatch on VU lw with G U=0 V-only (expect fault) in Test Case 9!", PTE_V_S_G, "lw", "Expected Fault"),  # case 9: G U=0 V-only+G lw expect fault
        ]
    cases = [  # SigCase list
        SigCase(num, title, label, reg, "cp_hgatp_perm_checks_rw", expected)  # SigCase record
        for num, title, label, reg, _msg, _flags, _access, expected in specs  # unpack case fields
    ]
    def emit_g_specs(selected_specs: list[tuple[str, str, str, str, str, str, str, str]]) -> None:  # loop G perm spec tuples
        selected_cases = [  # subset SigCases
            SigCase(num, title, label, reg, "cp_hgatp_perm_checks_rw", expected)  # SigCase record
            for num, title, label, reg, _msg, _flags, _access, expected in selected_specs  # unpack case fields
        ]
        for spec, case in zip(selected_specs, selected_cases):  # iterate cases/specs
            payload = 0x257A0200 + int(case.num) if mode == "VS" else 0x257A0300 + int(case.num)  # unique data pattern
            lines.extend(_asm_g_seed_case(test_data, paging, case=case, mode=mode, flags=spec[5], access=cast(Access, spec[6]), payload=payload))  # splice more asm into output

    if mode == "VS":
        emit_g_specs(specs[:6])  # expression/ call
        hs_cases = [  # HS HLV/HSV cases
            SigCase("7", "HS HLV of G leaf with G=1 XWR=111", "test7_hlv_g", "s4", "cp_hgatp_pte_g_bit_rw", "Successful"),  # case 7: HS HLV of G leaf with G=1 XWR=111
            SigCase("8", "HS HSV of G leaf with G=1 XWR=111", "test8_hsv_g", "s5", "cp_hgatp_pte_g_bit_rw", "Successful"),  # case 8: HS HSV of G leaf with G=1 XWR=111
        ]
        lines.extend(  # extend with following list
            [  # list begin
                *set_g_data_leaf(paging, PTE_XWR_U_G),  # unpack/splice helper output
                "  hfence.gvma",  # fence G-stage TLB after hgatp/PTE change
                *_case_banner(hs_cases[0]),  # unpack/splice helper output
                "  LI(t1, gpa_data)",  # pointer for access
                "  LI(s4, 0)",  # load immediate constant
                *_enter_guest("HS", relocated=False),
                "  hlv.w s4, (t1)",  # asm/data line in output list
                "  nop",  # delay slot / pad
                *_leave_guest(),  # leave to M
                *_sig(test_data, hs_cases[0]),  # SIGUPD
                *_case_banner(hs_cases[1]),  # unpack/splice helper output
                "  LI(t1, gpa_data)",  # pointer for access
                "  LI(t0, 0x257A0208)",  # load immediate
                *_enter_guest("HS", relocated=False),
                "  hsv.w t0, (t1)",  # asm/data line in output list
                "  nop",  # delay slot / pad
                "  hfence.gvma",  # fence G-stage TLB after hgatp/PTE change
                "  LI(s5, 0)",  # load immediate constant
                "  hlv.w s5, (t1)",  # asm/data line in output list
                "  nop",  # delay slot / pad
                *_leave_guest(),  # leave to M
                *_sig(test_data, hs_cases[1]),  # SIGUPD
            ]
        )  # end SvHCommon import list
        cases[6:6] = hs_cases  # splice HS cases at index 6
        emit_g_specs(specs[6:])  # expression/ call
    else:
        emit_g_specs(specs)  # expression/ call
    lines.extend(twin_data(paging))  # splice more asm into output
    return lines


def generate_g_perm_VSmode(test_data: TestData) -> list[str]:  # emitter helper generate_g_perm_VSmode
    """Output ``SvH_g_perm_VSmode-00.S``: G-stage permission checks from VS, plus HS HLV/HSV."""
    return [comment_banner("g_perm_VSmode", "SvH G-stage permission stimulus"), *build_twins(test_data, lambda td, p: _asm_g_perm(td, p, mode="VS"))]  # file header + twin body


def generate_g_perm_VUmode(test_data: TestData) -> list[str]:  # emitter helper generate_g_perm_VUmode
    """Output ``SvH_g_perm_VUmode-00.S``: G-stage permission checks from VU."""
    return [comment_banner("g_perm_VUmode", "SvH G-stage permission stimulus"), *build_twins(test_data, lambda td, p: _asm_g_perm(td, p, mode="VU"))]  # file header + twin body


def _asm_g_u_bit(test_data: TestData, paging: Paging) -> list[str]:  # G U-bit HLV/HSV from HS
    cases = [  # SigCase list
        SigCase("1", "G leaf U=1 XWR=111 HS HLV", "test1_u1_hlv", "a3", "cp_hgatp_u_mode_access_rw", "Successful"),  # SigCase metadata for SIGUPD
        SigCase("2", "G leaf U=1 XWR=111 HS HSV+HLV", "test2_u1_hsv", "a6", "cp_hgatp_u_mode_access_rw", "Successful"),  # SigCase metadata for SIGUPD
        SigCase("3", "G leaf U=0 XWR=111 HS HLV", "test3_u0_hlv", "a4", "cp_hgatp_u_mode_access_rw"),  # SigCase metadata for SIGUPD
        SigCase("4", "G leaf U=0 XWR=111 HS HSV", "test4_u0_hsv", "s3", "cp_hgatp_u_mode_access_rw"),  # SigCase metadata for SIGUPD
        SigCase("5", "Restore G leaf U=1 XWR=111 HS HLV", "test5_restore", "a7", "cp_hgatp_u_mode_access_rw", "Successful"),  # SigCase metadata for SIGUPD
    ]
    good = PTE_XWR_U  # PTE/recipe shorthand
    bad = PTE_XWR_S  # PTE/recipe shorthand
    return [
        *_g_only_setup(paging, g_flags=good),  # G-only paging setup
        *preload_spa(test_data, 0x257A0231),  # unpack/splice helper output
        "  LI(t1, gpa_data)",  # pointer for access
        *_enter_guest("HS", relocated=False),
        *_case_banner(cases[0]),  # unpack/splice helper output
        "  hfence.gvma",  # fence G-stage TLB after hgatp/PTE change
        "  LI(a3, 0)",  # load immediate constant
        "  hlv.w a3, (t1)",  # asm/data line in output list
        "  nop",  # delay slot / pad
        *_sig(test_data, cases[0]),  # SIGUPD
        *_case_banner(cases[1]),  # unpack/splice helper output
        "  hfence.gvma",  # fence G-stage TLB after hgatp/PTE change
        "  LI(t0, 0x257A0232)",  # load immediate
        "  hsv.w t0, (t1)",  # asm/data line in output list
        "  nop",  # delay slot / pad
        "  hfence.gvma",  # fence G-stage TLB after hgatp/PTE change
        "  LI(a6, 0)",  # load immediate constant
        "  hlv.w a6, (t1)",  # asm/data line in output list
        "  nop",  # delay slot / pad
        *_sig(test_data, cases[1]),  # SIGUPD
        *_leave_guest(),  # leave to M
        *set_g_data_leaf(paging, bad),  # unpack/splice helper output
        "  hfence.gvma",  # fence G-stage TLB after hgatp/PTE change
        *_enter_guest("HS", relocated=False),
        *_case_banner(cases[2]),  # unpack/splice helper output
        "  LI(a4, 0)",  # load immediate constant
        "  LI(t1, gpa_data)",  # pointer for access
        "  hlv.w a4, (t1)",  # asm/data line in output list
        "  nop",  # delay slot / pad
        *_sig(test_data, cases[2]),  # SIGUPD
        *_case_banner(cases[3]),  # unpack/splice helper output
        "  hfence.gvma",  # fence G-stage TLB after hgatp/PTE change
        "  LI(s3, 0)",  # load immediate constant
        "  LI(t0, 0xDEADBEEF)",  # load immediate
        "  hsv.w t0, (t1)",  # asm/data line in output list
        "  nop",  # delay slot / pad
        *_sig(test_data, cases[3]),  # SIGUPD
        *_leave_guest(),  # leave to M
        *set_g_data_leaf(paging, good),  # unpack/splice helper output
        "  hfence.gvma",  # fence G-stage TLB after hgatp/PTE change
        *_enter_guest("HS", relocated=False),
        *_case_banner(cases[4]),  # unpack/splice helper output
        "  LI(a7, 0)",  # load immediate constant
        "  LI(t1, gpa_data)",  # pointer for access
        "  hlv.w a7, (t1)",  # asm/data line in output list
        "  nop",  # delay slot / pad
        *_sig(test_data, cases[4]),  # SIGUPD
        *_leave_guest(),  # leave to M
        *twin_data(paging),  # unpack/splice helper output
    ]


def generate_g_u_bit_HSmode(test_data: TestData) -> list[str]:  # emitter helper generate_g_u_bit_HSmode
    """Output ``SvH_g_u_bit_HSmode-00.S``: G-stage U=0/U=1 HLV/HSV from HS (``cp_hgatp_u_mode_access_rw``)."""
    return [comment_banner("g_u_bit_HSmode", "SvH G-stage U-bit stimulus"), *build_twins(test_data, _asm_g_u_bit)]  # file header + twin body


def _asm_sum_upages(test_data: TestData, paging: Paging) -> list[str]:  # SUM=0 fault then SUM=1 on U-page
    cases = [  # SigCase list
        SigCase("1", "SUM=0 VS lw/sw of U=1 page", "test1_sum0_lw", "a3", "cp_vsatp_sum_effects_rw"),  # case 1: SUM=0 VS lw/sw of U=1 page
        SigCase("2", "SUM=0 SPA unchanged", "test2_sum0_spa", "t2", "cp_vsatp_sum_effects_rw", "Successful"),  # case 2: SUM=0 SPA unchanged
        SigCase("3", "SUM=1 VS store then load U=1 page", "test3_sum1_lw", "a7", "cp_vsatp_sum_effects_rw", "Successful"),  # case 3: SUM=1 VS store then load U=1 page
        SigCase("4", "SUM=1 SPA readback", "test4_sum1_spa", "t3", "cp_vsatp_sum_effects_rw", "Successful"),  # case 4: SUM=1 SPA readback
    ]
    lines = [  # asm output buffer
        *_vs_only_setup(paging, code_u=False, data_flags=PTE_XWR_U),  # unpack/splice helper output
        *preload_spa(test_data, 0xDEADBEEF),  # unpack/splice helper output
        *load_guest_va("a5", "va_data"),
        *_write_mxr_sum(0, 0),  # set MXR/SUM
        *_case_banner(cases[0]),  # unpack/splice helper output
        "  LI(a3, 0)",  # load immediate constant
        "  LI(a4, 0)",  # load immediate constant
        *_enter_guest("VS", relocated=True),
        "  lw a3, 0(a5)",  # load word
        "  nop",  # delay slot / pad
        "  sw a4, 0(a5)",  # store zero at guest VA (expect fault)
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        *_sig(test_data, cases[0]),  # SIGUPD
        *_case_banner(cases[1]),  # unpack/splice helper output
        "  la t1, test_region",  # SPA address of label
        "  lw t2, 0(t1)",  # load word
        *_sig(test_data, cases[1]),  # SIGUPD
        *_write_mxr_sum(0, 1),  # set MXR/SUM
        *_case_banner(cases[2]),  # unpack/splice helper output
        "  LI(a6, 0x257A0201)",  # load immediate
        *_enter_guest("VS", relocated=True),
        "  sw a6, 0(a5)",  # store pattern at guest VA
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        "  hfence.vvma",  # fence VS-stage TLB after vsatp/PTE change
        "  LI(a7, 0)",  # load immediate constant
        *_enter_guest("VS", relocated=True),
        "  lw a7, 0(a5)",  # load word
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        *_sig(test_data, cases[2]),  # SIGUPD
        *_case_banner(cases[3]),  # unpack/splice helper output
        "  la t1, test_region",  # SPA address of label
        "  lw t3, 0(t1)",  # load word
        *_sig(test_data, cases[3]),  # SIGUPD
        *twin_data(paging),  # unpack/splice helper output
    ]
    return lines


def generate_sum_Upages_VSmode(test_data: TestData) -> list[str]:  # emitter helper generate_sum_Upages_VSmode
    """Output ``SvH_sum_Upages_VSmode-00.S``: VS SUM=0 fault then SUM=1 success on U=1 pages."""
    return [comment_banner("sum_Upages_VSmode", "SvH VS SUM U-page stimulus"), *build_twins(test_data, _asm_sum_upages)]  # file header + twin body


def _asm_vs_perm(test_data: TestData, paging: Paging, *, mode: Guest) -> list[str]:  # VS-stage XWR/U/SUM matrix
    code_u = mode == "VU"  # U=1 on code if VU
    lines = [  # asm output buffer
        *_vs_only_setup(paging, code_u=code_u, data_flags=PTE_XWR_U if code_u else PTE_XWR_S),  # unpack/splice helper output
        *_write_mxr_sum(0, 0),  # set MXR/SUM
    ]
    if mode == "VS":
        cp = "cp_vsatp_spages_sum_rw cp_vsatp_perm_checks_rw"  # local setup variable
        specs = [  # packed case table
            ("1", "S-page XWR=111 VS sw+lw", "test1_rwx", "a3", "Mismatch on S-page R/W/X VS lw in Test Case 1!", PTE_XWR_S, "swlw", 0, 0, "Successful"),  # case 1: VS U=0 RWX MXR=0 SUM=0 sw+lw
            ("2", "S-page X-only VS lw", "test2_xonly_lw", "a4", "Mismatch on S-page X-only VS lw (expect fault) in Test Case 2!", PTE_X_ONLY_S, "lw", 0, 0, "Expected Fault"),  # case 2: VS U=0 X-only MXR=0 SUM=0 lw
            ("3", "S-page X-only VS sw", "test3_xonly_sw", "a3", "Mismatch on S-page X-only VS sw (expect fault) in Test Case 3!", PTE_X_ONLY_S, "sw", 0, 0, "Expected Fault"),  # case 3: VS U=0 X-only MXR=0 SUM=0 sw
            ("4", "S-page R-only VS lw", "test4_ronly", "a3", "Mismatch on S-page R-only VS lw in Test Case 4!", PTE_R_ONLY_S, "lw", 0, 0, "Successful"),  # case 4: VS U=0 R-only MXR=0 SUM=0 lw
            ("4b", "S-page R-only VS sw", "test4b_ronly_sw", "a4", "Mismatch on S-page R-only VS sw (expect fault) in Test Case 4b!", PTE_R_ONLY_S, "sw", 0, 0, "Expected Fault"),  # case 4b: VS U=0 R-only MXR=0 SUM=0 sw
            ("5", "S-page R/W (XWR=110) VS sw+lw", "test5_rw", "a3", "Mismatch on S-page R/W VS lw in Test Case 5!", PTE_DATA_VS, "swlw", 0, 0, "Successful"),  # case 5: VS U=0 R/W MXR=0 SUM=0 sw+lw
            ("6", "S-page R/X VS lw", "test6_rx", "a3", "Mismatch on S-page R/X VS lw in Test Case 6!", PTE_XR_S, "lw", 0, 0, "Successful"),  # case 6: VS U=0 R/X MXR=0 SUM=0 lw
            ("6b", "S-page R/X VS sw", "test6b_rx_sw", "a4", "Mismatch on S-page R/X VS sw (expect fault) in Test Case 6b!", PTE_XR_S, "sw", 0, 0, "Expected Fault"),  # case 6b: VS U=0 R/X MXR=0 SUM=0 sw
            ("7", "U=1 XWR=111 SUM=0 VS lw", "test7_u_lw", "a6", "Mismatch on U=1 VS lw with SUM=0 (expect fault) in Test Case 7!", PTE_XWR_U, "lw", 0, 0, "Expected Fault"),  # case 7: VS U=1 RWX MXR=0 SUM=0 lw
            ("8", "U=1 XWR=111 SUM=0 VS sw", "test8_u_sw", "a7", "Mismatch on U=1 VS sw with SUM=0 (expect fault) in Test Case 8!", PTE_XWR_U, "sw", 0, 0, "Expected Fault"),  # case 8: VS U=1 RWX MXR=0 SUM=0 sw
            ("9", "U=1 V-only VS sw", "test9_u_vonly_sw", "a3", "Mismatch on U=1 V-only VS sw (expect fault) in Test Case 9!", PTE_V_U, "sw", 0, 0, "Expected Fault"),  # case 9: VS U=1 V-only MXR=0 SUM=0 sw
            ("9b", "U=1 V-only VS lw", "test9b_u_vonly_lw", "s8", "Mismatch on U=1 V-only VS lw (expect fault) in Test Case 9b!", PTE_V_U, "lw", 0, 0, "Expected Fault"),  # case 9b: VS U=1 V-only MXR=0 SUM=0 lw
            ("10", "U=0 V-only VS lw", "test10_s_vonly_lw", "s2", "Mismatch on U=0 V-only VS lw (expect fault) in Test Case 10!", PTE_V_S, "lw", 0, 0, "Expected Fault"),  # case 10: VS U=0 V-only MXR=0 SUM=0 lw
            ("11", "SUM=1 S-page XWR=111 VS sw", "test11_sum1_rwx_sw", "a3", "Mismatch on SUM=1 S-page R/W/X VS sw in Test Case 11!", PTE_XWR_S, "sw", 0, 1, "Successful"),  # case 11: VS U=0 RWX MXR=0 SUM=1 sw
            ("12", "SUM=1 S-page R/W VS sw+lw", "test12_sum1_rw", "a3", "Mismatch on SUM=1 S-page R/W VS lw in Test Case 12!", PTE_DATA_VS, "swlw", 0, 1, "Successful"),  # case 12: VS U=0 R/W MXR=0 SUM=1 sw+lw
            ("13", "SUM=1 S-page R/X VS lw", "test13_sum1_rx", "a3", "Mismatch on SUM=1 S-page R/X VS lw in Test Case 13!", PTE_XR_S, "lw", 0, 1, "Successful"),  # case 13: VS U=0 R/X MXR=0 SUM=1 lw
            ("14", "SUM=1 S-page X-only ifetch", "test14_sum1_x_ifetch", "a3", "Mismatch on SUM=1 S-page X-only ifetch in Test Case 14!", PTE_X_ONLY_S, "jalr", 0, 1, "Successful"),  # case 14: VS U=0 X-only MXR=0 SUM=1 jalr
            ("12b", "SUM=1 S-page R/W VS lw only", "test12b_sum1_rw_lw", "a3", "Mismatch on SUM=1 S-page R/W VS lw-only in Test Case 12b!", PTE_DATA_VS, "lw", 0, 1, "Successful"),  # case 12b: VS U=0 R/W MXR=0 SUM=1 lw
            ("13b", "SUM=1 S-page R/X VS sw", "test13b_sum1_rx_sw", "a4", "Mismatch on SUM=1 S-page R/X VS sw (expect fault) in Test Case 13b!", PTE_XR_S, "sw", 0, 1, "Expected Fault"),  # case 13b: VS U=0 R/X MXR=0 SUM=1 sw
            ("15", "SUM=1 S-page R-only VS lw", "test15_sum1_ronly_lw", "a3", "Mismatch on SUM=1 S-page R-only VS lw in Test Case 15!", PTE_R_ONLY_S, "lw", 0, 1, "Successful"),  # case 15: VS U=0 R-only MXR=0 SUM=1 lw
            ("16", "SUM=1 S-page R-only VS sw", "test16_sum1_ronly_sw", "a4", "Mismatch on SUM=1 S-page R-only VS sw (expect fault) in Test Case 16!", PTE_R_ONLY_S, "sw", 0, 1, "Expected Fault"),  # case 16: VS U=0 R-only MXR=0 SUM=1 sw
            ("17", "SUM=1 S-page R-only VS jalr", "test17_sum1_ronly_jalr", "s2", "Mismatch on SUM=1 S-page R-only VS jalr (expect fault) in Test Case 17!", PTE_R_ONLY_S, "jalr", 0, 1, "Expected Fault"),  # case 17: VS U=0 R-only MXR=0 SUM=1 jalr
            ("18", "SUM=1 S-page R/W VS jalr", "test18_sum1_rw_jalr", "s3", "Mismatch on SUM=1 S-page R/W VS jalr (expect fault) in Test Case 18!", PTE_DATA_VS, "jalr", 0, 1, "Expected Fault"),  # case 18: VS U=0 R/W MXR=0 SUM=1 jalr
        ]
    else:
        cp = "cp_vsatp_perm_checks_rw"  # local setup variable
        specs = [  # packed case table
            ("1", "U=1 XWR=111 VU sw+lw", "test1_urw_rwx", "a3", "Mismatch on U=1 RWX VU lw in Test Case 1!", PTE_XWR_U, "swlw", 0, 0, "Successful"),  # case 1: VS U=1 RWX MXR=0 SUM=0 sw+lw
            ("2", "U=1 X-only VU lw", "test2_ux_lw", "a4", "Mismatch on U=1 X-only VU lw (expect fault) in Test Case 2!", PTE_X_ONLY_U, "lw", 0, 0, "Expected Fault"),  # case 2: VS U=1 X-only MXR=0 SUM=0 lw
            ("3", "U=1 X-only VU sw", "test3_ux_sw", "a3", "Mismatch on U=1 X-only VU sw (expect fault) in Test Case 3!", PTE_X_ONLY_U, "sw", 0, 0, "Expected Fault"),  # case 3: VS U=1 X-only MXR=0 SUM=0 sw
            ("4", "U=1 R-only VU lw OK, VU sw fault", "test4_ur_only", "a3", "Mismatch on U=1 R-only VU lw in Test Case 4!", PTE_R_ONLY_U, "lw", 0, 0, "Successful"),  # case 4: VS U=1 R-only MXR=0 SUM=0 lw
            ("5", "U=1 R/W VU sw+lw", "test5_urw", "a3", "Mismatch on U=1 R/W VU lw in Test Case 5!", PTE_RW_U, "swlw", 0, 0, "Successful"),  # case 5: VS U=1 R/W MXR=0 SUM=0 sw+lw
            ("6", "U=1 R/X VU lw OK, VU sw fault", "test6_urx", "a3", "Mismatch on U=1 R/X VU lw in Test Case 6!", PTE_XR_U, "lw", 0, 0, "Successful"),  # case 6: VS U=1 R/X MXR=0 SUM=0 lw
            ("7", "U=0 XWR=111 VU lw", "test7_s_lw", "a6", "Mismatch on U=0 VU lw (expect fault) in Test Case 7!", PTE_XWR_S, "lw", 0, 0, "Expected Fault"),  # case 7: VS U=0 RWX MXR=0 SUM=0 lw
            ("8", "U=1 V-only VU lw", "test8_uv_lw", "a7", "Mismatch on U=1 V-only VU lw (expect fault) in Test Case 8!", PTE_V_U, "lw", 0, 0, "Expected Fault"),  # case 8: VS U=1 V-only MXR=0 SUM=0 lw
            ("9", "U=0 XWR=111 VU sw", "test9_s_sw", "s2", "Mismatch on U=0 VU sw (expect fault) in Test Case 9!", PTE_XWR_S, "sw", 0, 0, "Expected Fault"),  # case 9: VS U=0 RWX MXR=0 SUM=0 sw
            ("10", "U=0 V-only VU lw", "test10_sv_lw", "s3", "Mismatch on U=0 V-only VU lw (expect fault) in Test Case 10!", PTE_V_S, "lw", 0, 0, "Expected Fault"),  # case 10: VS U=0 V-only MXR=0 SUM=0 lw
            ("11", "U=0 V-only VU sw", "test11_sv_sw", "s4", "Mismatch on U=0 V-only VU sw (expect fault) in Test Case 11!", PTE_V_S, "sw", 0, 0, "Expected Fault"),  # case 11: VS U=0 V-only MXR=0 SUM=0 sw
            ("12", "U=1 V-only VU sw", "test12_uv_sw", "s5", "Mismatch on U=1 V-only VU sw (expect fault) in Test Case 12!", PTE_V_U, "sw", 0, 0, "Expected Fault"),  # case 12: VS U=1 V-only MXR=0 SUM=0 sw
        ]
    cases = [SigCase(num, title, label, reg, cp, expected) for num, title, label, reg, _msg, _flags, _access, _mxr, _sum, expected in specs]  # SigCase list
    for spec, case in zip(specs, cases):  # iterate cases/specs
        payload = (0x257A0400 if mode == "VS" else 0x257A0700) + len(lines)  # unique data pattern
        lines.extend(  # extend with following list
            _asm_vs_seed_case(
                test_data,  # pass test counters
                paging,  # pass paging twin
                case=case,  # this case
                mode=mode,
                flags=spec[5],
                access=cast(Access, spec[6]),  # access kind
                mxr=spec[7],  # MXR bit
                sum_=spec[8],  # SUM bit
                payload=payload,  # data pattern
                exec_page=case.label == "test14_sum1_x_ifetch",  # use xonly exec page?
            )  # end SvHCommon import list
        )  # end SvHCommon import list
    lines.extend(_data(paging, regions=["test_region"], xonly_exec=mode == "VS"))  # splice more asm into output
    return lines


def generate_vs_perm_VSmode(test_data: TestData) -> list[str]:  # emitter helper generate_vs_perm_VSmode
    """Output ``SvH_vs_perm_VSmode-00.S``: VS XWR/U/SUM matrix (directed case count)."""
    return [comment_banner("vs_perm_VSmode", "SvH VS-stage permission stimulus"), *build_twins(test_data, lambda td, p: _asm_vs_perm(td, p, mode="VS"))]  # file header + twin body


def generate_vs_perm_VUmode(test_data: TestData) -> list[str]:  # emitter helper generate_vs_perm_VUmode
    """Output ``SvH_vs_perm_VUmode-00.S``: VU permission allow/deny on U vs S pages."""
    return [comment_banner("vs_perm_VUmode", "SvH VS-stage permission stimulus"), *build_twins(test_data, lambda td, p: _asm_vs_perm(td, p, mode="VU"))]  # file header + twin body


def _asm_mxr_sum(test_data: TestData, paging: Paging, *, mode: Guest) -> list[str]:  # MXR×SUM×S/U page matrix
    code_u = mode == "VU"  # U=1 on code if VU
    va_s_rw = "0x0000000080020000" if paging == "sv39" else "0x08002000"  # S-page RW VA (no TLB alias)
    lines = [  # asm output buffer
        *_vs_only_setup(paging, code_u=code_u, data_flags=PTE_XWR_U if code_u else PTE_XWR_S),  # unpack/splice helper output
        f"  .set va_s_rw, {va_s_rw}",  # S-page RW VA symbol
        *_vs_leaf_map(paging, va="va_s_rw", pa="test_region_s_rw", flags=PTE_XWR_S),  # unpack/splice helper output
        *fence_both_stages(),  # unpack/splice helper output
    ]
    x_s = PTE_X_ONLY_S  # local setup variable
    x_u = PTE_X_ONLY_U  # local setup variable
    rwx_s = PTE_XWR_S  # local setup variable
    rwx_u = PTE_XWR_U  # local setup variable
    if mode == "VS":
        specs = [  # packed case table
            ("1", "MXR=0 SUM=0 S-page X-only VS lw", "test1_mxr0_xs", "a3", x_s, "lw", 0, 0, "Expected Fault"),  # case 1: MXR=0 SUM=0 S-page X-only VS lw
            ("2", "MXR=1 SUM=0 S-page X-only VS lw", "test2_mxr1_xs_lw", "a4", x_s, "lw", 1, 0, "Successful"),  # case 2: MXR=1 SUM=0 S-page X-only VS lw
            ("3", "MXR=1 SUM=0 S-page X-only VS sw", "test3_mxr1_xs_sw", "a3", x_s, "sw", 1, 0, "Expected Fault"),  # case 3: MXR=1 SUM=0 S-page X-only VS sw
            ("4", "MXR=0 SUM=0 U-page X-only VS lw", "test4_mxr0_xu", "a6", x_u, "lw", 0, 0, "Expected Fault"),  # case 4: MXR=0 SUM=0 U-page X-only VS lw
            ("5", "MXR=1 SUM=0 U-page X-only VS lw", "test5_mxr1_xu", "a7", x_u, "lw", 1, 0, "Expected Fault"),  # case 5: MXR=1 SUM=0 U-page X-only VS lw
            ("6", "MXR=1 SUM=1 U-page X-only VS lw", "test6_mxr1_sum1_xu", "a3", x_u, "lw", 1, 1, "Successful"),  # case 6: MXR=1 SUM=1 U-page X-only VS lw
            ("7", "MXR=0 SUM=1 U-page XWR=111 VS lw", "test7_sum1_urw_lw", "a4", rwx_u, "lw", 0, 1, "Successful"),  # case 7: MXR=0 SUM=1 U-page XWR=111 VS lw
            ("8", "MXR=1 SUM=1 U-page XWR=111 VS sw+lw", "test8_sum1_urw_swlw", "a6", rwx_u, "swlw", 1, 1, "Successful"),  # case 8: MXR=1 SUM=1 U-page XWR=111 VS sw+lw
            ("9", "MXR=0 SUM=0 U-page XWR=111 VS sw", "test9_sum0_urw_sw", "s2", rwx_u, "sw", 0, 0, "Expected Fault"),  # case 9: MXR=0 SUM=0 U-page XWR=111 VS sw
            ("10", "MXR=0 SUM=0 S-page XWR=111 VS sw+lw", "test10_srw_swlw", "a7", rwx_s, "swlw", 0, 0, "Successful"),  # case 10: MXR=0 SUM=0 S-page XWR=111 VS sw+lw
        ]
        if paging == "sv39":
            specs.append(("10b", "MXR=0 SUM=0 S-page XWR=111 VS lw only", "test10b_srw_lw", "s11", rwx_s, "lw", 0, 0, "Successful"))  # Sv39-only extra case
        specs.extend(  # more MXR/SUM cases
            [  # list begin
                ("11", "MXR=0 SUM=1 S-page X-only VS lw", "test11_sum1_mxr0_xs", "s3", x_s, "lw", 0, 1, "Expected Fault"),  # case 11: MXR=0 SUM=1 S-page X-only VS lw
                ("12", "MXR=1 SUM=1 S-page XWR=111 VS lw", "test12_mxr1_sum1_srw", "s2", rwx_s, "lw", 1, 1, "Successful"),  # case 12: MXR=1 SUM=1 S-page XWR=111 VS lw
                ("13", "MXR=0 SUM=1 U-page X-only VS lw", "test13_sum1_mxr0_xu", "s4", x_u, "lw", 0, 1, "Expected Fault"),  # case 13: MXR=0 SUM=1 U-page X-only VS lw
                ("14", "MXR=1 SUM=1 U-page X-only VS sw", "test14_mxr1_sum1_xu_sw", "s5", x_u, "sw", 1, 1, "Expected Fault"),  # case 14: MXR=1 SUM=1 U-page X-only VS sw
                ("15", "MXR=1 SUM=0 U-page XWR=111 VS lw", "test15_mxr1_sum0_urw", "s6", rwx_u, "lw", 1, 0, "Expected Fault"),  # case 15: MXR=1 SUM=0 U-page XWR=111 VS lw
                ("16", "MXR=1 SUM=1 S-page X-only VS sw", "test16_mxr1_sum1_xs_sw", "s7", x_s, "sw", 1, 1, "Expected Fault"),  # case 16: MXR=1 SUM=1 S-page X-only VS sw
                ("17", "MXR=0 SUM=1 S-page XWR=111 VS lw", "test17_sum1_mxr0_srw", "s2", rwx_s, "lw", 0, 1, "Successful"),  # case 17: MXR=0 SUM=1 S-page XWR=111 VS lw
                ("18", "MXR=1 SUM=0 S-page XWR=111 VS sw+lw", "test18_mxr1_sum0_srw_sw", "s3", rwx_s, "swlw", 1, 0, "Successful"),  # case 18: MXR=1 SUM=0 S-page XWR=111 VS sw+lw
                ("19", "MXR=0 SUM=1 S-page X-only VS sw", "test19_sum1_xs_sw", "s4", x_s, "sw", 0, 1, "Expected Fault"),  # case 19: MXR=0 SUM=1 S-page X-only VS sw
                ("20", "MXR=0 SUM=1 U-page X-only VS sw", "test20_sum1_xu_sw", "s5", x_u, "sw", 0, 1, "Expected Fault"),  # case 20: MXR=0 SUM=1 U-page X-only VS sw
                ("21", "MXR=0 SUM=0 S-page XWR=111 VS jalr", "test21_srw_jalr", "s8", rwx_s, "jalr", 0, 0, "Successful"),  # case 21: MXR=0 SUM=0 S-page XWR=111 VS jalr
                ("22", "MXR=0 SUM=1 S-page XWR=111 VS jalr", "test22_sum1_srw_jalr", "s9", rwx_s, "jalr", 0, 1, "Successful"),  # case 22: MXR=0 SUM=1 S-page XWR=111 VS jalr
                ("23", "MXR=1 SUM=1 U-page XWR=111 VS jalr", "test23_urw_jalr", "s10", rwx_u, "jalr", 1, 1, "Successful"),  # case 23: MXR=1 SUM=1 U-page XWR=111 VS jalr
                ("24", "MXR=1 SUM=1 S-page XWR=111 VS sw+lw", "test24_mxr1_sum1_srw_sw", "s2", rwx_s, "swlw", 1, 1, "Successful"),  # case 24: MXR=1 SUM=1 S-page XWR=111 VS sw+lw
                ("25", "MXR=1 SUM=0 U-page X-only VS sw", "test25_mxr1_xu_sw", "s3", x_u, "sw", 1, 0, "Expected Fault"),  # case 25: MXR=1 SUM=0 U-page X-only VS sw
                ("26", "MXR=1 SUM=0 S-page X-only VS sw", "test26_mxr1_xs_sw", "s4", x_s, "sw", 1, 0, "Expected Fault"),  # case 26: MXR=1 SUM=0 S-page X-only VS sw
                ("27", "MXR=1 SUM=0 U-page XWR=111 VS sw", "test27_mxr1_sum0_urw_sw", "s5", rwx_u, "sw", 1, 0, "Expected Fault"),  # case 27: MXR=1 SUM=0 U-page XWR=111 VS sw
                ("28", "MXR=0 SUM=0 U-page X-only VS sw", "test28_mxr0_xu_sw", "s2", x_u, "sw", 0, 0, "Expected Fault"),  # case 28: MXR=0 SUM=0 U-page X-only VS sw
                ("29", "MXR=1 SUM=1 U-page XWR=111 VS lw", "test29_mxr1_sum1_urw_lw", "s3", rwx_u, "lw", 1, 1, "Successful"),  # case 29: MXR=1 SUM=1 U-page XWR=111 VS lw
                ("30", "MXR=1 SUM=1 S-page X-only VS lw", "test30_mxr1_sum1_xs_lw", "s4", x_s, "lw", 1, 1, "Successful"),  # case 30: MXR=1 SUM=1 S-page X-only VS lw
                ("31", "MXR=1 SUM=0 S-page XWR=111 VS lw only", "test31_mxr1_sum0_srw_lw", "s5", rwx_s, "lw", 1, 0, "Successful"),  # case 31: MXR=1 SUM=0 S-page XWR=111 VS lw only
                ("32", "MXR=1 SUM=0 S-page XWR=111 VS jalr", "test32_mxr1_sum0_srw_jalr", "s6", rwx_s, "jalr", 1, 0, "Successful"),  # case 32: MXR=1 SUM=0 S-page XWR=111 VS jalr
                ("32b", "MXR=1 SUM=1 S-page XWR=111 VS jalr", "test32b_mxr1_sum1_srw_jalr", "s8", rwx_s, "jalr", 1, 1, "Successful"),  # case 32b: MXR=1 SUM=1 S-page XWR=111 VS jalr
                ("33", "MXR=1 SUM=1 S-page X-only VS lw", "test33_mxr1_sum1_xs_lw2", "s7", x_s, "lw", 1, 1, "Successful"),  # case 33: MXR=1 SUM=1 S-page X-only VS lw
            ]
        )  # end SvHCommon import list
    else:
        specs = [  # packed case table
            ("1", "MXR=0 SUM=0 U-page X-only VU lw", "test1_mxr0_xu", "a3", x_u, "lw", 0, 0, "Expected Fault"),  # case 1: MXR=0 SUM=0 U-page X-only VU lw
            ("2", "MXR=1 SUM=0 U-page X-only VU lw", "test2_mxr1_xu_lw", "a4", x_u, "lw", 1, 0, "Successful"),  # case 2: MXR=1 SUM=0 U-page X-only VU lw
            ("3", "MXR=1 SUM=0 U-page X-only VU sw", "test3_mxr1_xu_sw", "a3", x_u, "sw", 1, 0, "Expected Fault"),  # case 3: MXR=1 SUM=0 U-page X-only VU sw
            ("4", "MXR=0 SUM=1 U-page XWR=111 VU lw", "test4_sum1_urw_lw", "a4", rwx_u, "lw", 0, 1, "Successful"),  # case 4: MXR=0 SUM=1 U-page XWR=111 VU lw
            ("5", "MXR=1 SUM=1 U-page XWR=111 VU sw+lw", "test5_sum1_urw_swlw", "a6", rwx_u, "swlw", 1, 1, "Successful"),  # case 5: MXR=1 SUM=1 U-page XWR=111 VU sw+lw
            ("6", "MXR=0 SUM=0 U-page XWR=111 VU sw+lw", "test6_sum0_urw_swlw", "a3", rwx_u, "swlw", 0, 0, "Successful"),  # case 6: MXR=0 SUM=0 U-page XWR=111 VU sw+lw
            ("7", "MXR=0 SUM=0 S-page XWR=111 VU lw", "test7_srw_lw", "a6", rwx_s, "lw", 0, 0, "Expected Fault"),  # case 7: MXR=0 SUM=0 S-page XWR=111 VU lw
            ("8", "MXR=1 SUM=1 S-page X-only VU lw", "test8_mxr1_sum1_xs", "a7", x_s, "lw", 1, 1, "Expected Fault"),  # case 8: MXR=1 SUM=1 S-page X-only VU lw
            ("9", "MXR=0 SUM=1 S-page XWR=111 VU lw", "test9_sum1_srw", "s2", rwx_s, "lw", 0, 1, "Expected Fault"),  # case 9: MXR=0 SUM=1 S-page XWR=111 VU lw
            ("10", "MXR=0 SUM=0 S-page X-only VU lw", "test10_sum0_xs", "s3", x_s, "lw", 0, 0, "Expected Fault"),  # case 10: MXR=0 SUM=0 S-page X-only VU lw
            ("11", "MXR=0 SUM=1 U-page X-only VU lw", "test11_sum1_mxr0_xu", "s4", x_u, "lw", 0, 1, "Expected Fault"),  # case 11: MXR=0 SUM=1 U-page X-only VU lw
            ("12", "MXR=0 SUM=1 U-page XWR=111 VU sw+lw", "test12_sum1_mxr0_urw_sw", "a3", rwx_u, "swlw", 0, 1, "Successful"),  # case 12: MXR=0 SUM=1 U-page XWR=111 VU sw+lw
            ("13", "MXR=1 SUM=0 S-page XWR=111 VU sw", "test13_mxr1_srw_sw", "a4", rwx_s, "sw", 1, 0, "Expected Fault"),  # case 13: MXR=1 SUM=0 S-page XWR=111 VU sw
            ("14", "MXR=1 SUM=1 S-page XWR=111 VU lw", "test14_mxr1_sum1_srw", "s5", rwx_s, "lw", 1, 1, "Expected Fault"),  # case 14: MXR=1 SUM=1 S-page XWR=111 VU lw
            ("15", "MXR=0 SUM=0 S-page X-only VU sw", "test15_xs_sw", "a6", x_s, "sw", 0, 0, "Expected Fault"),  # case 15: MXR=0 SUM=0 S-page X-only VU sw
            ("16", "MXR=1 SUM=1 U-page X-only VU jalr", "test16_xu_jalr", "s6", x_u, "jalr", 1, 1, "Expected Fault"),  # case 16: MXR=1 SUM=1 U-page X-only VU jalr
            ("17", "MXR=1 SUM=1 S-page XWR=111 VU jalr", "test17_srw_jalr", "s7", rwx_s, "jalr", 1, 1, "Expected Fault"),  # case 17: MXR=1 SUM=1 S-page XWR=111 VU jalr
            ("18", "MXR=1 SUM=0 U-page XWR=111 VU sw+lw", "test18_mxr1_sum0_urw", "a3", rwx_u, "swlw", 1, 0, "Successful"),  # case 18: MXR=1 SUM=0 U-page XWR=111 VU sw+lw
            ("19", "MXR=1 SUM=0 S-page X-only VU lw", "test19_mxr1_xs", "s8", x_s, "lw", 1, 0, "Expected Fault"),  # case 19: MXR=1 SUM=0 S-page X-only VU lw
            ("20", "MXR=0 SUM=1 S-page X-only VU sw", "test20_sum1_xs_sw", "a4", x_s, "sw", 0, 1, "Expected Fault"),  # case 20: MXR=0 SUM=1 S-page X-only VU sw
            ("21", "MXR=1 SUM=1 U-page X-only VU sw", "test21_mxr1_sum1_xu_sw", "a6", x_u, "sw", 1, 1, "Expected Fault"),  # case 21: MXR=1 SUM=1 U-page X-only VU sw
            ("22", "MXR=1 SUM=1 S-page XWR=111 VU sw", "test22_sum1_srw_sw", "a3", rwx_s, "sw", 1, 1, "Expected Fault"),  # case 22: MXR=1 SUM=1 S-page XWR=111 VU sw
            ("23", "MXR=0 SUM=0 U-page XWR=111 VU lw", "test23_sum0_urw_lw", "a4", rwx_u, "lw", 0, 0, "Successful"),  # case 23: MXR=0 SUM=0 U-page XWR=111 VU lw
            ("24", "MXR=1 SUM=0 U-page XWR=111 VU lw", "test24_mxr1_sum0_urw_lw", "a6", rwx_u, "lw", 1, 0, "Successful"),  # case 24: MXR=1 SUM=0 U-page XWR=111 VU lw
            ("25", "MXR=1 SUM=0 S-page X-only VU sw", "test25_mxr1_xs_sw", "a7", x_s, "sw", 1, 0, "Expected Fault"),  # case 25: MXR=1 SUM=0 S-page X-only VU sw
            ("26", "MXR=1 SUM=1 S-page X-only VU sw", "test26_mxr1_sum1_xs_sw", "s2", x_s, "sw", 1, 1, "Expected Fault"),  # case 26: MXR=1 SUM=1 S-page X-only VU sw
            ("27", "MXR=0 SUM=1 U-page X-only VU sw", "test27_sum1_xu_sw", "s3", x_u, "sw", 0, 1, "Expected Fault"),  # case 27: MXR=0 SUM=1 U-page X-only VU sw
            ("28", "MXR=0 SUM=1 S-page X-only VU lw", "test28_sum1_xs_lw", "s4", x_s, "lw", 0, 1, "Expected Fault"),  # case 28: MXR=0 SUM=1 S-page X-only VU lw
            ("29", "MXR=1 SUM=1 U-page X-only VU lw", "test29_mxr1_sum1_xu_lw", "s5", x_u, "lw", 1, 1, "Successful"),  # case 29: MXR=1 SUM=1 U-page X-only VU lw
            ("30", "MXR=0 SUM=0 U-page XWR=111 VU jalr", "test30_urw_jalr", "s6", rwx_u, "jalr", 0, 0, "Successful"),  # case 30: MXR=0 SUM=0 U-page XWR=111 VU jalr
            ("31", "MXR=1 SUM=0 U-page X-only VU jalr", "test31_xu_jalr_ok", "s7", x_u, "jalr", 1, 0, "Successful"),  # case 31: MXR=1 SUM=0 U-page X-only VU jalr
            ("32", "MXR=0 SUM=1 U-page XWR=111 VU jalr", "test32_sum1_urw_jalr", "s8", rwx_u, "jalr", 0, 1, "Successful"),  # case 32: MXR=0 SUM=1 U-page XWR=111 VU jalr
            ("33", "MXR=0 SUM=1 S-page XWR=111 VU sw", "test33_sum1_mxr0_srw_sw", "a3", rwx_s, "sw", 0, 1, "Expected Fault"),  # case 33: MXR=0 SUM=1 S-page XWR=111 VU sw
            ("34", "MXR=1 SUM=0 U-page X-only VU sw", "test34_mxr1_xu_sw2", "a4", x_u, "sw", 1, 0, "Expected Fault"),  # case 34: MXR=1 SUM=0 U-page X-only VU sw
            ("35", "MXR=1 SUM=0 S-page XWR=111 VU lw", "test35_mxr1_sum0_srw_lw", "a6", rwx_s, "lw", 1, 0, "Expected Fault"),  # case 35: MXR=1 SUM=0 S-page XWR=111 VU lw
            ("36", "MXR=1 SUM=1 U-page XWR=111 VU lw only", "test36_mxr1_sum1_urw_lw", "a7", rwx_u, "lw", 1, 1, "Successful"),  # case 36: MXR=1 SUM=1 U-page XWR=111 VU lw only
            ("37", "MXR=1 SUM=1 U-page XWR=111 VU jalr", "test37_mxr1_sum1_urw_jalr", "s2", rwx_u, "jalr", 1, 1, "Successful"),  # case 37: MXR=1 SUM=1 U-page XWR=111 VU jalr
        ]
    cases = [  # SigCase list
        SigCase(num, title, label, reg, "cp_vsstatus_mxr_sum_rw", expected)  # SigCase record
        for num, title, label, reg, _flags, _access, _mxr, _sum, expected in specs  # unpack case fields
    ]
    for index, (spec, case) in enumerate(zip(specs, cases), start=1):  # iterate cases/specs
        flags = spec[4]  # local setup variable
    # Dedicated VA/PA for S-page RWX so MXR=1 SUM=1 reads are not TLB-aliased
    # with prior X-only walks on va_data (seed uses va_s_rw).
        use_s_rw = flags == rwx_s  # use va_s_rw / test_region_s_rw
        lines.extend(  # extend with following list
            _asm_vs_seed_case(
                test_data,  # pass test counters
                paging,  # pass paging twin
                case=case,  # this case
                mode=mode,
                flags=flags,
                access=cast(Access, spec[5]),  # access kind
                mxr=spec[6],  # MXR bit
                sum_=spec[7],  # SUM bit
                payload=(0x257A0500 if mode == "VS" else 0x257A0600) + index,  # data pattern
                va="va_s_rw" if use_s_rw else "va_data",
                pa="test_region_s_rw" if use_s_rw else None,  # physical page
            )  # end SvHCommon import list
        )  # end SvHCommon import list
    lines.extend(_data(paging, regions=["test_region", "test_region_s_rw"]))  # splice more asm into output
    return lines


def generate_vsstatus_mxr_sum_VSmode(test_data: TestData) -> list[str]:  # emitter helper generate_vsstatus_mxr_sum_VSmode
    """Output ``SvH_vsstatus_mxr_sum_VSmode-00.S``: VS MXR×SUM×S/U page accesses."""
    return [comment_banner("vsstatus_mxr_sum_VSmode", "SvH VS MXR/SUM matrix stimulus"), *build_twins(test_data, lambda td, p: _asm_mxr_sum(td, p, mode="VS"))]  # file header + twin body


def generate_vsstatus_mxr_sum_VUmode(test_data: TestData) -> list[str]:  # emitter helper generate_vsstatus_mxr_sum_VUmode
    """Output ``SvH_vsstatus_mxr_sum_VUmode-00.S``: VU MXR×SUM; SUM does not grant S-pages to VU."""
    return [comment_banner("vsstatus_mxr_sum_VUmode", "SvH VU MXR/SUM matrix stimulus"), *build_twins(test_data, lambda td, p: _asm_mxr_sum(td, p, mode="VU"))]  # file header + twin body


def _asm_vu_rwx(test_data: TestData, paging: Paging) -> list[str]:  # VU two-stage U=1 allow / U=0 deny
    """VU two-stage U=1 XWR=111 allow + U=0 deny — match seed VA/GPA and maps."""
    vs_mode, g_mode = mode_names(paging)  # local setup variable
    cases = [  # SigCase list
        SigCase("1", "Both stages U=1 XWR=111 VU sw+lw", "test1_allow", "a3", "rwx_umode_pages_umode", "Successful"),  # SigCase metadata for SIGUPD
        SigCase("2", "VS leaf U=0, G leaf U=1 VU lw", "test2_deny", "a4", "rwx_umode_pages_umode"),  # SigCase metadata for SIGUPD
    ]
    # Coverpoints need VS leaf 11?11111 (incl. W) on both data (_rw) and ifetch (_x).
    u_rwx = PTE_XWR_U  # local setup variable
    s_rwx = PTE_XWR_S  # local setup variable
    lines: list[str] = [  # asm output buffer
        "  .set va_data,                 0x008001000",  # data VA symbol
        "  .set va_deny,                 0x008002000",  # deny VA symbol
        "  .set va_code,                 0x90000000" if paging == "sv32" else "  .set va_code,                 0x0000000090000000",  # code VA symbol
        "  .set gpa_data,                0x00C002000",  # data GPA symbol
        "  .set gpa_deny,                0x00C003000",  # deny GPA symbol
        "  .set gpa_code,                0x012000000",  # code GPA symbol
        "  .set gpa_rvtest_Vroot_pg_tbl, 0x01000A000",  # VS root PT GPA
        "  .set gpa_rvtest_vlvl0_pg_tbl, 0x01000B000",  # VS L0 PT GPA
    ]
    if paging == "sv39":
        lines.append("  .set gpa_rvtest_vlvl1_pg_tbl, 0x000000001000C000")  # VS L1 PT GPA (Sv39)
        lines.extend(  # extend with following list
            [  # list begin
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_code, LEVEL2)",  # paging macro emission
                f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {u_rwx}, gpa_code, LEVEL1)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_rvtest_Vroot_pg_tbl, LEVEL1)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, rvtest_Vroot_pg_tbl, {PTE_PT_G}, gpa_rvtest_Vroot_pg_tbl, LEVEL0)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, rvtest_vlvl1_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl1_pg_tbl, LEVEL0)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, rvtest_vlvl0_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, test_region, {u_rwx}, gpa_data, LEVEL0)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, test_region_deny, {u_rwx}, gpa_deny, LEVEL0)",  # paging macro emission
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_code, LEVEL2)",  # paging macro emission
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_code, {u_rwx}, va_code, LEVEL1)",  # paging macro emission
                "  csrr a0, mscratch",  # a0 = save-area base
                "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate save area
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL2)",  # paging macro emission
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)",  # paging macro emission
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_data, {u_rwx}, va_data, LEVEL0)",  # paging macro emission
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_deny, {s_rwx}, va_deny, LEVEL0)",  # paging macro emission
            ]
        )  # end SvHCommon import list
    else:
        lines.extend(  # extend with following list
            [  # list begin
                f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {u_rwx}, gpa_code, LEVEL1)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_rvtest_Vroot_pg_tbl, LEVEL1)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, rvtest_Vroot_pg_tbl, {PTE_PT_G}, gpa_rvtest_Vroot_pg_tbl, LEVEL0)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, rvtest_vlvl0_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, test_region, {u_rwx}, gpa_data, LEVEL0)",  # paging macro emission
                f"  G_PTE_SETUP({g_mode}, test_region_deny, {u_rwx}, gpa_deny, LEVEL0)",  # paging macro emission
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_code, {u_rwx}, va_code, LEVEL1)",  # paging macro emission
                "  csrr a0, mscratch",  # a0 = save-area base
                "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate save area
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)",  # paging macro emission
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_data, {u_rwx}, va_data, LEVEL0)",  # paging macro emission
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_deny, {s_rwx}, va_deny, LEVEL0)",  # paging macro emission
            ]
        )  # end SvHCommon import list
    lines.extend(enable_two_stage(paging))  # splice more asm into output
    lines.extend(preload_spa(test_data, 0x257A0B01))  # splice more asm into output
    # Seed-style single VU hop: sw then lw (hits write+read with same U=1 XWR=111 leaf).

    lines.extend(  # extend with following list
        [  # list begin
            *_case_banner(cases[0]),  # unpack/splice helper output
            "  LI(a5, va_data)",  # pointer for access
            "  LI(t0, 0x257A0B01)",  # load immediate
            *_enter_guest("VU", relocated=True),
            "  sw t0, 0(a5)",  # store at guest VA
            "  nop",  # delay slot / pad
            "  lw a3, 0(a5)",  # load word
            "  nop",  # delay slot / pad
            *_leave_guest(),  # leave to M
            *_sig(test_data, cases[0]),  # SIGUPD
            *_case_banner(cases[1]),  # unpack/splice helper output
            "  LI(a5, va_deny)",  # pointer for access
            "  LI(a4, 0)",  # load immediate constant
            *_enter_guest("VU", relocated=True),
            "  lw a4, 0(a5)",  # load word
            "  nop",  # delay slot / pad
            *_leave_guest(),  # leave to M
            *_sig(test_data, cases[1]),  # SIGUPD
            *data_section(  # unpack/splice helper output
                need_test_region=True,  # include test_region?
                need_hlvl0=True,
                need_vlvl0=True,
                need_hlvl1=paging == "sv39",
                need_vlvl1=paging == "sv39",
                extra_regions=_regions(["test_region_deny"]),  # extra named regions
            ),
        ]
    )  # end SvHCommon import list
    return lines


def generate_vu_rwx_two_stage_VUmode(test_data: TestData) -> list[str]:  # emitter helper generate_vu_rwx_two_stage_VUmode
    """Output ``SvH_vu_rwx_two_stage_VUmode-00.S``: VU on U=1 both stages, then U=0 deny."""
    return [comment_banner("vu_rwx_two_stage_VUmode", "SvH VU two-stage U-page stimulus"), *build_twins(test_data, _asm_vu_rwx)]  # file header + twin body


def _asm_xonly_vs(test_data: TestData, paging: Paging, *, mode: Guest) -> list[str]:  # X-only load MXR=0 fault
    code_u = mode == "VU"  # U=1 on code if VU
    cases = [  # SigCase list
        SigCase("1", f"{mode} load of X-only page with MXR=0", f"test1_mxr0_{mode.lower()}", "a3", f"xonly_mxr0_vs_{mode.lower()}"),  # SigCase record
    ]
    if mode == "VS":
        cases.append(SigCase("2", "Control addi after VS ifetch", "test2_ctrl", "a4", "xonly_mxr0_vs_vs", "Successful"))  # bump control value
    lines = [  # asm output buffer
        *_vs_only_setup(paging, code_u=code_u, data_flags=PTE_X_ONLY_U if code_u else PTE_X_ONLY_S),  # unpack/splice helper output
        *preload_spa(test_data, 0xDEADBEEF if mode == "VU" else 0x257A0801),  # unpack/splice helper output
        *_write_mxr_sum(0, 0),  # set MXR/SUM
        *_asm_load_case(test_data, case=cases[0], mode=mode, va="va_data", check_reg="a3"),  # unpack/splice helper output
    ]
    if mode == "VS":
        lines.extend([*_case_banner(cases[1]), "  LI(a4, 0x257A0801)", "  addi a4, a4, 1", *_sig(test_data, cases[1])])  # splice more asm into output
    lines.extend(twin_data(paging))  # splice more asm into output
    return lines


def generate_xonly_mxr0_VSmode(test_data: TestData) -> list[str]:  # emitter helper generate_xonly_mxr0_VSmode
    """Output ``SvH_xonly_mxr0_VSmode-00.S``: VS load of execute-only with MXR=0 (fault)."""
    return [comment_banner("xonly_mxr0_VSmode", "SvH X-only MXR=0 stimulus"), *build_twins(test_data, lambda td, p: _asm_xonly_vs(td, p, mode="VS"))]  # file header + twin body


def generate_xonly_mxr0_VUmode(test_data: TestData) -> list[str]:  # emitter helper generate_xonly_mxr0_VUmode
    """Output ``SvH_xonly_mxr0_VUmode-00.S``: VU load of execute-only U=1 with MXR=0 (fault)."""
    return [comment_banner("xonly_mxr0_VUmode", "SvH X-only MXR=0 stimulus"), *build_twins(test_data, lambda td, p: _asm_xonly_vs(td, p, mode="VU"))]  # file header + twin body


def _asm_xonly_hs(test_data: TestData, paging: Paging) -> list[str]:  # HS HLV of VS X-only MXR=0
    """HS hlv.w of a VS execute-only page with MXR=0 (expect fault)."""
    case = SigCase("1", "MXR=0 SPVP=1 VS X-only HS hlv.w", "test1_hlv", "a3", "xonly_mxr0_vs_hs")  # one SIGUPD
    return [
        *_vs_only_setup(paging, code_u=False, data_flags=PTE_X_ONLY_S),  # unpack/splice helper output
        *preload_spa(test_data, 0x257A0811),  # unpack/splice helper output
        *_write_mxr_sum(0, 0),
        "  LI(t0, HSTATUS_SPVP)",  # t0 = SPVP mask
        "  csrs hstatus, t0",  # SPVP=1: HLV walks VS-stage as VS
        *_case_banner(case),  # unpack/splice helper output
        *load_guest_va("a5", "va_data"),
        "  LI(a3, 0)",  # a3 stays 0 if HLV faults
        *_enter_guest("HS", relocated=False),  # T-SBI into HS
        "  hlv.w a3, (a5)",  # asm/data line in output list
        "  nop",  # pad after the access
        *_leave_guest(),
        "  LI(t0, HSTATUS_SPVP)",  # t0 = SPVP mask
        "  csrc hstatus, t0",  # set/clear CSR bit field
        *_sig(test_data, case),  # unpack/splice helper output
        *twin_data(paging),  # unpack/splice helper output
    ]


def generate_xonly_mxr0_HSmode(test_data: TestData) -> list[str]:  # emitter helper generate_xonly_mxr0_HSmode
    """Output ``SvH_xonly_mxr0_HSmode-00.S``: HS ``hlv.w`` of execute-only with MXR=0."""
    return [comment_banner("xonly_mxr0_HSmode", "SvH HS X-only MXR=0 stimulus"), *build_twins(test_data, _asm_xonly_hs)]  # file header + twin body


def _asm_xonly_gstage_hs(test_data: TestData, paging: Paging) -> list[str]:  # HS HLV of G X-only MXR=0
    """HS hlv.w of a G-stage execute-only GPA with MXR=0 (expect fault)."""
    case = SigCase("1", "G X-only U=1 MXR=0 HS hlv.w", "test1_g_xonly", "a3", "xonly_mxr0_g_hs")  # one SIGUPD
    return [
        *_g_only_setup(paging, g_flags=PTE_X_ONLY_U_G),  # unpack/splice helper output
        *preload_spa(test_data, 0x257A0821),  # unpack/splice helper output
        *_write_mxr_sum(0, 0),
        *_case_banner(case),  # unpack/splice helper output
        "  LI(t1, gpa_data)",  # t1 = GPA used as HLV pointer
        "  LI(a3, 0)",  # a3 stays 0 if HLV faults
        *_enter_guest("HS", relocated=False),  # T-SBI into HS
        "  hlv.w a3, (t1)",  # asm/data line in output list
        "  nop",  # pad after the access
        *_leave_guest(),
        *_sig(test_data, case),  # unpack/splice helper output
        *twin_data(paging),  # unpack/splice helper output
    ]


def generate_xonly_mxr0_gstage_HSmode(test_data: TestData) -> list[str]:  # emitter helper generate_xonly_mxr0_gstage_HSmode
    """Output ``SvH_xonly_mxr0_gstage_HSmode-00.S``: HS ``hlv.w`` of G-stage execute-only GPA."""
    return [comment_banner("xonly_mxr0_gstage_HSmode", "SvH G-stage X-only MXR=0 stimulus"), *build_twins(test_data, _asm_xonly_gstage_hs)]  # file header + twin body


