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
  → goto_vs / goto_vu → stimulus → goto_mmode → sigupd_* → twin_data
"""

from __future__ import annotations  # postpone annotation evaluation

from pathlib import Path  # filesystem paths for test output dir
from typing import Literal  # restrict paging twin to sv32/sv39

from testgen.asm.csr import gen_csr_read_sigupd  # CSR read into signature
from testgen.asm.helpers import write_sigupd  # GPR dump into signature
from testgen.data.state import TestData  # live testcase / SIGUPD counters

# Covergroup name written into SIGUPD / testcase metadata (must match coverpoints).
CG = "SvH_cg"  # covergroup tag for add_testcase / SIGUPD

# One paging twin: RV32 builds keep sv32; RV64 builds keep sv39.
Paging = Literal["sv32", "sv39"]  # which address-translation twin to emit

# ---------------------------------------------------------------------------
# Fixed addresses used by page-table macros and coverpoint bins.
# va_*  = guest virtual address (VS-stage input)
# gpa_* = guest physical address (G-stage input)
# ---------------------------------------------------------------------------

VA_CODE = 0x90000000  # guest VA where relocated VS/VU code runs
VA_DATA_SV32 = 0x008001000  # Sv32 guest VA of the data page
VA_DATA_SV39 = 0x0000000080010000  # Sv39 guest VA of the data page

GPA_CODE_SV32 = 0x012000000  # Sv32 GPA of guest code
GPA_CODE_SV39 = 0x0000000012000000  # Sv39 GPA of guest code
GPA_DATA_SV32 = 0x00C002000  # Sv32 GPA of guest data
GPA_DATA_SV39 = 0x0000000000C002000  # Sv39 GPA of guest data

GPA_VROOT_SV32 = 0x01000A000  # Sv32 GPA of the VS-stage root table
GPA_VLVL0_SV32 = 0x01000B000  # Sv32 GPA of the VS-stage L0 table
GPA_VROOT_SV39 = 0x000000001000A000  # Sv39 GPA of the VS-stage root table
GPA_VLVL0_SV39 = 0x000000001000B000  # Sv39 GPA of the VS-stage L0 table
GPA_VLVL1_SV39 = 0x000000001000C000  # Sv39 GPA of the VS-stage L1 table

# Flag text dropped into G_PTE_SETUP / VS_PTE_SETUP.
# G-stage leaves use U=1 because the hypervisor walks G-stage as user accesses.
PTE_CODE_G = "(PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V)"  # G: execute+read, U=1
PTE_DATA_G = "(PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V)"  # G: read+write, U=1
PTE_PT_G = "(PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V)"  # G leaf covering a VS PT page
PTE_V_ONLY = "(PTE_V)"  # non-leaf pointer: V=1 only (continue the walk)
PTE_CODE_VS = "(PTE_D | PTE_A | PTE_X | PTE_R | PTE_V)"  # VS code leaf, U=0
PTE_DATA_VS = "(PTE_D | PTE_A | PTE_W | PTE_R | PTE_V)"  # VS data leaf, U=0


# ---------------------------------------------------------------------------
# Output directory cleanup
# ---------------------------------------------------------------------------


def delete_old_asm_files() -> Path:  # wipe stale SvH .S before regen
    """Delete old tests/priv/SvH/*.S so a renamed test cannot leave a leftover file."""
    # Walk up from this file to the riscv-arch-test/ root.
    root = Path(__file__).resolve().parents[6]  # riscv-arch-test repo root
    if not (root / "tests" / "priv").is_dir():  # sanity-check layout
        raise RuntimeError(f"Cannot find riscv-arch-test root from {__file__}: got {root}")  # bad path
    out = root / "tests" / "priv" / "SvH"  # writer output directory
    out.mkdir(parents=True, exist_ok=True)  # create suite dir if missing
    for old in out.glob("*.S"):  # every previously generated assembly file
        old.unlink()  # remove so make testgen cannot pick up a stale name
    return out  # callers write new .S files here


# ---------------------------------------------------------------------------
# Paging mode names and Sv32/Sv39 twin wrapping
# ---------------------------------------------------------------------------


def mode_names(paging: Paging) -> tuple[str, str]:  # vsatp MODE, hgatp MODE
    """Return (vsatp MODE name, hgatp MODE name). G-stage uses Sv*x4."""
    if paging == "sv32":  # RV32 two-level twin
        return "sv32", "sv32x4"  # RV32 twin
    return "sv39", "sv39x4"  # RV64 twin


def _ifdef_sv32(lines: list[str]) -> list[str]:  # wrap for RV32-only builds
    """Wrap lines so only RV32 (SV32_SUPPORTED) keeps them."""
    return ["#ifdef SV32_SUPPORTED", *lines, "#endif  // SV32_SUPPORTED"]  # C preprocessor gate


def _ifdef_sv39(lines: list[str]) -> list[str]:  # wrap for RV64-only builds
    """Wrap lines so only RV64 (SV39_SUPPORTED) keeps them."""
    return ["#ifdef SV39_SUPPORTED", *lines, "#endif  // SV39_SUPPORTED"]  # C preprocessor gate


def combine_twins(asm_sv32: list[str], asm_sv39: list[str]) -> list[str]:  # one .S, two ifdefs
    """Put Sv32 and Sv39 bodies in one .S file; only one ifdef is live per build."""
    return [*_ifdef_sv32(asm_sv32), *_ifdef_sv39(asm_sv39)]  # concatenate gated twins


def build_twins(test_data: TestData, asm_for_paging) -> list[str]:  # build both twins safely
    """Build Sv32 and Sv39 assembly, then combine them under ifdefs.

    asm_for_paging(test_data, paging) must return assembly lines and may bump
    SIGUPD counters. Only one twin runs after preprocess, so we keep
    max(sv32, sv39) — not the sum — for SIGUPD_COUNT.
    """
    assert test_data.test_chunk is not None  # make_svh always opens a chunk first
    start_sig = test_data.test_chunk.sigupd_count  # count before either twin
    start_num = test_data.test_chunk.num_testcases  # testcase count before either twin
    asm_sv32 = asm_for_paging(test_data, "sv32")  # build Sv32; may bump counters
    sig32 = test_data.test_chunk.sigupd_count  # after Sv32
    num32 = test_data.test_chunk.num_testcases  # testcases after Sv32 twin
    test_data.test_chunk.sigupd_count = start_sig  # rewind so Sv39 does not add on top
    test_data.test_chunk.num_testcases = start_num  # rewind testcase counter too
    asm_sv39 = asm_for_paging(test_data, "sv39")  # build Sv39 from the same start
    sig39 = test_data.test_chunk.sigupd_count  # after Sv39
    num39 = test_data.test_chunk.num_testcases  # testcases after Sv39 twin
    test_data.test_chunk.sigupd_count = max(sig32, sig39)  # header uses the larger twin
    test_data.test_chunk.num_testcases = max(num32, num39)  # same for testcase count
    return combine_twins(asm_sv32, asm_sv39)  # emit both under ifdefs


# ---------------------------------------------------------------------------
# .set va_code / gpa_data / …  (symbols page-table macros use later)
# ---------------------------------------------------------------------------


def _set_sv32_symbols(*, with_data: bool = True, with_vlvl0: bool = True) -> list[str]:  # Sv32 .set block
    """Assembler .set lines for the Sv32 twin (2-level walk, no vlvl1)."""
    lines = [  # start symbol list
        f"  .set va_code,                 {hex(VA_CODE)}",  # guest VA of relocated code
        f"  .set gpa_code,                {hex(GPA_CODE_SV32)}",  # GPA of that code
        f"  .set gpa_rvtest_Vroot_pg_tbl, {hex(GPA_VROOT_SV32)}",  # GPA of VS root table
    ]  # end core Sv32 symbols
    if with_vlvl0:  # most tests need VS L0 GPA
        lines.append(f"  .set gpa_rvtest_vlvl0_pg_tbl, {hex(GPA_VLVL0_SV32)}")  # GPA of VS L0
    if with_data:  # optional guest data page symbols
        lines.extend(  # append data VA/GPA pair
            [  # data VA/GPA .set lines
                f"  .set va_data,                 {hex(VA_DATA_SV32)}",  # guest VA of data
                f"  .set gpa_data,                {hex(GPA_DATA_SV32)}",  # GPA of data
            ]  # end data symbols
        )  # close extend
    return lines  # assembler .set lines for Sv32


def _set_sv39_symbols(*, with_data: bool = True) -> list[str]:  # Sv39 .set block
    """Assembler .set lines for the Sv39 twin (3-level walk, includes vlvl1)."""
    lines = [  # start symbol list
        f"  .set va_code,                 {hex(VA_CODE)}",  # guest VA of relocated code
        f"  .set gpa_code,                {hex(GPA_CODE_SV39)}",  # GPA of that code
        f"  .set gpa_rvtest_Vroot_pg_tbl, {hex(GPA_VROOT_SV39)}",  # GPA of VS root table
        f"  .set gpa_rvtest_vlvl1_pg_tbl, {hex(GPA_VLVL1_SV39)}",  # extra level vs Sv32
        f"  .set gpa_rvtest_vlvl0_pg_tbl, {hex(GPA_VLVL0_SV39)}",  # GPA of VS L0 table
    ]  # end core Sv39 symbols
    if with_data:  # optional guest data page symbols
        lines.extend(  # append data VA/GPA pair
            [  # data VA/GPA .set lines
                f"  .set va_data,                 {hex(VA_DATA_SV39)}",  # guest VA of data
                f"  .set gpa_data,                {hex(GPA_DATA_SV39)}",  # GPA of data
            ]  # end data symbols
        )  # close extend
    return lines  # assembler .set lines for Sv39


def set_va_gpa_symbols(paging: Paging, *, with_data: bool = True, with_vlvl0: bool = True) -> list[str]:  # dispatch twin
    """Emit .set va_* / gpa_* for this paging twin."""
    if paging == "sv32":  # RV32 twin
        return _set_sv32_symbols(with_data=with_data, with_vlvl0=with_vlvl0)  # two-level symbols
    return _set_sv39_symbols(with_data=with_data)  # three-level symbols


# ---------------------------------------------------------------------------
# Page-table setup macros (G-stage then VS-stage)
# ---------------------------------------------------------------------------


def _page_table_macros(  # emit G_PTE_SETUP / VS_PTE_SETUP asm lines
    *,  # keyword-only args below
    g_mode: str,  # hgatp MODE name (sv32x4 or sv39x4)
    code_lvl: str,  # leaf level for guest code mapping
    with_data: bool = True,  # also map va_data / gpa_data
    data_g_flags: str = PTE_DATA_G,  # G-stage data leaf PTE bits
    data_vs_flags: str = PTE_DATA_VS,  # VS-stage data leaf PTE bits
    code_g_flags: str = PTE_CODE_G,  # G-stage code leaf PTE bits
    code_vs_flags: str = PTE_CODE_VS,  # VS-stage code leaf PTE bits
    g_data_pa_lbl: str = "test_region",  # SPA label for G data leaf
) -> list[str]:  # returns assembly macro lines
    """Emit G_PTE_SETUP / VS_PTE_SETUP for a guest that runs at va_code.

    Two walks:
      G-stage: GPA → real SPA (always as U-mode, so G leaves have U=1)
      VS-stage: VA  → GPA

    V_SAVE_AREA_SETUP is required when code VA != code PA.
    """
    lines: list[str] = []  # accumulate emitted asm lines
    if g_mode == "sv39x4":  # Sv39 three-level G-stage walk
        # --- G-stage: code + VS page-table pages + optional data ---
        lines.append(f"  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_code, LEVEL2)")  # G L2→hlvl1 for code
        lines.append(  # G superpage/leaf for guest code SPA
            f"  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, {code_g_flags}, gpa_code, {code_lvl})"  # map gpa_code→code
        )  # close append
        lines.append(  # G non-leaf toward VS root GPA
            f"  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_rvtest_Vroot_pg_tbl, LEVEL1)"  # G L1→hlvl0
        )  # close append
        lines.append(  # G leaf covering VS root page
            f"  G_PTE_SETUP(sv39x4, rvtest_Vroot_pg_tbl, {PTE_PT_G}, gpa_rvtest_Vroot_pg_tbl, LEVEL0)"  # VS root SPA
        )  # close append
        lines.append(  # G leaf covering VS L1 page
            f"  G_PTE_SETUP(sv39x4, rvtest_vlvl1_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl1_pg_tbl, LEVEL0)"  # VS L1 SPA
        )  # close append
        lines.append(  # G leaf covering VS L0 page
            f"  G_PTE_SETUP(sv39x4, rvtest_vlvl0_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)"  # VS L0 SPA
        )  # close append
        if with_data:  # map guest data through G-stage
            lines.append(f"  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)")  # G L1 for data
            lines.append(f"  G_PTE_SETUP(sv39x4, {g_data_pa_lbl}, {data_g_flags}, gpa_data, LEVEL0)")  # G data leaf
        # --- VS-stage: va_code → gpa_code, then relocate save area ---
        lines.append(  # VS L2 non-leaf for code VA
            f"  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_code, LEVEL2)"  # → vlvl1
        )  # close append
        lines.append(f"  VS_PTE_SETUP(sv39, GPA, gpa_code, {code_vs_flags}, va_code, LEVEL1)")  # VS code leaf→GPA
        lines.append("  csrr a0, mscratch")  # save-area pointer for V_SAVE_AREA_SETUP
        lines.append("  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)")  # relocate trap save area
        if with_data:  # VS-stage map for guest data VA
            lines.append(  # VS L2 non-leaf for data VA
                f"  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL2)"  # → vlvl1
            )  # close append
            lines.append(  # VS L1 non-leaf for data VA
                f"  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)"  # → vlvl0
            )  # close append
            lines.append(f"  VS_PTE_SETUP(sv39, GPA, gpa_data, {data_vs_flags}, va_data, LEVEL0)")  # VS data leaf
    else:  # Sv32 two-level walks
        # --- Sv32: two-level walk (no LEVEL2) ---
        lines.append(  # G superpage/leaf for guest code
            f"  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, {code_g_flags}, gpa_code, {code_lvl})"  # gpa_code→code
        )  # close append
        lines.append(  # G non-leaf toward VS root
            f"  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_rvtest_Vroot_pg_tbl, LEVEL1)"  # G L1→hlvl0
        )  # close append
        lines.append(  # G leaf covering VS root page
            f"  G_PTE_SETUP(sv32x4, rvtest_Vroot_pg_tbl, {PTE_PT_G}, gpa_rvtest_Vroot_pg_tbl, LEVEL0)"  # VS root SPA
        )  # close append
        lines.append(  # G leaf covering VS L0 page
            f"  G_PTE_SETUP(sv32x4, rvtest_vlvl0_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)"  # VS L0 SPA
        )  # close append
        if with_data:  # map guest data through G-stage
            lines.append(f"  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)")  # G L1 for data
            lines.append(f"  G_PTE_SETUP(sv32x4, {g_data_pa_lbl}, {data_g_flags}, gpa_data, LEVEL0)")  # G data leaf
        lines.append(f"  VS_PTE_SETUP(sv32, GPA, gpa_code, {code_vs_flags}, va_code, LEVEL1)")  # VS code leaf→GPA
        lines.append("  csrr a0, mscratch")  # save-area pointer for V_SAVE_AREA_SETUP
        lines.append("  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)")  # relocate trap save area
        if with_data:  # VS-stage map for guest data VA
            lines.append(  # VS L1 non-leaf for data VA
                f"  VS_PTE_SETUP(sv32, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)"  # → vlvl0
            )  # close append
            lines.append(f"  VS_PTE_SETUP(sv32, GPA, gpa_data, {data_vs_flags}, va_data, LEVEL0)")  # VS data leaf
    return lines  # all G then VS setup macros


def build_two_stage_maps(  # public wrapper around _page_table_macros
    paging: Paging,  # which twin (sv32/sv39)
    *,  # keyword-only PTE overrides below
    code_pte: str = PTE_CODE_VS,  # VS-stage code leaf flags
    data_pte: str = PTE_DATA_VS,  # VS-stage data leaf flags
    g_code_pte: str = PTE_CODE_G,  # G-stage code leaf flags
    g_data_pte: str = PTE_DATA_G,  # G-stage data leaf flags
    g_data_pa_lbl: str = "test_region",  # SPA label under G data leaf
    with_data: bool = True,  # include data mappings
    code_lvl: str = "LEVEL1",  # code leaf level in G/VS macros
) -> list[str]:  # assembly page-table setup lines
    """Build G-stage + VS-stage page tables for this paging twin."""
    _, g_mode = mode_names(paging)  # need hgatp MODE (Sv*x4)
    return _page_table_macros(  # emit G then VS macros
        g_mode=g_mode,  # sv32x4 or sv39x4
        code_lvl=code_lvl,  # code leaf level
        with_data=with_data,  # optional data maps
        data_g_flags=g_data_pte,  # G data PTE bits
        data_vs_flags=data_pte,  # VS data PTE bits
        code_g_flags=g_code_pte,  # G code PTE bits
        code_vs_flags=code_pte,  # VS code PTE bits
        g_data_pa_lbl=g_data_pa_lbl,  # physical label for data
    )  # close call


# ---------------------------------------------------------------------------
# Enable / disable translation and TLB fences
# ---------------------------------------------------------------------------


def enable_vs_and_g(vs_mode: str, g_mode: str) -> list[str]:  # write both satp CSRs + fences
    """Write vsatp and hgatp, then fence both stages."""
    # When G-stage is Sv*x4, VS leaves store GPAs (not PAs).
    vs_ppn_kind = "GPA" if g_mode.endswith("x4") else "PA"  # VS PPN is GPA under two-stage
    return [  # enable both stages
        f"  VSATP_SETUP({vs_mode}, {vs_ppn_kind})",  # vsatp.MODE + root PPN
        f"  HGATP_SETUP({g_mode})",  # hgatp.MODE + root PPN
        "  hfence.vvma",  # flush VS-stage TLB
        "  hfence.gvma",  # flush G-stage TLB
    ]  # end enable sequence


def enable_two_stage(paging: Paging) -> list[str]:  # enable for this twin
    """Enable vsatp + hgatp for this twin and fence both stages."""
    vs_mode, g_mode = mode_names(paging)  # MODE names for this twin
    return enable_vs_and_g(vs_mode, g_mode)  # write CSRs and fence


def enable_vs_only(vs_mode: str) -> list[str]:  # VS paging, G Bare
    """Enable VS-stage only; hgatp stays Bare (VS leaf PPNs are PAs)."""
    return [  # single-stage VS setup
        f"  VSATP_SETUP({vs_mode}, PA)",  # VS leaves store supervisor PAs
        "  csrw hgatp, x0",  # G-stage Bare
        "  hfence.vvma",  # flush VS TLB
        "  hfence.gvma",  # flush G TLB
    ]  # end VS-only enable


def disable_paging() -> list[str]:  # clear both satps
    """Clear vsatp and hgatp (identity addresses; use T-SBI hops)."""
    return [  # Bare both stages
        "  csrw vsatp, x0",  # clear VS-stage
        "  csrw hgatp, x0",  # clear G-stage
        "  hfence.vvma",  # flush VS TLB
        "  hfence.gvma",  # flush G TLB
    ]  # end disable


def fence_both_stages() -> list[str]:  # TLB shootdown only
    """Flush VS-stage and G-stage TLBs after a PTE rewrite."""
    return ["  hfence.vvma", "  hfence.gvma"]  # VS then G fence


def clear_mprv() -> list[str]:  # drop MPRV before SIGUPD
    """Clear mstatus.MPRV before SIGUPD when the signature is not guest-mapped."""
    return [  # clear MPRV bit
        "  LI(t0, MSTATUS_MPRV)",  # mask for MPRV
        "  csrc mstatus, t0",  # clear it in mstatus
    ]  # end clear


# ---------------------------------------------------------------------------
# Privilege hops (VA≠PA guest must return with goto_mmode, not TSBI a0=1)
# ---------------------------------------------------------------------------


def goto_vs() -> list[str]:  # drop into VS-mode
    """Enter VS-mode with VA≠PA relocate."""
    return ["  RVTEST_GOTO_LOWER_MODE VSmode"]  # hop to VS


def goto_vu() -> list[str]:  # drop into VU-mode
    """Enter VU-mode with VA≠PA relocate."""
    return ["  RVTEST_GOTO_LOWER_MODE VUmode"]  # hop to VU


def goto_hs() -> list[str]:  # drop into HS-mode
    """Enter HS-mode."""
    return ["  RVTEST_GOTO_LOWER_MODE HSmode"]  # hop to HS


def goto_mmode() -> list[str]:  # return to M before SIGUPD
    """Return to M-mode before SIGUPD (signature region is not guest-mapped)."""
    return ["  RVTEST_GOTO_MMODE"]  # hop back to M


# ---------------------------------------------------------------------------
# Simple stimulus helpers
# ---------------------------------------------------------------------------


def preload_spa(value: int, *, dest: str = "test_region") -> list[str]:  # M-mode store pattern
    """Store a known pattern to the physical page from M-mode."""
    return [  # write pattern at SPA
        f"  LI(t0, {hex(value)})",  # pattern guest loads should see if allowed
        f"  la t1, {dest}",  # SPA of the data page
        "  sw t0, 0(t1)",  # store word to physical page
    ]  # end preload


def load_guest_va(reg: str = "a5", symbol: str = "va_data") -> list[str]:  # put VA in a reg
    """Put the guest data VA into a register for a later guest load/store."""
    return [f"  LI({reg}, {symbol})"]  # load guest VA constant


def pte_bits(  # build PTE flag expression text
    *,  # keyword-only bit flags
    x: bool = False,  # execute permission
    w: bool = False,  # write permission
    r: bool = False,  # read permission
    u: bool = False,  # user-accessible (needed on G leaves)
    v: bool = True,  # valid bit
    a: bool = True,  # accessed bit
    d: bool = True,  # dirty bit
) -> str:  # "(PTE_D | …)" string for macros
    """Build a ``(PTE_D | PTE_A | …)`` expression from individual bits."""
    parts: list[str] = []  # collect enabled flag names
    if d:  # Dirty
        parts.append("PTE_D")  # include D
    if a:  # Accessed
        parts.append("PTE_A")  # include A
    if u:  # User
        parts.append("PTE_U")  # include U
    if x:  # eXecute
        parts.append("PTE_X")  # include X
    if w:  # Write
        parts.append("PTE_W")  # include W
    if r:  # Read
        parts.append("PTE_R")  # include R
    if v:  # Valid
        parts.append("PTE_V")  # include V
    if not parts:  # no bits selected
        return "(0)"  # empty PTE flags
    return "(" + " | ".join(parts) + ")"  # OR them for the macro


def set_g_data_leaf(paging: Paging, flags: str, *, pa_lbl: str = "test_region") -> list[str]:  # rewrite G data PTE
    """Overwrite the G-stage data leaf after the initial maps."""
    _, g_mode = mode_names(paging)  # need G MODE name
    return [f"  G_PTE_SETUP({g_mode}, {pa_lbl}, {flags}, gpa_data, LEVEL0)"]  # replace G data leaf


def set_vs_data_leaf(  # rewrite VS data PTE
    paging: Paging,  # twin selects vsatp MODE
    flags: str,  # new VS leaf PTE bits
    *,  # keyword-only below
    ppn_kind: Literal["GPA", "PA"] = "GPA",  # how leaf PPN is interpreted
    ppn: str | None = None,  # optional override of PPN symbol
    va: str = "va_data",  # guest VA for this leaf
) -> list[str]:  # one VS_PTE_SETUP line
    """Overwrite the VS-stage data leaf. Use PA when hgatp is Bare; GPA for two-stage."""
    vs_mode, _ = mode_names(paging)  # need vsatp MODE
    if ppn is None:  # pick default PPN symbol
        ppn = "gpa_data" if ppn_kind == "GPA" else "test_region"  # GPA vs SPA label
    return [f"  VS_PTE_SETUP({vs_mode}, {ppn_kind}, {ppn}, {flags}, {va}, LEVEL0)"]  # replace VS data leaf


def two_stage_setup(  # symbols + maps + enable in one call
    paging: Paging,  # which twin
    *,  # keyword-only PTE overrides
    data_pte: str = PTE_DATA_VS,  # VS data leaf flags
    g_data_pte: str = PTE_DATA_G,  # G data leaf flags
    code_pte: str = PTE_CODE_VS,  # VS code leaf flags
    with_data: bool = True,  # include data maps
) -> list[str]:  # full setup asm for one twin
    """Symbols + two-stage maps + enable vsatp/hgatp + fences (one twin)."""
    vs_mode, g_mode = mode_names(paging)  # MODE names for enable
    lines: list[str] = []  # accumulate setup asm
    lines.extend(set_va_gpa_symbols(paging, with_data=with_data))  # .set va/gpa symbols
    lines.extend(  # append page-table macros
        build_two_stage_maps(  # G + VS maps
            paging,  # twin
            code_pte=code_pte,  # VS code flags
            data_pte=data_pte,  # VS data flags
            g_data_pte=g_data_pte,  # G data flags
            with_data=with_data,  # optional data
        )  # close maps call
    )  # close extend
    lines.extend(enable_vs_and_g(vs_mode, g_mode))  # write satps + fences
    return lines  # complete twin setup


# ---------------------------------------------------------------------------
# SIGUPD / signature helpers
# ---------------------------------------------------------------------------


def count_sigupds(test_data: TestData, n: int) -> None:  # bump both counters
    """Add n to both sigupd_count and num_testcases on the open chunk."""
    assert test_data.test_chunk is not None  # chunk must be open
    test_data.test_chunk.sigupd_count += n  # SIGUPD slots in header
    test_data.test_chunk.num_testcases += n  # matching testcase count


def add_sigupd_count(test_data: TestData, n: int) -> None:  # bump SIGUPD only
    """Add n to sigupd_count only (used when cases are counted separately)."""
    if test_data.test_chunk is not None and n > 0:  # only if chunk open and positive
        test_data.test_chunk.sigupd_count += n  # grow signature size


def sigupd_gpr(  # coverpoint + GPR SIGUPD
    test_data: TestData,  # live counters
    check_reg: int,  # which xN to dump
    bin_name: str,  # coverpoint bin label
    coverpoint: str,  # coverpoint name
    *,  # keyword-only
    covergroup: str = CG,  # usually SvH_cg
) -> list[str]:  # asm lines for one check
    """Record a coverpoint bin and dump one GPR into the signature."""
    return [  # testcase then SIGUPD
        test_data.add_testcase(bin_name, coverpoint, covergroup),  # register bin metadata
        write_sigupd(check_reg, test_data),  # dump GPR to signature
    ]  # end sigupd_gpr


def sigupd_csr(  # coverpoint + CSR SIGUPD
    test_data: TestData,  # live counters
    check_reg: int,  # temp GPR for CSR value
    csr_name: str,  # CSR to read
    bin_name: str,  # coverpoint bin label
    coverpoint: str,  # coverpoint name
    *,  # keyword-only
    covergroup: str = CG,  # usually SvH_cg
    mask: int | None = None,  # optional CSR field mask
    mask_reg: int | None = None,  # optional mask GPR
) -> list[str]:  # asm lines for one check
    """Record a coverpoint bin and dump one CSR read into the signature."""
    return [  # testcase then CSR SIGUPD
        test_data.add_testcase(bin_name, coverpoint, covergroup),  # register bin metadata
        gen_csr_read_sigupd(check_reg, (csr_name, mask), test_data, mask_reg=mask_reg),  # read CSR→sig
    ]  # end sigupd_csr


def sigupd_labeled(label: str, check_reg: str = "a3") -> list[str]:  # fixed-label SIGUPD
    """Emit RVTEST_SIGUPD with a fixed label. Caller must count_sigupds."""
    return [  # label + SIGUPD macro
        f"  {label}:",  # local label for this check
        f"  RVTEST_SIGUPD(x2, x5, x4, {check_reg}, {label}, {label}_str)",  # dump with mismatch string
    ]  # end labeled sigupd


def mismatch_string(label: str, message: str) -> str:  # .string for SIGUPD fail text
    """Emit the .string referenced by RVTEST_SIGUPD on mismatch."""
    return f'{label}_str: .string "\\"{message}\\""'  # assembler string for fail message


def data_section(  # .data pages, tables, mismatch strings
    *,  # keyword-only region flags
    need_test_region: bool = True,  # physical data page
    need_hlvl0: bool = True,  # G-stage L0 table page
    need_vlvl0: bool = True,  # VS-stage L0 table page
    need_hlvl1: bool = False,  # G-stage L1 (Sv39)
    need_vlvl1: bool = False,  # VS-stage L1 (Sv39)
    extra_regions: list[str] | None = None,  # caller-supplied .data lines
    mismatch_strings: list[str] | None = None,  # SIGUPD fail .string lines
) -> list[str]:  # .pushsection … .popsection block
    """Emit .pushsection .data storage for pages, tables, and mismatch strings."""
    lines = ["", ".pushsection .data"]  # open .data section
    if need_test_region:  # guest/physical data page storage
        lines.extend(  # allocate test_region
            [  # physical test_region page
                ".p2align 12",  # 4 KiB page alignment
                "test_region:",  # SPA label used by G_PTE_SETUP
                "  .word 0",  # first word of page
                "  .word 0",  # pad
                "  .word 0",  # pad
                "  .word 0",  # pad
            ]  # end test_region
        )  # close extend
    if extra_regions:  # optional extra .data blobs
        lines.extend(extra_regions)  # append caller lines
    if need_hlvl1:  # Sv39 G-stage mid-level table
        lines.extend([".p2align 12", "rvtest_hlvl1_pg_tbl:", "  .zero 4096"])  # 4 KiB G L1
    if need_hlvl0:  # G-stage leaf-level table
        lines.extend([".p2align 12", "rvtest_hlvl0_pg_tbl:", "  .zero 4096"])  # 4 KiB G L0
    if need_vlvl1:  # Sv39 VS-stage mid-level table
        lines.extend([".p2align 12", "rvtest_vlvl1_pg_tbl:", "  .zero 4096"])  # 4 KiB VS L1
    if need_vlvl0:  # VS-stage leaf-level table
        lines.extend([".p2align 12", "rvtest_vlvl0_pg_tbl:", "  .zero 4096"])  # 4 KiB VS L0
    if mismatch_strings:  # fail messages for labeled SIGUPD
        lines.extend(mismatch_strings)  # append .string lines
    lines.extend([".popsection", ""])  # close .data section
    return lines  # full data block


def twin_data(paging: Paging, *, mismatch_strings: list[str] | None = None) -> list[str]:  # data for one twin
    """Data section for one paging twin (Sv39 also allocates LEVEL1 tables)."""
    return data_section(  # default pages + twin-specific L1
        need_hlvl1=(paging == "sv39"),  # G L1 only for Sv39
        need_vlvl1=(paging == "sv39"),  # VS L1 only for Sv39
        mismatch_strings=mismatch_strings,  # optional fail strings
    )  # close call
