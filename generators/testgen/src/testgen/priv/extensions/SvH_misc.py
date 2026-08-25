##################################
# priv/extensions/SvH_misc.py
#
# SvH misc family - true Python emitters, no runtime seed I/O.
# SPDX-License-Identifier: Apache-2.0
##################################

"""HFENCE, MPRV, TVM, PTE attributes, GPA width, VSBE.

Each ``generate_*`` is one output file. ``_finish_twin_test`` wraps Sv32/Sv39 ifdefs.
``Body.sigs`` / ``Body.cases`` set ``SIGUPD_COUNT`` to max of the two twins.
"""

from __future__ import annotations  # allow Mode / list[str] without quoted forward refs

from collections.abc import Callable  # body_fn type: Mode → Body
from dataclasses import dataclass  # Body / ManualSig records
from typing import Literal  # "sv32" | "sv39"

from testgen.asm.helpers import comment_banner  # file-level // banner in the .S
from testgen.data.state import TestData  # open TestChunk (SIGUPD / testcase counters)
from testgen.priv.extensions.SvHCommon import (  # shared SvH asm helpers and PTE recipes
    PTE_CODE_G,  # G-stage code leaf (U=1 X R V)
    PTE_CODE_VS,  # VS-stage code leaf
    PTE_DATA_G,  # G-stage R/W data leaf (U=1)
    PTE_DATA_VS,  # VS-stage R/W data leaf (U=0)
    PTE_V_ONLY,  # non-leaf pointer: V=1 only
    add_sigupd_count,  # add N to sigupd_count on the open chunk
    clear_mprv,  # csrc mstatus, MSTATUS_MPRV before SIGUPD
    data_section,  # .pushsection .data helper (single-arch bodies)
    goto_hs,  # RVTEST_GOTO_LOWER_MODE HSmode / T-SBI HS hop
    goto_mmode,  # return to M before signature dumps
    goto_vs,  # enter VS (VA!=PA relocate when needed)
    fence_both_stages,  # hfence.vvma then hfence.gvma
    sigupd_labeled,  # RVTEST_SIGUPD with a label (caller bumps counts)
    mismatch_string,  # .string "Mismatch …" for the writer
    preload_spa,  # M-mode store of a known word into test_region
    build_two_stage_maps,  # full G + VS page-table macros
    set_va_gpa_symbols,  # .set va_* / gpa_* symbols
    mode_names,  # ("sv32","sv32x4") or ("sv39","sv39x4")
    pte_bits,  # build "(PTE_D | …)" from bools
    twin_data,  # .data for one twin (Sv39 adds extra table pages)
    combine_twins,  # #ifdef SV32 / SV39 wrappers
)  # end SvHCommon import

Mode = Literal["sv32", "sv39"]  # paging twin argument for body_fn

# --- Leaf flag recipes used across misc tests ---
G_RW = PTE_DATA_G  # normal G R/W U=1 leaf
G_XONLY = pte_bits(x=True, u=True)  # G execute-only U=1 (MXR / xonly paths)
G_RW_AD0 = pte_bits(w=True, r=True, u=True, a=False, d=False)  # G R/W with A=D=0
VS_RW = PTE_DATA_VS  # normal VS R/W U=0 leaf
VS_XWR = pte_bits(x=True, w=True, r=True)  # VS XWR U=0
VS_XWR_AD0 = pte_bits(x=True, w=True, r=True, a=False, d=False)  # VS XWR with A=D=0
VS_U_RW = pte_bits(w=True, r=True, u=True)  # VS R/W U=1 (U-page / SUM)

# Assembler #defines for RV64 reserved / PBMT PTE bits (vs_pte_attr / g_pte_attr Sv39).
RV64_PTE_DEFS = [  # assembler #defines for reserved/PBMT PTE bits
    "#define PTE_BIT54 (_RISCV_ULL(1) << 54)",  # reserved bit 54
    "#define PTE_BIT55 (_RISCV_ULL(1) << 55)",  # reserved bit 55
    "#define PTE_BIT56 (_RISCV_ULL(1) << 56)",  # reserved bit 56
    "#define PTE_BIT57 (_RISCV_ULL(1) << 57)",  # reserved bit 57
    "#define PTE_BIT58 (_RISCV_ULL(1) << 58)",  # reserved bit 58
    "#define PTE_BIT59 (_RISCV_ULL(1) << 59)",  # reserved bit 59
    "#define PTE_BIT60 (_RISCV_ULL(1) << 60)",  # reserved bit 60
    "#define PTE_RSVD_ALL (_RISCV_ULL(0x7F) << 54)",  # all reserved [60:54]
    "#define PTE_PBMT1 (_RISCV_ULL(1) << 61)",  # PBMT encoding 1
    "#define PTE_PBMT2 (_RISCV_ULL(1) << 62)",  # PBMT encoding 2
    "#define PTE_PBMT3 (_RISCV_ULL(3) << 61)",  # PBMT encoding 3
]  # end RV64 PTE #define list


@dataclass(frozen=True)  # immutable record for twin asm body
class Body:  # one Sv32/Sv39 twin's emitted assembly
    """One paging twin's assembly plus how many SIGUPDs / cases it contains."""

    lines: list[str]  # assembly strings for this twin
    sigs: int  # number of RVTEST_SIGUPD sites in lines
    cases: int  # number of numbered test cases (usually == sigs)


@dataclass(frozen=True)  # immutable record for twin asm body
class ManualSig:  # one SIGUPD site description
    """One SIGUPD site: label, register to dump, mismatch message text."""

    label: str  # assembly label / string stem (test1_…)
    reg: str  # GPR name to dump (a3, t2, …)
    message: str  # human mismatch string for the writer


def _section_banner(title: str) -> list[str]:  # wide // banner for a test section
    """Emit a wide // section banner in the generated .S."""
    return ["", "// " + "-" * 128, f"// {title}", "// " + "-" * 128]  # return assembled lines


def _case_header(num: str, title: str, expected: str = "Successful") -> list[str]:  # per-case // header with expected result
    """Emit a per-case // header (number, title, expected result)."""
    return ["", "//" + "-" * 128, f"// Test case {num}: {title} | Expected: {expected}", "//" + "-" * 128]  # return assembled lines


def _sigupd_manual(sig: ManualSig, mismatches: list[str]) -> list[str]:  # append mismatch string and emit SIGUPD
    """Record mismatch text and emit RVTEST_SIGUPD for ``sig.reg``."""
    mismatches.append(mismatch_string(sig.label, sig.message))  # collected for .data
    return sigupd_labeled(sig.label, sig.reg)  # does not bump counters — Body.sigs does


def _sigupd_csr_manual(label: str, csr: str, reg: str, message: str, mismatches: list[str]) -> list[str]:  # CSR-read SIGUPD plus mismatch string
    """Emit CSR-read SIGUPD macro and record its mismatch string."""
    mismatches.append(mismatch_string(label, message))  # collect mismatch text for .data
    return [f"  {label}:", f"  RVTEST_SIGUPD_CSR_READ({csr}, {reg}, {label}, {label}_str)"]  # return assembled lines


def _set_twin_counts(test_data: TestData, start_sig: int, start_cases: int, sigs: int, cases: int) -> None:  # set SIGUPD/case counters from twin size
    """Set chunk counters to start + twin size (max twin already chosen by caller)."""
    if test_data.test_chunk is None:  # should not happen under make_svh
        return  # early exit if no open chunk
    test_data.test_chunk.sigupd_count = start_sig  # rewind to start
    add_sigupd_count(test_data, sigs)  # then add this twin's SIGUPD count
    test_data.test_chunk.num_testcases = max(start_cases + cases, test_data.test_chunk.num_testcases)  # keep max case count so far


def _finish_twin_test(test_data: TestData, title: str, body_fn: Callable[[Mode], Body]) -> list[str]:  # build Sv32+Sv39 twins; SIGUPD_COUNT = max
    """Run body_fn for sv32 and sv39; SIGUPD_COUNT = max of the two Bodies."""
    start_sig = test_data.test_chunk.sigupd_count if test_data.test_chunk is not None else 0  # SIGUPD count before this test
    start_cases = test_data.test_chunk.num_testcases if test_data.test_chunk is not None else 0  # testcase count before this test
    sv32 = body_fn("sv32")  # Body for the Sv32 twin
    sv39 = body_fn("sv39")  # Body for the Sv39 twin
    _set_twin_counts(test_data, start_sig, start_cases, max(sv32.sigs, sv39.sigs), max(sv32.cases, sv39.cases))  # SIGUPD_COUNT = max of the two Bodies
    return [comment_banner(title, "SvH directed coverpoint stimulus"), *combine_twins(sv32.lines, sv39.lines)]  # banner plus twin combine


def _finish_single_test(test_data: TestData, title: str, body: Body, *, rv64_only: bool = False) -> list[str]:  # emit one Body; optional RV64-only ifdef
    """Emit one Body (no Sv32 twin). Optional ``#ifdef SV39_SUPPORTED`` wrap."""
    start_sig = test_data.test_chunk.sigupd_count if test_data.test_chunk is not None else 0  # SIGUPD count before this test
    start_cases = test_data.test_chunk.num_testcases if test_data.test_chunk is not None else 0  # testcase count before this test
    _set_twin_counts(test_data, start_sig, start_cases, body.sigs, body.cases)  # SIGUPD_COUNT = max of the two Bodies
    lines = [comment_banner(title, "SvH directed coverpoint stimulus"), *body.lines]  # banner plus this Body's asm
    if rv64_only:  # e.g. gpa_width — no RV32 twin
        return ["#ifdef SV39_SUPPORTED", *lines, "#endif  // SV39_SUPPORTED"]  # RV64-only gate around body
    return lines  # assembled asm for this twin/helper


def _g_stage_maps(paging: Mode, *, data_lbl: str = "test_region", gpa_data: str = "gpa_data") -> list[str]:  # G-stage code+data maps (vsatp Bare by caller)
    """G-stage only maps: code superpage + data leaf (vsatp left Bare by the caller)."""
    _, g_mode = mode_names(paging)  # sv32x4 / sv39x4
    code_lvl = "LEVEL2" if paging == "sv39" else "LEVEL1"  # top level for code GPA
    lines = [f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {PTE_CODE_G}, gpa_code, {code_lvl})"]  # G code/data superpage map
    if paging == "sv39":  # extra L2 non-leaf for data GPA
        lines.append(f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, {gpa_data}, LEVEL2)")  # append one map/asm line
    lines.extend(  # extend with asm lines
        [  # list of asm lines
            f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, {gpa_data}, LEVEL1)",  # L1 → L0
            f"  G_PTE_SETUP({g_mode}, {data_lbl}, {G_RW}, {gpa_data}, LEVEL0)",  # data leaf → SPA
        ]  # end list
    )  # end call
    return lines  # assembled asm for this twin/helper


def _vs_only_maps(paging: Mode, *, data_flags: str = VS_RW) -> list[str]:  # VS-stage maps with PA PPNs (hgatp Bare)
    """VS-stage maps with PA PPNs (caller keeps hgatp Bare)."""
    vs_mode, _ = mode_names(paging)  # "sv32" or "sv39"
    lines: list[str] = []  # accumulate VS map macros
    if paging == "sv39":  # three-level VS walk
        lines.extend(  # extend with asm lines
            [  # list of asm lines
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_code, LEVEL2)",  # code L2
                f"  SUPERPAGE_VS_PTE_SETUP({vs_mode}, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)",  # code SPA
                "  csrr a0, mscratch",  # save-area pointer for V_SAVE_AREA_SETUP
                "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate trap save area
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL2)",  # data L2
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)",  # data L1
                f"  VS_PTE_SETUP({vs_mode}, PA, test_region, {data_flags}, va_data, LEVEL0)",  # data leaf
            ]  # end list
        )  # end call
    else:  # two-level Sv32 walk
        lines.extend(  # extend with asm lines
            [  # list of asm lines
                f"  SUPERPAGE_VS_PTE_SETUP({vs_mode}, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)",  # VS code superpage to SPA
                "  csrr a0, mscratch",  # save-area pointer for V_SAVE_AREA_SETUP
                "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate trap save area under VA
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)",  # VS-stage PTE setup macro
                f"  VS_PTE_SETUP({vs_mode}, PA, test_region, {data_flags}, va_data, LEVEL0)",  # VS-stage PTE setup macro
            ]  # end list
        )  # end call
    lines.extend([f"  VSATP_SETUP({vs_mode}, PA)", "  csrw hgatp, x0", *fence_both_stages()])  # VS on, G Bare
    return lines  # assembled asm for this twin/helper


def _data_region(name: str = "test_region", *, dword: bool = False) -> list[str]:  # page-aligned zeroed data label
    """Emit a page-aligned data label with four zero words/dwords."""
    cell = ".dword 0" if dword else ".word 0"  # RV64 often uses dword for alignment clarity
    return [".p2align 12", f"{name}:", f"  {cell}", f"  {cell}", f"  {cell}", f"  {cell}"]  # return assembled lines


def _asm_g_adbit(paging: Mode) -> Body:  # G/VS A=D=0 fault cases then restore
    """G A/D=0 on VS-PT map then VS leaf A/D=0 — lw/sw/jalr all expect faults."""
    vs_mode, g_mode = mode_names(paging)  # vsatp MODE and hgatp MODE names
    mismatches: list[str] = []  # collected for twin_data
    lines = [  # start building asm line list
        *set_va_gpa_symbols(paging),  # .set va_* / gpa_*
        "  csrw medeleg, x0",  # keep faults at M
        "  csrw hedeleg, x0",  # no HS exception delegation
        *build_two_stage_maps(paging, data_pte=VS_XWR, g_data_pte=G_RW, with_data=True),  # baseline maps
        # G leaf covering the VS L0 table page has A=D=0 → walking VS PT should fault
        f"  G_PTE_SETUP({g_mode}, rvtest_vlvl0_pg_tbl, {G_RW_AD0}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)",  # G-stage PTE setup macro
        f"  VSATP_SETUP({vs_mode}, GPA)",  # VS leaves store GPAs
        f"  HGATP_SETUP({g_mode})",  # program hgatp MODE/PPN
        *fence_both_stages(),  # HFENCE.VVMA then HFENCE.GVMA
        "  sfence.vma",  # extra fence used by the directed seed
        *preload_spa(0x257A0251),  # M-mode store known word to SPA
        *_section_banner("Test Cases Start from here"),  # section // banner
    ]  # end list
    # Cases 1–3: fault because G cannot walk the VS page-table page (A=D=0)
    cases = [  # case tuples: num, title, regs, asm body
        ("1", "implicit G A=D=0 on VS-PT map - VS lw", "a3", "test1_impl_g_lw", ["  LI(a5, va_data)", "  LI(a3, 0)", *goto_vs(), "  lw a3, 0(a5)", "  nop", *goto_mmode()]),  # G A=D=0 VS-PT map: VS lw case
        ("2", "implicit G A=D=0 on VS-PT map - VS sw", "s3", "test2_impl_g_sw", [*fence_both_stages(), "  sfence.vma", "  LI(a5, va_data)", "  LI(t0, 0xBAD00FAD)", *goto_vs(), "  sw t0, 0(a5)", "  nop", *goto_mmode(), "  la t3, test_region", "  lw s3, 0(t3)"]),  # VS sw case under A=D=0
        ("3", "implicit G A=D=0 on VS-PT map - VS jalr", "s4", "test3_impl_g_jalr", [*fence_both_stages(), "  sfence.vma", "  LI(a5, va_data)", "  LI(s4, 0)", *goto_vs(), "  nop", "  jalr ra, a5, 0", "  nop", *goto_mmode()]),  # G A=D=0 VS-PT map: VS jalr case
    ]  # end list
    for num, title, reg, label, body in cases:  # emit cases 1–3 fault headers + SIGUPD
        lines.extend(_case_header(num, title, "Expected Fault"))  # case // header
        lines.extend(body)  # case stimulus asm
        lines.extend(_sigupd_manual(ManualSig(label, reg, f"Mismatch on {title}"), mismatches))  # SIGUPD + mismatch string
    # Restore G leaf A=D=1; set VS data leaf A=D=0 for cases 4–6
    lines.extend([f"  G_PTE_SETUP({g_mode}, rvtest_vlvl0_pg_tbl, {G_RW}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)", f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_data, {VS_XWR_AD0}, va_data, LEVEL0)", *fence_both_stages(), "  sfence.vma"])  # restore G A=D=1; set VS leaf A=D=0
    cases2 = [  # case tuples: num, title, regs, asm body
        ("4", "VS leaf A=D=00 - VS lw", "a4", "test4_vs_ad00_lw", ["  LI(a5, va_data)", "  LI(a4, 0)", *goto_vs(), "  lw a4, 0(a5)", "  nop", *goto_mmode()]),  # VS leaf A=D=0: VS lw case
        ("5", "VS leaf A=D=00 - VS sw", "s3", "test5_vs_ad00_sw", [*fence_both_stages(), "  sfence.vma", "  LI(a5, va_data)", "  LI(t0, 0xBAD00FAD)", *goto_vs(), "  sw t0, 0(a5)", "  nop", *goto_mmode(), "  la t3, test_region", "  lw s3, 0(t3)"]),  # VS sw case under A=D=0
        ("6", "VS leaf A=D=00 - VS jalr", "s5", "test6_vs_ad00_jalr", [*fence_both_stages(), "  sfence.vma", "  LI(a5, va_data)", "  LI(s5, 0)", *goto_vs(), "  nop", "  jalr ra, a5, 0", "  nop", *goto_mmode()]),  # VS leaf A=D=0: VS jalr case
    ]  # end list
    for num, title, reg, label, body in cases2:  # emit cases 4–6 fault headers + SIGUPD
        lines.extend(_case_header(num, title, "Expected Fault"))  # case // header
        lines.extend(body)  # case stimulus asm
        lines.extend(_sigupd_manual(ManualSig(label, reg, f"Mismatch on {title}"), mismatches))  # SIGUPD + mismatch string
    lines.extend(twin_data(paging, mismatch_strings=mismatches))  # twin .data with mismatch strings
    return Body(lines, 6, 6)  # six SIGUPDs, six cases


def generate_g_adbit_VSmode(test_data: TestData) -> list[str]:  # entry: g_adbit_VSmode twin test
    """Output ``SvH_g_adbit_VSmode-00.S``: G/VS A=D=0 faults, then A=D=1 success."""
    return _finish_twin_test(test_data, "g_adbit_VSmode", _asm_g_adbit)  # Sv32/Sv39 twin wrap


def _asm_g_pte_attr_sv32() -> Body:  # Sv32 G leaf RSW HLV/HSV cases
    mismatches: list[str] = []  # mismatch strings for .data
    lines = ["  .set gpa_data, 0x00C002000", "  .set gpa_code, 0x80000000", *_g_stage_maps("sv32"), "  csrw vsatp, x0", "  HGATP_SETUP(sv32x4)", *fence_both_stages(), *preload_spa(0x257A0210), "  LI(t1, gpa_data)", *_section_banner("Test Cases Start from here")]  # GPA symbols + G maps + Bare VS + preload
    for idx, (rsw, reg) in enumerate([("0", "a3"), ("0x100", "a4"), ("0x200", "a6"), ("PTE_SOFT", "a7")], 1):  # four RSW encodings for G leaf
        payload = 0x257A0210 + idx - 1  # unique store pattern per RSW
        label = f"test{idx}_rsw{idx - 1:02b}"  # SIGUPD label for this RSW
        lines.extend(_case_header(str(idx), f"G leaf RSW={idx - 1:02b} HS HLV+HSV"))  # case // header
        lines.extend([f"  G_PTE_SETUP(sv32x4, test_region, ({G_RW} | {rsw}), gpa_data, LEVEL0)", "  hfence.gvma", *goto_hs(), f"  LI(t0, {hex(payload)})", "  LI(t1, gpa_data)", "  hsv.w t0, (t1)", "  nop", "  hfence.gvma", f"  hlv.w {reg}, (t1)", "  nop", *goto_mmode()])  # rewrite G leaf, HFENCE.GVMA, HS HSV+HLV
        lines.extend(_sigupd_manual(ManualSig(label, reg, f"Mismatch on HS HLV/HSV with G RSW={idx - 1:02b}"), mismatches))  # SIGUPD + mismatch string
    lines.extend(twin_data("sv32", mismatch_strings=mismatches))  # twin .data with mismatch strings
    return Body(lines, 4, 4)  # pack lines + SIGUPD/case counts


def _g_attr_hs_case(label: str, reg: str, flags: str, value: int, msg: str) -> tuple[list[str], ManualSig]:  # one HS HLV+HSV case for a G leaf flag mix
    return ([f"  G_PTE_SETUP(sv39x4, test_region, {flags}, gpa_data, LEVEL0)", "  hfence.gvma", *goto_hs(), f"  LI(t0, {hex(value)})", "  LI(t1, gpa_data)", "  hsv.w t0, (t1)", "  nop", "  hfence.gvma", f"  LI({reg}, 0)", f"  hlv.w {reg}, (t1)", "  nop", *goto_mmode()], ManualSig(label, reg, msg))  # rewrite G leaf, HFENCE.GVMA, HS HSV+HLV


def _asm_g_pte_attr_sv39() -> Body:  # Sv39 G RSW/reserved/PBMT HLV/HSV cases
    mismatches: list[str] = []  # mismatch strings for .data
    lines = [*RV64_PTE_DEFS, "  .set gpa_data, 0x0000000000C002000", "  .set gpa_code, 0x0000000080000000", *_g_stage_maps("sv39"), "  csrw vsatp, x0", "  csrw satp, x0", "  HGATP_SETUP(sv39x4)", *fence_both_stages(), *preload_spa(0x257A0240), "  LI(t1, gpa_data)", *_section_banner("Test Cases Start from here")]  # PTE #defines + G maps + Bare VS + preload
    for num, name, bit, reg, value in [("1", "00", "0", "a3", 0x257A0240), ("2", "11", "PTE_SOFT", "a6", 0x257A0241), ("2b", "01", "0x100", "a4", 0x257A0242), ("2c", "10", "0x200", "a5", 0x257A0243)]:  # G RSW HLV/HSV success cases
        lines.extend(_case_header(num, f"G leaf RSW={name} HS HSV+HLV"))  # case // header
        body, sig = _g_attr_hs_case(f"test{num}_rsw{name}", reg, f"({G_RW} | {bit})", value, f"Mismatch on G RSW={name}")  # asm + ManualSig for this flag mix
        lines.extend(body)  # case stimulus asm
        lines.extend(_sigupd_manual(sig, mismatches))  # SIGUPD + mismatch string
    for num, bit, reg in [("3a", "PTE_BIT54", "a4"), ("3b", "PTE_BIT55", "a6"), ("3c", "PTE_BIT56", "a7"), ("3d", "PTE_BIT57", "s2"), ("3e", "PTE_BIT58", "s3"), ("3f", "PTE_BIT59", "s4"), ("3g", "PTE_BIT60", "s5"), ("3h", "PTE_RSVD_ALL", "s6")]:  # walk reserved or PBMT encodings
        lines.extend(_case_header(num, f"G reserved {bit} HS HLV+HSV", "Expected Fault"))  # case // header
        body, sig = _g_attr_hs_case(f"test{num}_{bit.lower()}", reg, f"({G_RW} | {bit})", 0x257A02C1, f"Mismatch on G reserved {bit}")  # asm + ManualSig for this flag mix
        lines.extend(body)  # case stimulus asm
        lines.extend(_sigupd_manual(sig, mismatches))  # SIGUPD + mismatch string
    lines.extend(["  LI(t0, MENVCFG_PBMTE)", "  csrs menvcfg, t0"])  # toggle PBMTE in menvcfg/henvcfg
    for num, bit, reg in [("4a", "PTE_PBMT1", "a7"), ("4b", "PTE_PBMT2", "s7"), ("4c", "PTE_PBMT3", "s8")]:  # walk reserved or PBMT encodings
        lines.extend(_case_header(num, f"G {bit} PBMTE=1 HS HLV+HSV"))  # case // header
        body, sig = _g_attr_hs_case(f"test{num}_{bit.lower()}", reg, f"({G_RW} | {bit})", 0x257A0244, f"Mismatch on G {bit} PBMTE=1")  # asm + ManualSig for this flag mix
        lines.extend(body)  # case stimulus asm
        lines.extend(_sigupd_manual(sig, mismatches))  # SIGUPD + mismatch string
    lines.extend(["  LI(t0, MENVCFG_PBMTE)", "  csrc menvcfg, t0"])  # toggle PBMTE in menvcfg/henvcfg
    for num, bit, reg in [("4d", "PTE_PBMT1", "s9"), ("4e", "PTE_PBMT2", "s10"), ("4f", "PTE_PBMT3", "s11")]:  # walk reserved or PBMT encodings
        lines.extend(_case_header(num, f"G {bit} PBMTE=0 HS HLV+HSV", "Expected Fault"))  # case // header
        body, sig = _g_attr_hs_case(f"test{num}_{bit.lower()}_nosup", reg, f"({G_RW} | {bit})", 0xDEADBEEF, f"Mismatch on G {bit} PBMTE=0")  # asm + ManualSig for this flag mix
        lines.extend(body)  # case stimulus asm
        lines.extend(_sigupd_manual(sig, mismatches))  # SIGUPD + mismatch string
    lines.extend(_case_header("5", "Restore valid G leaf HS HLV"))  # case // header
    lines.extend([f"  G_PTE_SETUP(sv39x4, test_region, {G_RW}, gpa_data, LEVEL0)", *preload_spa(0x257A0241), "  hfence.gvma", *goto_hs(), "  LI(s2, 0)", "  LI(t1, gpa_data)", "  hlv.w s2, (t1)", "  nop", *goto_mmode()])  # restore valid G leaf then HS HLV
    lines.extend(_sigupd_manual(ManualSig("test5_restore", "s2", "Mismatch on restored G leaf HLV"), mismatches))  # SIGUPD + mismatch string
    lines.extend(twin_data("sv39", mismatch_strings=mismatches))  # twin .data with mismatch strings
    return Body(lines, 20, 20)  # pack lines + SIGUPD/case counts


def generate_g_pte_attr_VSmode(test_data: TestData) -> list[str]:  # entry: g_pte_attr twin test
    """Output ``SvH_g_pte_attr_VSmode-00.S``: HS HLV/HSV on G RSW, reserved, and PBMT bits."""
    return _finish_twin_test(test_data, "g_pte_attr_VSmode", lambda p: _asm_g_pte_attr_sv32() if p == "sv32" else _asm_g_pte_attr_sv39())  # Sv32/Sv39 twin wrap


def _asm_g_struct(paging: Mode) -> Body:  # misaligned G superpage then valid 4KiB leaf
    mismatches: list[str] = []  # mismatch strings for .data
    _, g_mode = mode_names(paging)  # G-stage MODE name only
    data_gpa = "0x00000000C0000000" if paging == "sv39" else "0x00C000000"  # data GPA for this twin
    code_gpa = "0x0000000080000000" if paging == "sv39" else "0x80000000"  # code GPA for this twin
    top_lvl = "LEVEL2" if paging == "sv39" else "LEVEL1"  # superpage level for this twin
    load = "hlv.d" if paging == "sv39" else "hlv.w"  # asm: HLV (ignores MPRV)
    value = 0x257A0D12 if paging == "sv39" else 0x257A0D02  # preload pattern for this twin
    lines = [f"  .set gpa_data, {data_gpa}", f"  .set gpa_code, {code_gpa}", f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {PTE_CODE_G}, gpa_code, {top_lvl})", f"  SUPERPAGE_G_PTE_SETUP({g_mode}, test_region, {G_RW}, gpa_data, {top_lvl})", "  csrw vsatp, x0", f"  HGATP_SETUP({g_mode})", "  hfence.gvma", *preload_spa(value), *_section_banner("Test Cases Start from here"), *_case_header("1", f"Misaligned {top_lvl} G superpage HS HLV", "Expected Fault"), "  LI(t1, gpa_data)", "  LI(a3, 0)", *goto_hs(), f"  {load} a3, (t1)", "  nop", *goto_mmode(), *_sigupd_manual(ManualSig("test1_misalign", "a3", "Mismatch on misaligned G superpage HLV"), mismatches), *_case_header("2", "Valid 4KiB leaf plus HFENCE.GVMA HS HLV")]  # G superpages + misaligned HLV case start
    if paging == "sv39":  # Sv39 needs an extra table level
        lines.append(f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL2)")  # append one map/asm line
    lines.extend([f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)", f"  G_PTE_SETUP({g_mode}, test_region, {G_RW}, gpa_data, LEVEL0)", f"  HGATP_SETUP({g_mode})", *goto_hs(), "  hfence.gvma", "  LI(t1, gpa_data)", f"  {load} a4, (t1)", "  nop", *goto_mmode(), *_sigupd_manual(ManualSig("test2_ok", "a4", "Mismatch on restored G leaf HLV"), mismatches), *twin_data(paging, mismatch_strings=mismatches)])  # rewrite leaf PTE then fence/stimulus
    return Body(lines, 2, 2)  # pack lines + SIGUPD/case counts


def generate_g_struct_HSmode(test_data: TestData) -> list[str]:  # entry: g_struct twin test
    """Output ``SvH_g_struct_HSmode-00.S``: misaligned G superpage, then valid 4KiB leaf."""
    return _finish_twin_test(test_data, "g_struct_HSmode", _asm_g_struct)  # Sv32/Sv39 twin wrap


def _asm_gpa_width() -> Body:  # canonical vs non-canonical GPA (RV64)
    mismatches: list[str] = []  # mismatch strings for .data
    lines = ["  .set gpa_ok,   0x00000000C002000", "  .set gpa_wide, 0x00000200C002000", "  .set gpa_code, 0x0000000080000000", f"  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, {PTE_CODE_G}, gpa_code, LEVEL2)", "  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_ok, LEVEL2)", "  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_ok, LEVEL1)", f"  G_PTE_SETUP(sv39x4, test_region, {G_RW}, gpa_ok, LEVEL0)", "  csrw vsatp, x0", "  HGATP_SETUP(sv39x4)", "  hfence.gvma", *preload_spa(0x257A0E02), *_section_banner("Test Cases Start from here")]  # canonical/wide GPA maps + preload
    cases = [  # case tuples: num, title, regs, asm body
        ("1", "non-canonical GPA ld", "a3", "test1_wide", ["  LI(a5, gpa_wide)", "  LI(a3, 0)", "  RVTEST_TSBI_GOTO_VSMODE", "  ld a3, 0(a5)", "  nop", *goto_mmode()], "Expected Fault"),  # non-canonical GPA ld case
        ("2", "canonical GPA ld", "a4", "test2_ok", ["  LI(a5, gpa_ok)", "  RVTEST_TSBI_GOTO_VSMODE", "  ld a4, 0(a5)", "  nop", *goto_mmode()], "Successful"),  # canonical GPA ld case
        ("3", "non-canonical GPA sd", "a6", "test3_wide_sw", ["  LI(a5, gpa_wide)", "  LI(t0, 0xBAD00FAD)", "  RVTEST_TSBI_GOTO_VSMODE", "  sd t0, 0(a5)", "  nop", *goto_mmode(), "  la t1, test_region", "  ld a6, 0(t1)"], "Expected Fault"),  # non-canonical GPA sd + SPA check case
    ]  # end list
    for num, title, reg, label, body, expected in cases:  # emit each case header, body, SIGUPD
        lines.extend(_case_header(num, title, expected))  # case // header
        lines.extend(body)  # case stimulus asm
        lines.extend(_sigupd_manual(ManualSig(label, reg, f"Mismatch on {title}"), mismatches))  # SIGUPD + mismatch string
    lines.extend(data_section(need_vlvl0=False, need_hlvl1=True, need_test_region=True, mismatch_strings=mismatches))  # .data section for this emitter
    return Body(lines, 3, 3)  # pack lines + SIGUPD/case counts


def generate_gpa_width_VSmode(test_data: TestData) -> list[str]:  # entry: gpa_width RV64-only test
    """Output ``SvH_gpa_width_VSmode-00.S`` (RV64): canonical vs non-canonical GPA."""
    return _finish_single_test(test_data, "gpa_width_VSmode", _asm_gpa_width(), rv64_only=True)  # single-body wrap (no Sv32 twin)


def _asm_hfence_gvma_mode(paging: Mode) -> Body:  # HFENCE.GVMA after Bare↔paged hgatp
    mismatches: list[str] = []  # mismatch strings for .data
    _, g_mode = mode_names(paging)  # G-stage MODE name only
    vmid_shift = "44" if paging == "sv39" else "22"  # VMID field bit position in hgatp
    lines = ["  .set gpa_data, 0x00C002000", f"  .set gpa_code, {'0x0000000080000000' if paging == 'sv39' else '0x80000000'}", *_g_stage_maps(paging), "  csrw vsatp, x0", "  csrw hgatp, x0", "  hfence.gvma", *preload_spa(0x257A0911), *_section_banner("Test Cases Start from here"), *_case_header("1", f"hgatp Bare to {g_mode} plus HFENCE.GVMA x0,a6; HS HLV"), f"  HGATP_SETUP({g_mode})", "  csrr t0, hgatp", "  LI(t1, 1)", f"  slli t1, t1, {vmid_shift}", "  or t0, t0, t1", "  csrw hgatp, t0", *goto_hs(), "  LI(a6, 1)", "  hfence.gvma x0, a6", "  LI(t1, gpa_data)", "  hlv.w a3, (t1)", "  nop", *goto_mmode(), *_sigupd_manual(ManualSig("test1_bare_to_paged", "a3", "Mismatch on Bare to Paged HFENCE.GVMA HLV"), mismatches), *_case_header("2", f"hgatp {g_mode} to Bare plus HFENCE.GVMA; HS HLV of SPA"), *preload_spa(0x257A0912), "  csrw hgatp, x0", *goto_hs(), "  hfence.gvma", "  la t1, test_region", "  hlv.w a3, (t1)", "  nop", *goto_mmode(), *_sigupd_manual(ManualSig("test2_paged_to_bare", "a3", "Mismatch on Paged to Bare HFENCE.GVMA HLV"), mismatches), *twin_data(paging, mismatch_strings=mismatches)]  # Bare↔paged hgatp + HFENCE.GVMA + HS HLV cases
    return Body(lines, 2, 2)  # pack lines + SIGUPD/case counts


def generate_hfence_gvma_mode_HSmode(test_data: TestData) -> list[str]:  # entry: hfence_gvma_mode twin
    """Output ``SvH_hfence_gvma_mode_HSmode-00.S``: HFENCE.GVMA after Bare↔paged hgatp."""
    return _finish_twin_test(test_data, "hfence_gvma_mode_HSmode", _asm_hfence_gvma_mode)  # Sv32/Sv39 twin wrap


def _asm_hfence_gvma_ops(paging: Mode) -> Body:  # HFENCE.GVMA rs1/rs2 encodings then HLV
    mismatches: list[str] = []  # mismatch strings for .data
    _, g_mode = mode_names(paging)  # G-stage MODE name only
    vmid_shift = "44" if paging == "sv39" else "22"  # VMID field bit position in hgatp
    lines = ["  .set gpa_data, 0x00C002000", f"  .set gpa_code, {'0x0000000080000000' if paging == 'sv39' else '0x80000000'}", *_g_stage_maps(paging), "  csrw vsatp, x0", f"  HGATP_SETUP({g_mode})", "  csrr t0, hgatp", "  LI(t1, 1)", f"  slli t1, t1, {vmid_shift}", "  or t0, t0, t1", "  csrw hgatp, t0", *preload_spa(0x257A0921), "  LI(a5, gpa_data)", "  LI(a6, 1)", *_section_banner("Test Cases Start from here")]  # GPA symbols + G maps + Bare VS + preload
    for num, op, value, label in [("1", "hfence.gvma a5, x0", 0x257A0921, "test1_gpa"), ("2", "hfence.gvma x0, a6", 0x257A0922, "test2_vmid"), ("3", "hfence.gvma a5, a6", 0x257A0923, "test3_both")]:  # HFENCE.GVMA GPA/VMID/both encodings
        lines.extend(_case_header(num, f"{op} then HLV"))  # case // header
        if num != "1":  # reload SPA / pointers for later cases
            lines.extend(preload_spa(value))  # store known word into SPA
            lines.extend(["  LI(a5, gpa_data)", "  LI(a6, 1)"])  # reload GPA pointer and VMID=1
        lines.extend([*goto_hs(), f"  {op}", "  hlv.w a3, (a5)", "  nop", *goto_mmode()])  # asm: HLV (ignores MPRV)
        lines.extend(_sigupd_manual(ManualSig(label, "a3", f"Mismatch on {op} HLV"), mismatches))  # SIGUPD + mismatch string
    lines.extend(twin_data(paging, mismatch_strings=mismatches))  # twin .data with mismatch strings
    return Body(lines, 3, 3)  # pack lines + SIGUPD/case counts


def generate_hfence_gvma_ops_HSmode(test_data: TestData) -> list[str]:  # entry: hfence_gvma_ops twin
    """Output ``SvH_hfence_gvma_ops_HSmode-00.S``: HFENCE.GVMA (rs1,rs2) encodings then HLV."""
    return _finish_twin_test(test_data, "hfence_gvma_ops_HSmode", _asm_hfence_gvma_ops)  # Sv32/Sv39 twin wrap


def _asm_hfence_vvma(paging: Mode) -> Body:  # HFENCE.VVMA variants then VS load
    mismatches: list[str] = []  # mismatch strings for .data
    asid_shift = "44" if paging == "sv39" else "22"  # ASID field bit position in vsatp
    lines = [*set_va_gpa_symbols(paging), *_vs_only_maps(paging), *preload_spa(0x257A0901), *_section_banner("Test Cases Start from here")]  # VA/GPA symbols + VS maps + preload banner
    cases = [  # case tuples: num, title, regs, asm body
        ("1", "hfence.vvma", 0x257A0901, "test1_all", ["  RVTEST_TSBI_GOTO_SMODE", "  hfence.vvma", *goto_mmode(), "  LI(a5, va_data)"]),  # HFENCE.VVMA variant then VS lw prep
        ("2", "hfence.vvma a5, x0", 0x257A0902, "test2_gva", ["  LI(a5, va_data)", "  RVTEST_TSBI_GOTO_SMODE", "  hfence.vvma a5, x0", *goto_mmode()]),  # HFENCE.VVMA variant then VS lw prep
        ("3", "hfence.vvma x0, a6 and a5,a6", 0x257A0903, "test3_asid", ["  LI(a5, va_data)", "  csrr t0, vsatp", "  LI(t1, 1)", f"  slli t1, t1, {asid_shift}", "  or t0, t0, t1", "  csrw vsatp, t0", "  LI(a6, 1)", "  RVTEST_TSBI_GOTO_SMODE", "  hfence.vvma x0, a6", "  hfence.vvma a5, a6", *goto_mmode()]),  # HFENCE.VVMA variant then VS lw prep
    ]  # end list
    for num, op, value, label, prep in cases:  # each HFENCE.VVMA variant then VS lw
        lines.extend(_case_header(num, f"{op} then VS lw"))  # case // header
        if num != "1":  # reload SPA / pointers for later cases
            lines.extend(preload_spa(value))  # store known word into SPA
        lines.extend([*prep, *goto_vs(), "  lw a3, 0(a5)", "  nop", *goto_mmode()])  # asm: load via guest VA
        lines.extend(_sigupd_manual(ManualSig(label, "a3", f"Mismatch on {op} VS lw"), mismatches))  # SIGUPD + mismatch string
    lines.extend(twin_data(paging, mismatch_strings=mismatches))  # twin .data with mismatch strings
    return Body(lines, 3, 3)  # pack lines + SIGUPD/case counts


def generate_hfence_vvma_HSmode(test_data: TestData) -> list[str]:  # entry: hfence_vvma twin
    """Output ``SvH_hfence_vvma_HSmode-00.S``: HFENCE.VVMA variants then VS load."""
    return _finish_twin_test(test_data, "hfence_vvma_HSmode", _asm_hfence_vvma)  # Sv32/Sv39 twin wrap


def _mpv_mask(paging: Mode) -> str:  # MSTATUS_MPV or MSTATUSH_MPV by XLEN
    return "MSTATUS_MPV" if paging == "sv39" else "MSTATUSH_MPV"  # CSR/bit-mask name for this twin


def _mpv_csr(paging: Mode) -> str:  # mstatus or mstatush holding MPV
    return "mstatus" if paging == "sv39" else "mstatush"  # CSR/bit-mask name for this twin


def _asm_mprv_hgatp(paging: Mode) -> Body:  # MPRV+MPP+MPV with G-stage maps
    mismatches: list[str] = []  # mismatch strings for .data
    _, g_mode = mode_names(paging)  # G-stage MODE name only
    lines = [f"  .set gpa_xonly, {'0x0000000000C002000' if paging == 'sv39' else '0x00C002000'}", f"  .set gpa_rw,    {'0x0000000000C003000' if paging == 'sv39' else '0x00C003000'}"]  # xonly and R/W GPA symbols
    for gpa, region, flags in [("gpa_xonly", "test_region_x", G_XONLY), ("gpa_rw", "test_region_rw", G_RW)]:  # map each GPA to its SPA leaf
        if paging == "sv39":  # Sv39 needs an extra table level
            lines.extend([f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, {gpa}, LEVEL2)", f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, {gpa}, LEVEL1)"])  # rewrite leaf PTE then fence/stimulus
        else:  # Sv32 two-level walk
            lines.append(f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, {gpa}, LEVEL1)")  # append one map/asm line
        lines.append(f"  G_PTE_SETUP({g_mode}, {region}, {flags}, {gpa}, LEVEL0)")  # append one map/asm line
    lines.extend(["  csrw vsatp, x0", "  csrw satp, x0", f"  HGATP_SETUP({g_mode})", *fence_both_stages(), *preload_spa(0x257A0151, dest="test_region_x"), *preload_spa(0x257A0152, dest="test_region_rw"), *_section_banner("Test Cases Start from here")])  # enable paging / fences / more maps
    # Seed keeps MPRV set across cases 2-6; only clear at end of case 7.
    mpv = _mpv_mask(paging)  # MPV bit mask for this XLEN
    mpv_csr = _mpv_csr(paging)  # CSR that holds MPV
    cases = [  # case tuples: num, title, regs, asm body
        ("1", "Direct SPA lw baseline", "a3", "test1_spa", ["  la t1, test_region_x", "  lw a3, 0(t1)"], False),  # asm: SPA of physical page
        (  # case tuple start
            "2",  # case number
            "MPRV=1 MPP=M lw of SPA",  # case title
            "a4",  # SIGUPD register
            "test2_m",  # SIGUPD label
            [  # list of asm lines
                "  LI(t0, MSTATUS_MPP)",  # asm: MPP field mask
                "  csrc mstatus, t0",  # asm: clear mstatus bits in t0
                "  LI(t0, MPP_MMODE)",  # asm: MPP = Machine
                "  csrs mstatus, t0",  # asm: set mstatus bits from t0
                f"  LI(t0, {mpv})",  # asm: MPV bitmask into t0
                f"  csrc {mpv_csr}, t0",  # asm: clear MPV
                "  LI(t0, MSTATUS_MPRV)",  # asm: MPRV bit mask
                "  csrs mstatus, t0",  # asm: set mstatus bits from t0
                "  LI(a4, 0)",  # asm: zero result before access
                "  la t1, test_region_x",  # asm: SPA of physical page
                "  lw a4, 0(t1)",  # asm: SPA/MPRV load
                "  nop",  # asm: nop padding
            ],  # end asm body list
            False,  # leave MPRV set across cases
        ),  # end case tuple
        (  # case tuple start
            "3",  # case number
            "MPRV=1 MPP=S MPV=0 lw of SPA",  # case title
            "a5",  # SIGUPD register
            "test3_hs",  # SIGUPD label
            [  # list of asm lines
                "  LI(t0, MSTATUS_MPP)",  # asm: MPP field mask
                "  csrc mstatus, t0",  # asm: clear mstatus bits in t0
                "  LI(t0, MPP_SMODE)",  # asm: MPP = Supervisor
                "  csrs mstatus, t0",  # asm: set mstatus bits from t0
                "  LI(a5, 0)",  # asm: zero result before access
                "  la t1, test_region_x",  # asm: SPA of physical page
                "  lw a5, 0(t1)",  # asm: SPA/MPRV load
                "  nop",  # asm: nop padding
            ],  # end asm body list
            False,  # leave MPRV set across cases
        ),  # end case tuple
        (  # case tuple start
            "4",  # case number
            "MPRV=1 MPP=S MPV=1 lw of X-only GPA",  # case title
            "a6",  # SIGUPD register
            "test4_vs",  # SIGUPD label
            [  # list of asm lines
                f"  LI(t0, {mpv})",  # asm: MPV bitmask into t0
                f"  csrs {mpv_csr}, t0",  # asm: set MPV in mstatus/mstatush
                "  LI(a6, 0)",  # asm: zero result before access
                "  LI(t1, gpa_xonly)",  # asm: X-only GPA (expect fault under MPRV+MPV)
                "  lw a6, 0(t1)",  # asm: SPA/MPRV load
                "  nop",  # asm: nop padding
            ],  # end asm body list
            False,  # leave MPRV set across cases
        ),  # end case tuple
        (  # case tuple start
            "5",  # case number
            "MPRV=1 MPP=U MPV=0 lw of SPA",  # case title
            "a7",  # SIGUPD register
            "test5_u",  # SIGUPD label
            [  # list of asm lines
                "  LI(t0, MSTATUS_MPP)",  # asm: MPP field mask
                "  csrc mstatus, t0",  # asm: clear mstatus bits in t0
                f"  LI(t0, {mpv})",  # asm: MPV bitmask into t0
                f"  csrc {mpv_csr}, t0",  # asm: clear MPV
                "  LI(a7, 0)",  # asm: zero result before access
                "  la t1, test_region_x",  # asm: SPA of physical page
                "  lw a7, 0(t1)",  # asm: SPA/MPRV load
                "  nop",  # asm: nop padding
            ],  # end asm body list
            False,  # leave MPRV set across cases
        ),  # end case tuple
        (  # case tuple start
            "6",  # case number
            "MPRV=1 MPP=U MPV=1 lw of X-only GPA",  # case title
            "s1",  # SIGUPD register
            "test6_vu",  # SIGUPD label
            [  # list of asm lines
                f"  LI(t0, {mpv})",  # asm: MPV bitmask into t0
                f"  csrs {mpv_csr}, t0",  # asm: set MPV in mstatus/mstatush
                "  LI(s1, 0)",  # asm: zero result before access
                "  LI(t1, gpa_xonly)",  # asm: X-only GPA (expect fault under MPRV+MPV)
                "  lw s1, 0(t1)",  # asm: SPA/MPRV load
                "  nop",  # asm: nop padding
            ],  # end asm body list
            False,  # leave MPRV set across cases
        ),  # end case tuple
        (  # case tuple start
            "7",  # case number
            "HLV of R/W GPA ignores MPRV",  # case title
            "s2",  # SIGUPD register
            "test7_hlv",  # SIGUPD label
            ["  LI(s2, 0)", "  LI(t1, gpa_rw)", "  hlv.w s2, (t1)", "  nop"],  # asm: R/W GPA for HLV
            True,  # clear MPRV after this case
        ),  # end case tuple
    ]  # end list
    for num, title, reg, label, body, clear in cases:  # MPRV cases; clear MPRV after HLV case
        lines.extend(_case_header(num, title, "Expected Fault" if num in {"4", "6"} else "Successful"))  # case // header
        lines.extend(body)  # case stimulus asm
        if clear:  # HLV case: drop MPRV/MPV before SIGUPD
            lines.extend(clear_mprv())  # clear MPRV before SIGUPD
            lines.extend([f"  LI(t0, {mpv})", f"  csrc {mpv_csr}, t0"])  # asm: MPV bitmask into t0
        lines.extend(_sigupd_manual(ManualSig(label, reg, f"Mismatch on {title}"), mismatches))  # SIGUPD + mismatch string
    extra = [*_data_region("test_region_x"), *_data_region("test_region_rw")]  # extra .data regions for this test
    lines.extend(data_section(need_test_region=False, need_vlvl0=False, need_hlvl1=paging == "sv39", extra_regions=extra, mismatch_strings=mismatches))  # .data section for this emitter
    return Body(lines, 7, 7)  # pack lines + SIGUPD/case counts


def generate_mprv_hgatp_Mmode(test_data: TestData) -> list[str]:  # entry: mprv_hgatp twin
    """Output ``SvH_mprv_hgatp_Mmode-00.S``: MPRV+MPP+MPV with G-stage (``cp_hgatp_mprv_effects``)."""
    return _finish_twin_test(test_data, "mprv_hgatp_Mmode", _asm_mprv_hgatp)  # Sv32/Sv39 twin wrap


def _asm_mprv_sum(paging: Mode) -> Body:  # MPRV as VS on U-page with SUM 0/1
    mismatches: list[str] = []  # mismatch strings for .data
    vs_mode, g_mode = mode_names(paging)  # vsatp MODE and hgatp MODE names
    lines = [f"  .set va_u, {'0x0000000080010000' if paging == 'sv39' else '0x008001000'}", *set_va_gpa_symbols(paging), *build_two_stage_maps(paging, data_pte=VS_U_RW, g_data_pte=G_RW, with_data=True), f"  VSATP_SETUP({vs_mode}, GPA)", f"  HGATP_SETUP({g_mode})", "  csrw satp, x0", *fence_both_stages(), *preload_spa(0x257A0C02), "  LI(t0, MSTATUS_MPP)", "  csrc mstatus, t0", "  LI(t0, MPP_SMODE)", "  csrs mstatus, t0", f"  LI(t0, {_mpv_mask(paging)})", f"  csrs {_mpv_csr(paging)}, t0", "  LI(t0, MSTATUS_MPRV)", "  csrs mstatus, t0", "  LI(t0, SSTATUS_SUM)", "  csrc sstatus, t0", "  csrc vsstatus, t0", "  hfence.vvma", *_section_banner("Test Cases Start from here")]  # U-page VA + two-stage maps + MPRV/SUM setup
    cases = [  # case tuples: num, title, regs, asm body
        ("1", "MPRV SUM=0 U-page lw", "a3", "test1_sum0", ["  LI(a5, va_u)", "  LI(a3, 0)", "  lw a3, 0(a5)", "  nop"], "Expected Fault"),  # asm: U-page VA
        ("2", "MPRV SUM=1 U-page lw", "a4", "test2_sum1", ["  LI(t0, SSTATUS_SUM)", "  csrs sstatus, t0", "  csrs vsstatus, t0", "  hfence.vvma", "  LI(t0, MSTATUS_MPRV)", "  csrs mstatus, t0", "  LI(a5, va_u)", "  lw a4, 0(a5)", "  nop"], "Successful"),  # SUM=1 U-page lw case
        ("3", "MPRV SUM=1 U-page sw+lw", "a6", "test3_sum1_sw", ["  LI(t0, MSTATUS_MPRV)", "  csrs mstatus, t0", "  LI(a5, va_u)", "  LI(t0, 0x257A0C03)", "  sw t0, 0(a5)", "  nop", "  lw a6, 0(a5)", "  nop"], "Successful"),  # SUM=1 U-page sw+lw case
    ]  # end list
    for num, title, reg, label, body, expected in cases:  # emit each case header, body, SIGUPD
        lines.extend(_case_header(num, title, expected))  # case // header
        lines.extend(body)  # case stimulus asm
        lines.extend(clear_mprv())  # clear MPRV before SIGUPD
        lines.extend(_sigupd_manual(ManualSig(label, reg, f"Mismatch on {title}"), mismatches))  # SIGUPD + mismatch string
    lines.extend(twin_data(paging, mismatch_strings=mismatches))  # twin .data with mismatch strings
    return Body(lines, 3, 3)  # pack lines + SIGUPD/case counts


def generate_mprv_sum_two_stage_Mmode(test_data: TestData) -> list[str]:  # entry: mprv_sum twin
    """Output ``SvH_mprv_sum_two_stage_Mmode-00.S``: MPRV as VS on a U-page, SUM=0 then SUM=1."""
    return _finish_twin_test(test_data, "mprv_sum_two_stage_Mmode", _asm_mprv_sum)  # Sv32/Sv39 twin wrap


def _asm_mprv_vsatp(paging: Mode) -> Body:  # MPRV with VS-only maps, MPP=S/U
    mismatches: list[str] = []  # mismatch strings for .data
    vs_mode, _ = mode_names(paging)  # VS-stage MODE name only
    va_s = "0x0000000080010000" if paging == "sv39" else "0x008001000"  # S-page guest VA
    va_u = "0x0000000080020000" if paging == "sv39" else "0x008002000"  # U-page guest VA
    lines = [f"  .set va_s, {va_s}", f"  .set va_u, {va_u}"]  # S/U VA symbols for VS-only maps
    for va in ("va_s", "va_u"):  # build VS walk for each VA
        if paging == "sv39":  # Sv39 needs an extra table level
            lines.extend([f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL2)", f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL1)"])  # rewrite leaf PTE then fence/stimulus
        else:  # Sv32 two-level walk
            lines.append(f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL1)")  # append one map/asm line
    lines.extend([f"  VS_PTE_SETUP({vs_mode}, PA, test_region_s, {VS_RW}, va_s, LEVEL0)", f"  VS_PTE_SETUP({vs_mode}, PA, test_region_u, {VS_U_RW}, va_u, LEVEL0)", f"  VSATP_SETUP({vs_mode}, PA)", "  csrw hgatp, x0", "  csrw satp, x0", *fence_both_stages(), *preload_spa(0x257A0141, dest="test_region_s"), *preload_spa(0x257A0142, dest="test_region_u"), *_section_banner("Test Cases Start from here")])  # S/U VAs then VS leaves + Bare G
    cases = [  # case tuples: num, title, regs, asm body
        ("1", "MPRV=0 raw M-mode load", "a3", "test1_mprv0", [*clear_mprv(), f"  LI(t0, {_mpv_mask(paging)})", f"  csrc {_mpv_csr(paging)}, t0", "  LI(a3, 0)", "  LI(a5, va_s)", "  lw a3, 0(a5)", "  nop"], "Expected Fault"),  # MPRV=0 raw M-mode load (expect fault)
        ("2", "MPRV=1 MPP=S MPV=1 load S-page", "a4", "test2_mprv_s", ["  LI(t0, MSTATUS_MPP)", "  csrc mstatus, t0", "  LI(t0, MPP_SMODE)", "  csrs mstatus, t0", f"  LI(t0, {_mpv_mask(paging)})", f"  csrs {_mpv_csr(paging)}, t0", "  LI(t0, MSTATUS_MPRV)", "  csrs mstatus, t0", "  LI(a4, 0)", "  LI(a5, va_s)", "  lw a4, 0(a5)", "  nop"], "Successful"),  # MPRV=1 MPP=S MPV=1 load S-page
        ("3", "MPRV=1 MPP=U MPV=1 load U-page", "a6", "test3_mprv_u", ["  LI(t0, MSTATUS_MPP)", "  csrc mstatus, t0", "  LI(t0, MSTATUS_MPRV)", "  csrs mstatus, t0", "  LI(a6, 0)", "  LI(a5, va_u)", "  lw a6, 0(a5)", "  nop"], "Successful"),  # MPRV=1 MPP=U MPV=1 load U-page
    ]  # end list
    for num, title, reg, label, body, expected in cases:  # emit each case header, body, SIGUPD
        lines.extend(_case_header(num, title, expected))  # case // header
        lines.extend(body)  # case stimulus asm
        lines.extend(clear_mprv())  # clear MPRV before SIGUPD
        if num == "3":  # clear MPV after U-page case
            lines.extend([f"  LI(t0, {_mpv_mask(paging)})", f"  csrc {_mpv_csr(paging)}, t0"])  # append asm lines
        lines.extend(_sigupd_manual(ManualSig(label, reg, f"Mismatch on {title}"), mismatches))  # SIGUPD + mismatch string
    extra = [*_data_region("test_region_s"), *_data_region("test_region_u")]  # extra .data regions for this test
    lines.extend(data_section(need_test_region=False, need_hlvl0=False, need_hlvl1=False, need_vlvl1=paging == "sv39", extra_regions=extra, mismatch_strings=mismatches))  # .data section for this emitter
    return Body(lines, 3, 3)  # pack lines + SIGUPD/case counts


def generate_mprv_vsatp_Mmode(test_data: TestData) -> list[str]:  # entry: mprv_vsatp twin
    """Output ``SvH_mprv_vsatp_Mmode-00.S``: MPRV with VS-only maps, MPP=S/U and MPV."""
    return _finish_twin_test(test_data, "mprv_vsatp_Mmode", _asm_mprv_vsatp)  # Sv32/Sv39 twin wrap


def _asm_tvm(paging: Mode) -> Body:  # TVM=0 allows HS hgatp write; TVM=1 traps
    mismatches: list[str] = []  # mismatch strings for .data
    mode, shift = ("HGATP_MODE_SV39X4", 60) if paging == "sv39" else ("HGATP_MODE_SV32X4", 31)  # hgatp MODE constant and MODE bit pos
    lines = ["  csrw vsatp, x0", "  csrw hgatp, x0", "  csrw medeleg, x0", "  csrw hedeleg, x0", *_section_banner("Test Cases Start from here"), *_case_header("1", f"TVM=0 HS write hgatp.MODE={mode}"), "  LI(t0, MSTATUS_TVM)", "  csrc mstatus, t0", *goto_hs(), f"  LI(t0, ({mode} << {shift}))", "  csrw hgatp, t0", *_sigupd_csr_manual("test1_hgatp", "hgatp", "a4", "Mismatch on hgatp write with TVM=0", mismatches), *goto_mmode(), *_case_header("2", "TVM=1 HS hgatp write illegal", "Expected Fault"), "  LI(t0, MSTATUS_TVM)", "  csrs mstatus, t0", "  LI(a4, 0x257A0131)", *goto_hs(), "  csrw hgatp, x0", "  nop", "  addi a4, a4, 1", *goto_mmode(), "  LI(t0, MSTATUS_TVM)", "  csrc mstatus, t0", *_sigupd_manual(ManualSig("test2_marker", "a4", "Mismatch on TVM=1 illegal hgatp write marker"), mismatches), *data_section(need_test_region=False, need_hlvl0=False, need_vlvl0=False, mismatch_strings=mismatches)]  # TVM=0 hgatp write then TVM=1 illegal write
    return Body(lines, 2, 2)  # pack lines + SIGUPD/case counts


def generate_tvm_hgatp_HSmode(test_data: TestData) -> list[str]:  # entry: tvm_hgatp twin
    """Output ``SvH_tvm_hgatp_HSmode-00.S``: TVM=0 allows HS ``csrw hgatp``; TVM=1 traps."""
    return _finish_twin_test(test_data, "tvm_hgatp_HSmode", _asm_tvm)  # Sv32/Sv39 twin wrap


def _asm_vs_pte_attr_sv32() -> Body:  # Sv32 VS RSW sw/lw cases
    mismatches: list[str] = []  # mismatch strings for .data
    lines = [*set_va_gpa_symbols("sv32"), *_vs_only_maps("sv32"), "  LI(a5, va_data)", *_section_banner("Test Cases Start from here")]  # VA/GPA symbols + VS maps + preload banner
    rsw = [("00", "0", 0x257A0301, "s2", "a3"), ("01", "0x100", 0x257A0302, "s3", "a4"), ("10", "0x200", 0x257A0303, "s4", "a6"), ("11", "PTE_SOFT", 0x257A0304, "s5", "a7")]  # RSW name/flag/value/reg tuples
    n = 1  # case number for RSW sw/lw pairs
    for name, flag, value, sw_reg, lw_reg in rsw:  # Sv32 RSW sw then lw pairs
        if name != "00":  # rewrite VS leaf with this RSW
            lines.extend([f"  VS_PTE_SETUP(sv32, PA, test_region, ({VS_RW} | {flag}), va_data, LEVEL0)", "  hfence.vvma"])  # rewrite leaf PTE then fence/stimulus
        lines.extend(_case_header(str(n), f"RSW={name} VS sw"))  # case // header
        lines.extend([f"  LI(t0, {hex(value)})", *goto_vs(), "  sw t0, 0(a5)", "  nop", *goto_mmode(), "  la t1, test_region", f"  lw {sw_reg}, 0(t1)"])  # asm: SPA of physical page
        lines.extend(_sigupd_manual(ManualSig(f"test{n}_rsw{name}_sw", sw_reg, f"Mismatch on RSW={name} VS sw SPA"), mismatches))  # SIGUPD + mismatch string
        n += 1  # next case number
        lines.extend(_case_header(str(n), f"RSW={name} VS lw only"))  # case // header
        lines.extend(["  hfence.vvma", *goto_vs(), f"  lw {lw_reg}, 0(a5)", "  nop", *goto_mmode()])  # fence then VS lw-only
        lines.extend(_sigupd_manual(ManualSig(f"test{n}_rsw{name}_lw", lw_reg, f"Mismatch on RSW={name} VS lw"), mismatches))  # SIGUPD + mismatch string
        n += 1  # next case number
    lines.extend(twin_data("sv32", mismatch_strings=mismatches))  # twin .data with mismatch strings
    return Body(lines, 8, 8)  # pack lines + SIGUPD/case counts


def _asm_vs_pte_attr_sv39() -> Body:  # Sv39 VS RSW/reserved/PBMT cases
    mismatches: list[str] = []  # mismatch strings for .data
    lines = [*RV64_PTE_DEFS, "  .set va_code, 0x0000000090000000", "  .set va_rsw00, 0x0000000080010000", "  .set va_rsw01, 0x0000000080020000", "  .set va_rsw10, 0x0000000080030000", "  .set va_rsw11, 0x0000000080040000", "  .set va_rsvd,  0x0000000080050000", "  .set va_pbmt,  0x0000000080060000", "  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)", f"  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)", "  csrr a0, mscratch", "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)"]  # PTE #defines + G maps + Bare VS + preload
    for va, region, flags in [("va_rsw00", "test_region0", VS_RW), ("va_rsw01", "test_region1", f"({VS_RW} | 0x100)"), ("va_rsw10", "test_region2", f"({VS_RW} | 0x200)"), ("va_rsw11", "test_region3", f"({VS_RW} | PTE_SOFT)"), ("va_rsvd", "test_region4", f"({VS_RW} | PTE_RSVD_ALL)"), ("va_pbmt", "test_region5", f"({VS_RW} | PTE_PBMT3)")]:  # VS leaf per VA/region/flags
        lines.extend([f"  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL2)", f"  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL1)", f"  VS_PTE_SETUP(sv39, PA, {region}, {flags}, {va}, LEVEL0)"])  # rewrite leaf PTE then fence/stimulus
    lines.extend(["  VSATP_SETUP(sv39, PA)", "  csrw hgatp, x0", *fence_both_stages()])  # enable paging / fences / more maps
    for i in range(6):  # preload or emit each test_region
        lines.extend(preload_spa(0x257A0301 + i, dest=f"test_region{i}"))  # store known word into SPA
    lines.extend(_section_banner("Test Cases Start from here"))  # append asm lines
    for num, name, va, reg, extra in [("1", "00", "va_rsw00", "a3", None), ("2", "01", "va_rsw01", "a4", "2b"), ("3", "10", "va_rsw10", "a6", "3b"), ("4", "11", "va_rsw11", "a7", "4b")]:  # RSW sw+lw and optional lw-only
        lines.extend(_case_header(num, f"RSW={name} VS sw+lw"))  # case // header
        lines.extend([f"  LI(a5, {va})", f"  LI(t0, {hex(0x257A0300 + int(num))})", *goto_vs(), "  sw t0, 0(a5)", "  nop", f"  lw {reg}, 0(a5)", "  nop", *goto_mmode()])  # asm: store under MPRV translation
        lines.extend(_sigupd_manual(ManualSig(f"test{num}_rsw{name}", reg, f"Mismatch on RSW={name} VS sw+lw"), mismatches))  # SIGUPD + mismatch string
        if extra:  # optional lw-only follow-up case
            exreg = "s2" if extra == "2b" else "s3" if extra == "3b" else "s4"  # GPR for lw-only follow-up
            lines.extend(_case_header(extra, f"RSW={name} VS lw only"))  # case // header
            lines.extend(["  hfence.vvma", f"  LI(a5, {va})", *goto_vs(), f"  lw {exreg}, 0(a5)", "  nop", *goto_mmode()])  # fence then VS lw-only
            lines.extend(_sigupd_manual(ManualSig(f"test{extra}_rsw{name}_lw", exreg, f"Mismatch on RSW={name} VS lw-only"), mismatches))  # SIGUPD + mismatch string
    for prefix, bit, reg in [("5a", "PTE_BIT54", "a6"), ("5b", "PTE_BIT55", "a7"), ("5c", "PTE_BIT56", "s2"), ("5d", "PTE_BIT57", "s3"), ("5e", "PTE_BIT58", "s4"), ("5f", "PTE_BIT59", "s5"), ("5g", "PTE_BIT60", "s6"), ("5h", "PTE_RSVD_ALL", "s7")]:  # reserved-bit or PBMT VS cases
        lines.extend(_case_header(prefix, f"Reserved {bit} VS lw", "Expected Fault"))  # case // header
        lines.extend([f"  VS_PTE_SETUP(sv39, PA, test_region4, ({VS_RW} | {bit}), va_rsvd, LEVEL0)", "  hfence.vvma", "  LI(a5, va_rsvd)", f"  LI({reg}, 0)", *goto_vs(), f"  lw {reg}, 0(a5)", "  nop", *goto_mmode()])  # rewrite VS leaf, fence, VS access
        lines.extend(_sigupd_manual(ManualSig(f"test{prefix}_{bit.lower()}", reg, f"Mismatch on reserved {bit} VS lw"), mismatches))  # SIGUPD + mismatch string
    for prefix, bit in [("6a", "PTE_BIT54"), ("6b", "PTE_BIT55"), ("6c", "PTE_BIT56"), ("6d", "PTE_BIT57"), ("6e", "PTE_BIT58"), ("6f", "PTE_RSVD_ALL")]:  # reserved-bit VS store cases
        lines.extend(_case_header(prefix, f"Reserved {bit} VS sw", "Expected Fault"))  # case // header
        lines.extend([f"  VS_PTE_SETUP(sv39, PA, test_region4, ({VS_RW} | {bit}), va_rsvd, LEVEL0)", "  hfence.vvma", "  LI(a5, va_rsvd)", "  LI(t0, 0xBAD00FAD)", *goto_vs(), "  sw t0, 0(a5)", "  nop", *goto_mmode(), "  la t1, test_region4", "  lw a3, 0(t1)"])  # rewrite VS leaf, fence, VS access
        lines.extend(_sigupd_manual(ManualSig(f"test{prefix}_sw_{bit.lower()}", "a3", f"Mismatch on reserved {bit} VS sw"), mismatches))  # SIGUPD + mismatch string
    for prefix, bit, reg, value in [("6g", "PTE_BIT59", "a3", 0x257A0359), ("6h", "PTE_BIT60", "a4", 0x257A0360)]:  # soft-RSW or jalr success cases
        lines.extend(_case_header(prefix, f"Soft-RSW {bit} VS sw+lw"))  # case // header
        lines.extend([f"  VS_PTE_SETUP(sv39, PA, test_region4, ({VS_RW} | {bit}), va_rsvd, LEVEL0)", "  hfence.vvma", "  LI(a5, va_rsvd)", f"  LI(t0, {hex(value)})", *goto_vs(), "  sw t0, 0(a5)", "  nop", f"  lw {reg}, 0(a5)", "  nop", *goto_mmode()])  # rewrite VS leaf, fence, VS access
        lines.extend(_sigupd_manual(ManualSig(f"test{prefix}_sw_{bit.lower()}", reg, f"Mismatch on soft-RSW {bit} VS sw"), mismatches))  # SIGUPD + mismatch string
    lines.extend(_case_header("7", "Reserved bit54 X-leaf VS jalr", "Expected Fault"))  # case // header
    lines.extend([f"  VS_PTE_SETUP(sv39, PA, test_region4, ({PTE_CODE_VS} | PTE_BIT54), va_rsvd, LEVEL0)", "  hfence.vvma", "  LI(a5, va_rsvd)", "  LI(a4, 0)", *goto_vs(), "  nop", "  jalr ra, a5, 0", "  nop", *goto_mmode()])  # rewrite VS leaf, fence, VS access
    lines.extend(_sigupd_manual(ManualSig("test7_rsvd_jalr", "a4", "Mismatch on reserved bit54 VS jalr"), mismatches))  # SIGUPD + mismatch string
    for prefix, bit, reg, value in [("7b", "PTE_BIT59", "s2", 0x257A0759), ("7c", "PTE_BIT60", "s3", 0x257A0760)]:  # soft-RSW or jalr success cases
        lines.extend(_case_header(prefix, f"Soft-RSW {bit} X-leaf VS jalr"))  # case // header
        lines.extend([*preload_spa(0x00008067, dest="test_region4"), f"  VS_PTE_SETUP(sv39, PA, test_region4, ({PTE_CODE_VS} | {bit}), va_rsvd, LEVEL0)", "  hfence.vvma", "  LI(a5, va_rsvd)", f"  LI({reg}, 0)", *goto_vs(), "  nop", "  jalr ra, a5, 0", f"  LI({reg}, {hex(value)})", "  nop", *goto_mmode()])  # rewrite VS leaf, fence, VS access
        lines.extend(_sigupd_manual(ManualSig(f"test{prefix}_jalr_{bit.lower()}", reg, f"Mismatch on soft-RSW {bit} VS jalr"), mismatches))  # SIGUPD + mismatch string
    lines.extend(["  LI(t0, MENVCFG_PBMTE)", "  csrc menvcfg, t0", "  LI(t0, HENVCFG_PBMTE)", "  csrc henvcfg, t0"])  # toggle PBMTE in menvcfg/henvcfg
    for prefix, bit, reg in [("8a", "PTE_PBMT1", "a6"), ("8b", "PTE_PBMT2", "a7"), ("8c", "PTE_PBMT3", "s2")]:  # reserved-bit or PBMT VS cases
        lines.extend(_case_header(prefix, f"{bit} PBMTE=0 VS lw+sw", "Expected Fault"))  # case // header
        lines.extend([f"  VS_PTE_SETUP(sv39, PA, test_region5, ({VS_RW} | {bit}), va_pbmt, LEVEL0)", "  hfence.vvma", "  LI(a5, va_pbmt)", f"  LI({reg}, 0)", *goto_vs(), f"  lw {reg}, 0(a5)", "  nop", f"  sw {reg}, 0(a5)", "  nop", *goto_mmode()])  # rewrite VS leaf, fence, VS access
        lines.extend(_sigupd_manual(ManualSig(f"test{prefix}_{bit.lower()}_nosup", reg, f"Mismatch on {bit} PBMTE=0 VS"), mismatches))  # SIGUPD + mismatch string
    lines.extend(_case_header("8d", "PBMT=1 X-leaf PBMTE=0 VS jalr", "Expected Fault"))  # case // header
    lines.extend([f"  VS_PTE_SETUP(sv39, PA, test_region5, ({PTE_CODE_VS} | PTE_PBMT1), va_pbmt, LEVEL0)", "  hfence.vvma", "  LI(a5, va_pbmt)", "  LI(s3, 0)", *goto_vs(), "  nop", "  jalr ra, a5, 0", "  nop", *goto_mmode()])  # rewrite VS leaf, fence, VS access
    lines.extend(_sigupd_manual(ManualSig("test8d_pbmt1_nosup_x", "s3", "Mismatch on PBMT=1 PBMTE=0 VS jalr"), mismatches))  # SIGUPD + mismatch string
    extra: list[str] = []  # collect per-region .data labels
    for i in range(6):  # preload or emit each test_region
        extra.extend(_data_region(f"test_region{i}"))  # add zeroed page for this region
    lines.extend(data_section(need_test_region=False, need_hlvl0=False, need_hlvl1=False, need_vlvl1=True, extra_regions=extra, mismatch_strings=mismatches))  # .data section for this emitter
    return Body(lines, 31, 31)  # pack lines + SIGUPD/case counts


def generate_vs_pte_attr_VSmode(test_data: TestData) -> list[str]:  # entry: vs_pte_attr twin
    """Output ``SvH_vs_pte_attr_VSmode-00.S``: VS RSW, reserved bits, PBMT (Sv39)."""
    return _finish_twin_test(test_data, "vs_pte_attr_VSmode", lambda p: _asm_vs_pte_attr_sv32() if p == "sv32" else _asm_vs_pte_attr_sv39())  # Sv32/Sv39 twin wrap


def _asm_vsbe(paging: Mode) -> Body:  # VSBE=0 LE check then VSBE=1 attempt
    """VSBE=0 little-endian check, then VSBE=1 attempt (Sail may force VSBE back to 0)."""
    mismatches: list[str] = []  # mismatch strings for .data
    lines = [  # start building asm line list
        *set_va_gpa_symbols(paging),  # .set va_* / gpa_*
        *_vs_only_maps(paging, data_flags=VS_XWR),  # VS on, hgatp Bare
        "  LI(a5, va_data)",  # guest pointer for sw/lw
        "  LI(s1, 0xA1B2C3D4)",  # known endian pattern
        *_section_banner("Test Cases Start from here"),  # section // banner
        # --- VSBE=0 path (must behave little-endian) ---
        *_case_header("1", "VSBE=0 VS lw after sw"),  # store/load guest memory
        "  LI(t0, HSTATUS_VSBE)",  # VSBE endian control bit
        "  csrc hstatus, t0",  # clear VSBE
        "  la t1, test_region",  # asm: SPA of physical page
        "  sw x0, 0(t1)",  # clear SPA before guest store
        *goto_vs(),  # enter VS-mode
        "  sw s1, 0(a5)",  # VS store pattern
        "  nop",  # asm: nop padding
        *goto_mmode(),  # return to M-mode
        "  hfence.vvma",  # asm: HFENCE.VVMA
        *goto_vs(),  # enter VS-mode
        "  lw a3, 0(a5)",  # asm: load via guest VA
        "  nop",  # asm: nop padding
        *goto_mmode(),  # return to M-mode
        *_sigupd_manual(ManualSig("test1_vsbe0_lw", "a3", "Mismatch on VSBE=0 VS lw"), mismatches),  # load word
        *_case_header("2", "VSBE=0 M-mode SPA readback"),  # case // header
        "  la t1, test_region",  # asm: SPA of physical page
        "  lw t2, 0(t1)",  # SPA LE view of the same word
        *_sigupd_manual(ManualSig("test2_vsbe0_spa", "t2", "Mismatch on VSBE=0 SPA LE readback"), mismatches),  # SIGUPD site record
        # --- VSBE=1 attempt (Sail legalize_hstatus may keep VSBE=0) ---
        *_case_header("3", "VSBE=1 hstatus readback"),  # case // header
        "  LI(t0, HSTATUS_VSBE)",  # VSBE endian control bit
        "  csrs hstatus, t0",  # try to set VSBE
        *_sigupd_csr_manual("test3_vsbe1_hstatus", "hstatus", "a4", "Mismatch on hstatus after VSBE set attempt", mismatches),  # VSBE endian
        *_case_header("4", "VSBE=1 attempt VS lw after sw"),  # store/load guest memory
        "  la t1, test_region",  # asm: SPA of physical page
        "  sw x0, 0(t1)",  # case field string
        *goto_vs(),  # enter VS-mode
        "  sw s1, 0(a5)",  # case field string
        "  nop",  # asm: nop padding
        *goto_mmode(),  # return to M-mode
        "  hfence.vvma",  # asm: HFENCE.VVMA
        *goto_vs(),  # enter VS-mode
        "  lw a4, 0(a5)",  # asm: load via guest VA
        "  nop",  # asm: nop padding
        *goto_mmode(),  # return to M-mode
        *_sigupd_manual(ManualSig("test4_vsbe1_lw", "a4", "Mismatch on VSBE=1 attempt VS lw"), mismatches),  # SIGUPD site record
        *_case_header("5", "VSBE=1 attempt M-mode SPA byte view"),  # case // header
        "  la t1, test_region",  # asm: SPA of physical page
        "  lw t3, 0(t1)",  # case field string
        *_sigupd_manual(ManualSig("test5_vsbe1_spa", "t3", "Mismatch on VSBE=1 attempt SPA byte view"), mismatches),  # SIGUPD site record
        "  LI(t0, HSTATUS_VSBE)",  # VSBE endian control bit
        "  csrc hstatus, t0",  # leave VSBE clear for any later code
        *twin_data(paging, mismatch_strings=mismatches),  # .data for this paging twin
    ]  # end list
    return Body(lines, 5, 5)  # pack lines + SIGUPD/case counts


def generate_vsbe_endian_VSmode(test_data: TestData) -> list[str]:  # entry: vsbe_endian twin
    """Output ``SvH_vsbe_endian_VSmode-00.S``: VSBE=0 then VSBE=1 endian check (``vsbe_hstatus``)."""
    return _finish_twin_test(test_data, "vsbe_endian_VSmode", _asm_vsbe)  # Sv32/Sv39 twin wrap


