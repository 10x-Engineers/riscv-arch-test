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

from __future__ import annotations  # allow forward references in type hints
from collections.abc import Iterable  # type hint for case iterables
from dataclasses import dataclass  # frozen AccessCase record
from typing import Literal  # Paging = "sv32" | "sv39"

from testgen.asm.helpers import comment_banner, write_sigupd  # .S banner + GPR SIGUPD
from testgen.data.state import TestData  # ACT4 testcase registry
from testgen.priv.extensions.SvHCommon import (
    CG,  # covergroup name "SvH_cg"
    PTE_CODE_G,  # G-stage X+R leaf flags
    PTE_CODE_VS,  # VS-stage X+R leaf flags
    PTE_DATA_G,  # G-stage R/W data leaf flags
    PTE_DATA_VS,  # VS-stage R/W data leaf flags
    PTE_RW_S_V0,  # V=0 R/W S-mode shape (VS invalid)
    PTE_RW_U_G,  # R/W U=1 with G=1
    PTE_RW_U_V0,  # V=0 R/W U=1 (G invalid)
    PTE_V_ONLY,  # non-leaf: valid bit only
    PTE_XR_S_V0,  # V=0 X/R S-mode shape (VS invalid ifetch)
    PTE_XR_U,  # X/R U=1 (valid G/VS fetch leaf)
    PTE_XR_U_V0,  # V=0 X/R U=1 (G invalid ifetch)
    PTE_XWR_U_V0,  # V=0 U=1 XWR (VS invalid with U=1)
    build_twins,  # emit sv32 + sv39 ifdef twins
    build_two_stage_maps,  # shared VS+G page-table skeleton
    enable_vs_and_g,  # csrw vsatp/hgatp + fences
    fence_both_stages,  # sfence.vvma + hfence.gvma
    GOTO_MMODE,  # return to M after VS/HS stimulus
    GOTO_VS,  # enter VS for guest accesses
    load_guest_va,  # LI(a5, va_symbol)
    mode_names,  # (vs_mode, g_mode) string pair
    preload_spa,  # seed test_region before fault probes
    set_g_data_leaf,  # rewrite G data L0 PTE flags
    set_va_gpa_symbols,  # .set va_data / gpa_data
    set_vs_data_leaf,  # rewrite VS data L0 PTE flags
    twin_data,  # .data section for paging twin
)

Paging = Literal["sv32", "sv39"]  # one paging twin; only one ifdef compiles per XLEN


# --- G-stage leaf flag recipes (always U=1 when the walk should succeed) ---
G_VALID = PTE_DATA_G  # normal R/W G data leaf — used when G stage must succeed (twostage VS-bad)
G_VALID_GBIT = PTE_RW_U_G  # same + G=1 — hgatp restore / default G data leaf in _g_stage_bare_setup
G_INVALID_XWR = PTE_XWR_U_V0  # V=0 but XWR set — hgatp V=0 lw/sw/ifetch cases
G_INVALID_RW = PTE_RW_U_V0  # V=0 R/W — twostage G-bad lw/sw matrix
G_INVALID_XR = PTE_XR_U_V0  # V=0 X/R — reserved; fetch variants use G_INVALID_XWR or PTE_XR_U_V0

# --- VS-stage leaf flag recipes ---
VS_VALID_RW = PTE_DATA_VS  # normal R/W VS data leaf — twostage G-bad / vsatp ok path
VS_VALID_XR = PTE_CODE_VS  # X+R (fetch-friendly) VS leaf — twostage jalr when G is valid
VS_INVALID_RW = PTE_RW_S_V0  # V=0 R/W, U=0 — twostage VS-bad lw/sw + build_two_stage_maps default
VS_INVALID_XR = PTE_XR_S_V0  # V=0 X/R for jalr target — twostage VS-bad jalr at va_fetch
VS_INVALID_XWR_U = PTE_XWR_U_V0  # V=0 U=1 XWR — vsatp va_inv leaf in _vs_only_fault_setup


@dataclass(frozen=True)  # immutable case record passed into emitters
class AccessCase:
    """One numbered fault/access case inside a body."""

    num: str  # printed as "Test case N:" in the .S banner
    title: str  # human-readable case title in the // header
    coverpoint: str  # cp_* name for coverage bin
    bin_name: str  # bin stem before _sigupd adds _sv32/_sv39 suffix
    check_reg: int  # ABI register number to dump (13=a3, 14=a4, …)
    lines: tuple[str, ...]  # assembly lines that perform the access (no SIGUPD yet)


def _case_header(num: str, title: str, expected: str = "Expected Fault") -> list[str]:
    """Emit the per-case // header lines in the generated assembly."""
    return [  # three assembly comment lines framing the case
        "//---------------------------------------------------------------------------------------------------------------------------------",  # top rule
        f"// Test case {num}: {title} | Expected: {expected}",  # case id + title + expectation
        "//---------------------------------------------------------------------------------------------------------------------------------",  # bottom rule
    ]


def _sigupd(test_data: TestData, case: AccessCase, paging: Paging) -> list[str]:
    """ACT4 testcase + GPR SIGUPD; bin suffix is sv32 or sv39."""
    return [
        test_data.add_testcase(f"{case.bin_name}_{paging}", case.coverpoint, CG),  # register bin under coverpoint
        write_sigupd(case.check_reg, test_data),  # dump check_reg GPR into signature
    ]


def _asm_for_cases(test_data: TestData, cases: Iterable[AccessCase], paging: Paging) -> list[str]:
    """Emit each ``AccessCase``: banner, stimulus lines, then SIGUPD."""
    lines: list[str] = [
        "",  # blank line before case section
        "// --------------------------------------------------------------------------------------------------------------------------------",  # top section rule
        "//                                               Test Cases Start from here",  # section title
        "// --------------------------------------------------------------------------------------------------------------------------------",  # bottom section rule
    ]
    for case in cases:  # iterate every AccessCase in definition order
        lines.extend(_case_header(case.num, case.title))  # // Test case N: …
        lines.extend(case.lines)  # stimulus assembly (load/store/jalr/hlv/hsv)
        lines.extend(_sigupd(test_data, case, paging))  # add_testcase + write_sigupd
        lines.append("")  # blank line between cases
    return lines  # full case block ready to splice into twin body


def _g_stage_bare_setup(test_data: TestData, paging: Paging) -> list[str]:
    """vsatp Bare + hgatp ON; G leaves carry U=1 for successful walks.

    Code and data GPAs are identity-friendly so VS Bare can use GPA as pointer.
    """
    _, g_mode = mode_names(paging)  # "sv32x4" or "sv39x4" for G_PTE_SETUP
    lines = [  # GPA symbols used by G maps and VS Bare pointers
        "  .set gpa_data, 0x00C002000",  # guest data GPA (maps to test_region SPA)
        "  .set gpa_code, 0x80000000",  # guest code GPA (superpage target)
    ]
    if paging == "sv39":  # Sv39x4 needs L2 + L1 non-leaves
        lines.extend(  # L2/L1 non-leaves + code superpage for Sv39x4
            [  # Sv39x4 G-stage walk for code and data
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_code, LEVEL2)",  # code L2 non-leaf
                f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {PTE_CODE_G}, gpa_code, LEVEL2)",  # code superpage
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL2)",  # data L2 non-leaf
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)",  # data L1 non-leaf
            ]
        )
    else:  # Sv32x4: megapage code + one L1 for data
        lines.extend(  # code megapage + data L1→L0 for Sv32x4
            [  # Sv32x4 G-stage walk for code and data
                f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {PTE_CODE_G}, gpa_code, LEVEL1)",  # code megapage
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)",  # data L1 non-leaf
            ]
        )
    lines.extend(  # leaf, enable G, fences, preload, guest pointer
        [  # shared enable + preload after the walk is built
            f"  G_PTE_SETUP({g_mode}, test_region, {G_VALID_GBIT}, gpa_data, LEVEL0)",  # valid U=1 R/W data leaf
            "  csrw vsatp, x0",  # VS Bare — guest uses GPA / SPA identity
            f"  HGATP_SETUP({g_mode})",  # turn G-stage on
            *fence_both_stages(),  # publish page-table changes
            *preload_spa(test_data, 0x257A0221),  # known pattern at test_region SPA
            *load_guest_va("a5", "gpa_data"),  # a5 = pointer for VS Bare lw/sw
        ]
    )
    return lines  # G Bare-VS setup for hgatp fault twin


def _asm_hgatp_fault(test_data: TestData, paging: Paging) -> list[str]:
    """One paging twin: invalid/non-leaf G PTE, VS/HS accesses, restore, ifetch, store."""
    _, g_mode = mode_names(paging)  # G-stage MODE symbol for restore case 6
    cases = [  # ordered AccessCase list for this twin
        AccessCase(  # case 1: VS Bare load of V=0 G leaf
            "1",  # case number in the .S banner
            "G leaf V=0, VS Bare lw",  # title
            "cp_hgatp_invalid_pte",  # coverpoint
            f"{paging}_v0_lw",  # bin stem before _sigupd adds paging again
            13,  # dump a3 — stays 0 if lw traps
            (  # stimulus: poison leaf, hop VS, lw, return M
                *set_g_data_leaf(paging, G_INVALID_XWR),  # rewrite G L0 to V=0 XWR
                "  hfence.gvma",  # publish G TLB change
                "  LI(a3, 0)",  # fault sentinel — stays 0 if lw traps
                "  RVTEST_TSBI_GOTO_VSMODE",  # M → VS (VS Bare uses GPA in a5)
                "  lw a3, 0(a5)",  # load through G — expect guest-page fault
                "  nop",  # pipeline padding after load
                *GOTO_MMODE,  # return to M for SIGUPD
            ),
        ),
        AccessCase(  # case 2: VS Bare load of L0 non-leaf
            "2",  # case number
            "G L0 non-leaf PTE_V only, VS Bare lw",  # title
            "cp_hgatp_nonleaf_lvl0",  # coverpoint
            f"{paging}_nonleaf_lw",  # bin stem
            14,  # dump a4
            (  # stimulus: non-leaf L0, hop VS, lw, return M
                *set_g_data_leaf(paging, PTE_V_ONLY),  # L0 leaf slot holds non-leaf PTE_V
                "  hfence.gvma",  # publish G TLB change
                "  LI(a4, 0)",  # fault sentinel
                "  RVTEST_TSBI_GOTO_VSMODE",  # enter VS
                "  lw a4, 0(a5)",  # load through non-leaf — expect fault
                "  nop",  # padding
                *GOTO_MMODE,  # back to M
            ),
        ),
        AccessCase(  # case 3: HS HLV of V=0 GPA
            "3",  # case number
            "HS HLV to V=0 GPA",  # title
            "cp_hgatp_invalid_pte",  # coverpoint
            f"{paging}_hlv_v0",  # bin stem
            16,  # dump a6
            (  # stimulus: V=0 leaf, hop HS, hlv.w, return M
                *set_g_data_leaf(paging, G_INVALID_XWR),  # poison G data leaf again
                "  hfence.gvma",  # publish G TLB change
                "  RVTEST_TSBI_GOTO_SMODE",  # M → HS for hypervisor load
                "  LI(a6, 0)",  # fault sentinel
                "  LI(t1, gpa_data)",  # GPA pointer for HLV
                "  hlv.w a6, (t1)",  # hypervisor load of guest memory — expect fault
                "  nop",  # padding
                *GOTO_MMODE,  # back to M
            ),
        ),
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
                "  LI(t1, gpa_data)",  # GPA pointer
                "  hsv.w t0, (t1)",  # hypervisor store — expect guest-page fault
                "  nop",  # padding
                *GOTO_MMODE,  # back to M
            ),
        ),
        AccessCase(  # case 5: HS HSV of L0 non-leaf
            "5",  # case number
            "HS HSV to L0 non-leaf GPA",  # title
            "cp_hgatp_nonleaf_lvl0",  # coverpoint
            f"{paging}_hsv_nonleaf",  # bin stem
            19,  # dump s3
            (  # stimulus: non-leaf L0, hop HS, hsv.w, return M
                *set_g_data_leaf(paging, PTE_V_ONLY),  # non-leaf L0 shape
                "  hfence.gvma",  # publish G TLB change
                "  RVTEST_TSBI_GOTO_SMODE",  # enter HS
                "  LI(s3, 0)",  # fault sentinel
                "  LI(t0, 0xCAFEBABE)",  # store payload
                "  LI(t1, gpa_data)",  # GPA pointer
                "  hsv.w t0, (t1)",  # expect fault on non-leaf L0
                "  nop",  # padding
                *GOTO_MMODE,  # back to M
            ),
        ),
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
                "  LI(t1, gpa_data)",  # GPA pointer
                "  hlv.w s5, (t1)",  # hypervisor load — expect fault
                "  nop",  # padding
                *GOTO_MMODE,  # back to M
            ),
        ),
        AccessCase(  # case 6: restore valid leaf and succeed
            "6",  # case number
            "Restore valid U=1 R/W G leaf, VS Bare lw",  # title
            "hgatp_exception_reporting",  # coverpoint
            f"{paging}_restore_lw",  # bin stem
            17,  # dump a7
            (  # stimulus: good leaf, hop VS, lw preload, return M
                f"  G_PTE_SETUP({g_mode}, test_region, {G_VALID_GBIT}, gpa_data, LEVEL0)",  # restore valid leaf
                "  hfence.gvma",  # publish restored leaf
                "  LI(a7, 0)",  # will become the preload if load succeeds
                "  RVTEST_TSBI_GOTO_VSMODE",  # enter VS
                "  lw a7, 0(a5)",  # expect success (preload pattern 0x257A0221)
                "  nop",  # padding
                *GOTO_MMODE,  # back to M
            ),
        ),
        AccessCase(  # case 7: VS Bare ifetch of V=0 G leaf
            "7",  # case number
            "VS Bare jalr into V=0 G leaf GPA",  # title
            "cp_hgatp_invalid_pte",  # coverpoint
            f"{paging}_v0_ifetch",  # bin stem
            20,  # dump s4
            (  # stimulus: V=0 leaf, hop VS, jalr, return M
                *set_g_data_leaf(paging, G_INVALID_XWR),  # V=0 leaf for ifetch fault
                "  hfence.gvma",  # publish G TLB change
                "  LI(s4, 0)",  # sentinel — stays 0 if jalr traps
                "  LI(a5, gpa_data)",  # jalr target = GPA of V=0 page
                "  RVTEST_TSBI_GOTO_VSMODE",  # enter VS
                "  nop",  # padding before jalr
                "  jalr ra, a5, 0",  # ifetch through G — expect fault
                "  nop",  # padding after jalr
                *GOTO_MMODE,  # back to M
            ),
        ),
        AccessCase(  # case 8: VS Bare store of V=0 G leaf + SPA check
            "8",  # case number
            "G leaf V=0, VS Bare sw",  # title
            "hgatp_exception_reporting",  # coverpoint
            f"{paging}_v0_sw",  # bin stem
            13,  # dump a3 (SPA readback after fault)
            (  # stimulus: V=0 leaf, hop VS, sw, SPA readback
                *set_g_data_leaf(paging, G_INVALID_XWR),  # V=0 leaf again
                "  hfence.gvma",  # publish G TLB change
                "  LI(a5, gpa_data)",  # store target GPA
                "  LI(t0, 0xDEADBEEF)",  # store payload (must not land if fault)
                "  RVTEST_TSBI_GOTO_VSMODE",  # enter VS
                "  nop",  # padding before sw
                "  sw t0, 0(a5)",  # expect guest-page fault — SPA unchanged
                "  nop",  # padding
                *GOTO_MMODE,  # back to M
                "  la t1, test_region",  # SPA pointer for readback
                "  lw a3, 0(t1)",  # still the old preload if store faulted
            ),
        ),
    ]
    return [  # setup + cases + .data for this twin
        *_g_stage_bare_setup(test_data, paging),  # maps + enable + preload + a5
        *_asm_for_cases(test_data, cases, paging),  # nine cases with SIGUPD each
        *twin_data(paging),  # twin-specific .data
    ]


def generate_hgatp_fault_VSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_hgatp_fault_VSmode-00.S`` (9 SIGUPD sites per twin)."""
    return [
        comment_banner("hgatp_fault_VSmode", "SvH directed coverpoint stimulus"),  # file // banner
        *build_twins(test_data, _asm_hgatp_fault),  # sv32 + sv39 ifdef twins
    ]


def _map_fetch_va(paging: Paging, flags: str) -> list[str]:
    """VS-stage leaf at ``va_fetch`` used for jalr/ifetch invalid-PTE cases."""
    vs_mode, _ = mode_names(paging)  # "sv32" or "sv39" for VS_PTE_SETUP
    lines: list[str] = []  # accumulate VS walk for va_fetch
    if paging == "sv39":  # Sv39 needs L2 + L1 non-leaves
        lines.extend(  # L2 and L1 non-leaves for Sv39
            [
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_fetch, LEVEL2)",  # fetch L2
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_fetch, LEVEL1)",  # fetch L1
            ]
        )
    else:  # Sv32: single L1 non-leaf
        lines.append(f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_fetch, LEVEL1)")  # fetch L1
    lines.append(f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_data, {flags}, va_fetch, LEVEL0)")  # fetch L0 leaf (valid or V=0)
    return lines  # VS map for fetch VA


def _asm_twostage_invalid(test_data: TestData, paging: Paging) -> list[str]:
    """Invalid VS or G leaf × lw/sw/jalr with medeleg/hedeleg cleared."""
    lines = [  # shared two-stage setup before the matrix
        *set_va_gpa_symbols(paging),  # .set va_data / gpa_data
        "  .set va_fetch, 0x008003000",  # extra VA used only as jalr target
        "  csrw medeleg, x0",  # do not delegate exceptions to S
        "  csrw hedeleg, x0",  # do not delegate to VS — traps stay at M
        *build_two_stage_maps(paging, data_pte=VS_INVALID_RW, g_data_pte=G_VALID),  # default VS-bad / G-good skeleton
        *enable_vs_and_g(*mode_names(paging)),  # both stages ON
        *preload_spa(test_data, 0x257A0A01),  # seed SPA for lw readback cases
    ]
    # Matrix: (case#, access, which stage is V=0, dump-reg name, ABI#, store payload)
    invalid_matrix = [  # six cases: lw/sw/jalr × VS-bad or G-bad
        ("1", "lw", "vs", "a3", 13, "0"),  # VS leaf V=0, load — expect fault
        ("2", "lw", "g", "a4", 14, "0"),  # G leaf V=0, load — expect fault
        ("3", "sw", "vs", "a6", 16, "0xDEADBEEF"),  # VS leaf V=0, store — expect fault
        ("4", "sw", "g", "a7", 17, "0xBADCAFE"),  # G leaf V=0, store — expect fault
        ("5", "jalr", "vs", "s4", 20, "0"),  # VS leaf V=0, ifetch — expect fault
        ("6", "jalr", "g", "s5", 21, "0"),  # G leaf V=0, ifetch — expect fault
    ]

    cases: list[AccessCase] = []  # built AccessCase list from the matrix
    for num, access_type, pte_shape, check_name, check_reg, payload in invalid_matrix:  # one row per case
        pte_title = "VS leaf V=0, G valid" if pte_shape == "vs" else "VS valid, G leaf V=0"  # banner title fragment
        cp_suffix = "x" if access_type == "jalr" else "rw"  # coverpoint ends in _x or _rw
        coverpoint = f"VM_permission_invalid_{pte_shape}_{cp_suffix}"  # e.g. VM_permission_invalid_vs_rw
        setup: list[str] = []  # per-case PTE rewrite before access
        if access_type == "jalr":  # ifetch needs va_fetch map + G leaf flags
            setup.extend(_map_fetch_va(paging, VS_INVALID_XR if pte_shape == "vs" else VS_VALID_XR))  # map va_fetch
            setup.extend(
                set_g_data_leaf(
                    paging,
                    # G leaf: V=0 only when pte_shape == "g"; else valid X/R U=1
                    PTE_XR_U_V0 if pte_shape == "g" else PTE_XR_U,  # G invalid vs valid for jalr path
                )
            )
        else:  # lw/sw: rewrite data leaves on both stages
            setup.extend(set_vs_data_leaf(paging, VS_INVALID_RW if pte_shape == "vs" else VS_VALID_RW))  # VS leaf flags
            setup.extend(set_g_data_leaf(paging, G_VALID if pte_shape == "vs" else G_INVALID_RW))  # G leaf flags
        setup.extend(fence_both_stages())  # publish PTE changes

        if access_type == "lw":  # load path
            body = [  # setup + hop + lw + return M
                *setup,  # PTE rewrites + fences
                *load_guest_va("a5", "va_data"),  # guest VA pointer
                f"  LI({check_name}, 0)",  # fault sentinel
                *GOTO_VS,  # enter VS
                f"  lw {check_name}, 0(a5)",  # load — expect fault
                "  nop",  # padding
                *GOTO_MMODE,  # back to M
            ]
        elif access_type == "sw":  # store path + SPA readback
            body = [  # setup + hop + sw + SPA readback
                *setup,  # PTE rewrites + fences
                *load_guest_va("a5", "va_data"),  # guest VA pointer
                f"  LI(t0, {payload})",  # store payload
                *GOTO_VS,  # enter VS
                "  sw t0, 0(a5)",  # store — expect fault
                "  nop",  # padding
                *GOTO_MMODE,  # back to M
                "  la t1, test_region",  # SPA pointer
                f"  lw {check_name}, 0(t1)",  # read SPA — preload unchanged if store faulted
            ]
        else:  # jalr / ifetch path
            body = [  # setup + hop + jalr + return M
                *setup,  # PTE rewrites + fences
                "  LI(t0, va_fetch)",  # fetch VA into t0
                f"  LI({check_name}, 0)",  # sentinel
                *GOTO_VS,  # enter VS
                "  nop",  # padding before jalr
                "  jalr ra, t0, 0",  # ifetch — expect fault
                "  nop",  # padding
                *GOTO_MMODE,  # back to M
            ]

        cases.append(  # record this matrix row as an AccessCase
            AccessCase(  # one numbered case from the matrix
                num,  # case number string
                f"{pte_title}, VS {access_type}",  # title
                coverpoint,  # cp_* name
                f"{paging}_{pte_shape}_v0_{access_type}",  # bin stem
                check_reg,  # ABI number to dump
                tuple(body),  # assembly lines for this case
            )
        )
    return [*lines, *_asm_for_cases(test_data, cases, paging), *twin_data(paging)]  # setup + cases + .data


def generate_twostage_invalid_VSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_twostage_invalid_VSmode-00.S``: invalid VS or G leaf × lw/sw/jalr."""
    return [
        comment_banner("twostage_invalid_VSmode", "SvH directed coverpoint stimulus"),  # file // banner
        *build_twins(test_data, _asm_twostage_invalid),  # sv32 + sv39 twins
    ]


def _vs_only_fault_setup(test_data: TestData, paging: Paging) -> list[str]:
    """VS-stage ON, hgatp Bare: three VAs — ok / invalid / non-leaf — share test_region SPA."""
    vs_mode, _ = mode_names(paging)  # "sv32" or "sv39"
    lines = [  # VA symbols for ok / invalid / non-leaf / code
        "  .set va_ok,     0x008001000",  # valid VS leaf → test_region
        "  .set va_inv,    0x008002000",  # V=0 VS leaf → same SPA (should fault)
        "  .set va_nleaf,  0x008003000",  # L0 non-leaf shape → fault
        "  .set va_code,   0x90000000",  # guest code VA for trap save area
    ]
    if paging == "sv39":  # Sv39 walk skeleton
        lines.extend(  # code + save-area + data L2/L1 for Sv39
            [
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_code, LEVEL2)",  # code L2
                f"  SUPERPAGE_VS_PTE_SETUP({vs_mode}, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)",  # code superpage
                "  csrr a0, mscratch",  # M save-area pointer
                "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate trap save area
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_ok, LEVEL2)",  # data L2
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_ok, LEVEL1)",  # data L1
            ]
        )
    else:  # Sv32 walk skeleton
        lines.extend(  # code + save-area + data L1 for Sv32
            [  # Sv32 VS walk for code and data VAs
                f"  SUPERPAGE_VS_PTE_SETUP({vs_mode}, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)",  # code megapage
                "  csrr a0, mscratch",  # M save-area pointer
                "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate trap save area
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_ok, LEVEL1)",  # data L1
            ]
        )
    lines.extend(  # three leaves + enable VS Bare-G + preload
        [  # shared leaves and enable after the walk skeleton
            f"  VS_PTE_SETUP({vs_mode}, PA, test_region, {VS_VALID_RW}, va_ok, LEVEL0)",  # valid data leaf
            f"  VS_PTE_SETUP({vs_mode}, PA, test_region, {VS_INVALID_XWR_U}, va_inv, LEVEL0)",  # V=0 U=1 leaf
            f"  VS_PTE_SETUP({vs_mode}, PA, test_region, {PTE_V_ONLY}, va_nleaf, LEVEL0)",  # non-leaf L0
            f"  VSATP_SETUP({vs_mode}, PA)",  # VS leaves store PAs (hgatp Bare)
            "  csrw hgatp, x0",  # G Bare
            *fence_both_stages(),  # publish page-table changes
            *preload_spa(test_data, 0x257A0310),  # seed SPA for success/fault checks
        ]
    )
    return lines  # VS-only fault setup for this twin


def _asm_vsatp_fault(test_data: TestData, paging: Paging) -> list[str]:
    """VS-only maps: valid, V=0, and non-leaf leaves; VS and HS accesses."""
    # (case#, access, leaf kind, VA symbol, dump-reg name, ABI#, store payload)
    invalid_matrix = [  # four cases: lw/sw × invalid/nonleaf
        ("1", "lw", "invalid", "va_inv", "a3", 13, "0"),  # V=0 leaf, load — expect page fault
        ("2", "sw", "invalid", "va_inv", "s2", 18, "0xDEADBEEF"),  # V=0 leaf, store — expect fault
        ("3", "lw", "nonleaf", "va_nleaf", "a4", 14, "0"),  # L0 non-leaf, load — expect fault
        ("4", "sw", "nonleaf", "va_nleaf", "s3", 19, "0xCAFEBABE"),  # L0 non-leaf, store — expect fault
    ]

    cases: list[AccessCase] = []  # built AccessCase list from the matrix
    for num, access_type, pte_shape, va_symbol, check_name, check_reg, payload in invalid_matrix:  # matrix rows 1–4
        if access_type == "lw":  # load stimulus
            body = [  # load path: point, sentinel, hop, lw, return
                *load_guest_va("a5", va_symbol),  # a5 = VA (va_inv or va_nleaf)
                f"  LI({check_name}, 0)",  # fault sentinel
                *GOTO_VS,  # enter VS
                f"  lw {check_name}, 0(a5)",  # load — expect page fault
                "  nop",  # padding
                *GOTO_MMODE,  # back to M
            ]
        else:  # store stimulus
            body = [  # store path: point, sentinel, payload, hop, sw, return
                *load_guest_va("a5", va_symbol),  # a5 = VA
                f"  LI({check_name}, 0)",  # fault sentinel (for consistency; store uses SPA readback in some twins)
                f"  LI(t0, {payload})",  # store payload
                *GOTO_VS,  # enter VS
                "  sw t0, 0(a5)",  # store — expect fault
                "  nop",  # padding
                *GOTO_MMODE,  # back to M
            ]
        cases.append(  # record this matrix row as an AccessCase
            AccessCase(  # one numbered VS fault case
                num,  # case number string
                f"VS {access_type} of {'V=0 leaf' if pte_shape == 'invalid' else 'L0 non-leaf'}",  # title
                "cp_vsatp_invalid_pte" if pte_shape == "invalid" else "cp_vsatp_nonleaf_lvl0",  # coverpoint
                f"{paging}_{pte_shape}_{access_type}",  # bin stem
                check_reg,  # ABI number to dump
                tuple(body),  # assembly lines
            )
        )
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
                    *load_guest_va("a5", "va_inv"),  # V=0 leaf VA
                    "  LI(a6, 0)",  # fault sentinel
                    "  RVTEST_GOTO_LOWER_MODE HSmode",  # enter HS
                    "  hlv.w a6, (a5)",  # hypervisor load — expect fault on V=0 VS leaf
                    "  nop",  # padding
                    *GOTO_MMODE,  # back to M
                ),
            ),
            AccessCase(  # case 6: HS HSV with SPVP=1 on V=0 leaf
                "6",  # case number
                "HS hsv.w on V=0 leaf with SPVP=1",  # title
                "cp_vsatp_invalid_pte",  # coverpoint
                f"{paging}_hsv_spvp_v0",  # bin stem
                20,  # dump s4
                (  # hop HS, hsv.w, clear SPVP
                    *load_guest_va("a5", "va_inv"),  # V=0 leaf VA
                    "  LI(s4, 0)",  # fault sentinel
                    "  LI(t0, 0xBADCAFE)",  # store payload
                    "  RVTEST_GOTO_LOWER_MODE HSmode",  # enter HS
                    "  hsv.w t0, (a5)",  # hypervisor store — expect fault
                    "  nop",  # padding
                    *GOTO_MMODE,  # back to M
                    "  LI(t0, HSTATUS_SPVP)",  # bit mask to clear SPVP
                    "  csrc hstatus, t0",  # restore hstatus for later cases
                ),
            ),
            AccessCase(  # case 7: prove allow path on valid leaf
                "7",  # case number
                "Valid leaf VS lw",  # title
                "cp_vsatp_invalid_pte",  # still under the same CP family; proves allow path
                f"{paging}_valid_lw",  # bin stem
                17,  # dump a7
                (
                    *load_guest_va("a5", "va_ok"),  # valid leaf VA
                    *GOTO_VS,  # enter VS
                    "  lw a7, 0(a5)",  # load — expect preload pattern (success)
                    "  nop",  # padding
                    *GOTO_MMODE,  # back to M
                ),
            ),
            AccessCase(  # case 8: VS ifetch of V=0 leaf
                "8",  # case number
                "VS jalr into V=0 leaf",  # title
                "cp_vsatp_invalid_pte",  # coverpoint
                f"{paging}_v0_ifetch",  # bin stem
                21,  # dump s5
                (
                    *load_guest_va("a5", "va_inv"),  # V=0 leaf VA as jalr target
                    "  LI(s5, 0)",  # fault sentinel
                    *GOTO_VS,  # enter VS
                    "  nop",  # padding before jalr
                    "  jalr ra, a5, 0",  # ifetch of V=0 leaf — expect fault
                    "  nop",  # padding
                    *GOTO_MMODE,  # back to M
                ),
            ),
        ]
    )
    return [  # setup + cases + .data for this twin
        *_vs_only_fault_setup(test_data, paging),  # three VAs + enable + preload
        *_asm_for_cases(test_data, cases, paging),  # eight cases with SIGUPD each
        *twin_data(paging),  # twin-specific .data
    ]


def generate_vsatp_fault_VSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_vsatp_fault_VSmode-00.S``: VS invalid/non-leaf plus HS HLV/HSV (8 SIGUPD)."""
    return [
        comment_banner("vsatp_fault_VSmode", "SvH directed coverpoint stimulus"),  # file // banner
        *build_twins(test_data, _asm_vsatp_fault),  # sv32 + sv39 twins
    ]
