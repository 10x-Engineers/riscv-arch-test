##################################
# priv/extensions/SvHCommon.py
#
# Shared helpers for SvH test generators (hypervisor two-stage paging).
# SPDX-License-Identifier: Apache-2.0
##################################

"""Shared helpers that build RISC-V assembly strings for SvH tests.

Every public function returns a list of assembly lines (or updates counters).
Family files (SvH_twostage, SvH_csr, …) call these helpers; this file never
talks to Sail or the DUT.

Usual order inside one paging twin (sv32 or sv39):
  set_va_gpa_symbols → build_two_stage_maps → enable_two_stage
  → GOTO_VS / GOTO_VU → stimulus → GOTO_MMODE → add_testcase + write_sigupd → twin_data
"""

from __future__ import annotations  # allow forward refs in type hints (Python 3.9 compat)

# typing: literal paging-mode tag; testgen state object for counters/allocators
from typing import Literal

from testgen.data.state import TestData

# Covergroup name written into SIGUPD / testcase metadata (must match coverpoints).
CG = "SvH_cg"

# One paging twin: RV32 builds keep sv32; RV64 builds keep sv39.
Paging = Literal["sv32", "sv39"]

# GPR number -> ABI name for assembler output (allocator hands out numbers).
# Registers 0-4 are intentionally excluded from this mapping and should not be used as scratch:
# 0 (zero) is hardwired to 0; 1 (ra) is return address; 2-4 (sp, gp, tp) are reserved by the framework.
INT_TO_ABI = {
    5: "t0",  # temp
    6: "t1",  # temp
    7: "t2",  # temp
    8: "s0",  # saved
    9: "s1",  # saved
    10: "a0",  # arg / return
    11: "a1",  # arg
    12: "a2",  # arg
    13: "a3",  # arg
    14: "a4",  # arg
    15: "a5",  # arg
    16: "a6",  # arg
    17: "a7",  # arg
    18: "s2",  # saved
    19: "s3",  # saved
    20: "s4",  # saved
    21: "s5",  # saved
    22: "s6",  # saved
    23: "s7",  # saved
    24: "s8",  # saved
    25: "s9",  # saved
    26: "s10",  # saved
    27: "s11",  # saved
    28: "t3",  # temp
    29: "t4",  # temp
    30: "t5",  # temp
    31: "t6",  # temp
}
ABI_TO_INT = {name: reg for reg, name in INT_TO_ABI.items()}  # reverse lookup for rare ABI→number needs

# ---------------------------------------------------------------------------
# Fixed addresses used by page-table macros and coverpoint bins.
# va_*  = guest virtual address (VS-stage input)
# gpa_* = guest physical address (G-stage input)
# ---------------------------------------------------------------------------

VA_CODE = 0x90000000  # guest VA where test code runs (shared across twins)
VA_DATA_SV32 = 0x008001000  # Sv32 guest VA of the data page
VA_DATA_SV39 = 0x0000000080010000  # Sv39 guest VA of the data page (wider VA space)

GPA_CODE_SV32 = 0x012000000  # Sv32 GPA of guest code
GPA_CODE_SV39 = 0x0000000012000000  # Sv39 GPA of guest code
GPA_DATA_SV32 = 0x00C002000  # Sv32 GPA of guest data
GPA_DATA_SV39 = 0x0000000000C002000  # Sv39 GPA of guest data

GPA_VROOT_SV32 = 0x01000A000  # Sv32 GPA of the VS-stage root table
GPA_VLVL0_SV32 = 0x01000B000  # Sv32 GPA of the VS-stage L0 table
GPA_VROOT_SV39 = 0x000000001000A000  # Sv39 GPA of the VS-stage root table
GPA_VLVL0_SV39 = 0x000000001000B000  # Sv39 GPA of the VS-stage L0 table
GPA_VLVL1_SV39 = 0x000000001000C000  # Sv39 GPA of the VS-stage L1 table (3-level walk only)

# Flag text dropped into G_PTE_SETUP / VS_PTE_SETUP.
# G-stage leaves use U=1 because the hypervisor walks G-stage as user accesses.
PTE_CODE_G = "(PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V)"  # G: execute+read, U=1
PTE_DATA_G = "(PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V)"  # G: read+write, U=1
PTE_PT_G = "(PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V)"  # G leaf covering a VS PT page
PTE_V_ONLY = "(PTE_V)"  # valid non-leaf pointer (no R/W/X)
PTE_CODE_VS = "(PTE_D | PTE_A | PTE_X | PTE_R | PTE_V)"  # VS code leaf: execute+read
PTE_DATA_VS = "(PTE_D | PTE_A | PTE_W | PTE_R | PTE_V)"  # VS data leaf: read+write

# Permission-matrix leaf recipes (order D,A,U,X,W,R,V).
PTE_XWR_U = "(PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V)"  # VS/VU rwx, U=1
PTE_XWR_S = "(PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V)"  # VS rwx, U=0
PTE_XR_U = "(PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V)"  # VS xr, U=1
PTE_XR_S = "(PTE_D | PTE_A | PTE_X | PTE_R | PTE_V)"  # VS xr, U=0
PTE_X_ONLY_U = "(PTE_D | PTE_A | PTE_U | PTE_X | PTE_V)"  # VS/VU x-only, U=1
PTE_X_ONLY_S = "(PTE_D | PTE_A | PTE_X | PTE_V)"  # VS x-only, U=0
PTE_R_ONLY_U = "(PTE_D | PTE_A | PTE_U | PTE_R | PTE_V)"  # VS/VU r-only, U=1
PTE_R_ONLY_S = "(PTE_D | PTE_A | PTE_R | PTE_V)"  # VS r-only, U=0
PTE_RW_U = "(PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V)"  # VS/VU rw, U=1
PTE_V_U = "(PTE_D | PTE_A | PTE_U | PTE_V)"  # VS valid-only, U=1
PTE_V_S = "(PTE_D | PTE_A | PTE_V)"  # VS valid-only, U=0
PTE_RW_U_AD0 = "(PTE_U | PTE_W | PTE_R | PTE_V)"  # VS rw U=1, A=D=0 (fault on first touch)
PTE_XWR_S_AD0 = "(PTE_X | PTE_W | PTE_R | PTE_V)"  # VS rwx U=0, A=D=0 (fault on first touch)

# Invalid-leaf recipes (V=0) for two-stage faults.
PTE_XWR_U_V0 = "(PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R)"  # U=1 rwx, V=0
PTE_XR_U_V0 = "(PTE_D | PTE_A | PTE_U | PTE_X | PTE_R)"  # U=1 xr, V=0
PTE_RW_U_V0 = "(PTE_D | PTE_A | PTE_U | PTE_W | PTE_R)"  # U=1 rw, V=0
PTE_XR_S_V0 = "(PTE_D | PTE_A | PTE_X | PTE_R)"  # U=0 xr, V=0
PTE_RW_S_V0 = "(PTE_D | PTE_A | PTE_W | PTE_R)"  # U=0 rw, V=0

# G-stage leaves with G=1 (only for HS HLV/HSV and G-perm tests).
PTE_RW_U_G = "(PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V | PTE_G)"  # rw U=1, G=1
PTE_XWR_U_G = "(PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R | PTE_V | PTE_G)"  # rwx U=1, G=1
PTE_XWR_S_G = "(PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V | PTE_G)"  # rwx U=0, G=1
PTE_X_ONLY_U_G = "(PTE_D | PTE_A | PTE_U | PTE_X | PTE_V | PTE_G)"  # x-only U=1, G=1
PTE_V_U_G = "(PTE_D | PTE_A | PTE_U | PTE_V | PTE_G)"  # valid-only U=1, G=1
PTE_V_S_G = "(PTE_D | PTE_A | PTE_V | PTE_G)"  # valid-only U=0, G=1


# ---------------------------------------------------------------------------
# Paging mode names and Sv32/Sv39 twin wrapping
# ---------------------------------------------------------------------------


def mode_names(paging: Paging) -> tuple[str, str]:
    """Return (vsatp MODE name, hgatp MODE name). G-stage uses Sv*x4."""
    if paging == "sv32":
        return "sv32", "sv32x4"  # RV32: 2-level VS, 2-level G (×4 page size)
    return "sv39", "sv39x4"  # RV64: 3-level VS, 3-level G (×4 page size)


def _ifdef_sv32(lines: list[str]) -> list[str]:
    """Wrap lines so only RV32 (SV32_SUPPORTED) keeps them."""
    return ["#ifdef SV32_SUPPORTED", *lines, "#endif  // SV32_SUPPORTED"]  # preprocessor guard for Sv32 twin


def _ifdef_sv39(lines: list[str]) -> list[str]:
    """Wrap lines so only RV64 (SV39_SUPPORTED) keeps them."""
    return ["#ifdef SV39_SUPPORTED", *lines, "#endif  // SV39_SUPPORTED"]  # preprocessor guard for Sv39 twin


def combine_twins(asm_sv32: list[str], asm_sv39: list[str]) -> list[str]:
    """Put Sv32 and Sv39 bodies in one .S file; only one ifdef is live per build."""
    return [*_ifdef_sv32(asm_sv32), *_ifdef_sv39(asm_sv39)]  # concatenate both guarded twins


def build_twins(test_data: TestData, asm_for_paging) -> list[str]:
    """Build Sv32 and Sv39 assembly, then combine them under ifdefs.

    asm_for_paging(test_data, paging) must return assembly lines and may bump
    SIGUPD counters. Only one twin runs after preprocess, so we keep
    max(sv32, sv39) — not the sum — for SIGUPD_COUNT.
    """
    assert test_data.test_chunk is not None  # make_svh always opens a chunk first
    start_sig = test_data.test_chunk.sigupd_count  # count before either twin
    start_num = test_data.test_chunk.num_testcases  # testcase count before either twin
    start_strs = len(test_data.test_chunk.data_strings)  # string count before either twin
    asm_sv32 = asm_for_paging(test_data, "sv32")  # build Sv32 body (may bump counters)
    sig32 = test_data.test_chunk.sigupd_count  # SIGUPD slots used by Sv32 twin
    num32 = test_data.test_chunk.num_testcases  # testcases recorded by Sv32 twin
    sv32_strs = test_data.test_chunk.data_strings[start_strs:]  # Sv32-only .data strings
    test_data.test_chunk.sigupd_count = start_sig  # rewind: only one twin runs, don't double-count
    test_data.test_chunk.num_testcases = start_num  # rewind testcase counter for Sv39 pass
    del test_data.test_chunk.data_strings[start_strs:]  # drop Sv32 strings before Sv39 rebuild
    asm_sv39 = asm_for_paging(test_data, "sv39")  # build Sv39 body on clean counters
    sig39 = test_data.test_chunk.sigupd_count  # SIGUPD slots used by Sv39 twin
    num39 = test_data.test_chunk.num_testcases  # testcases recorded by Sv39 twin
    sv39_strs = test_data.test_chunk.data_strings[start_strs:]  # Sv39-only .data strings
    test_data.test_chunk.sigupd_count = max(sig32, sig39)  # header size = larger twin (both ifdef'd)
    test_data.test_chunk.num_testcases = max(num32, num39)  # same rule for testcase metadata
    test_data.test_chunk.data_strings[start_strs:] = combine_twins(sv32_strs, sv39_strs)  # merge .data under ifdefs
    return combine_twins(asm_sv32, asm_sv39)  # merge code bodies under ifdefs


# ---------------------------------------------------------------------------
# .set va_code / gpa_data / …  (symbols page-table macros use later)
# ---------------------------------------------------------------------------


def _set_sv32_symbols(*, with_data: bool = True, with_vlvl0: bool = True) -> list[str]:
    """Assembler .set lines for the Sv32 twin (2-level walk, no vlvl1)."""
    lines = [
        f"  .set va_code,                 {hex(VA_CODE)}",  # guest code VA symbol
        f"  .set gpa_code,                {hex(GPA_CODE_SV32)}",  # guest code GPA symbol
        f"  .set gpa_rvtest_Vroot_pg_tbl, {hex(GPA_VROOT_SV32)}",  # VS root table GPA
    ]
    if with_vlvl0:
        lines.append(f"  .set gpa_rvtest_vlvl0_pg_tbl, {hex(GPA_VLVL0_SV32)}")  # VS L0 table GPA
    if with_data:
        lines.extend(
            [
                f"  .set va_data,                 {hex(VA_DATA_SV32)}",  # guest data VA symbol
                f"  .set gpa_data,                {hex(GPA_DATA_SV32)}",  # guest data GPA symbol
            ]
        )
    return lines


def _set_sv39_symbols(*, with_data: bool = True) -> list[str]:
    """Assembler .set lines for the Sv39 twin (3-level walk, includes vlvl1)."""
    lines = [
        f"  .set va_code,                 {hex(VA_CODE)}",  # guest code VA symbol
        f"  .set gpa_code,                {hex(GPA_CODE_SV39)}",  # guest code GPA symbol
        f"  .set gpa_rvtest_Vroot_pg_tbl, {hex(GPA_VROOT_SV39)}",  # VS root table GPA
        f"  .set gpa_rvtest_vlvl1_pg_tbl, {hex(GPA_VLVL1_SV39)}",  # VS L1 table GPA (Sv39 only)
        f"  .set gpa_rvtest_vlvl0_pg_tbl, {hex(GPA_VLVL0_SV39)}",  # VS L0 table GPA
    ]
    if with_data:
        lines.extend(
            [
                f"  .set va_data,                 {hex(VA_DATA_SV39)}",  # guest data VA symbol
                f"  .set gpa_data,                {hex(GPA_DATA_SV39)}",  # guest data GPA symbol
            ]
        )
    return lines


def set_va_gpa_symbols(paging: Paging, *, with_data: bool = True, with_vlvl0: bool = True) -> list[str]:
    """Emit .set va_* / gpa_* for this paging twin."""
    if paging == "sv32":
        return _set_sv32_symbols(with_data=with_data, with_vlvl0=with_vlvl0)  # 2-level symbol set
    return _set_sv39_symbols(with_data=with_data)  # 3-level symbol set


# ---------------------------------------------------------------------------
# Page-table setup macros (G-stage then VS-stage)
# ---------------------------------------------------------------------------


def _page_table_macros(
    *,
    g_mode: str,  # hgatp MODE name (sv32x4 or sv39x4)
    code_lvl: str,  # leaf level for guest code mapping
    with_data: bool = True,  # also map va_data / gpa_data
    data_g_flags: str = PTE_DATA_G,
    data_vs_flags: str = PTE_DATA_VS,
    code_g_flags: str = PTE_CODE_G,
    code_vs_flags: str = PTE_CODE_VS,
    g_data_pa_lbl: str = "test_region",
) -> list[str]:
    """Emit G_PTE_SETUP / VS_PTE_SETUP for a guest that runs at va_code.

    Two walks:
      G-stage: GPA → real SPA (always as U-mode, so G leaves have U=1)
      VS-stage: VA  → GPA

    V_SAVE_AREA_SETUP is required when code VA != code PA.
    """
    lines: list[str] = []
    if g_mode == "sv39x4":
        # --- G-stage: code + VS page-table pages + optional data ---
        lines.append(f"  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_code, LEVEL2)")  # G L2→hlvl1 for code
        lines.append(  # G superpage/leaf for guest code SPA
            f"  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, {code_g_flags}, gpa_code, {code_lvl})"  # map gpa_code→code
        )
        lines.append(  # G non-leaf toward VS root GPA
            f"  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_rvtest_Vroot_pg_tbl, LEVEL1)"  # G L1→hlvl0
        )
        lines.append(  # G leaf covering VS root page
            f"  G_PTE_SETUP(sv39x4, rvtest_Vroot_pg_tbl, {PTE_PT_G}, gpa_rvtest_Vroot_pg_tbl, LEVEL0)"  # VS root SPA
        )
        lines.append(  # G leaf covering VS L1 page
            f"  G_PTE_SETUP(sv39x4, rvtest_vlvl1_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl1_pg_tbl, LEVEL0)"  # VS L1 SPA
        )
        lines.append(  # G leaf covering VS L0 page
            f"  G_PTE_SETUP(sv39x4, rvtest_vlvl0_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)"  # VS L0 SPA
        )
        if with_data:
            lines.append(f"  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)")  # G L1 for data
            lines.append(f"  G_PTE_SETUP(sv39x4, {g_data_pa_lbl}, {data_g_flags}, gpa_data, LEVEL0)")  # G data leaf
        # --- VS-stage: va_code → gpa_code, then relocate save area ---
        lines.append(  # VS L2 non-leaf for code VA
            f"  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_code, LEVEL2)"
        )
        lines.append(f"  VS_PTE_SETUP(sv39, GPA, gpa_code, {code_vs_flags}, va_code, LEVEL1)")  # VS L1 code leaf VA→GPA
        lines.append("  csrr a0, mscratch")  # read trap save pointer into a0 for V_SAVE_AREA_SETUP
        lines.append("  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)")  # relocate trap save area to mapped VA
        if with_data:
            lines.append(  # VS L2 non-leaf for data VA
                f"  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL2)"
            )
            lines.append(  # VS L1 non-leaf for data VA
                f"  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)"
            )
            lines.append(f"  VS_PTE_SETUP(sv39, GPA, gpa_data, {data_vs_flags}, va_data, LEVEL0)")  # VS L0 data leaf
    else:
        # --- Sv32: two-level walk (no LEVEL2) ---
        lines.append(  # G superpage/leaf for guest code
            f"  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, {code_g_flags}, gpa_code, {code_lvl})"  # gpa_code→code
        )
        lines.append(  # G non-leaf toward VS root
            f"  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_rvtest_Vroot_pg_tbl, LEVEL1)"  # G L1→hlvl0
        )
        lines.append(  # G leaf covering VS root page
            f"  G_PTE_SETUP(sv32x4, rvtest_Vroot_pg_tbl, {PTE_PT_G}, gpa_rvtest_Vroot_pg_tbl, LEVEL0)"  # VS root SPA
        )
        lines.append(  # G leaf covering VS L0 page
            f"  G_PTE_SETUP(sv32x4, rvtest_vlvl0_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)"  # VS L0 SPA
        )
        if with_data:
            lines.append(f"  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)")  # G L1 for data
            lines.append(f"  G_PTE_SETUP(sv32x4, {g_data_pa_lbl}, {data_g_flags}, gpa_data, LEVEL0)")  # G data leaf
        lines.append(f"  VS_PTE_SETUP(sv32, GPA, gpa_code, {code_vs_flags}, va_code, LEVEL1)")  # VS code leaf VA→GPA
        lines.append("  csrr a0, mscratch")  # read trap save pointer into a0 for V_SAVE_AREA_SETUP
        lines.append("  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)")  # relocate trap save area to mapped VA
        if with_data:
            lines.append(  # VS L1 non-leaf for data VA
                f"  VS_PTE_SETUP(sv32, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)"
            )
            lines.append(f"  VS_PTE_SETUP(sv32, GPA, gpa_data, {data_vs_flags}, va_data, LEVEL0)")  # VS data leaf
    return lines


def build_two_stage_maps(
    paging: Paging,
    *,
    code_pte: str = PTE_CODE_VS,
    data_pte: str = PTE_DATA_VS,
    g_code_pte: str = PTE_CODE_G,
    g_data_pte: str = PTE_DATA_G,
    g_data_pa_lbl: str = "test_region",
    with_data: bool = True,  # include data mappings
    code_lvl: str = "LEVEL1",  # code leaf level in G/VS macros
) -> list[str]:
    """Build G-stage + VS-stage page tables for this paging twin."""
    _, g_mode = mode_names(paging)  # hgatp MODE (sv32x4 or sv39x4)
    return _page_table_macros(
        g_mode=g_mode,  # selects Sv32 vs Sv39 G-stage walk depth
        code_lvl=code_lvl,  # superpage/leaf level for guest code
        with_data=with_data,  # omit data VA/GPA maps when False
        data_g_flags=g_data_pte,  # G data leaf permission bits
        data_vs_flags=data_pte,  # VS data leaf permission bits
        code_g_flags=g_code_pte,  # G code leaf permission bits
        code_vs_flags=code_pte,  # VS code leaf permission bits
        g_data_pa_lbl=g_data_pa_lbl,  # physical label for G data leaf PPN
    )


# ---------------------------------------------------------------------------
# Enable / disable translation and TLB fences
# ---------------------------------------------------------------------------


def enable_vs_and_g(vs_mode: str, g_mode: str) -> list[str]:
    """Write vsatp and hgatp, then fence both stages."""
    # When G-stage is Sv*x4, VS leaves store GPAs (not PAs).
    vs_ppn_kind = "GPA" if g_mode.endswith("x4") else "PA"  # VS PPN is GPA under two-stage
    return [
        f"  VSATP_SETUP({vs_mode}, {vs_ppn_kind})",  # vsatp.MODE + root PPN (GPA or PA)
        f"  HGATP_SETUP({g_mode})",  # hgatp.MODE + G-stage root PPN
        "  hfence.vvma",  # flush VS-stage TLB after vsatp write
        "  hfence.gvma",  # flush G-stage TLB after hgatp write
    ]


def enable_two_stage(paging: Paging) -> list[str]:
    """Enable vsatp + hgatp for this twin and fence both stages."""
    vs_mode, g_mode = mode_names(paging)  # resolve MODE strings for this twin
    return enable_vs_and_g(vs_mode, g_mode)  # write CSRs and fence


def enable_vs_only(vs_mode: str) -> list[str]:
    """Enable VS-stage only; hgatp stays Bare (VS leaf PPNs are PAs)."""
    return [
        f"  VSATP_SETUP({vs_mode}, PA)",  # VS leaves store supervisor PAs (hgatp Bare)
        "  csrw hgatp, x0",  # G-stage off → identity GPA=SPA
        "  hfence.vvma",  # flush VS TLB
        "  hfence.gvma",  # flush G TLB (no-op when Bare, but spec-safe)
    ]


def disable_paging() -> list[str]:
    """Clear vsatp and hgatp (identity addresses; use T-SBI hops)."""
    return [
        "  csrw vsatp, x0",  # VS-stage off
        "  csrw hgatp, x0",  # G-stage off
        "  hfence.vvma",  # flush VS TLB
        "  hfence.gvma",  # flush G TLB
    ]


def fence_both_stages() -> list[str]:
    """Flush VS-stage and G-stage TLBs after a PTE rewrite."""
    return ["  hfence.vvma", "  hfence.gvma"]  # VS then G fence pair


def clear_mprv(test_data: TestData) -> list[str]:
    """Clear mstatus.MPRV before SIGUPD when the signature is not guest-mapped."""
    # Exclude 0 (zero, hardwired) and 1 (ra, return address) to prevent silent test failures or crashes
    regs = test_data.int_regs.get_registers(1, exclude_regs=[0, 1])  # borrow one scratch GPR
    mask = INT_TO_ABI[regs[0]]  # assembler name for the temp register
    lines = [
        f"  LI({mask}, MSTATUS_MPRV)",  # load MPRV bit mask constant
        f"  csrc mstatus, {mask}",  # clear MPRV so SIGUPD uses M-mode mapping
    ]
    test_data.int_regs.return_registers(regs)  # return scratch to allocator pool
    return lines


# ---------------------------------------------------------------------------
# Privilege hops (VA≠PA guest must return with goto_mmode, not TSBI a0=1)
# ---------------------------------------------------------------------------

GOTO_VS = ["  RVTEST_GOTO_LOWER_MODE VSmode"]  # drop from M to guest VS
GOTO_VU = ["  RVTEST_GOTO_LOWER_MODE VUmode"]  # drop from M/HS/VS to guest VU
GOTO_HS = ["  RVTEST_GOTO_LOWER_MODE HSmode"]  # drop from M to hypervisor HS
GOTO_MMODE = ["  RVTEST_GOTO_MMODE"]  # return to M-mode (required when VA≠PA)


# ---------------------------------------------------------------------------
# Simple stimulus helpers
# ---------------------------------------------------------------------------


def preload_spa(test_data: TestData, value: int, *, dest: str = "test_region") -> list[str]:
    """Store a known pattern to the physical page from M-mode (allocator-chosen temps)."""
    # Exclude 0 (zero, hardwired) and 1 (ra, return address) to prevent silent test failures or crashes
    regs = test_data.int_regs.get_registers(2, exclude_regs=[0, 1])  # pattern reg + address reg
    pattern, addr = INT_TO_ABI[regs[0]], INT_TO_ABI[regs[1]]  # map numbers to ABI names
    lines = [
        f"  LI({pattern}, {hex(value)})",  # known pattern guest loads should see if allowed
        f"  la {addr}, {dest}",  # load physical page label address
        f"  sw {pattern}, 0({addr})",  # store pattern to start of physical page
    ]
    test_data.int_regs.return_registers(regs)  # return temps to allocator pool
    return lines


def load_guest_va(reg: str = "a5", symbol: str = "va_data") -> list[str]:
    """Put the guest data VA into a register for a later guest load/store."""
    return [f"  LI({reg}, {symbol})"]  # materialize guest VA constant into register


def set_g_data_leaf(paging: Paging, flags: str, *, pa_lbl: str = "test_region") -> list[str]:
    """Overwrite the G-stage data leaf after the initial maps."""
    _, g_mode = mode_names(paging)  # hgatp MODE for G_PTE_SETUP
    return [f"  G_PTE_SETUP({g_mode}, {pa_lbl}, {flags}, gpa_data, LEVEL0)"]  # rewrite G data PTE in place


def set_vs_data_leaf(
    paging: Paging,  # twin selects vsatp MODE
    flags: str,  # new VS leaf PTE bits
    *,
    ppn_kind: Literal["GPA", "PA"] = "GPA",  # how leaf PPN is interpreted
    ppn: str | None = None,
    va: str = "va_data",
) -> list[str]:
    """Overwrite the VS-stage data leaf. Use PA when hgatp is Bare; GPA for two-stage."""
    vs_mode, _ = mode_names(paging)  # vsatp MODE for VS_PTE_SETUP
    if ppn is None:
        ppn = "gpa_data" if ppn_kind == "GPA" else "test_region"  # default PPN label by stage
    return [f"  VS_PTE_SETUP({vs_mode}, {ppn_kind}, {ppn}, {flags}, {va}, LEVEL0)"]  # rewrite VS data PTE


def two_stage_setup(  # symbols + maps + enable in one call
    paging: Paging,
    *,
    data_pte: str = PTE_DATA_VS,
    g_data_pte: str = PTE_DATA_G,  # G data leaf flags
    code_pte: str = PTE_CODE_VS,
    with_data: bool = True,  # include data maps
) -> list[str]:
    """Symbols + two-stage maps + enable vsatp/hgatp + fences (one twin)."""
    vs_mode, g_mode = mode_names(paging)  # resolve CSR MODE strings
    lines: list[str] = []
    lines.extend(set_va_gpa_symbols(paging, with_data=with_data))  # .set va/gpa symbols first
    lines.extend(
        build_two_stage_maps(  # G + VS page-table macros
            paging,
            code_pte=code_pte,  # VS code leaf flags
            data_pte=data_pte,  # VS data leaf flags
            g_data_pte=g_data_pte,  # G data leaf flags
            with_data=with_data,
        )
    )
    lines.extend(enable_vs_and_g(vs_mode, g_mode))  # turn on translation + fence
    return lines


# ---------------------------------------------------------------------------
# SIGUPD / signature helpers
# Testcases are recorded with test_data.add_testcase() and then dumped with
# write_sigupd() / gen_csr_read_sigupd(). Both pair calls also bump the SIGUPD
# counter, so the header size always matches the number of emitted checks.
# ---------------------------------------------------------------------------


def data_section(  # .data pages, tables
    *,
    need_test_region: bool = True,  # physical data page
    need_hlvl0: bool = True,
    need_vlvl0: bool = True,
    need_hlvl1: bool = False,
    need_vlvl1: bool = False,
    extra_regions: list[str] | None = None,  # caller-supplied .data lines
) -> list[str]:
    """Emit .pushsection .data storage for pages, tables, and testcase strings."""
    lines = ["", ".pushsection .data"]  # open writable data section
    if need_test_region:
        lines.extend(
            [
                ".p2align 12",  # 4 KiB page alignment
                "test_region:",  # label for physical data page
                "  .word 0",  # first word of page
                "  .word 0",  # pad word
                "  .word 0",  # pad word
                "  .word 0",  # pad word
            ]
        )
    if extra_regions:
        lines.extend(extra_regions)  # append caller-defined .data blobs
    if need_hlvl1:
        lines.extend([".p2align 12", "rvtest_hlvl1_pg_tbl:", "  .zero 4096"])  # 4 KiB G L1 table
    if need_hlvl0:
        lines.extend([".p2align 12", "rvtest_hlvl0_pg_tbl:", "  .zero 4096"])  # 4 KiB G L0 table
    if need_vlvl1:
        lines.extend([".p2align 12", "rvtest_vlvl1_pg_tbl:", "  .zero 4096"])  # 4 KiB VS L1 table
    if need_vlvl0:
        lines.extend([".p2align 12", "rvtest_vlvl0_pg_tbl:", "  .zero 4096"])  # 4 KiB VS L0 table
    lines.extend([".popsection", ""])  # close .data section
    return lines


def twin_data(paging: Paging) -> list[str]:
    """Data section for one paging twin (Sv39 also allocates LEVEL1 tables)."""
    return data_section(  # default pages + twin-specific L1 tables
        need_hlvl1=(paging == "sv39"),  # G L1 only for 3-level Sv39 walk
        need_vlvl1=(paging == "sv39"),  # VS L1 only for 3-level Sv39 walk
    )
