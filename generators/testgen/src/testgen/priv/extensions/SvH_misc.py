##################################
# priv/extensions/SvH_misc.py
#
# SvH misc family - true Python emitters, no runtime seed I/O.
# SPDX-License-Identifier: Apache-2.0
##################################

"""HFENCE, MPRV, TVM, PTE attributes, GPA width, VSBE.

Each ``generate_*`` is one output file. Twins wrap via ``build_twins``
(max SIGUPD_COUNT), single bodies wrap in ``#ifdef SV39_SUPPORTED``.
Every SIGUPD testcase is recorded with ``add_testcase`` + ``write_sigupd``
(or ``gen_csr_read_sigupd``) so labels and counters stay in sync.
"""

from __future__ import annotations  # postponed annotation eval

from typing import Literal  # Sv32/Sv39 mode alias

from testgen.asm.csr import gen_csr_read_sigupd  # CSR read into signature
from testgen.asm.helpers import comment_banner, write_sigupd  # file banner + SIGUPD emit
from testgen.data.state import TestData  # testcase counter state
from testgen.priv.extensions.SvHCommon import (  # shared SvH paging/mode helpers
    ABI_TO_INT,  # GPR name → sig index
    CG,  # covergroup tag for add_testcase
    PTE_CODE_G,  # SvHCommon.PTE_CODE_G
    PTE_CODE_VS,  # SvHCommon.PTE_CODE_VS
    PTE_DATA_G,  # SvHCommon.PTE_DATA_G
    PTE_DATA_VS,  # SvHCommon.PTE_DATA_VS
    PTE_RW_U,  # SvHCommon.PTE_RW_U
    PTE_RW_U_AD0,  # SvHCommon.PTE_RW_U_AD0
    PTE_V_ONLY,  # SvHCommon.PTE_V_ONLY
    PTE_X_ONLY_U,  # SvHCommon.PTE_X_ONLY_U
    PTE_XWR_S,  # SvHCommon.PTE_XWR_S
    PTE_XWR_S_AD0,  # SvHCommon.PTE_XWR_S_AD0
    build_twins,  # Sv32+Sv39 twin wrapper
    build_two_stage_maps,  # G+VS page-table macros
    clear_mprv,  # csrc mstatus, MSTATUS_MPRV before SIGUPD
    data_section,  # .data pages/tables
    fence_both_stages,  # TLB shootdown both stages
    GOTO_HS,  # relocated hop M→HS (GOTO)
    GOTO_MMODE,  # return trap path to M
    GOTO_VS,  # relocated hop M→VS
    mode_names,  # vsatp/hgatp MODE strings
    preload_spa,  # M-mode store pattern into SPA
    set_va_gpa_symbols,  # .set va/gpa symbols
    twin_data,  # .data section for twin
)  # end SvHCommon import list

Mode = Literal["sv32", "sv39"]  # Sv32/Sv39 paging mode alias

# --- Leaf flag recipes used across misc tests ---
G_RW = PTE_DATA_G  # normal G R/W U=1 leaf
G_XONLY = PTE_X_ONLY_U  # G execute-only U=1 (MXR / xonly paths)
G_RW_AD0 = PTE_RW_U_AD0  # G R/W with A=D=0
VS_RW = PTE_DATA_VS  # normal VS R/W U=0 leaf
VS_XWR = PTE_XWR_S  # VS XWR U=0
VS_XWR_AD0 = PTE_XWR_S_AD0  # VS XWR with A=D=0
VS_U_RW = PTE_RW_U  # VS R/W U=1 (U-page / SUM)

# Assembler #defines for RV64 reserved / PBMT PTE bits (vs_pte_attr / g_pte_attr Sv39).
RV64_PTE_DEFS = [  # assembler #defines for reserved/PBMT PTE bits
    "#define PTE_BIT54 (_RISCV_ULL(1) << 54)",  # assembler PTE bit definition
    "#define PTE_BIT55 (_RISCV_ULL(1) << 55)",  # assembler PTE bit definition
    "#define PTE_BIT56 (_RISCV_ULL(1) << 56)",  # assembler PTE bit definition
    "#define PTE_BIT57 (_RISCV_ULL(1) << 57)",  # assembler PTE bit definition
    "#define PTE_BIT58 (_RISCV_ULL(1) << 58)",  # assembler PTE bit definition
    "#define PTE_BIT59 (_RISCV_ULL(1) << 59)",  # assembler PTE bit definition
    "#define PTE_BIT60 (_RISCV_ULL(1) << 60)",  # assembler PTE bit definition
    "#define PTE_RSVD_ALL (_RISCV_ULL(0x7F) << 54)",  # assembler PTE bit definition
    "#define PTE_PBMT1 (_RISCV_ULL(1) << 61)",  # assembler PTE bit definition
    "#define PTE_PBMT2 (_RISCV_ULL(1) << 62)",  # assembler PTE bit definition
    "#define PTE_PBMT3 (_RISCV_ULL(3) << 61)",  # assembler PTE bit definition
]


def _section_banner(title: str) -> list[str]:  # wide // section divider
    """Emit a wide // section banner in the generated .S."""
    return ["", "// " + "-" * 128, f"// {title}", "// " + "-" * 128]


def _case_header(num: str, title: str, expected: str = "Successful") -> list[str]:  # per-case // title block
    """Emit a per-case // header (number, title, expected result)."""
    return ["", "//" + "-" * 128, f"// Test case {num}: {title} | Expected: {expected}", "//" + "-" * 128]


def _g_stage_maps(paging: Mode, *, data_lbl: str = "test_region", gpa_data: str = "gpa_data") -> list[str]:  # G code+data maps (vsatp Bare)
    """G-stage only maps: code superpage + data leaf (vsatp left Bare by the caller)."""
    _, g_mode = mode_names(paging)  # expression/ call
    code_lvl = "LEVEL2" if paging == "sv39" else "LEVEL1"  # top level for code GPA
    lines = [f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {PTE_CODE_G}, gpa_code, {code_lvl})"]
    if paging == "sv39":
        lines.append(f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, {gpa_data}, LEVEL2)")  # splice more asm into output
    lines.extend(  # extend with asm lines
        [  # list of asm lines
            f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, {gpa_data}, LEVEL1)",  # paging macro emission
            f"  G_PTE_SETUP({g_mode}, {data_lbl}, {G_RW}, {gpa_data}, LEVEL0)",  # paging macro emission
        ]
    )  # end SvHCommon import list
    return lines  # assembled asm for this twin/helper


def _vs_only_maps(paging: Mode, *, data_flags: str = VS_RW) -> list[str]:  # VS maps + vsatp on
    """VS-stage maps with PA PPNs (caller keeps hgatp Bare)."""
    vs_mode, _ = mode_names(paging)  # local setup variable
    lines: list[str] = []  # accumulate asm output lines
    if paging == "sv39":
        lines.extend(  # extend with asm lines
            [  # list of asm lines
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_code, LEVEL2)",  # paging macro emission
                f"  SUPERPAGE_VS_PTE_SETUP({vs_mode}, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)",  # paging macro emission
                "  csrr a0, mscratch",  # a0 = trap save-area base
                "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate trap save area
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL2)",  # paging macro emission
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)",  # paging macro emission
                f"  VS_PTE_SETUP({vs_mode}, PA, test_region, {data_flags}, va_data, LEVEL0)",  # paging macro emission
            ]
        )  # end SvHCommon import list
    else:
        lines.extend(  # extend with asm lines
            [  # list of asm lines
                f"  SUPERPAGE_VS_PTE_SETUP({vs_mode}, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)",  # paging macro emission
                "  csrr a0, mscratch",  # a0 = trap save-area base
                "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate trap save area under VA
                f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)",  # paging macro emission
                f"  VS_PTE_SETUP({vs_mode}, PA, test_region, {data_flags}, va_data, LEVEL0)",  # paging macro emission
            ]
        )  # end SvHCommon import list
    lines.extend([f"  VSATP_SETUP({vs_mode}, PA)", "  csrw hgatp, x0", *fence_both_stages()])  # splice more asm into output
    return lines  # assembled asm for this twin/helper


def _data_region(name: str = "test_region", *, dword: bool = False) -> list[str]:  # 4-word aligned data page
    """Emit a page-aligned data label with four zero words/dwords."""
    cell = ".dword 0" if dword else ".word 0"  # RV64 often uses dword for alignment clarity
    return [".p2align 12", f"{name}:", f"  {cell}", f"  {cell}", f"  {cell}", f"  {cell}"]


def _asm_g_adbit(test_data: TestData, paging: Mode) -> list[str]:  # emitter helper _asm_g_adbit
    """G A/D=0 on VS-PT map then VS leaf A/D=0 — lw/sw/jalr all expect faults."""
    vs_mode, g_mode = mode_names(paging)  # local setup variable
    lines = [
        *set_va_gpa_symbols(paging),  # unpack/splice helper output
        "  csrw medeleg, x0",  # keep faults at M
        "  csrw hedeleg, x0",  # no HS exception delegation
        *build_two_stage_maps(paging, data_pte=VS_XWR, g_data_pte=G_RW, with_data=True),  # unpack/splice helper output
        # G leaf covering the VS L0 table page has A=D=0 → walking VS PT should fault
        f"  G_PTE_SETUP({g_mode}, rvtest_vlvl0_pg_tbl, {G_RW_AD0}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)",  # paging macro emission
        f"  VSATP_SETUP({vs_mode}, GPA)",  # VS leaves store GPAs
        f"  HGATP_SETUP({g_mode})",  # program hgatp MODE/PPN
        *fence_both_stages(),  # unpack/splice helper output
        "  sfence.vma",  # extra fence used by the directed seed
        *preload_spa(test_data, 0x257A0251),  # unpack/splice helper output
        *_section_banner("Test Cases Start from here"),  # section // banner
    ]
    # Cases 1–3: fault because G cannot walk the VS page-table page (A=D=0)
    cases = [  # case tuples: num, title, regs, label, coverpoint, asm body
        ("1", "implicit G A=D=0 on VS-PT map - VS lw", "a3", "test1_impl_g_lw", "cp_hgatp_adbit_behavior", ["  LI(a5, va_data)", "  LI(a3, 0)", *GOTO_VS, "  lw a3, 0(a5)", "  nop", *GOTO_MMODE]),  # directed case spec tuple
        ("2", "implicit G A=D=0 on VS-PT map - VS sw", "s3", "test2_impl_g_sw", "cp_hgatp_adbit_behavior", [*fence_both_stages(), "  sfence.vma", "  LI(a5, va_data)", "  LI(t0, 0xBAD00FAD)", *GOTO_VS, "  sw t0, 0(a5)", "  nop", *GOTO_MMODE, "  la t3, test_region", "  lw s3, 0(t3)"]),  # directed case spec tuple
        ("3", "implicit G A=D=0 on VS-PT map - VS jalr", "s4", "test3_impl_g_jalr", "cp_hgatp_adbit_behavior_x", ["  LI(a5, va_data)", "  LI(s4, 0)", *GOTO_VS, "  nop", "  jalr ra, a5, 0", "  nop", *GOTO_MMODE]),  # directed case spec tuple
    ]
    for num, title, reg, label, coverpoint, body in cases:  # iterate cases/specs
        lines.extend(_case_header(num, title, "Expected Fault"))  # case // header
        lines.extend(body)  # case stimulus asm
        lines.extend([test_data.add_testcase(label, coverpoint, CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    # Restore G leaf A=D=1; set VS data leaf A=D=0 for cases 4–6
    lines.extend([f"  G_PTE_SETUP({g_mode}, rvtest_vlvl0_pg_tbl, {G_RW}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)", f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_data, {VS_XWR_AD0}, va_data, LEVEL0)", *fence_both_stages(), "  sfence.vma"])  # splice more asm into output
    cases2 = [  # case tuples: num, title, regs, label, coverpoint, asm body
        ("4", "VS leaf A=D=00 - VS lw", "a4", "test4_vs_ad00_lw", "cp_hgatp_adbit_vs_ad_rw", ["  LI(a5, va_data)", "  LI(a4, 0)", *GOTO_VS, "  lw a4, 0(a5)", "  nop", *GOTO_MMODE]),  # directed case spec tuple
        ("5", "VS leaf A=D=00 - VS sw", "s3", "test5_vs_ad00_sw", "cp_hgatp_adbit_vs_ad_rw", [*fence_both_stages(), "  sfence.vma", "  LI(a5, va_data)", "  LI(t0, 0xBAD00FAD)", *GOTO_VS, "  sw t0, 0(a5)", "  nop", *GOTO_MMODE, "  la t3, test_region", "  lw s3, 0(t3)"]),  # directed case spec tuple
        ("6", "VS leaf A=D=00 - VS jalr", "s5", "test6_vs_ad00_jalr", "cp_hgatp_adbit_vs_ad_x", ["  LI(a5, va_data)", "  LI(s5, 0)", *GOTO_VS, "  nop", "  jalr ra, a5, 0", "  nop", *GOTO_MMODE]),  # directed case spec tuple
    ]
    for num, title, reg, label, coverpoint, body in cases2:  # iterate cases/specs
        lines.extend(_case_header(num, title, "Expected Fault"))  # case // header
        lines.extend(body)  # case stimulus asm
        lines.extend([test_data.add_testcase(label, coverpoint, CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    lines.extend(twin_data(paging))  # splice more asm into output
    return lines  # finished asm line list


def generate_g_adbit_VSmode(test_data: TestData) -> list[str]:  # emitter helper generate_g_adbit_VSmode
    """Output ``SvH_g_adbit_VSmode-00.S``: G/VS A=D=0 faults, then A=D=1 success."""
    return [comment_banner("g_adbit_VSmode", "SvH directed coverpoint stimulus"), *build_twins(test_data, _asm_g_adbit)]  # file header + twin body


def _asm_g_pte_attr_sv32(test_data: TestData) -> list[str]:  # emitter helper _asm_g_pte_attr_sv32
    lines = [  # GPA symbols + G maps + Bare VS + preload
        "  .set gpa_data, 0x00C002000",  # assembler VA/GPA symbol
        "  .set gpa_code, 0x80000000",  # assembler VA/GPA symbol
        *_g_stage_maps("sv32"),  # unpack/splice helper output
        "  csrw vsatp, x0",  # Bare vsatp (VS paging off)
        "  HGATP_SETUP(sv32x4)",  # see macro: paging/mode setup
        *fence_both_stages(),  # unpack/splice helper output
        *preload_spa(test_data, 0x257A0210),  # unpack/splice helper output
        "  LI(t1, gpa_data)",  # load GPA pointer
        *_section_banner("Test Cases Start from here"),
    ]
    for idx, (rsw, reg) in enumerate([("0", "a3"), ("0x100", "a4"), ("0x200", "a6"), ("PTE_SOFT", "a7")], 1):  # iterate cases/specs
        payload = 0x257A0210 + idx - 1  # unique store pattern per RSW
        label = f"test{idx}_rsw{idx - 1:02b}"  # SIGUPD label for this RSW
        lines.extend(_case_header(str(idx), f"G leaf RSW={idx - 1:02b} HS HLV+HSV"))  # case // header
        lines.extend([f"  G_PTE_SETUP(sv32x4, test_region, ({G_RW} | {rsw}), gpa_data, LEVEL0)", "  hfence.gvma", *GOTO_HS, f"  LI(t0, {hex(payload)})", "  LI(t1, gpa_data)", "  hsv.w t0, (t1)", "  nop", "  hfence.gvma", f"  hlv.w {reg}, (t1)", "  nop", *GOTO_MMODE])  # splice more asm into output
        lines.extend([test_data.add_testcase(label, "cp_hgatp_pte_rsw", CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    lines.extend(twin_data("sv32"))  # splice more asm into output
    return lines  # finished asm line list


def _g_attr_hs_case(label: str, reg: str, flags: str, value: int) -> list[str]:  # HS HSV+HLV on one G leaf
    return [f"  G_PTE_SETUP(sv39x4, test_region, {flags}, gpa_data, LEVEL0)", "  hfence.gvma", *GOTO_HS, f"  LI(t0, {hex(value)})", "  LI(t1, gpa_data)", "  hsv.w t0, (t1)", "  nop", "  hfence.gvma", f"  LI({reg}, 0)", f"  hlv.w {reg}, (t1)", "  nop", *GOTO_MMODE]  # relocated VA!=PA mode hop


def _asm_g_pte_attr_sv39(test_data: TestData) -> list[str]:  # emitter helper _asm_g_pte_attr_sv39
    lines = [
        *RV64_PTE_DEFS,
        "  .set gpa_data, 0x0000000000C002000",  # assembler VA/GPA symbol
        "  .set gpa_code, 0x0000000080000000",  # assembler VA/GPA symbol
        *_g_stage_maps("sv39"),  # unpack/splice helper output
        "  csrw vsatp, x0",  # Bare vsatp (VS paging off)
        "  csrw satp, x0",  # Bare satp (HS paging off)
        "  HGATP_SETUP(sv39x4)",  # see macro: paging/mode setup
        *fence_both_stages(),  # unpack/splice helper output
        *preload_spa(test_data, 0x257A0240),  # unpack/splice helper output
        "  LI(t1, gpa_data)",  # load GPA pointer
        *_section_banner("Test Cases Start from here"),
    ]
    for num, name, bit, reg, value in [("1", "00", "0", "a3", 0x257A0240), ("2", "11", "PTE_SOFT", "a6", 0x257A0241), ("2b", "01", "0x100", "a4", 0x257A0242), ("2c", "10", "0x200", "a5", 0x257A0243)]:  # iterate cases/specs
        lines.extend(_case_header(num, f"G leaf RSW={name} HS HSV+HLV"))  # case // header
        lines.extend(_g_attr_hs_case(f"test{num}_rsw{name}", reg, f"({G_RW} | {bit})", value))  # asm for this flag mix
        lines.extend([test_data.add_testcase(f"test{num}_rsw{name}", "cp_hgatp_pte_rsw", CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    for num, bit, reg in [("3a", "PTE_BIT54", "a4"), ("3b", "PTE_BIT55", "a6"), ("3c", "PTE_BIT56", "a7"), ("3d", "PTE_BIT57", "s2"), ("3e", "PTE_BIT58", "s3"), ("3f", "PTE_BIT59", "s4"), ("3g", "PTE_BIT60", "s5"), ("3h", "PTE_RSVD_ALL", "s6")]:  # iterate cases/specs
        lines.extend(_case_header(num, f"G reserved {bit} HS HLV+HSV", "Expected Fault"))  # case // header
        lines.extend(_g_attr_hs_case(f"test{num}_{bit.lower()}", reg, f"({G_RW} | {bit})", 0x257A02C1))  # asm for this flag mix
        lines.extend([test_data.add_testcase(f"test{num}_{bit.lower()}", "cp_hgatp_reserved_fields_rw", CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    lines.extend(["  LI(t0, MENVCFG_PBMTE)", "  csrs menvcfg, t0"])  # toggle PBMTE in menvcfg/henvcfg
    for num, bit, reg in [("4a", "PTE_PBMT1", "a7"), ("4b", "PTE_PBMT2", "s7"), ("4c", "PTE_PBMT3", "s8")]:  # iterate cases/specs
        lines.extend(_case_header(num, f"G {bit} PBMTE=1 HS HLV+HSV"))  # case // header
        lines.extend(_g_attr_hs_case(f"test{num}_{bit.lower()}", reg, f"({G_RW} | {bit})", 0x257A0244))  # asm for this flag mix
        lines.extend([test_data.add_testcase(f"test{num}_{bit.lower()}", "cp_hgatp_svpbmt_rw", CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    lines.extend(["  LI(t0, MENVCFG_PBMTE)", "  csrc menvcfg, t0"])  # toggle PBMTE in menvcfg/henvcfg
    for num, bit, reg in [("4d", "PTE_PBMT1", "s9"), ("4e", "PTE_PBMT2", "s10"), ("4f", "PTE_PBMT3", "s11")]:  # iterate cases/specs
        lines.extend(_case_header(num, f"G {bit} PBMTE=0 HS HLV+HSV", "Expected Fault"))  # case // header
        lines.extend(_g_attr_hs_case(f"test{num}_{bit.lower()}_nosup", reg, f"({G_RW} | {bit})", 0xDEADBEEF))  # asm for this flag mix
        lines.extend([test_data.add_testcase(f"test{num}_{bit.lower()}_nosup", "cp_hgatp_svpbmt_rw", CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    lines.extend(_case_header("5", "Restore valid G leaf HS HLV"))  # case // header
    lines.extend([f"  G_PTE_SETUP(sv39x4, test_region, {G_RW}, gpa_data, LEVEL0)", *preload_spa(test_data, 0x257A0241), "  hfence.gvma", *GOTO_HS, "  LI(s2, 0)", "  LI(t1, gpa_data)", "  hlv.w s2, (t1)", "  nop", *GOTO_MMODE])  # splice more asm into output
    lines.extend([test_data.add_testcase("test5_restore", "cp_hgatp_pte_rsw", CG), write_sigupd(ABI_TO_INT["s2"], test_data)])  # splice more asm into output
    lines.extend(twin_data("sv39"))  # splice more asm into output
    return lines  # finished asm line list


def generate_g_pte_attr_VSmode(test_data: TestData) -> list[str]:  # emitter helper generate_g_pte_attr_VSmode
    """Output ``SvH_g_pte_attr_VSmode-00.S``: HS HLV/HSV on G RSW, reserved, and PBMT bits."""
    return [comment_banner("g_pte_attr_VSmode", "SvH directed coverpoint stimulus"), *build_twins(test_data, lambda td, p: _asm_g_pte_attr_sv32(td) if p == "sv32" else _asm_g_pte_attr_sv39(td))]  # file header + twin body


def _asm_g_struct(test_data: TestData, paging: Mode) -> list[str]:  # emitter helper _asm_g_struct
    _, g_mode = mode_names(paging)  # expression/ call
    data_gpa = "0x00000000C0000000" if paging == "sv39" else "0x00C000000"  # GPA constants for this twin
    code_gpa = "0x0000000080000000" if paging == "sv39" else "0x80000000"  # code GPA for this twin
    top_lvl = "LEVEL2" if paging == "sv39" else "LEVEL1"  # superpage level for this twin
    load = "hlv.d" if paging == "sv39" else "hlv.w"  # asm: HLV (ignores MPRV)
    value = 0x257A0D12 if paging == "sv39" else 0x257A0D02  # preload pattern for this twin
    lines = [  # G superpages + misaligned HLV case start
        f"  .set gpa_data, {data_gpa}",
        f"  .set gpa_code, {code_gpa}",
        f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {PTE_CODE_G}, gpa_code, {top_lvl})",  # paging macro emission
        f"  SUPERPAGE_G_PTE_SETUP({g_mode}, test_region, {G_RW}, gpa_data, {top_lvl})",  # paging macro emission
        "  csrw vsatp, x0",  # Bare vsatp (VS paging off)
        f"  HGATP_SETUP({g_mode})",  # paging macro emission
        "  hfence.gvma",  # fence G-stage TLB after hgatp/PTE change
        *preload_spa(test_data, value),  # unpack/splice helper output
        *_section_banner("Test Cases Start from here"),
        *_case_header("1", f"Misaligned {top_lvl} G superpage HS HLV", "Expected Fault"),  # unpack/splice helper output
        "  LI(t1, gpa_data)",  # load GPA pointer
        "  LI(a3, 0)",  # load immediate constant
        *GOTO_HS,  # unpack/splice helper output
        f"  {load} a3, (t1)",
        "  nop",  # pad after access/trap window
        *GOTO_MMODE,  # unpack/splice helper output
        *[test_data.add_testcase("test1_misalign", "hgatp_misaligned_superpage", CG), write_sigupd(13, test_data)],  # unpack/splice helper output
        *_case_header("2", "Valid 4KiB leaf plus HFENCE.GVMA HS HLV"),  # unpack/splice helper output
    ]
    if paging == "sv39":
        lines.append(f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL2)")  # splice more asm into output
    lines.extend([  # rewrite leaf PTE then fence/stimulus
        f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)",  # paging macro emission
        f"  G_PTE_SETUP({g_mode}, test_region, {G_RW}, gpa_data, LEVEL0)",  # paging macro emission
        f"  HGATP_SETUP({g_mode})",  # paging macro emission
        *GOTO_HS,  # unpack/splice helper output
        "  hfence.gvma",  # fence G-stage TLB after hgatp/PTE change
        "  LI(t1, gpa_data)",  # load GPA pointer
        f"  {load} a4, (t1)",
        "  nop",  # pad after access/trap window
        *GOTO_MMODE,  # unpack/splice helper output
        *[test_data.add_testcase("test2_ok", "hgatp_root_table_alignment_and_size", CG), write_sigupd(14, test_data)],  # unpack/splice helper output
        *twin_data(paging),  # unpack/splice helper output
    ])  # expression/ call
    return lines  # finished asm line list


def generate_g_struct_HSmode(test_data: TestData) -> list[str]:  # emitter helper generate_g_struct_HSmode
    """Output ``SvH_g_struct_HSmode-00.S``: misaligned G superpage, then valid 4KiB leaf."""
    return [comment_banner("g_struct_HSmode", "SvH directed coverpoint stimulus"), *build_twins(test_data, _asm_g_struct)]  # file header + twin body


def _asm_gpa_width(test_data: TestData) -> list[str]:  # emitter helper _asm_gpa_width
    lines = [  # canonical/wide GPA maps + preload
        "  .set gpa_ok,   0x00000000C002000",  # assembler VA/GPA symbol
        "  .set gpa_wide, 0x00000200C002000",  # assembler VA/GPA symbol
        "  .set gpa_code, 0x0000000080000000",  # assembler VA/GPA symbol
        f"  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, {PTE_CODE_G}, gpa_code, LEVEL2)",  # paging macro emission
        "  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, (PTE_V), gpa_ok, LEVEL2)",  # see macro: paging/mode setup
        "  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, (PTE_V), gpa_ok, LEVEL1)",  # see macro: paging/mode setup
        f"  G_PTE_SETUP(sv39x4, test_region, {G_RW}, gpa_ok, LEVEL0)",  # paging macro emission
        "  csrw vsatp, x0",  # Bare vsatp (VS paging off)
        "  HGATP_SETUP(sv39x4)",  # see macro: paging/mode setup
        "  hfence.gvma",  # fence G-stage TLB after hgatp/PTE change
        *preload_spa(test_data, 0x257A0E02),  # unpack/splice helper output
        *_section_banner("Test Cases Start from here"),
    ]
    cases = [  # case tuples: num, title, regs, label, asm body, expected
        ("1", "non-canonical GPA ld", "a3", "test1_wide", ["  LI(a5, gpa_wide)", "  LI(a3, 0)", "  RVTEST_TSBI_GOTO_VSMODE", "  ld a3, 0(a5)", "  nop", *GOTO_MMODE], "Expected Fault"),  # directed case spec tuple
        ("2", "canonical GPA ld", "a4", "test2_ok", ["  LI(a5, gpa_ok)", "  RVTEST_TSBI_GOTO_VSMODE", "  ld a4, 0(a5)", "  nop", *GOTO_MMODE], "Successful"),  # directed case spec tuple
        ("3", "non-canonical GPA sd", "a6", "test3_wide_sw", ["  LI(a5, gpa_wide)", "  LI(t0, 0xBAD00FAD)", "  RVTEST_TSBI_GOTO_VSMODE", "  sd t0, 0(a5)", "  nop", *GOTO_MMODE, "  la t1, test_region", "  ld a6, 0(t1)"], "Expected Fault"),  # directed case spec tuple
    ]
    for num, title, reg, label, body, expected in cases:  # iterate cases/specs
        lines.extend(_case_header(num, title, expected))  # case // header
        lines.extend(body)  # case stimulus asm
        lines.extend([test_data.add_testcase(label, "cp_hgatp_gpa_width_checks", CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    lines.extend(data_section(need_vlvl0=False, need_hlvl1=True, need_test_region=True))  # splice more asm into output
    return lines  # finished asm line list


def generate_gpa_width_VSmode(test_data: TestData) -> list[str]:  # emitter helper generate_gpa_width_VSmode
    """Output ``SvH_gpa_width_VSmode-00.S`` (RV64): canonical vs non-canonical GPA."""
    body = [comment_banner("gpa_width_VSmode", "SvH directed coverpoint stimulus"), *_asm_gpa_width(test_data)]  # wrapped twin body for RV64 gate
    return ["#ifdef SV39_SUPPORTED", *body, "#endif  // SV39_SUPPORTED"]  # RV64-only gate


def _asm_hfence_gvma_mode(test_data: TestData, paging: Mode) -> list[str]:  # emitter helper _asm_hfence_gvma_mode
    _, g_mode = mode_names(paging)  # expression/ call
    vmid_shift = "44" if paging == "sv39" else "22"  # VMID field bit position in hgatp
    lines = [  # Bare↔paged hgatp + HFENCE.GVMA + HS HLV cases
        "  .set gpa_data, 0x00C002000",  # assembler VA/GPA symbol
        f"  .set gpa_code, {'0x0000000080000000' if paging == 'sv39' else '0x80000000'}",
        *_g_stage_maps(paging),  # unpack/splice helper output
        "  csrw vsatp, x0",  # Bare vsatp (VS paging off)
        "  csrw hgatp, x0",  # Bare hgatp (G paging off)
        "  hfence.gvma",  # fence G-stage TLB after hgatp/PTE change
        *preload_spa(test_data, 0x257A0911),  # unpack/splice helper output
        *_section_banner("Test Cases Start from here"),
        *_case_header("1", f"hgatp Bare to {g_mode} plus HFENCE.GVMA x0,a6; HS HLV"),  # unpack/splice helper output
        f"  HGATP_SETUP({g_mode})",  # paging macro emission
        "  csrr t0, hgatp",  # read CSR into GPR
        "  LI(t1, 1)",  # load immediate constant
        f"  slli t1, t1, {vmid_shift}",
        "  or t0, t0, t1",  # asm emission line
        "  csrw hgatp, t0",  # write CSR
        *GOTO_HS,  # unpack/splice helper output
        "  LI(a6, 1)",  # load immediate constant
        "  hfence.gvma x0, a6",  # asm emission line
        "  LI(t1, gpa_data)",  # load GPA pointer
        "  hlv.w a3, (t1)",  # asm/data line in output list
        "  nop",  # pad after access/trap window
        *GOTO_MMODE,  # unpack/splice helper output
        *[test_data.add_testcase("test1_bare_to_paged", "cp_hgatp_mode_change_hfence", CG), write_sigupd(ABI_TO_INT["a3"], test_data)],  # unpack/splice helper output
        *_case_header("2", f"hgatp {g_mode} to Bare plus HFENCE.GVMA; HS HLV of SPA"),  # unpack/splice helper output
        *preload_spa(test_data, 0x257A0912),  # unpack/splice helper output
        "  csrw hgatp, x0",  # Bare hgatp (G paging off)
        *GOTO_HS,  # unpack/splice helper output
        "  hfence.gvma",  # fence G-stage TLB after hgatp/PTE change
        "  la t1, test_region",  # SPA address of label
        "  hlv.w a3, (t1)",  # asm/data line in output list
        "  nop",  # pad after access/trap window
        *GOTO_MMODE,  # unpack/splice helper output
        *[test_data.add_testcase("test2_paged_to_bare", "cp_hgatp_mode_change_hfence", CG), write_sigupd(ABI_TO_INT["a3"], test_data)],  # unpack/splice helper output
        *twin_data(paging),  # unpack/splice helper output
    ]
    return lines  # finished asm line list


def generate_hfence_gvma_mode_HSmode(test_data: TestData) -> list[str]:  # emitter helper generate_hfence_gvma_mode_HSmode
    """Output ``SvH_hfence_gvma_mode_HSmode-00.S``: HFENCE.GVMA after Bare↔paged hgatp."""
    return [comment_banner("hfence_gvma_mode_HSmode", "SvH directed coverpoint stimulus"), *build_twins(test_data, _asm_hfence_gvma_mode)]  # file header + twin body


def _asm_hfence_gvma_ops(test_data: TestData, paging: Mode) -> list[str]:  # emitter helper _asm_hfence_gvma_ops
    _, g_mode = mode_names(paging)  # expression/ call
    vmid_shift = "44" if paging == "sv39" else "22"  # VMID field bit position in hgatp
    lines = [  # GPA symbols + G maps + Bare VS + preload
        "  .set gpa_data, 0x00C002000",  # assembler VA/GPA symbol
        f"  .set gpa_code, {'0x0000000080000000' if paging == 'sv39' else '0x80000000'}",
        *_g_stage_maps(paging),  # unpack/splice helper output
        "  csrw vsatp, x0",  # Bare vsatp (VS paging off)
        f"  HGATP_SETUP({g_mode})",  # paging macro emission
        "  csrr t0, hgatp",  # read CSR into GPR
        "  LI(t1, 1)",  # load immediate constant
        f"  slli t1, t1, {vmid_shift}",
        "  or t0, t0, t1",  # asm emission line
        "  csrw hgatp, t0",  # write CSR
        *preload_spa(test_data, 0x257A0921),  # unpack/splice helper output
        "  LI(a5, gpa_data)",  # load GPA pointer
        "  LI(a6, 1)",  # load immediate constant
        *_section_banner("Test Cases Start from here"),
    ]
    for num, op, value, label in [("1", "hfence.gvma a5, x0", 0x257A0921, "test1_gpa"), ("2", "hfence.gvma x0, a6", 0x257A0922, "test2_vmid"), ("3", "hfence.gvma a5, a6", 0x257A0923, "test3_both")]:  # iterate cases/specs
        lines.extend(_case_header(num, f"{op} then HLV"))  # case // header
        if num != "1":
            lines.extend(preload_spa(test_data, value))  # splice more asm into output
            lines.extend(["  LI(a5, gpa_data)", "  LI(a6, 1)"])  # reload GPA pointer and VMID=1
        lines.extend([*GOTO_HS, f"  {op}", "  hlv.w a3, (a5)", "  nop", *GOTO_MMODE])  # splice more asm into output
        lines.extend([test_data.add_testcase(label, "cp_hfence_gvma_operand", CG), write_sigupd(ABI_TO_INT["a3"], test_data)])  # splice more asm into output
    lines.extend(twin_data(paging))  # splice more asm into output
    return lines  # finished asm line list


def generate_hfence_gvma_ops_HSmode(test_data: TestData) -> list[str]:  # emitter helper generate_hfence_gvma_ops_HSmode
    """Output ``SvH_hfence_gvma_ops_HSmode-00.S``: HFENCE.GVMA (rs1,rs2) encodings then HLV."""
    return [comment_banner("hfence_gvma_ops_HSmode", "SvH directed coverpoint stimulus"), *build_twins(test_data, _asm_hfence_gvma_ops)]  # file header + twin body


def _asm_hfence_vvma(test_data: TestData, paging: Mode) -> list[str]:  # emitter helper _asm_hfence_vvma
    asid_shift = "44" if paging == "sv39" else "22"  # VMID/ASID field shift for fence ops
    lines = [*set_va_gpa_symbols(paging), *_vs_only_maps(paging), *preload_spa(test_data, 0x257A0901), *_section_banner("Test Cases Start from here")]
    cases = [  # case tuples: num, title, regs, label, asm body
        ("1", "hfence.vvma", 0x257A0901, "test1_all", ["  RVTEST_TSBI_GOTO_SMODE", "  hfence.vvma", *GOTO_MMODE, "  LI(a5, va_data)"]),  # directed case spec tuple
        ("2", "hfence.vvma a5, x0", 0x257A0902, "test2_gva", ["  LI(a5, va_data)", "  RVTEST_TSBI_GOTO_SMODE", "  hfence.vvma a5, x0", *GOTO_MMODE]),  # directed case spec tuple
        ("3", "hfence.vvma x0, a6 and a5,a6", 0x257A0903, "test3_asid", ["  LI(a5, va_data)", "  csrr t0, vsatp", "  LI(t1, 1)", f"  slli t1, t1, {asid_shift}", "  or t0, t0, t1", "  csrw vsatp, t0", "  LI(a6, 1)", "  RVTEST_TSBI_GOTO_SMODE", "  hfence.vvma x0, a6", "  hfence.vvma a5, a6", *GOTO_MMODE]),  # directed case spec tuple
    ]
    for num, op, value, label, prep in cases:  # iterate cases/specs
        lines.extend(_case_header(num, f"{op} then VS lw"))  # case // header
        if num != "1":
            lines.extend(preload_spa(test_data, value))  # splice more asm into output
        lines.extend([*prep, *GOTO_VS, "  lw a3, 0(a5)", "  nop", *GOTO_MMODE])  # splice more asm into output
        lines.extend([test_data.add_testcase(label, "cp_hfence_vvma_operand", CG), write_sigupd(ABI_TO_INT["a3"], test_data)])  # splice more asm into output
    lines.extend(twin_data(paging))  # splice more asm into output
    return lines  # finished asm line list


def generate_hfence_vvma_HSmode(test_data: TestData) -> list[str]:  # emitter helper generate_hfence_vvma_HSmode
    """Output ``SvH_hfence_vvma_HSmode-00.S``: HFENCE.VVMA variants then VS load."""
    return [comment_banner("hfence_vvma_HSmode", "SvH directed coverpoint stimulus"), *build_twins(test_data, _asm_hfence_vvma)]  # file header + twin body


def _mpv_mask(paging: Mode) -> str:  # emitter helper _mpv_mask
    return "MSTATUS_MPV" if paging == "sv39" else "MSTATUSH_MPV"  # CSR/bit-mask name for this twin


def _mpv_csr(paging: Mode) -> str:  # emitter helper _mpv_csr
    return "mstatus" if paging == "sv39" else "mstatush"  # CSR/bit-mask name for this twin


def _asm_mprv_hgatp(test_data: TestData, paging: Mode) -> list[str]:  # emitter helper _asm_mprv_hgatp
    _, g_mode = mode_names(paging)  # expression/ call
    lines = [f"  .set gpa_xonly, {'0x0000000000C002000' if paging == 'sv39' else '0x00C002000'}", f"  .set gpa_rw,    {'0x0000000000C003000' if paging == 'sv39' else '0x00C003000'}"]
    for gpa, region, flags in [("gpa_xonly", "test_region_x", G_XONLY), ("gpa_rw", "test_region_rw", G_RW)]:  # iterate cases/specs
        if paging == "sv39":
            lines.extend([f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, {gpa}, LEVEL2)", f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, {gpa}, LEVEL1)"])  # splice more asm into output
        else:
            lines.append(f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, {gpa}, LEVEL1)")  # splice more asm into output
        lines.append(f"  G_PTE_SETUP({g_mode}, {region}, {flags}, {gpa}, LEVEL0)")  # splice more asm into output
    lines.extend(["  csrw vsatp, x0", "  csrw satp, x0", f"  HGATP_SETUP({g_mode})", *fence_both_stages(), *preload_spa(test_data, 0x257A0151, dest="test_region_x"), *preload_spa(test_data, 0x257A0152, dest="test_region_rw"), *_section_banner("Test Cases Start from here")])  # splice more asm into output
    # Seed keeps MPRV set across cases 2-6; only clear at end of case 7.
    mpv = _mpv_mask(paging)  # MPV bit mask for this XLEN
    mpv_csr = _mpv_csr(paging)  # CSR that holds MPV
    cases = [  # case tuples: num, title, regs, label, asm body, clear MPRV, coverpoint
        ("1", "Direct SPA lw baseline", "a3", "test1_spa", ["  la t1, test_region_x", "  lw a3, 0(t1)"], False, "cp_hgatp_mprv_effects_m"),  # asm: SPA of physical page
        ("2", "MPRV=1 MPP=M lw of SPA", "a4", "test2_m", ["  LI(t0, MSTATUS_MPP)", "  csrc mstatus, t0", "  LI(t0, MPP_MMODE)", "  csrs mstatus, t0", f"  LI(t0, {mpv})", f"  csrc {mpv_csr}, t0", "  LI(t0, MSTATUS_MPRV)", "  csrs mstatus, t0", "  LI(a4, 0)", "  la t1, test_region_x", "  lw a4, 0(t1)", "  nop"], False, "cp_hgatp_mprv_effects_m"),  # asm: SPA/MPRV load
        ("3", "MPRV=1 MPP=S MPV=0 lw of SPA", "a5", "test3_hs", ["  LI(t0, MSTATUS_MPP)", "  csrc mstatus, t0", "  LI(t0, MPP_SMODE)", "  csrs mstatus, t0", "  LI(a5, 0)", "  la t1, test_region_x", "  lw a5, 0(t1)", "  nop"], False, "cp_hgatp_mprv_effects_hs"),  # asm: SPA/MPRV load
        ("4", "MPRV=1 MPP=S MPV=1 lw of X-only GPA", "a6", "test4_vs", [f"  LI(t0, {mpv})", f"  csrs {mpv_csr}, t0", "  LI(a6, 0)", "  LI(t1, gpa_xonly)", "  lw a6, 0(t1)", "  nop"], False, "cp_hgatp_mprv_effects_vs"),  # asm: SPA/MPRV load
        ("5", "MPRV=1 MPP=U MPV=0 lw of SPA", "a7", "test5_u", ["  LI(t0, MSTATUS_MPP)", "  csrc mstatus, t0", f"  LI(t0, {mpv})", f"  csrc {mpv_csr}, t0", "  LI(a7, 0)", "  la t1, test_region_x", "  lw a7, 0(t1)", "  nop"], False, "cp_hgatp_mprv_effects_u"),  # asm: SPA/MPRV load
        ("6", "MPRV=1 MPP=U MPV=1 lw of X-only GPA", "s1", "test6_vu", [f"  LI(t0, {mpv})", f"  csrs {mpv_csr}, t0", "  LI(s1, 0)", "  LI(t1, gpa_xonly)", "  lw s1, 0(t1)", "  nop"], False, "cp_hgatp_mprv_effects_vu"),  # asm: SPA/MPRV load
        ("7", "HLV of R/W GPA ignores MPRV", "s2", "test7_hlv", ["  LI(s2, 0)", "  LI(t1, gpa_rw)", "  hlv.w s2, (t1)", "  nop"], True, "cp_hgatp_mprv_effects_hlv"),  # asm: R/W GPA for HLV
    ]
    for num, title, reg, label, body, clear, coverpoint in cases:  # iterate cases/specs
        lines.extend(_case_header(num, title, "Expected Fault" if num in {"4", "6"} else "Successful"))  # case // header
        lines.extend(body)  # case stimulus asm
        if clear:
            lines.extend(clear_mprv(test_data))  # splice more asm into output
            lines.extend([f"  LI(t0, {mpv})", f"  csrc {mpv_csr}, t0"])  # asm: MPV bitmask into t0
        lines.extend([test_data.add_testcase(label, coverpoint, CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    extra = [*_data_region("test_region_x"), *_data_region("test_region_rw")]  # local setup variable
    lines.extend(data_section(need_test_region=False, need_vlvl0=False, need_hlvl1=paging == "sv39", extra_regions=extra))  # splice more asm into output
    return lines  # finished asm line list


def generate_mprv_hgatp_Mmode(test_data: TestData) -> list[str]:  # emitter helper generate_mprv_hgatp_Mmode
    """Output ``SvH_mprv_hgatp_Mmode-00.S``: MPRV+MPP+MPV with G-stage (``cp_hgatp_mprv_effects``)."""
    return [comment_banner("mprv_hgatp_Mmode", "SvH directed coverpoint stimulus"), *build_twins(test_data, _asm_mprv_hgatp)]  # file header + twin body


def _asm_mprv_sum(test_data: TestData, paging: Mode) -> list[str]:  # emitter helper _asm_mprv_sum
    vs_mode, g_mode = mode_names(paging)  # local setup variable
    lines = [  # U-page VA + two-stage maps + MPRV/SUM setup
        f"  .set va_u, {'0x0000000080010000' if paging == 'sv39' else '0x008001000'}",
        *set_va_gpa_symbols(paging),  # unpack/splice helper output
        *build_two_stage_maps(paging, data_pte=VS_U_RW, g_data_pte=G_RW, with_data=True),  # unpack/splice helper output
        f"  VSATP_SETUP({vs_mode}, GPA)",  # paging macro emission
        f"  HGATP_SETUP({g_mode})",  # paging macro emission
        "  csrw satp, x0",  # Bare satp (HS paging off)
        *fence_both_stages(),  # unpack/splice helper output
        *preload_spa(test_data, 0x257A0C02),  # unpack/splice helper output
        "  LI(t0, MSTATUS_MPP)",  # MPP field mask
        "  csrc mstatus, t0",  # set/clear CSR bit field
        "  LI(t0, MPP_SMODE)",  # set MPP to S or M
        "  csrs mstatus, t0",  # set/clear CSR bit field
        f"  LI(t0, {_mpv_mask(paging)})",
        f"  csrs {_mpv_csr(paging)}, t0",
        "  LI(t0, MSTATUS_MPRV)",  # MPRV load-as-lower-priv bit
        "  csrs mstatus, t0",  # set/clear CSR bit field
        "  LI(t0, SSTATUS_SUM)",  # load immediate constant
        "  csrc sstatus, t0",  # set/clear CSR bit field
        "  csrc vsstatus, t0",  # set/clear CSR bit field
        "  hfence.vvma",  # fence VS-stage TLB after vsatp/PTE change
        *_section_banner("Test Cases Start from here"),
    ]
    cases = [  # case tuples: num, title, regs, label, asm body, expected
        ("1", "MPRV SUM=0 U-page lw", "a3", "test1_sum0", ["  LI(a5, va_u)", "  LI(a3, 0)", "  lw a3, 0(a5)", "  nop"], "Expected Fault"),  # asm: U-page VA
        ("2", "MPRV SUM=1 U-page lw", "a4", "test2_sum1", ["  LI(t0, SSTATUS_SUM)", "  csrs sstatus, t0", "  csrs vsstatus, t0", "  hfence.vvma", "  LI(t0, MSTATUS_MPRV)", "  csrs mstatus, t0", "  LI(a5, va_u)", "  lw a4, 0(a5)", "  nop"], "Successful"),  # SUM=1 U-page lw case
        ("3", "MPRV SUM=1 U-page sw+lw", "a6", "test3_sum1_sw", ["  LI(t0, MSTATUS_MPRV)", "  csrs mstatus, t0", "  LI(a5, va_u)", "  LI(t0, 0x257A0C03)", "  sw t0, 0(a5)", "  nop", "  lw a6, 0(a5)", "  nop"], "Successful"),  # SUM=1 U-page sw+lw case
    ]
    for num, title, reg, label, body, expected in cases:  # iterate cases/specs
        lines.extend(_case_header(num, title, expected))  # case // header
        lines.extend(body)  # case stimulus asm
        lines.extend(clear_mprv(test_data))  # splice more asm into output
        lines.extend([test_data.add_testcase(label, "mprv_sum_effect_hs_two_stage", CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    lines.extend(twin_data(paging))  # splice more asm into output
    return lines  # finished asm line list


def generate_mprv_sum_two_stage_Mmode(test_data: TestData) -> list[str]:  # emitter helper generate_mprv_sum_two_stage_Mmode
    """Output ``SvH_mprv_sum_two_stage_Mmode-00.S``: MPRV as VS on a U-page, SUM=0 then SUM=1."""
    return [comment_banner("mprv_sum_two_stage_Mmode", "SvH directed coverpoint stimulus"), *build_twins(test_data, _asm_mprv_sum)]  # file header + twin body


def _asm_mprv_vsatp(test_data: TestData, paging: Mode) -> list[str]:  # emitter helper _asm_mprv_vsatp
    vs_mode, _ = mode_names(paging)  # local setup variable
    va_s = "0x0000000080010000" if paging == "sv39" else "0x008001000"  # S-page guest VA
    va_u = "0x0000000080020000" if paging == "sv39" else "0x008002000"  # U-page guest VA
    lines = [f"  .set va_s, {va_s}", f"  .set va_u, {va_u}"]  # S/U VA symbols for VS-only maps
    for va in ("va_s", "va_u"):  # iterate cases/specs
        if paging == "sv39":
            lines.extend([f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL2)", f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL1)"])  # splice more asm into output
        else:
            lines.append(f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL1)")  # splice more asm into output
    lines.extend([f"  VS_PTE_SETUP({vs_mode}, PA, test_region_s, {VS_RW}, va_s, LEVEL0)", f"  VS_PTE_SETUP({vs_mode}, PA, test_region_u, {VS_U_RW}, va_u, LEVEL0)", f"  VSATP_SETUP({vs_mode}, PA)", "  csrw hgatp, x0", "  csrw satp, x0", *fence_both_stages(), *preload_spa(test_data, 0x257A0141, dest="test_region_s"), *preload_spa(test_data, 0x257A0142, dest="test_region_u"), *_section_banner("Test Cases Start from here")])  # splice more asm into output
    cases = [  # case tuples: num, title, regs, label, asm body, expected
        ("1", "MPRV=0 raw M-mode load", "a3", "test1_mprv0", [*clear_mprv(test_data), f"  LI(t0, {_mpv_mask(paging)})", f"  csrc {_mpv_csr(paging)}, t0", "  LI(a3, 0)", "  LI(a5, va_s)", "  lw a3, 0(a5)", "  nop"], "Expected Fault"),  # MPRV=0 raw M-mode load (expect fault)
        ("2", "MPRV=1 MPP=S MPV=1 load S-page", "a4", "test2_mprv_s", ["  LI(t0, MSTATUS_MPP)", "  csrc mstatus, t0", "  LI(t0, MPP_SMODE)", "  csrs mstatus, t0", f"  LI(t0, {_mpv_mask(paging)})", f"  csrs {_mpv_csr(paging)}, t0", "  LI(t0, MSTATUS_MPRV)", "  csrs mstatus, t0", "  LI(a4, 0)", "  LI(a5, va_s)", "  lw a4, 0(a5)", "  nop"], "Successful"),  # MPRV=1 MPP=S MPV=1 load S-page
        ("3", "MPRV=1 MPP=U MPV=1 load U-page", "a6", "test3_mprv_u", ["  LI(t0, MSTATUS_MPP)", "  csrc mstatus, t0", "  LI(t0, MSTATUS_MPRV)", "  csrs mstatus, t0", "  LI(a6, 0)", "  LI(a5, va_u)", "  lw a6, 0(a5)", "  nop"], "Successful"),  # MPRV=1 MPP=U MPV=1 load U-page
    ]
    for num, title, reg, label, body, expected in cases:  # iterate cases/specs
        lines.extend(_case_header(num, title, expected))  # case // header
        lines.extend(body)  # case stimulus asm
        lines.extend(clear_mprv(test_data))  # splice more asm into output
        if num == "3":
            lines.extend([f"  LI(t0, {_mpv_mask(paging)})", f"  csrc {_mpv_csr(paging)}, t0"])  # splice more asm into output
        lines.extend([test_data.add_testcase(label, {"1": "cp_vsatp_mprv_effects_off", "2": "cp_vsatp_mprv_effects_s", "3": "cp_vsatp_mprv_effects_u"}[num], CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    extra = [*_data_region("test_region_s"), *_data_region("test_region_u")]  # local setup variable
    lines.extend(data_section(need_test_region=False, need_hlvl0=False, need_hlvl1=False, need_vlvl1=paging == "sv39", extra_regions=extra))  # splice more asm into output
    return lines  # finished asm line list


def generate_mprv_vsatp_Mmode(test_data: TestData) -> list[str]:  # emitter helper generate_mprv_vsatp_Mmode
    """Output ``SvH_mprv_vsatp_Mmode-00.S``: MPRV with VS-only maps, MPP=S/U and MPV."""
    return [comment_banner("mprv_vsatp_Mmode", "SvH directed coverpoint stimulus"), *build_twins(test_data, _asm_mprv_vsatp)]  # file header + twin body


def _asm_tvm(test_data: TestData, paging: Mode) -> list[str]:  # emitter helper _asm_tvm
    mode, shift = ("HGATP_MODE_SV39X4", 60) if paging == "sv39" else ("HGATP_MODE_SV32X4", 31)  # hgatp MODE constant and MODE bit pos
    lines = [  # TVM=0 hgatp write then TVM=1 illegal write
        "  csrw vsatp, x0",  # Bare vsatp (VS paging off)
        "  csrw hgatp, x0",  # Bare hgatp (G paging off)
        "  csrw medeleg, x0",  # no M-mode exception delegation
        "  csrw hedeleg, x0",  # no HS exception delegation
        *_section_banner("Test Cases Start from here"),
        *_case_header("1", f"TVM=0 HS write hgatp.MODE={mode}"),  # unpack/splice helper output
        "  LI(t0, MSTATUS_TVM)",  # TVM trap-on-hgatp-write bit
        "  csrc mstatus, t0",  # set/clear CSR bit field
        *GOTO_HS,  # unpack/splice helper output
        f"  LI(t0, ({mode} << {shift}))",
        "  csrw hgatp, t0",  # write CSR
        *[test_data.add_testcase("test1_hgatp", "cp_hgatp_tvm_effects", CG), gen_csr_read_sigupd(ABI_TO_INT["a4"], ("hgatp", None), test_data)],  # unpack/splice helper output
        *GOTO_MMODE,  # unpack/splice helper output
        *_case_header("2", "TVM=1 HS hgatp write illegal", "Expected Fault"),  # unpack/splice helper output
        "  LI(t0, MSTATUS_TVM)",  # TVM trap-on-hgatp-write bit
        "  csrs mstatus, t0",  # set/clear CSR bit field
        "  LI(a4, 0x257A0131)",  # load immediate constant
        *GOTO_HS,  # unpack/splice helper output
        "  csrw hgatp, x0",  # Bare hgatp (G paging off)
        "  nop",  # pad after access/trap window
        "  addi a4, a4, 1",  # bump marker if no trap (TVM case)
        *GOTO_MMODE,  # unpack/splice helper output
        "  LI(t0, MSTATUS_TVM)",  # TVM trap-on-hgatp-write bit
        "  csrc mstatus, t0",  # set/clear CSR bit field
        *[test_data.add_testcase("test2_marker", "cp_hgatp_tvm_effects", CG), write_sigupd(ABI_TO_INT["a4"], test_data)],  # unpack/splice helper output
        *data_section(need_test_region=False, need_hlvl0=False, need_vlvl0=False),  # unpack/splice helper output
    ]
    return lines  # finished asm line list


def generate_tvm_hgatp_HSmode(test_data: TestData) -> list[str]:  # emitter helper generate_tvm_hgatp_HSmode
    """Output ``SvH_tvm_hgatp_HSmode-00.S``: TVM=0 allows HS ``csrw hgatp``; TVM=1 traps."""
    return [comment_banner("tvm_hgatp_HSmode", "SvH directed coverpoint stimulus"), *build_twins(test_data, _asm_tvm)]  # file header + twin body


def _asm_vs_pte_attr_sv32(test_data: TestData) -> list[str]:  # emitter helper _asm_vs_pte_attr_sv32
    lines = [*set_va_gpa_symbols("sv32"), *_vs_only_maps("sv32"), "  LI(a5, va_data)", *_section_banner("Test Cases Start from here")]
    rsw = [("00", "0", 0x257A0301, "s2", "a3"), ("01", "0x100", 0x257A0302, "s3", "a4"), ("10", "0x200", 0x257A0303, "s4", "a6"), ("11", "PTE_SOFT", 0x257A0304, "s5", "a7")]  # RSW case table
    n = 1  # case number for RSW sw/lw pairs
    for name, flag, value, sw_reg, lw_reg in rsw:  # iterate cases/specs
        if name != "00":
            lines.extend([f"  VS_PTE_SETUP(sv32, PA, test_region, ({VS_RW} | {flag}), va_data, LEVEL0)", "  hfence.vvma"])  # splice more asm into output
        lines.extend(_case_header(str(n), f"RSW={name} VS sw"))  # case // header
        lines.extend([f"  LI(t0, {hex(value)})", *GOTO_VS, "  sw t0, 0(a5)", "  nop", *GOTO_MMODE, "  la t1, test_region", f"  lw {sw_reg}, 0(t1)"])  # splice more asm into output
        lines.extend([test_data.add_testcase(f"test{n}_rsw{name}_sw", "cp_vsatp_pte_rsw", CG), write_sigupd(ABI_TO_INT[sw_reg], test_data)])  # splice more asm into output
        n += 1  # next case number
        lines.extend(_case_header(str(n), f"RSW={name} VS lw only"))  # case // header
        lines.extend(["  hfence.vvma", *GOTO_VS, f"  lw {lw_reg}, 0(a5)", "  nop", *GOTO_MMODE])  # splice more asm into output
        lines.extend([test_data.add_testcase(f"test{n}_rsw{name}_lw", "cp_vsatp_pte_rsw", CG), write_sigupd(ABI_TO_INT[lw_reg], test_data)])  # splice more asm into output
        n += 1  # next case number
    lines.extend(twin_data("sv32"))  # splice more asm into output
    return lines  # finished asm line list


def _asm_vs_pte_attr_sv39(test_data: TestData) -> list[str]:  # emitter helper _asm_vs_pte_attr_sv39
    lines = [
        *RV64_PTE_DEFS,
        "  .set va_code, 0x0000000090000000",  # assembler VA/GPA symbol
        "  .set va_rsw00, 0x0000000080010000",  # assembler VA/GPA symbol
        "  .set va_rsw01, 0x0000000080020000",  # assembler VA/GPA symbol
        "  .set va_rsw10, 0x0000000080030000",  # assembler VA/GPA symbol
        "  .set va_rsw11, 0x0000000080040000",  # assembler VA/GPA symbol
        "  .set va_rsvd,  0x0000000080050000",  # assembler VA/GPA symbol
        "  .set va_pbmt,  0x0000000080060000",  # assembler VA/GPA symbol
        "  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, (PTE_V), va_code, LEVEL2)",  # see macro: paging/mode setup
        f"  SUPERPAGE_VS_PTE_SETUP(sv39, rvtest_code_begin, {PTE_CODE_VS}, va_code, LEVEL1)",  # paging macro emission
        "  csrr a0, mscratch",  # a0 = trap save-area base
        "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # see macro: paging/mode setup
    ]
    for va, flags, region in [("va_rsw00", VS_RW, 0), ("va_rsw01", f"({VS_RW} | 0x100)", 1), ("va_rsw10", f"({VS_RW} | 0x200)", 2), ("va_rsw11", f"({VS_RW} | PTE_SOFT)", 3), ("va_rsvd", f"({VS_RW} | PTE_RSVD_ALL)", 4), ("va_pbmt", f"({VS_RW} | PTE_PBMT3)", 5)]:  # iterate cases/specs
        lines.extend([f"  VS_PTE_SETUP(sv39, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL2)", f"  VS_PTE_SETUP(sv39, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL1)", f"  VS_PTE_SETUP(sv39, PA, test_region{region}, {flags}, {va}, LEVEL0)"])  # splice more asm into output
    lines.extend(["  VSATP_SETUP(sv39, PA)", "  csrw hgatp, x0", *fence_both_stages()])  # splice more asm into output
    for i in range(6):  # iterate cases/specs
        lines.extend(preload_spa(test_data, 0x257A0301 + i, dest=f"test_region{i}"))  # splice more asm into output
    lines.extend(_section_banner("Test Cases Start from here"))  # splice more asm into output
    rsw_cases: list[tuple[str, str, str, str, str | None]] = [("1", "00", "va_rsw00", "a3", None), ("2", "01", "va_rsw01", "a4", "2b"), ("3", "10", "va_rsw10", "a6", "3b"), ("4", "11", "va_rsw11", "a7", "4b")]  # RSW sw+lw and optional lw-only
    for num, name, va, reg, extra in rsw_cases:  # iterate cases/specs
        lines.extend(_case_header(num, f"RSW={name} VS sw+lw"))  # case // header
        lines.extend([f"  LI(a5, {va})", f"  LI(t0, {hex(0x257A0300 + int(num))})", *GOTO_VS, "  sw t0, 0(a5)", "  nop", f"  lw {reg}, 0(a5)", "  nop", *GOTO_MMODE])  # splice more asm into output
        lines.extend([test_data.add_testcase(f"test{num}_rsw{name}", "cp_vsatp_pte_rsw", CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
        if extra:
            exreg = "s2" if extra == "2b" else "s3" if extra == "3b" else "s4"  # GPR for lw-only follow-up
            lines.extend(_case_header(extra, f"RSW={name} VS lw only"))  # case // header
            lines.extend(["  hfence.vvma", f"  LI(a5, {va})", *GOTO_VS, f"  lw {exreg}, 0(a5)", "  nop", *GOTO_MMODE])  # splice more asm into output
            lines.extend([test_data.add_testcase(f"test{extra}_rsw{name}_lw", "cp_vsatp_pte_rsw", CG), write_sigupd(ABI_TO_INT[exreg], test_data)])  # splice more asm into output
    for prefix, bit, reg in [("5a", "PTE_BIT54", "a6"), ("5b", "PTE_BIT55", "a7"), ("5c", "PTE_BIT56", "s2"), ("5d", "PTE_BIT57", "s3"), ("5e", "PTE_BIT58", "s4"), ("5f", "PTE_BIT59", "s5"), ("5g", "PTE_BIT60", "s6"), ("5h", "PTE_RSVD_ALL", "s7")]:  # iterate cases/specs
        lines.extend(_case_header(prefix, f"Reserved {bit} VS lw", "Expected Fault"))  # case // header
        lines.extend([f"  VS_PTE_SETUP(sv39, PA, test_region4, ({VS_RW} | {bit}), va_rsvd, LEVEL0)", "  hfence.vvma", "  LI(a5, va_rsvd)", f"  LI({reg}, 0)", *GOTO_VS, f"  lw {reg}, 0(a5)", "  nop", *GOTO_MMODE])  # splice more asm into output
        lines.extend([test_data.add_testcase(f"test{prefix}_{bit.lower()}", "cp_vsatp_reserved_fields_rw", CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    for prefix, bit in [("6a", "PTE_BIT54"), ("6b", "PTE_BIT55"), ("6c", "PTE_BIT56"), ("6d", "PTE_BIT57"), ("6e", "PTE_BIT58"), ("6f", "PTE_RSVD_ALL")]:  # iterate cases/specs
        lines.extend(_case_header(prefix, f"Reserved {bit} VS sw", "Expected Fault"))  # case // header
        lines.extend([f"  VS_PTE_SETUP(sv39, PA, test_region4, ({VS_RW} | {bit}), va_rsvd, LEVEL0)", "  hfence.vvma", "  LI(a5, va_rsvd)", "  LI(t0, 0xBAD00FAD)", *GOTO_VS, "  sw t0, 0(a5)", "  nop", *GOTO_MMODE, "  la t1, test_region4", "  lw a3, 0(t1)"])  # splice more asm into output
        lines.extend([test_data.add_testcase(f"test{prefix}_sw_{bit.lower()}", "cp_vsatp_reserved_fields_rw", CG), write_sigupd(ABI_TO_INT["a3"], test_data)])  # splice more asm into output
    for prefix, bit, reg, value in [("6g", "PTE_BIT59", "a3", 0x257A0359), ("6h", "PTE_BIT60", "a4", 0x257A0360)]:  # iterate cases/specs
        lines.extend(_case_header(prefix, f"Soft-RSW {bit} VS sw+lw"))  # case // header
        lines.extend([f"  VS_PTE_SETUP(sv39, PA, test_region4, ({VS_RW} | {bit}), va_rsvd, LEVEL0)", "  hfence.vvma", "  LI(a5, va_rsvd)", f"  LI(t0, {hex(value)})", *GOTO_VS, "  sw t0, 0(a5)", "  nop", f"  lw {reg}, 0(a5)", "  nop", *GOTO_MMODE])  # splice more asm into output
        lines.extend([test_data.add_testcase(f"test{prefix}_sw_{bit.lower()}", "cp_vsatp_reserved_fields_rw", CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    lines.extend(_case_header("7", "Reserved bit54 X-leaf VS jalr", "Expected Fault"))  # case // header
    lines.extend([f"  VS_PTE_SETUP(sv39, PA, test_region4, ({PTE_CODE_VS} | PTE_BIT54), va_rsvd, LEVEL0)", "  hfence.vvma", "  LI(a5, va_rsvd)", "  LI(a4, 0)", *GOTO_VS, "  nop", "  jalr ra, a5, 0", "  nop", *GOTO_MMODE])  # splice more asm into output
    lines.extend([test_data.add_testcase("test7_rsvd_jalr", "cp_vsatp_reserved_fields_x", CG), write_sigupd(ABI_TO_INT["a4"], test_data)])  # splice more asm into output
    for prefix, bit, reg, value in [("7b", "PTE_BIT59", "s2", 0x257A0759), ("7c", "PTE_BIT60", "s3", 0x257A0760)]:  # iterate cases/specs
        lines.extend(_case_header(prefix, f"Soft-RSW {bit} X-leaf VS jalr"))  # case // header
        lines.extend([*preload_spa(test_data, 0x00008067, dest="test_region4"), f"  VS_PTE_SETUP(sv39, PA, test_region4, ({PTE_CODE_VS} | {bit}), va_rsvd, LEVEL0)", "  hfence.vvma", "  LI(a5, va_rsvd)", f"  LI({reg}, 0)", *GOTO_VS, "  nop", "  jalr ra, a5, 0", f"  LI({reg}, {hex(value)})", "  nop", *GOTO_MMODE])  # splice more asm into output
        lines.extend([test_data.add_testcase(f"test{prefix}_jalr_{bit.lower()}", "cp_vsatp_reserved_fields_x", CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    lines.extend(["  LI(t0, MENVCFG_PBMTE)", "  csrc menvcfg, t0", "  LI(t0, HENVCFG_PBMTE)", "  csrc henvcfg, t0"])  # toggle PBMTE in menvcfg/henvcfg
    for prefix, bit, reg in [("8a", "PTE_PBMT1", "a6"), ("8b", "PTE_PBMT2", "a7"), ("8c", "PTE_PBMT3", "s2")]:  # iterate cases/specs
        lines.extend(_case_header(prefix, f"{bit} PBMTE=0 VS lw+sw", "Expected Fault"))  # case // header
        lines.extend([f"  VS_PTE_SETUP(sv39, PA, test_region5, ({VS_RW} | {bit}), va_pbmt, LEVEL0)", "  hfence.vvma", "  LI(a5, va_pbmt)", f"  LI({reg}, 0)", *GOTO_VS, f"  lw {reg}, 0(a5)", "  nop", f"  sw {reg}, 0(a5)", "  nop", *GOTO_MMODE])  # splice more asm into output
        lines.extend([test_data.add_testcase(f"test{prefix}_{bit.lower()}_nosup", "cp_vsatp_svpbmt_rw", CG), write_sigupd(ABI_TO_INT[reg], test_data)])  # splice more asm into output
    lines.extend(_case_header("8d", "PBMT=1 X-leaf PBMTE=0 VS jalr", "Expected Fault"))  # case // header
    lines.extend([f"  VS_PTE_SETUP(sv39, PA, test_region5, ({PTE_CODE_VS} | PTE_PBMT1), va_pbmt, LEVEL0)", "  hfence.vvma", "  LI(a5, va_pbmt)", "  LI(s3, 0)", *GOTO_VS, "  nop", "  jalr ra, a5, 0", "  nop", *GOTO_MMODE])  # splice more asm into output
    lines.extend([test_data.add_testcase("test8d_pbmt1_nosup_x", "cp_vsatp_svpbmt_x", CG), write_sigupd(ABI_TO_INT["s3"], test_data)])  # splice more asm into output
    extra_regions: list[str] = []  # collect per-region .data labels
    for i in range(6):  # iterate cases/specs
        extra_regions.extend(_data_region(f"test_region{i}"))  # local setup variable
    lines.extend(data_section(need_test_region=False, need_hlvl0=False, need_hlvl1=False, need_vlvl1=True, extra_regions=extra_regions))  # splice more asm into output
    return lines  # finished asm line list


def generate_vs_pte_attr_VSmode(test_data: TestData) -> list[str]:  # emitter helper generate_vs_pte_attr_VSmode
    """Output ``SvH_vs_pte_attr_VSmode-00.S``: VS RSW, reserved bits, PBMT (Sv39)."""
    return [comment_banner("vs_pte_attr_VSmode", "SvH directed coverpoint stimulus"), *build_twins(test_data, lambda td, p: _asm_vs_pte_attr_sv32(td) if p == "sv32" else _asm_vs_pte_attr_sv39(td))]  # file header + twin body


def _asm_vsbe(test_data: TestData, paging: Mode) -> list[str]:  # emitter helper _asm_vsbe
    """VSBE=0 little-endian check, then VSBE=1 attempt (Sail may force VSBE back to 0)."""
    lines = [
        *set_va_gpa_symbols(paging),  # unpack/splice helper output
        *_vs_only_maps(paging, data_flags=VS_XWR),  # unpack/splice helper output
        "  LI(a5, va_data)",  # load guest VA pointer
        "  LI(s1, 0xA1B2C3D4)",  # load immediate constant
        *_section_banner("Test Cases Start from here"),  # section // banner
        # --- VSBE=0 path (must behave little-endian) ---
        *_case_header("1", "VSBE=0 VS lw after sw"),  # store/load guest memory
        "  LI(t0, HSTATUS_VSBE)",  # VSBE endian control bit
        "  csrc hstatus, t0",  # set/clear CSR bit field
        "  la t1, test_region",  # asm: SPA of physical page
        "  sw x0, 0(t1)",  # clear SPA before VS store
        *GOTO_VS,  # unpack/splice helper output
        "  sw s1, 0(a5)",  # VS store pattern
        "  nop",  # asm: nop padding
        *GOTO_MMODE,  # unpack/splice helper output
        "  hfence.vvma",  # asm: HFENCE.VVMA
        *GOTO_VS,  # unpack/splice helper output
        "  lw a3, 0(a5)",  # asm: load via guest VA
        "  nop",  # asm: nop padding
        *GOTO_MMODE,  # unpack/splice helper output
        *[test_data.add_testcase("test1_vsbe0_lw", "cp_vsatp_endianess", CG), write_sigupd(ABI_TO_INT["a3"], test_data)],  # unpack/splice helper output
        *_case_header("2", "VSBE=0 M-mode SPA readback"),  # case // header
        "  la t1, test_region",  # asm: SPA of physical page
        "  lw t2, 0(t1)",  # load via guest VA or HLV
        *[test_data.add_testcase("test2_vsbe0_spa", "cp_vsatp_endianess", CG), write_sigupd(ABI_TO_INT["t2"], test_data)],  # unpack/splice helper output
        # --- VSBE=1 attempt (Sail legalize_hstatus may keep VSBE=0) ---
        *_case_header("3", "VSBE=1 hstatus readback"),  # case // header
        "  LI(t0, HSTATUS_VSBE)",  # VSBE endian control bit
        "  csrs hstatus, t0",  # try to set VSBE
        *[test_data.add_testcase("test3_vsbe1_hstatus", "cp_vsatp_endianess", CG), gen_csr_read_sigupd(ABI_TO_INT["a4"], ("hstatus", None), test_data)],  # unpack/splice helper output
        *_case_header("4", "VSBE=1 attempt VS lw after sw"),  # store/load guest memory
        "  la t1, test_region",  # asm: SPA of physical page
        "  sw x0, 0(t1)",  # case field string
        *GOTO_VS,  # unpack/splice helper output
        "  sw s1, 0(a5)",  # case field string
        "  nop",  # asm: nop padding
        *GOTO_MMODE,  # unpack/splice helper output
        "  hfence.vvma",  # asm: HFENCE.VVMA
        *GOTO_VS,  # unpack/splice helper output
        "  lw a4, 0(a5)",  # asm: load via guest VA
        "  nop",  # asm: nop padding
        *GOTO_MMODE,  # unpack/splice helper output
        *[test_data.add_testcase("test4_vsbe1_lw", "cp_vsatp_endianess", CG), write_sigupd(ABI_TO_INT["a4"], test_data)],  # unpack/splice helper output
        *_case_header("5", "VSBE=1 attempt M-mode SPA byte view"),  # case // header
        "  la t1, test_region",  # asm: SPA of physical page
        "  lw t3, 0(t1)",  # case field string
        *[test_data.add_testcase("test5_vsbe1_spa", "cp_vsatp_endianess", CG), write_sigupd(ABI_TO_INT["t3"], test_data)],  # unpack/splice helper output
        "  LI(t0, HSTATUS_VSBE)",  # VSBE endian control bit
        "  csrc hstatus, t0",  # leave VSBE clear for any later code
        *twin_data(paging),  # unpack/splice helper output
    ]
    return lines  # finished asm line list


def generate_vsbe_endian_VSmode(test_data: TestData) -> list[str]:  # emitter helper generate_vsbe_endian_VSmode
    """Output ``SvH_vsbe_endian_VSmode-00.S``: VSBE=0 then VSBE=1 endian check (``vsbe_hstatus``)."""
    return [comment_banner("vsbe_endian_VSmode", "SvH directed coverpoint stimulus"), *build_twins(test_data, _asm_vsbe)]  # file header + twin body
