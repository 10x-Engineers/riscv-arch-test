##################################
# priv/extensions/SvH_fault.py
#
# SvH fault family — invalid PTE / non-leaf faults for G-stage, VS-stage,
# and both stages together. Every assembly line is built in Python.
# Offline seeds under _park/svh_seed/ are reference only (not read at runtime).
# SPDX-License-Identifier: Apache-2.0
##################################

"""Invalid PTE and non-leaf faults for G-stage, VS-stage, and two-stage.

``AccessCase`` holds one numbered case: title, coverpoint, check register, and
the assembly lines for the access. ``_asm_for_cases`` prints the banner, those
lines, and a SIGUPD. medeleg/hedeleg are cleared in two-stage invalid so
faults report at M-mode (not delegated away).
"""

from __future__ import annotations  # allow list[str] / Paging without quoted forward refs

from collections.abc import Iterable  # type for a list/tuple of AccessCase
from dataclasses import dataclass  # frozen case records
from typing import Literal  # "sv32" | "sv39"

from testgen.asm.helpers import comment_banner  # file-level // banner in the .S
from testgen.data.state import TestData  # open TestChunk (SIGUPD counters)
from testgen.priv.extensions.SvHCommon import (  # shared SvH PTE / mode helpers
    CG,  # covergroup name "SvH_cg" stamped into SIGUPD helpers
    PTE_CODE_G,  # G-stage code leaf flags (U=1 X R V)
    PTE_CODE_VS,  # VS-stage code leaf flags
    PTE_DATA_G,  # G-stage R/W data leaf (U=1)
    PTE_DATA_VS,  # VS-stage R/W data leaf (U=0)
    PTE_V_ONLY,  # non-leaf pointer: V=1 only (continue walk / illegal at L0)
    enable_vs_and_g,  # write vsatp+hgatp then both HFENCEs
    set_g_data_leaf,  # rewrite only the G-stage data LEVEL0 leaf
    goto_mmode,  # RVTEST_GOTO_MMODE before SIGUPD
    goto_vs,  # RVTEST_GOTO_LOWER_MODE VSmode (VA!=PA relocate)
    fence_both_stages,  # hfence.vvma then hfence.gvma
    load_guest_va,  # LI(reg, symbol) for guest pointer
    sigupd_gpr,  # dump one GPR + bump counters + coverpoint string
    preload_spa,  # M-mode store of a known word into test_region
    build_two_stage_maps,  # full G + VS page-table setup macros
    set_va_gpa_symbols,  # .set va_* / gpa_* symbols
    set_vs_data_leaf,  # rewrite only the VS-stage data LEVEL0 leaf
    mode_names,  # ("sv32","sv32x4") or ("sv39","sv39x4")
    pte_bits,  # build "(PTE_D | …)" text from bools
    twin_data,  # .pushsection .data for one twin
    build_twins,  # Sv32 + Sv39 ifdefs; SIGUPD_COUNT = max twin
)  # end SvHCommon imports

Paging = Literal["sv32", "sv39"]  # one paging twin; only one ifdef compiles per XLEN


# --- G-stage leaf flag recipes (always U=1 when the walk should succeed) ---
G_VALID = PTE_DATA_G  # normal R/W G data leaf
G_VALID_GBIT = "(PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_G)"  # same + G=1
G_INVALID_XWR = pte_bits(d=True, a=True, u=True, x=True, w=True, r=True, v=False)  # V=0 but XWR set
G_INVALID_RW = pte_bits(d=True, a=True, u=True, w=True, r=True, v=False)  # V=0 R/W
G_INVALID_XR = pte_bits(d=True, a=True, u=True, x=True, r=True, v=False)  # V=0 X/R

# --- VS-stage leaf flag recipes ---
VS_VALID_RW = PTE_DATA_VS  # normal R/W VS data leaf
VS_VALID_XR = PTE_CODE_VS  # X+R (fetch-friendly) VS leaf
VS_INVALID_RW = pte_bits(d=True, a=True, w=True, r=True, v=False)  # V=0 R/W, U=0
VS_INVALID_XR = pte_bits(d=True, a=True, x=True, r=True, v=False)  # V=0 X/R for jalr target
VS_INVALID_XWR_U = pte_bits(d=True, a=True, u=True, x=True, w=True, r=True, v=False)  # V=0 U=1 XWR


@dataclass(frozen=True)  # immutable record so cases cannot be mutated after build
class AccessCase:  # one numbered fault/access case inside a body
    """One numbered fault/access case inside a body."""

    num: str  # printed as "Test case N:" in the .S banner
    title: str  # human title after the case number
    coverpoint: str  # SvH_cg coverpoint id for SIGUPD / testcase string
    bin_name: str  # unique bin stem; paging suffix added in _sigupd
    check_reg: int  # ABI register number to dump (13=a3, 14=a4, …)
    lines: tuple[str, ...]  # assembly lines that perform the access (no SIGUPD yet)


def _case_header(num: str, title: str, expected: str = "Expected Fault") -> list[str]:  # per-case // banner
    """Emit the per-case // header lines in the generated assembly."""
    return [  # three assembly comment lines framing the case
        "//---------------------------------------------------------------------------------------------------------------------------------",  # top rule
        f"// Test case {num}: {title} | Expected: {expected}",  # case id + title + expectation
        "//---------------------------------------------------------------------------------------------------------------------------------",  # bottom rule
    ]  # end case header list


def _sigupd(test_data: TestData, case: AccessCase, paging: Paging) -> list[str]:  # dump check_reg + coverpoint
    """Dump ``case.check_reg`` and stamp coverpoint; bin name includes paging twin."""
    # Unique bin per twin so writer data_strings labels never collide across ifdefs.
    return sigupd_gpr(  # emit SIGUPD helper lines for this case
        test_data,  # bumps sigupd_count / num_testcases on the open chunk
        case.check_reg,  # which GPR to dump
        f"{case.bin_name}_{paging}",  # e.g. sv32_v0_lw_sv32
        case.coverpoint,  # coverpoint string for Questa / SIGUPD metadata
        covergroup=CG,  # always SvH_cg
    )  # end sigupd_gpr call


def _asm_for_cases(test_data: TestData, cases: Iterable[AccessCase], paging: Paging) -> list[str]:  # emit all cases
    """Emit each ``AccessCase``: banner, stimulus lines, then SIGUPD."""
    lines: list[str] = [  # section box before the first case
        "",  # blank line before the section box
        "// --------------------------------------------------------------------------------------------------------------------------------",  # top section rule
        "//                                               Test Cases Start from here",  # section title
        "// --------------------------------------------------------------------------------------------------------------------------------",  # bottom section rule
    ]  # end section-box list
    for case in cases:  # one AccessCase at a time
        lines.extend(_case_header(case.num, case.title))  # // Test case N: …
        lines.extend(case.lines)  # PTE edit / hop / access / return
        lines.extend(_sigupd(test_data, case, paging))  # dump check_reg
        lines.append("")  # blank line between cases
    return lines  # full case stream for this twin


def _g_stage_bare_setup(paging: Paging) -> list[str]:  # vsatp Bare + hgatp ON maps
    """vsatp Bare + hgatp ON; G leaves carry U=1 for successful walks.

    Code and data GPAs are identity-friendly so VS Bare can use GPA as pointer.
    """
    _, g_mode = mode_names(paging)  # "sv32x4" or "sv39x4" for G_PTE_SETUP
    lines = [  # GPA symbols used by G maps and VS Bare pointers
        "  .set gpa_data, 0x00C002000",  # GPA of the data page (also used as VS Bare pointer)
        "  .set gpa_code, 0x80000000",  # GPA of guest code for G-stage code map
    ]  # end GPA .set lines
    if paging == "sv39":  # three-level G walk
        lines.extend(  # L2/L1 non-leaves + code superpage for Sv39x4
            [  # Sv39x4 G-stage walk for code and data
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_code, LEVEL2)",  # L2 → L1 for code
                f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {PTE_CODE_G}, gpa_code, LEVEL2)",  # code SPA
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL2)",  # L2 → L1 for data
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)",  # L1 → L0 for data
            ]  # end Sv39 G walk lines
        )  # end extend Sv39
    else:  # two-level Sv32x4 walk
        lines.extend(  # code megapage + data L1→L0 for Sv32x4
            [  # Sv32x4 G-stage walk for code and data
                f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {PTE_CODE_G}, gpa_code, LEVEL1)",  # code SPA
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)",  # L1 → L0 for data
            ]  # end Sv32 G walk lines
        )  # end extend Sv32
    lines.extend(  # leaf, enable G, fences, preload, guest pointer
        [  # shared enable + preload after the walk is built
            f"  G_PTE_SETUP({g_mode}, test_region, {G_VALID_GBIT}, gpa_data, LEVEL0)",  # initial valid G leaf (+G)
            "  csrw vsatp, x0",  # VS Bare — guest uses GPA / SPA identity
            f"  HGATP_SETUP({g_mode})",  # turn G-stage on
            *fence_both_stages(),  # publish both stage TLBs
            *preload_spa(0x257A0221),  # known word in physical test_region
            *load_guest_va("a5", "gpa_data"),  # a5 = gpa_data (VS Bare pointer)
        ]  # end enable/preload lines
    )  # end extend enable block
    return lines  # G Bare-VS setup for hgatp fault twin


def _asm_hgatp_fault(test_data: TestData, paging: Paging) -> list[str]:  # one G-fault twin body
    """One paging twin: invalid/non-leaf G PTE, VS/HS accesses, restore, ifetch, store."""
    _, g_mode = mode_names(paging)  # needed when restoring a valid leaf by hand
    cases = [  # ordered AccessCase list for this twin
        AccessCase(  # case 1: VS Bare load of V=0 G leaf
            "1",  # case number in the .S banner
            "G leaf V=0, VS Bare lw",  # title
            "cp_hgatp_invalid_pte",  # coverpoint
            f"{paging}_v0_lw",  # bin stem before _sigupd adds paging again
            13,  # dump a3 (x13)
            (  # stimulus: poison leaf, hop VS, lw, return M
                *set_g_data_leaf(paging, G_INVALID_XWR),  # rewrite G leaf to V=0
                "  hfence.gvma",  # publish G TLB change
                "  LI(a3, 0)",  # fault sentinel — stays 0 if lw traps
                "  RVTEST_TSBI_GOTO_VSMODE",  # VS Bare hop (identity)
                "  lw a3, 0(a5)",  # expect guest-page fault
                "  nop",  # retire padding after the access
                *goto_mmode(),  # back to M for SIGUPD
            ),  # end case 1 lines
        ),  # end AccessCase 1
        AccessCase(  # case 2: VS Bare load of L0 non-leaf
            "2",  # case number
            "G L0 non-leaf PTE_V only, VS Bare lw",  # title
            "cp_hgatp_nonleaf_lvl0",  # coverpoint
            f"{paging}_nonleaf_lw",  # bin stem
            14,  # dump a4
            (  # stimulus: non-leaf L0, hop VS, lw, return M
                *set_g_data_leaf(paging, PTE_V_ONLY),  # L0 looks like a non-leaf (illegal)
                "  hfence.gvma",  # publish G TLB change
                "  LI(a4, 0)",  # fault sentinel
                "  RVTEST_TSBI_GOTO_VSMODE",  # VS Bare hop
                "  lw a4, 0(a5)",  # expect fault
                "  nop",  # retire padding
                *goto_mmode(),  # back to M
            ),  # end case 2 lines
        ),  # end AccessCase 2
        AccessCase(  # case 3: HS HLV of V=0 GPA
            "3",  # case number
            "HS HLV to V=0 GPA",  # title
            "cp_hgatp_invalid_pte",  # coverpoint
            f"{paging}_hlv_v0",  # bin stem
            16,  # dump a6
            (  # stimulus: V=0 leaf, hop HS, hlv.w, return M
                *set_g_data_leaf(paging, G_INVALID_XWR),  # V=0 leaf again
                "  hfence.gvma",  # publish G TLB change
                "  RVTEST_TSBI_GOTO_SMODE",  # enter HS (identity)
                "  LI(a6, 0)",  # fault sentinel
                "  LI(t1, gpa_data)",  # HLV address = GPA
                "  hlv.w a6, (t1)",  # hypervisor load of guest PA — expect fault
                "  nop",  # retire padding
                *goto_mmode(),  # back to M
            ),  # end case 3 lines
        ),  # end AccessCase 3
        AccessCase(  # case 4: HS HSV of V=0 GPA
            "4",  # case number
            "HS HSV to V=0 GPA",  # title
            "cp_hgatp_invalid_pte",  # coverpoint
            f"{paging}_hsv_v0",  # bin stem
            18,  # dump s2
            (  # stimulus: reuse V=0 leaf, hop HS, hsv.w, return M
                "  hfence.gvma",  # leaf still V=0 from previous case
                "  RVTEST_TSBI_GOTO_SMODE",  # enter HS
                "  LI(s2, 0)",  # sentinel (HSV does not write s2 on success path)
                "  LI(t0, 0xDEADBEEF)",  # store payload
                "  LI(t1, gpa_data)",  # HSV address = GPA
                "  hsv.w t0, (t1)",  # hypervisor store — expect fault
                "  nop",  # retire padding
                *goto_mmode(),  # back to M
            ),  # end case 4 lines
        ),  # end AccessCase 4
        AccessCase(  # case 5: HS HSV of L0 non-leaf
            "5",  # case number
            "HS HSV to L0 non-leaf GPA",  # title
            "cp_hgatp_nonleaf_lvl0",  # coverpoint
            f"{paging}_hsv_nonleaf",  # bin stem
            19,  # dump s3
            (  # stimulus: non-leaf L0, hop HS, hsv.w, return M
                *set_g_data_leaf(paging, PTE_V_ONLY),  # switch leaf to non-leaf shape
                "  hfence.gvma",  # publish G TLB change
                "  RVTEST_TSBI_GOTO_SMODE",  # enter HS
                "  LI(s3, 0)",  # fault sentinel
                "  LI(t0, 0xCAFEBABE)",  # store payload
                "  LI(t1, gpa_data)",  # HSV address = GPA
                "  hsv.w t0, (t1)",  # expect fault on non-leaf L0
                "  nop",  # retire padding
                *goto_mmode(),  # back to M
            ),  # end case 5 lines
        ),  # end AccessCase 5
        AccessCase(  # case 5b: HS HLV of L0 non-leaf
            "5b",  # case number (sibling of 5)
            "HS HLV to L0 non-leaf GPA",  # title
            "cp_hgatp_nonleaf_lvl0",  # coverpoint
            f"{paging}_hlv_nonleaf",  # bin stem
            21,  # dump s5
            (  # stimulus: reuse non-leaf, hop HS, hlv.w, return M
                "  hfence.gvma",  # still non-leaf from case 5
                "  RVTEST_TSBI_GOTO_SMODE",  # enter HS
                "  LI(s5, 0)",  # fault sentinel
                "  LI(t1, gpa_data)",  # HLV address = GPA
                "  hlv.w s5, (t1)",  # expect fault
                "  nop",  # retire padding
                *goto_mmode(),  # back to M
            ),  # end case 5b lines
        ),  # end AccessCase 5b
        AccessCase(  # case 6: restore valid leaf and succeed
            "6",  # case number
            "Restore valid U=1 R/W G leaf, VS Bare lw",  # title
            "hgatp_exception_reporting",  # coverpoint
            f"{paging}_restore_lw",  # bin stem
            17,  # dump a7
            (  # stimulus: good leaf, hop VS, lw preload, return M
                f"  G_PTE_SETUP({g_mode}, test_region, {G_VALID_GBIT}, gpa_data, LEVEL0)",  # put a good leaf back
                "  hfence.gvma",  # publish restored leaf
                "  LI(a7, 0)",  # will become the preload if load succeeds
                "  RVTEST_TSBI_GOTO_VSMODE",  # VS Bare hop
                "  lw a7, 0(a5)",  # expect success (preload pattern)
                "  nop",  # retire padding
                *goto_mmode(),  # back to M
            ),  # end case 6 lines
        ),  # end AccessCase 6
        AccessCase(  # case 7: VS Bare ifetch of V=0 G leaf
            "7",  # case number
            "VS Bare jalr into V=0 G leaf GPA",  # title
            "cp_hgatp_invalid_pte",  # coverpoint
            f"{paging}_v0_ifetch",  # bin stem
            20,  # dump s4
            (  # stimulus: V=0 leaf, hop VS, jalr, return M
                *set_g_data_leaf(paging, G_INVALID_XWR),  # V=0 again for fetch
                "  hfence.gvma",  # publish G TLB change
                "  LI(s4, 0)",  # sentinel
                "  LI(a5, gpa_data)",  # jalr target = GPA of V=0 page
                "  RVTEST_TSBI_GOTO_VSMODE",  # VS Bare hop
                "  nop",  # padding before jalr
                "  jalr ra, a5, 0",  # ifetch through G — expect fault
                "  nop",  # retire padding
                *goto_mmode(),  # back to M
            ),  # end case 7 lines
        ),  # end AccessCase 7
        AccessCase(  # case 8: VS Bare store of V=0 G leaf + SPA check
            "8",  # case number
            "G leaf V=0, VS Bare sw",  # title
            "hgatp_exception_reporting",  # coverpoint
            f"{paging}_v0_sw",  # bin stem
            13,  # dump a3 — SPA readback after failed store
            (  # stimulus: V=0 leaf, hop VS, sw, SPA readback
                *set_g_data_leaf(paging, G_INVALID_XWR),  # rewrite G leaf to V=0
                "  hfence.gvma",  # publish G TLB change
                "  LI(a5, gpa_data)",  # guest pointer = GPA
                "  LI(t0, 0xDEADBEEF)",  # store payload that must NOT land
                "  RVTEST_TSBI_GOTO_VSMODE",  # VS Bare hop
                "  nop",  # padding before sw
                "  sw t0, 0(a5)",  # expect guest-page fault
                "  nop",  # retire padding
                *goto_mmode(),  # back to M
                "  la t1, test_region",  # SPA of the same page
                "  lw a3, 0(t1)",  # still the old preload if store faulted
            ),  # end case 8 lines
        ),  # end AccessCase 8
    ]  # end cases list
    return [  # setup + cases + .data for this twin
        *_g_stage_bare_setup(paging),  # maps + enable + preload + a5
        *_asm_for_cases(test_data, cases, paging),  # nine cases with SIGUPD each
        *twin_data(paging),  # .data pages for this twin
    ]  # end twin return list


def generate_hgatp_fault_VSmode(test_data: TestData) -> list[str]:  # public entry: G-stage faults
    """Output ``SvH_hgatp_fault_VSmode-00.S`` (9 SIGUPD sites per twin)."""
    return [  # banner then Sv32/Sv39 twins
        comment_banner("hgatp_fault_VSmode", "SvH directed coverpoint stimulus"),  # file // banner
        *build_twins(test_data, _asm_hgatp_fault),  # emit both paging twins
    ]  # end generate return


def _map_fetch_va(paging: Paging, flags: str) -> list[str]:  # VS leaf at va_fetch for jalr
    """VS-stage leaf at ``va_fetch`` used for jalr/ifetch invalid-PTE cases."""
    vs_mode, _ = mode_names(paging)  # "sv32" or "sv39"
    lines: list[str] = []  # accumulate VS walk to va_fetch
    if paging == "sv39":  # three-level walk down to va_fetch
        lines.extend(  # L2 and L1 non-leaves for Sv39
            [  # Sv39 VS walk for fetch VA
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_fetch, LEVEL2)",  # L2
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_fetch, LEVEL1)",  # L1
            ]  # end Sv39 fetch walk
        )  # end extend Sv39
    else:  # Sv32: one non-leaf then the leaf
        lines.append(f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_fetch, LEVEL1)")  # L1 → L0
    lines.append(f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_data, {flags}, va_fetch, LEVEL0)")  # leaf flags for jalr
    return lines  # VS map for fetch VA


def _asm_twostage_invalid(test_data: TestData, paging: Paging) -> list[str]:  # VS/G V=0 × lw/sw/jalr
    """Invalid VS or G leaf × lw/sw/jalr with medeleg/hedeleg cleared."""
    lines = [  # shared two-stage setup before the matrix
        *set_va_gpa_symbols(paging),  # .set va_code / gpa_data / …
        "  .set va_fetch, 0x008003000",  # extra VA used only as jalr target
        "  csrw medeleg, x0",  # do not delegate exceptions to S
        "  csrw hedeleg, x0",  # do not delegate to VS — traps stay at M
        *build_two_stage_maps(paging, data_pte=VS_INVALID_RW, g_data_pte=G_VALID),  # start with bad VS leaf
        *enable_vs_and_g(*mode_names(paging)),  # vsatp + hgatp + fences
        *preload_spa(0x257A0A01),  # known SPA word for store SPA checks
    ]  # end shared setup list
    # Matrix: (case#, access, which stage is V=0, dump-reg name, ABI#, store payload)
    invalid_matrix = [  # six cases: lw/sw/jalr × VS-bad or G-bad
        ("1", "lw", "vs", "a3", 13, "0"),  # VS leaf V=0, load
        ("2", "lw", "g", "a4", 14, "0"),  # G leaf V=0, load
        ("3", "sw", "vs", "a6", 16, "0xDEADBEEF"),  # VS leaf V=0, store
        ("4", "sw", "g", "a7", 17, "0xBADCAFE"),  # G leaf V=0, store
        ("5", "jalr", "vs", "s4", 20, "0"),  # VS leaf V=0, ifetch
        ("6", "jalr", "g", "s5", 21, "0"),  # G leaf V=0, ifetch
    ]  # end invalid_matrix

    cases: list[AccessCase] = []  # built AccessCase list from the matrix
    for num, access_type, pte_shape, check_name, check_reg, payload in invalid_matrix:  # one matrix row
        pte_title = "VS leaf V=0, G valid" if pte_shape == "vs" else "VS valid, G leaf V=0"  # human title stem
        cp_suffix = "x" if access_type == "jalr" else "rw"  # coverpoint ends in _x or _rw
        coverpoint = f"VM_permission_invalid_{pte_shape}_{cp_suffix}"  # e.g. VM_permission_invalid_vs_rw
        setup: list[str] = []  # PTE edits + fences before the hop
        if access_type == "jalr":  # need a fetch VA mapping
            setup.extend(_map_fetch_va(paging, VS_INVALID_XR if pte_shape == "vs" else VS_VALID_XR))  # map va_fetch
            setup.extend(  # rewrite G data leaf for this ifetch case
                set_g_data_leaf(  # G leaf edit helper
                    paging,  # which twin's LEVEL0 G leaf
                    # G leaf: V=0 only when pte_shape == "g"; else valid X/R U=1
                    pte_bits(d=True, a=True, u=True, x=True, r=True, v=pte_shape != "g"),  # V bit from stage under test
                )  # end set_g_data_leaf
            )  # end extend G leaf for jalr
        else:  # lw / sw use va_data
            setup.extend(set_vs_data_leaf(paging, VS_INVALID_RW if pte_shape == "vs" else VS_VALID_RW))  # VS leaf
            setup.extend(set_g_data_leaf(paging, G_VALID if pte_shape == "vs" else G_INVALID_RW))  # G leaf
        setup.extend(fence_both_stages())  # publish the edited leaves

        if access_type == "lw":  # guest load path
            body = [  # setup + hop + lw + return M
                *setup,  # PTE edits + fences
                *load_guest_va("a5", "va_data"),  # guest pointer
                f"  LI({check_name}, 0)",  # fault sentinel
                *goto_vs(),  # enter VS (VA relocate)
                f"  lw {check_name}, 0(a5)",  # expect fault
                "  nop",  # retire padding
                *goto_mmode(),  # back to M
            ]  # end lw body
        elif access_type == "sw":  # guest store path + SPA check
            body = [  # setup + hop + sw + SPA readback
                *setup,  # PTE edits + fences
                *load_guest_va("a5", "va_data"),  # guest pointer
                f"  LI(t0, {payload})",  # store data that must not land on fault
                *goto_vs(),  # enter VS
                "  sw t0, 0(a5)",  # expect fault
                "  nop",  # retire padding
                *goto_mmode(),  # back to M
                "  la t1, test_region",  # SPA readback
                f"  lw {check_name}, 0(t1)",  # dump SPA word into check_reg
            ]  # end sw body
        else:  # jalr
            body = [  # setup + hop + jalr + return M
                *setup,  # PTE edits + fences
                "  LI(t0, va_fetch)",  # fetch VA into t0
                f"  LI({check_name}, 0)",  # sentinel
                *goto_vs(),  # enter VS
                "  nop",  # padding before jalr
                "  jalr ra, t0, 0",  # ifetch — expect fault
                "  nop",  # retire padding
                *goto_mmode(),  # back to M
            ]  # end jalr body

        cases.append(  # record this matrix row as an AccessCase
            AccessCase(  # one numbered case from the matrix
                num,  # case number string
                f"{pte_title}, VS {access_type}",  # full title
                coverpoint,  # coverpoint id
                f"{paging}_{pte_shape}_v0_{access_type}",  # bin stem
                check_reg,  # ABI number to dump
                tuple(body),  # assembly lines for this case
            )  # end AccessCase
        )  # end append
    return [*lines, *_asm_for_cases(test_data, cases, paging), *twin_data(paging)]  # setup + cases + .data


def generate_twostage_invalid_VSmode(test_data: TestData) -> list[str]:  # public entry: two-stage invalid
    """Output ``SvH_twostage_invalid_VSmode-00.S``: invalid VS or G leaf × lw/sw/jalr."""
    return [  # banner then Sv32/Sv39 twins
        comment_banner("twostage_invalid_VSmode", "SvH directed coverpoint stimulus"),  # file // banner
        *build_twins(test_data, _asm_twostage_invalid),  # emit both paging twins
    ]  # end generate return


def _vs_only_fault_setup(paging: Paging) -> list[str]:  # VS ON, hgatp Bare, three data VAs
    """VS-stage ON, hgatp Bare: three VAs — ok / invalid / non-leaf — share test_region SPA."""
    vs_mode, _ = mode_names(paging)  # "sv32" or "sv39" for VSATP_SETUP
    lines = [  # VA symbols for ok / invalid / non-leaf / code
        "  .set va_ok,     0x008001000",  # valid VS leaf → test_region
        "  .set va_inv,    0x008002000",  # V=0 VS leaf → same SPA (should fault)
        "  .set va_nleaf,  0x008003000",  # L0 non-leaf shape → fault
        "  .set va_code,   0x90000000",  # guest code VA
    ]  # end VA .set lines
    if paging == "sv39":  # three-level VS walk
        lines.extend(  # code + save-area + data L2/L1 for Sv39
            [  # Sv39 VS walk for code and data VAs
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_code, LEVEL2)",  # code walk L2
                f"  SUPERPAGE_VS_PTE_SETUP({vs_mode}, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)",  # code SPA
                "  csrr a0, mscratch",  # save-area pointer for V_SAVE_AREA_SETUP
                "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate trap save area
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_ok, LEVEL2)",  # data walk L2
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_ok, LEVEL1)",  # data walk L1
            ]  # end Sv39 VS walk
        )  # end extend Sv39
    else:  # two-level Sv32 walk
        lines.extend(  # code + save-area + data L1 for Sv32
            [  # Sv32 VS walk for code and data VAs
                f"  SUPERPAGE_VS_PTE_SETUP({vs_mode}, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)",  # code SPA
                "  csrr a0, mscratch",  # save-area pointer for V_SAVE_AREA_SETUP
                "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate trap save area
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_ok, LEVEL1)",  # data walk L1
            ]  # end Sv32 VS walk
        )  # end extend Sv32
    lines.extend(  # three leaves + enable VS Bare-G + preload
        [  # shared leaves and enable after the walk skeleton
            f"  VS_PTE_SETUP({vs_mode}, PA, test_region, {VS_VALID_RW}, va_ok, LEVEL0)",  # good leaf
            f"  VS_PTE_SETUP({vs_mode}, PA, test_region, {VS_INVALID_XWR_U}, va_inv, LEVEL0)",  # V=0 leaf
            f"  VS_PTE_SETUP({vs_mode}, PA, test_region, {PTE_V_ONLY}, va_nleaf, LEVEL0)",  # non-leaf at L0
            f"  VSATP_SETUP({vs_mode}, PA)",  # VS leaves store PAs (hgatp Bare)
            "  csrw hgatp, x0",  # G Bare
            *fence_both_stages(),  # publish both stage TLBs
            *preload_spa(0x257A0310),  # known word for valid lw check
        ]  # end leaves/enable lines
    )  # end extend leaves block
    return lines  # VS-only fault setup for this twin


def _asm_vsatp_fault(test_data: TestData, paging: Paging) -> list[str]:  # one VS-fault twin body
    """VS-only maps: valid, V=0, and non-leaf leaves; VS and HS accesses."""
    # (case#, access, leaf kind, VA symbol, dump-reg name, ABI#, store payload)
    invalid_matrix = [  # four cases: lw/sw × invalid/nonleaf
        ("1", "lw", "invalid", "va_inv", "a3", 13, "0"),  # V=0 leaf, load
        ("2", "sw", "invalid", "va_inv", "s2", 18, "0xDEADBEEF"),  # V=0 leaf, store
        ("3", "lw", "nonleaf", "va_nleaf", "a4", 14, "0"),  # L0 non-leaf, load
        ("4", "sw", "nonleaf", "va_nleaf", "s3", 19, "0xCAFEBABE"),  # L0 non-leaf, store
    ]  # end invalid_matrix

    cases: list[AccessCase] = []  # built AccessCase list from the matrix
    for num, access_type, pte_shape, va_symbol, check_name, check_reg, payload in invalid_matrix:  # one row
        if access_type == "lw":  # guest load of bad VA
            body = [  # load path: point, sentinel, hop, lw, return
                *load_guest_va("a5", va_symbol),  # point a5 at va_inv or va_nleaf
                f"  LI({check_name}, 0)",  # fault sentinel
                *goto_vs(),  # enter VS
                f"  lw {check_name}, 0(a5)",  # expect page fault
                "  nop",  # retire padding
                *goto_mmode(),  # back to M
            ]  # end lw body
        else:  # sw
            body = [  # store path: point, sentinel, payload, hop, sw, return
                *load_guest_va("a5", va_symbol),  # point a5 at bad VA
                f"  LI({check_name}, 0)",  # fault sentinel
                f"  LI(t0, {payload})",  # store payload
                *goto_vs(),  # enter VS
                "  sw t0, 0(a5)",  # expect fault
                "  nop",  # retire padding
                *goto_mmode(),  # back to M
            ]  # end sw body
        cases.append(  # record this matrix row as an AccessCase
            AccessCase(  # one numbered VS fault case
                num,  # case number string
                f"VS {access_type} of {'V=0 leaf' if pte_shape == 'invalid' else 'L0 non-leaf'}",  # title
                "cp_vsatp_invalid_pte" if pte_shape == "invalid" else "cp_vsatp_nonleaf_lvl0",  # coverpoint
                f"{paging}_{pte_shape}_{access_type}",  # bin stem
                check_reg,  # ABI number to dump
                tuple(body),  # assembly lines
            )  # end AccessCase
        )  # end append
    cases.extend(  # cases 5–8: HS HLV/HSV, valid lw, jalr
        [  # extra AccessCase list beyond the matrix
            AccessCase(  # case 5: HS HLV with SPVP=1 on V=0 leaf
                "5",  # case number
                "HS hlv.w on V=0 leaf with SPVP=1",  # title
                "cp_vsatp_invalid_pte",  # coverpoint
                f"{paging}_hlv_spvp_v0",  # bin stem
                16,  # dump a6
                (  # set SPVP, hop HS, hlv.w, return M
                    "  LI(t0, HSTATUS_SPVP)",  # SPVP=1 → HLV uses VS-stage as supervisor
                    "  csrs hstatus, t0",  # set SPVP in hstatus
                    *load_guest_va("a5", "va_inv"),  # a5 = V=0 VA
                    "  LI(a6, 0)",  # fault sentinel
                    "  RVTEST_GOTO_LOWER_MODE HSmode",  # enter HS
                    "  hlv.w a6, (a5)",  # expect fault on V=0 VS leaf
                    "  nop",  # retire padding
                    *goto_mmode(),  # back to M
                ),  # end case 5 lines
            ),  # end AccessCase 5
            AccessCase(  # case 6: HS HSV with SPVP=1 on V=0 leaf
                "6",  # case number
                "HS hsv.w on V=0 leaf with SPVP=1",  # title
                "cp_vsatp_invalid_pte",  # coverpoint
                f"{paging}_hsv_spvp_v0",  # bin stem
                20,  # dump s4
                (  # hop HS, hsv.w, clear SPVP
                    *load_guest_va("a5", "va_inv"),  # a5 = V=0 VA
                    "  LI(s4, 0)",  # fault sentinel
                    "  LI(t0, 0xBADCAFE)",  # store payload
                    "  RVTEST_GOTO_LOWER_MODE HSmode",  # enter HS
                    "  hsv.w t0, (a5)",  # expect fault
                    "  nop",  # retire padding
                    *goto_mmode(),  # back to M
                    "  LI(t0, HSTATUS_SPVP)",  # bit mask to clear
                    "  csrc hstatus, t0",  # clear SPVP for later cases
                ),  # end case 6 lines
            ),  # end AccessCase 6
            AccessCase(  # case 7: prove allow path on valid leaf
                "7",  # case number
                "Valid leaf VS lw",  # title
                "cp_vsatp_invalid_pte",  # still under the same CP family; proves allow path
                f"{paging}_valid_lw",  # bin stem
                17,  # dump a7
                (  # hop VS, lw good VA, return M
                    *load_guest_va("a5", "va_ok"),  # good VA
                    *goto_vs(),  # enter VS
                    "  lw a7, 0(a5)",  # expect preload pattern
                    "  nop",  # retire padding
                    *goto_mmode(),  # back to M
                ),  # end case 7 lines
            ),  # end AccessCase 7
            AccessCase(  # case 8: VS ifetch of V=0 leaf
                "8",  # case number
                "VS jalr into V=0 leaf",  # title
                "cp_vsatp_invalid_pte",  # coverpoint
                f"{paging}_v0_ifetch",  # bin stem
                21,  # dump s5
                (  # hop VS, jalr into V=0 page, return M
                    *load_guest_va("a5", "va_inv"),  # a5 = V=0 VA
                    "  LI(s5, 0)",  # fault sentinel
                    *goto_vs(),  # enter VS
                    "  nop",  # padding before jalr
                    "  jalr ra, a5, 0",  # ifetch of V=0 leaf — expect fault
                    "  nop",  # retire padding
                    *goto_mmode(),  # back to M
                ),  # end case 8 lines
            ),  # end AccessCase 8
        ]  # end extra cases list
    )  # end extend cases 5–8
    return [  # setup + cases + .data for this twin
        *_vs_only_fault_setup(paging),  # three VAs + enable + preload
        *_asm_for_cases(test_data, cases, paging),  # eight cases with SIGUPD each
        *twin_data(paging),  # .data pages for this twin
    ]  # end twin return list


def generate_vsatp_fault_VSmode(test_data: TestData) -> list[str]:  # public entry: VS-stage faults
    """Output ``SvH_vsatp_fault_VSmode-00.S``: VS invalid/non-leaf plus HS HLV/HSV (8 SIGUPD)."""
    return [  # banner then Sv32/Sv39 twins
        comment_banner("vsatp_fault_VSmode", "SvH directed coverpoint stimulus"),  # file // banner
        *build_twins(test_data, _asm_vsatp_fault),  # emit both paging twins
    ]  # end generate return
