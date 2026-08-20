##################################
# priv/extensions/SvHCommon.py
#
# Shared emit helpers for SvH privileged testgen (hypervisor two-stage).
# SPDX-License-Identifier: Apache-2.0
##################################

"""Shared assembly emitters for SvH family modules.

Family ``generate_*`` functions compose these helpers. This module only
returns lists of assembly strings; it does not execute on the DUT.

Typical sequence:
  ``emit_va_gpa_sets``, ``emit_two_stage_maps``, ``emit_enable_paging``,
  guest hop (``emit_goto_vs`` / ``emit_goto_vu``), stimulus, ``emit_goto_mmode``,
  ``twin_data_section``.
"""

from __future__ import annotations  # allow Path | None style annotations if added later

from pathlib import Path  # filesystem path to riscv-arch-test/ and tests/priv/SvH
from typing import Literal  # Paging / GuestMode string unions

from testgen.asm.csr import gen_csr_read_sigupd  # CSR-read SIGUPD assembly
from testgen.asm.helpers import write_sigupd  # GPR SIGUPD assembly
from testgen.data.state import TestData  # open TestChunk (sigupd_count, num_testcases)

CG = "SvH_cg"  # covergroup name stamped into SIGUPD / testcase strings
Paging = Literal["sv32", "sv39"]  # one paging twin; RV32 compiles sv32, RV64 compiles sv39
GuestMode = Literal["VS", "VU", "HS", "M"]  # privilege used for hops

# ---------------------------------------------------------------------------
# Canonical VA/GPA values used by page-table macros and coverpoints.
# va_*  = guest virtual address (VS-stage input)
# gpa_* = guest physical address (G-stage input)
# Numeric values must match the directed seeds / coverpoint address bins.
# ---------------------------------------------------------------------------

VA_CODE = 0x90000000  # guest VA where relocated VS/VU code executes
VA_DATA_SV32 = 0x008001000  # Sv32 guest VA of the data page
VA_DATA_SV39 = 0x0000000080010000  # Sv39 guest VA of the data page (same VPN layout, 64-bit)

GPA_CODE_SV32 = 0x012000000  # Sv32 GPA of guest code (G-stage maps this to rvtest_code_begin)
GPA_CODE_SV39 = 0x0000000012000000  # Sv39 GPA of guest code
GPA_DATA_SV32 = 0x00C002000  # Sv32 GPA of guest data (G-stage maps this to test_region)
GPA_DATA_SV39 = 0x0000000000C002000  # Sv39 GPA of guest data

GPA_VROOT_SV32 = 0x01000A000  # Sv32 GPA of the VS-stage root page table
GPA_VLVL0_SV32 = 0x01000B000  # Sv32 GPA of the VS-stage L0 table
GPA_VROOT_SV39 = 0x000000001000A000  # Sv39 GPA of the VS-stage root
GPA_VLVL0_SV39 = 0x000000001000B000  # Sv39 GPA of the VS-stage L0 table
GPA_VLVL1_SV39 = 0x000000001000C000  # Sv39 GPA of the VS-stage L1 table (third walk level)

# Text dropped into G_PTE_SETUP / VS_PTE_SETUP. G-stage leaves need U=1
# because the hypervisor walks G-stage as user accesses.
PTE_CODE_G = "(PTE_D | PTE_A | PTE_U | PTE_X | PTE_R | PTE_V)"  # G leaf: execute + read, U=1
PTE_DATA_G = "(PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V)"  # G leaf: read + write, U=1
PTE_PT_G = "(PTE_D | PTE_A | PTE_U | PTE_W | PTE_R | PTE_V)"  # G leaf covering a VS page-table page
PTE_V_ONLY = "(PTE_V)"  # non-leaf pointer: V=1, no R/W/X (continue the walk)
PTE_CODE_VS = "(PTE_D | PTE_A | PTE_X | PTE_R | PTE_V)"  # VS code leaf: U=0 (supervisor guest)
PTE_DATA_VS = "(PTE_D | PTE_A | PTE_W | PTE_R | PTE_V)"  # VS data leaf: read + write, U=0
PTE_XONLY_VS = "(PTE_D | PTE_A | PTE_X | PTE_V)"  # VS execute-only (MXR tests)
PTE_RONLY_VS = "(PTE_D | PTE_A | PTE_R | PTE_V)"  # VS read-only


def arch_test_root() -> Path:
    """Walk up from this file to the riscv-arch-test/ directory."""
    root = Path(__file__).resolve().parents[6]  # .../priv/extensions → riscv-arch-test
    if not (root / "tests" / "priv").is_dir():  # sanity check we landed on the repo root
        raise RuntimeError(f"Cannot resolve riscv-arch-test root from {__file__}: got {root}")
    return root  # used by clean_svh_output_dir


def clean_svh_output_dir() -> Path:
    """Delete old generated .S so a renamed scenario cannot leave a stale file."""
    out = arch_test_root() / "tests" / "priv" / "SvH"  # writer output directory
    out.mkdir(parents=True, exist_ok=True)  # create the suite dir if this is a fresh tree
    for old in out.glob("*.S"):  # every previously generated assembly file
        old.unlink()  # remove it so make testgen cannot pick up a renamed leftover
    return out  # callers may log the path; make_svh ignores the return


def paging_modes(paging: Paging) -> tuple[str, str]:
    """vsatp MODE name, then hgatp MODE name (G-stage is Sv*x4)."""
    if paging == "sv32":  # RV32 twin
        return "sv32", "sv32x4"  # vsatp Sv32, hgatp Sv32x4
    return "sv39", "sv39x4"  # RV64 twin: vsatp Sv39, hgatp Sv39x4


def ifdef_sv32(lines: list[str]) -> list[str]:
    """RV32 builds keep this block; RV64 preprocessor drops it."""
    return ["#ifdef SV32_SUPPORTED", *lines, "#endif  // SV32_SUPPORTED"]


def ifdef_sv39(lines: list[str]) -> list[str]:
    """RV64 builds keep this block; RV32 preprocessor drops it."""
    return ["#ifdef SV39_SUPPORTED", *lines, "#endif  // SV39_SUPPORTED"]


def wrap_sv32_sv39(body_sv32: list[str], body_sv39: list[str]) -> list[str]:
    """One source file, two paging modes. Only one ifdef is live per build."""
    return [*ifdef_sv32(body_sv32), *ifdef_sv39(body_sv39)]  # concatenate both ifdef wrappers


def emit_twin(
    test_data: TestData,
    body_fn,
) -> list[str]:
    """Call body_fn twice (sv32 then sv39) and wrap with ifdefs.

    body_fn bumps SIGUPD counts. Only one branch compiles, so we keep
    max(sv32, sv39) — not the sum — for SIGUPD_COUNT in the header.
    """
    assert test_data.test_chunk is not None  # make_svh always opens a chunk before generate_*
    start_sig = test_data.test_chunk.sigupd_count  # SIGUPD count before either twin runs
    start_num = test_data.test_chunk.num_testcases  # testcase count before either twin runs
    body_sv32 = body_fn(test_data, "sv32")  # emit Sv32 assembly; increments chunk counters
    sig32 = test_data.test_chunk.sigupd_count  # SIGUPD count after the Sv32 body
    num32 = test_data.test_chunk.num_testcases  # testcase count after the Sv32 body
    test_data.test_chunk.sigupd_count = start_sig  # rewind so Sv39 does not add on top of Sv32
    test_data.test_chunk.num_testcases = start_num  # rewind testcase count the same way
    body_sv39 = body_fn(test_data, "sv39")  # emit Sv39 assembly from the same starting counts
    sig39 = test_data.test_chunk.sigupd_count  # SIGUPD count after the Sv39 body
    num39 = test_data.test_chunk.num_testcases  # testcase count after the Sv39 body
    test_data.test_chunk.sigupd_count = max(sig32, sig39)  # header SIGUPD_COUNT = larger twin
    test_data.test_chunk.num_testcases = max(num32, num39)  # header testcase count = larger twin
    return wrap_sv32_sv39(body_sv32, body_sv39)  # both bodies in one .S, gated by SV32/SV39 ifdefs


# ---------------------------------------------------------------------------
# .set va_code / gpa_data / …  — symbols the PT macros use later
# ---------------------------------------------------------------------------

def emit_va_gpa_sets_sv32(*, with_data: bool = True, with_vlvl0: bool = True) -> list[str]:
    """Sv32 names: 2-level walk, so no vlvl1 GPA."""
    lines = [  # assembler .set symbols consumed by G_PTE_SETUP / VS_PTE_SETUP
        f"  .set va_code,                 {hex(VA_CODE)}",  # guest VA of relocated test code
        f"  .set gpa_code,                {hex(GPA_CODE_SV32)}",  # GPA of that code (G-stage input)
        f"  .set gpa_rvtest_Vroot_pg_tbl, {hex(GPA_VROOT_SV32)}",  # GPA of the VS-stage root table
    ]
    if with_vlvl0:  # most tests need the VS L0 table GPA; omit only if the seed never named it
        lines.append(f"  .set gpa_rvtest_vlvl0_pg_tbl, {hex(GPA_VLVL0_SV32)}")  # GPA of VS L0 table
    if with_data:  # omit when the test has no data leaf (ifetch-only)
        lines.extend(
            [
                f"  .set va_data,                 {hex(VA_DATA_SV32)}",  # guest VA of the data page
                f"  .set gpa_data,                {hex(GPA_DATA_SV32)}",  # GPA of the data page
            ]
        )
    return lines  # list of .set lines for the Sv32 twin


def emit_va_gpa_sets_sv39(*, with_data: bool = True) -> list[str]:
    """Sv39 names: 3-level walk, so we also name vlvl1."""
    lines = [  # assembler .set symbols consumed by G_PTE_SETUP / VS_PTE_SETUP
        f"  .set va_code,                 {hex(VA_CODE)}",  # guest VA of relocated test code
        f"  .set gpa_code,                {hex(GPA_CODE_SV39)}",  # GPA of that code (G-stage input)
        f"  .set gpa_rvtest_Vroot_pg_tbl, {hex(GPA_VROOT_SV39)}",  # GPA of the VS-stage root table
        f"  .set gpa_rvtest_vlvl1_pg_tbl, {hex(GPA_VLVL1_SV39)}",  # GPA of the VS-stage L1 table
        f"  .set gpa_rvtest_vlvl0_pg_tbl, {hex(GPA_VLVL0_SV39)}",  # GPA of the VS-stage L0 table
    ]
    if with_data:  # omit when the test has no data leaf (ifetch-only)
        lines.extend(
            [
                f"  .set va_data,                 {hex(VA_DATA_SV39)}",  # guest VA of the data page
                f"  .set gpa_data,                {hex(GPA_DATA_SV39)}",  # GPA of the data page
            ]
        )
    return lines  # list of .set lines for the Sv39 twin


def emit_va_gpa_sets(paging: Paging, *, with_data: bool = True, with_vlvl0: bool = True) -> list[str]:
    """Dispatch to the Sv32 or Sv39 .set emitter."""
    if paging == "sv32":  # RV32 twin: two-level names, optional vlvl0
        return emit_va_gpa_sets_sv32(with_data=with_data, with_vlvl0=with_vlvl0)
    return emit_va_gpa_sets_sv39(with_data=with_data)  # RV64 twin: always includes vlvl1


def emit_two_stage_page_tables(
    *,
    g_mode: str,
    vs_mode: str,
    code_lvl: str,
    with_data: bool = True,
    data_g_flags: str = PTE_DATA_G,
    data_vs_flags: str = PTE_DATA_VS,
    code_g_flags: str = PTE_CODE_G,
    code_vs_flags: str = PTE_CODE_VS,
    g_data_pa_lbl: str = "test_region",
) -> list[str]:
    """Write G_PTE_SETUP / VS_PTE_SETUP for a guest that runs at va_code.

    Two walks:
      G-stage: GPA → real SPA (always as U-mode, so G leaves have U=1)
      VS-stage: VA  → GPA

    V_SAVE_AREA_SETUP is required when code VA != code PA, otherwise the
    trap handler cannot find the save area after we hop into VS.
    """
    lines: list[str] = []  # accumulated G then VS setup macros
    if g_mode == "sv39x4":  # Sv39 G-stage: three-level walk (LEVEL2 / LEVEL1 / LEVEL0)
        # G-stage: map guest code superpage + the VS page-table pages themselves
        lines.append(f"  G_PTE_SETUP(sv39x4, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_code, LEVEL2)")  # G L2 ptr for code GPA
        lines.append(
            f"  SUPERPAGE_G_PTE_SETUP(sv39x4, rvtest_code_begin, {code_g_flags}, gpa_code, {code_lvl})"  # G leaf: GPA code → SPA of .text
        )
        lines.append(
            f"  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_rvtest_Vroot_pg_tbl, LEVEL1)"  # G L1 ptr for VS root GPA
        )
        lines.append(
            f"  G_PTE_SETUP(sv39x4, rvtest_Vroot_pg_tbl, {PTE_PT_G}, gpa_rvtest_Vroot_pg_tbl, LEVEL0)"  # G leaf: VS root table page
        )
        lines.append(
            f"  G_PTE_SETUP(sv39x4, rvtest_vlvl1_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl1_pg_tbl, LEVEL0)"  # G leaf: VS L1 table page
        )
        lines.append(
            f"  G_PTE_SETUP(sv39x4, rvtest_vlvl0_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)"  # G leaf: VS L0 table page
        )
        if with_data:  # G-stage walk of the guest data GPA
            lines.append(f"  G_PTE_SETUP(sv39x4, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)")  # G L1 ptr for data GPA
            lines.append(f"  G_PTE_SETUP(sv39x4, {g_data_pa_lbl}, {data_g_flags}, gpa_data, LEVEL0)")  # G leaf: data GPA → SPA

        # VS-stage: va_code → gpa_code, then relocate the save area so VS entry is legal
        lines.append(
            f"  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_code, LEVEL2)"  # VS L2 ptr for code VA
        )
        lines.append(f"  VS_PTE_SETUP(sv39, GPA, gpa_code, {code_vs_flags}, va_code, LEVEL1)")  # VS superpage: va_code → gpa_code
        lines.append("  csrr a0, mscratch")  # a0 = M-mode save-area pointer required by V_SAVE_AREA_SETUP
        lines.append("  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)")  # copy save area to guest VA
        if with_data:  # VS-stage walk of va_data → gpa_data
            lines.append(
                f"  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL2)"  # VS L2 ptr for data VA
            )
            lines.append(
                f"  VS_PTE_SETUP(sv39, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)"  # VS L1 ptr for data VA
            )
            lines.append(f"  VS_PTE_SETUP(sv39, GPA, gpa_data, {data_vs_flags}, va_data, LEVEL0)")  # VS leaf: va_data → gpa_data
    else:
        # Sv32: two-level walk (no LEVEL2 G/VS tables).
        lines.append(
            f"  SUPERPAGE_G_PTE_SETUP(sv32x4, rvtest_code_begin, {code_g_flags}, gpa_code, {code_lvl})"  # G leaf: GPA code → SPA of .text
        )
        lines.append(
            f"  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_rvtest_Vroot_pg_tbl, LEVEL1)"  # G L1 ptr for VS root GPA
        )
        lines.append(
            f"  G_PTE_SETUP(sv32x4, rvtest_Vroot_pg_tbl, {PTE_PT_G}, gpa_rvtest_Vroot_pg_tbl, LEVEL0)"  # G leaf: VS root table page
        )
        lines.append(
            f"  G_PTE_SETUP(sv32x4, rvtest_vlvl0_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)"  # G leaf: VS L0 table page
        )
        if with_data:  # G-stage walk of the guest data GPA
            lines.append(f"  G_PTE_SETUP(sv32x4, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)")  # G L1 ptr for data GPA
            lines.append(f"  G_PTE_SETUP(sv32x4, {g_data_pa_lbl}, {data_g_flags}, gpa_data, LEVEL0)")  # G leaf: data GPA → SPA

        lines.append(f"  VS_PTE_SETUP(sv32, GPA, gpa_code, {code_vs_flags}, va_code, LEVEL1)")  # VS superpage: va_code → gpa_code
        lines.append("  csrr a0, mscratch")  # a0 = M-mode save-area pointer
        lines.append("  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)")  # relocate save area to va_code
        if with_data:  # VS-stage walk of va_data → gpa_data
            lines.append(
                f"  VS_PTE_SETUP(sv32, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)"  # VS L1 ptr for data VA
            )
            lines.append(f"  VS_PTE_SETUP(sv32, GPA, gpa_data, {data_vs_flags}, va_data, LEVEL0)")  # VS leaf: va_data → gpa_data
    return lines  # G then VS setup macros for this paging mode


def emit_two_stage_maps(
    paging: Paging,
    *,
    code_pte: str = PTE_CODE_VS,
    data_pte: str = PTE_DATA_VS,
    g_code_pte: str = PTE_CODE_G,
    g_data_pte: str = PTE_DATA_G,
    g_data_pa_lbl: str = "test_region",
    with_data: bool = True,
    code_lvl: str = "LEVEL1",
) -> list[str]:
    """Resolve Sv32/Sv39 mode names and emit two-stage page-table setup."""
    vs_mode, g_mode = paging_modes(paging)  # ("sv32","sv32x4") or ("sv39","sv39x4")
    return emit_two_stage_page_tables(  # expand macros with those mode names
        g_mode=g_mode,  # hgatp MODE string for G_PTE_SETUP
        vs_mode=vs_mode,  # vsatp MODE string (passed through for callers that need it)
        code_lvl=code_lvl,  # G-stage superpage level for guest code
        with_data=with_data,  # False = code maps only (ifetch tests)
        data_g_flags=g_data_pte,  # G-stage data leaf permission bits
        data_vs_flags=data_pte,  # VS-stage data leaf permission bits
        code_g_flags=g_code_pte,  # G-stage code leaf permission bits
        code_vs_flags=code_pte,  # VS-stage code leaf permission bits
        g_data_pa_lbl=g_data_pa_lbl,  # SPA symbol of the data page (usually test_region)
    )


def emit_enable_vs_g(vs_mode: str, g_mode: str) -> list[str]:
    """Enable vsatp and hgatp, then fence both stages.

    When G-stage is Sv*x4, VSATP_SETUP uses GPA PPNs.
    """
    vs_arg = "GPA" if g_mode.endswith("x4") else "PA"  # two-stage: VS leaves store GPAs, not PAs
    return [
        f"  VSATP_SETUP({vs_mode}, {vs_arg})",  # write vsatp.MODE + root PPN
        f"  HGATP_SETUP({g_mode})",  # write hgatp.MODE + root PPN
        "  hfence.vvma",  # invalidate VS-stage TLB
        "  hfence.gvma",  # invalidate G-stage TLB
    ]


def emit_enable_and_fence(vs_mode: str, g_mode: str) -> list[str]:
    """Alias of emit_enable_vs_g (older family drafts used this name)."""
    return emit_enable_vs_g(vs_mode, g_mode)  # identical enable + both fences


def emit_enable_paging(paging: Paging) -> list[str]:
    """Enable vsatp/hgatp for this paging twin and fence both stages."""
    vs_mode, g_mode = paging_modes(paging)  # resolve MODE names from "sv32" / "sv39"
    return emit_enable_and_fence(vs_mode, g_mode)  # VSATP_SETUP + HGATP_SETUP + fences


def emit_enable_vs_hgatp_bare(vs_mode: str) -> list[str]:
    """Enable VS-stage translation with hgatp Bare (VS leaf PPNs are PAs)."""
    return [
        f"  VSATP_SETUP({vs_mode}, PA)",  # VS leaves store supervisor PAs (no G-stage)
        "  csrw hgatp, x0",  # G-stage Bare
        "  hfence.vvma",  # invalidate VS-stage TLB
        "  hfence.gvma",  # invalidate G-stage TLB after hgatp clear
    ]


def emit_both_bare() -> list[str]:
    """Clear vsatp and hgatp. Use T-SBI hops; addresses are identity-mapped."""
    return [
        "  csrw vsatp, x0",  # VS-stage Bare
        "  csrw hgatp, x0",  # G-stage Bare
        "  hfence.vvma",  # invalidate VS-stage TLB
        "  hfence.gvma",  # invalidate G-stage TLB
    ]


def emit_hfence_both() -> list[str]:
    """Flush VS-stage and G-stage TLBs after a PTE rewrite."""
    return ["  hfence.vvma", "  hfence.gvma"]  # VVMA then GVMA


def emit_clear_mprv() -> list[str]:
    """Clear mstatus.MPRV before SIGUPD when the signature is not guest-mapped."""
    return [
        "  LI(t0, MSTATUS_MPRV)",  # t0 = MPRV bit mask
        "  csrc mstatus, t0",  # MPRV=0 so the SIGUPD store uses M-mode addressing
    ]


# ---------------------------------------------------------------------------
# Privilege hops. VA≠PA guest must return with GOTO_MMODE, not TSBI a0=1.
# ---------------------------------------------------------------------------


def emit_goto_vs() -> list[str]:
    """Enter VS-mode with VA≠PA relocate (GOTO_LOWER_MODE)."""
    return ["  RVTEST_GOTO_LOWER_MODE VSmode"]  # not T-SBI; required when va_code != PA


def emit_goto_vu() -> list[str]:
    """Enter VU-mode with VA≠PA relocate (GOTO_LOWER_MODE)."""
    return ["  RVTEST_GOTO_LOWER_MODE VUmode"]


def emit_goto_hs() -> list[str]:
    """Enter HS-mode (GOTO_LOWER_MODE)."""
    return ["  RVTEST_GOTO_LOWER_MODE HSmode"]


def emit_goto_mmode() -> list[str]:
    """Return to M-mode before SIGUPD (signature region is not guest-mapped)."""
    return ["  RVTEST_GOTO_MMODE"]  # a0=0 path: VA→PA when returning from a relocated guest


def emit_goto_vs_vu_hs(mode: GuestMode) -> list[str]:
    """Dispatch a lower-mode hop, or emit nothing for M-mode."""
    if mode == "VS":  # virtual supervisor
        return emit_goto_vs()
    if mode == "VU":  # virtual user
        return emit_goto_vu()
    if mode == "HS":  # hypervisor supervisor (HS)
        return emit_goto_hs()
    return []  # M-mode: already at the destination; no hop


def emit_spa_preload(value: int, *, dest: str = "test_region") -> list[str]:
    """Store a known pattern to the physical page from M-mode."""
    return [
        f"  LI(t0, {hex(value)})",  # pattern that later guest loads should observe (if allowed)
        f"  la t1, {dest}",  # SPA of the data page
        "  sw t0, 0(t1)",  # write the pattern through M-mode identity map
    ]


def emit_load_va_ptr(reg: str = "a5", symbol: str = "va_data") -> list[str]:
    """Load the guest data VA into ``reg`` for a subsequent guest load/store."""
    return [f"  LI({reg}, {symbol})"]  # typical: a5 = va_data before hopping into VS


def emit_nop_pad() -> list[str]:
    """Single nop (pipeline / retire padding used in directed seeds)."""
    return ["  nop"]


def emit_sigupd_gpr(
    test_data: TestData,
    check_reg: int,
    bin_name: str,
    coverpoint: str,
    *,
    covergroup: str = CG,
) -> list[str]:
    """Register a coverpoint bin and emit a GPR SIGUPD."""
    return [
        test_data.add_testcase(bin_name, coverpoint, covergroup),  # record bin + increment counters
        write_sigupd(check_reg, test_data),  # RVTEST_SIGUPD of that GPR (x-reg number)
    ]


def emit_sigupd_csr(
    test_data: TestData,
    check_reg: int,
    csr_name: str,
    bin_name: str,
    coverpoint: str,
    *,
    covergroup: str = CG,
    mask: int | None = None,
    mask_reg: int | None = None,
) -> list[str]:
    """Register a coverpoint bin and emit a CSR-read SIGUPD."""
    return [
        test_data.add_testcase(bin_name, coverpoint, covergroup),  # record bin + increment counters
        gen_csr_read_sigupd(check_reg, (csr_name, mask), test_data, mask_reg=mask_reg),  # csrr + SIGUPD
    ]


def emit_manual_sigupd(label: str, check_reg: str = "a3") -> list[str]:
    """Emit ``RVTEST_SIGUPD`` with fixed pointer registers. Caller must ``bump_sigupd``."""
    return [
        f"  {label}:",  # local label referenced by the mismatch .string
        f"  RVTEST_SIGUPD(x2, x5, x4, {check_reg}, {label}, {label}_str)",  # dump check_reg; x2/x5/x4 are SIG pointers
    ]


def emit_mismatch_string(label: str, message: str) -> str:
    """Emit the ``.string`` referenced by ``RVTEST_SIGUPD`` on mismatch."""
    return f'{label}_str: .string "\\"{message}\\""'  # writer / assembler expects this name


def emit_data_section(
    *,
    need_test_region: bool = True,
    need_hlvl0: bool = True,
    need_vlvl0: bool = True,
    need_hlvl1: bool = False,
    need_vlvl1: bool = False,
    extra_regions: list[str] | None = None,
    mismatch_strings: list[str] | None = None,
) -> list[str]:
    """Emit ``.pushsection .data`` storage for ``test_region``, page tables, and mismatch strings."""
    lines = ["", ".pushsection .data"]  # switch from .text to .data after RVTEST_CODE_END material
    if need_test_region:  # 4 KiB-aligned guest data page (SPA)
        lines.extend(
            [
                ".p2align 12",  # 4 KiB alignment required for a leaf page
                "test_region:",  # SPA label used by G_PTE_SETUP / SPA readback
                "  .word 0",  # first word (preload / store target)
                "  .word 0",
                "  .word 0",
                "  .word 0",
            ]
        )
    if extra_regions:  # additional labeled pages (e.g. second data region)
        lines.extend(extra_regions)
    if need_hlvl1:  # G-stage L1 table page (Sv39 only)
        lines.extend([".p2align 12", "rvtest_hlvl1_pg_tbl:", "  .zero 4096"])
    if need_hlvl0:  # G-stage L0 table page
        lines.extend([".p2align 12", "rvtest_hlvl0_pg_tbl:", "  .zero 4096"])
    if need_vlvl1:  # VS-stage L1 table page (Sv39 only)
        lines.extend([".p2align 12", "rvtest_vlvl1_pg_tbl:", "  .zero 4096"])
    if need_vlvl0:  # VS-stage L0 table page
        lines.extend([".p2align 12", "rvtest_vlvl0_pg_tbl:", "  .zero 4096"])
    if mismatch_strings:  # .string table for RVTEST_SIGUPD mismatch text
        lines.extend(mismatch_strings)
    lines.extend([".popsection", ""])  # return to the previous section
    return lines


# Back-compat alias used by older family drafts
emit_pt_data_section = emit_data_section  # same function; keep the old name working


def bump_sigupd(test_data: TestData, n: int) -> None:
    """Add ``n`` to the current chunk ``sigupd_count``."""
    if test_data.test_chunk is not None and n > 0:  # ignore if no chunk, or a no-op increment
        test_data.test_chunk.sigupd_count += n  # writer uses this for #define SIGUPD_COUNT


def mark_scenario(test_data: TestData, n_sig: int = 1) -> None:
    """Count SIGUPD sites and ensure the chunk reports at least one testcase."""
    bump_sigupd(test_data, n_sig)  # add n_sig to sigupd_count
    if test_data.test_chunk is not None:  # make_svh always has a chunk; guard for unit tests
        test_data.test_chunk.num_testcases = max(test_data.test_chunk.num_testcases, 1)  # writer floor


def pte_flags(*, x: bool = False, w: bool = False, r: bool = False, u: bool = False, v: bool = True, a: bool = True, d: bool = True) -> str:
    """Return a ``(PTE_D | PTE_A | …)`` expression from individual PTE bits."""
    parts: list[str] = []  # assembler identifiers, left-to-right D, A, U, X, W, R, V
    if d:  # dirty bit (stores require D=1 when Svade / ADUE=0)
        parts.append("PTE_D")
    if a:  # accessed bit (implicit A=0 faults when ADUE=0)
        parts.append("PTE_A")
    if u:  # user bit (G-stage success leaves need U=1; VU needs U=1 at VS-stage)
        parts.append("PTE_U")
    if x:  # execute permission
        parts.append("PTE_X")
    if w:  # write permission
        parts.append("PTE_W")
    if r:  # read permission
        parts.append("PTE_R")
    if v:  # valid bit (V=0 → page / guest-page fault)
        parts.append("PTE_V")
    if not parts:  # all bits False: empty OR is illegal; emit a zero PTE
        return "(0)"
    return "(" + " | ".join(parts) + ")"  # e.g. (PTE_D | PTE_A | PTE_R | PTE_V)


def emit_g_data_leaf(paging: Paging, flags: str, *, pa_lbl: str = "test_region") -> list[str]:
    """Rewrite the G-stage data leaf after the initial maps."""
    _, g_mode = paging_modes(paging)  # hgatp MODE name (sv32x4 / sv39x4)
    return [f"  G_PTE_SETUP({g_mode}, {pa_lbl}, {flags}, gpa_data, LEVEL0)"]  # overwrite G data leaf flags


def emit_vs_data_leaf(
    paging: Paging,
    flags: str,
    *,
    ppn_kind: Literal["GPA", "PA"] = "GPA",
    ppn: str | None = None,
    va: str = "va_data",
) -> list[str]:
    """Rewrite the VS-stage data leaf. Use ``PA`` when hgatp is Bare; ``GPA`` for two-stage."""
    vs_mode, _ = paging_modes(paging)  # vsatp MODE name (sv32 / sv39)
    if ppn is None:  # default PPN symbol depends on whether G-stage is on
        ppn = "gpa_data" if ppn_kind == "GPA" else "test_region"  # GPA vs SPA of the data page
    return [f"  VS_PTE_SETUP({vs_mode}, {ppn_kind}, {ppn}, {flags}, {va}, LEVEL0)"]  # overwrite VS data leaf


def emit_standard_prologue(
    paging: Paging,
    *,
    data_pte: str = PTE_DATA_VS,
    g_data_pte: str = PTE_DATA_G,
    code_pte: str = PTE_CODE_VS,
    with_data: bool = True,
) -> list[str]:
    """Emit VA/GPA symbols, two-stage maps, vsatp/hgatp enable, and fences."""
    vs_mode, g_mode = paging_modes(paging)  # MODE names for VSATP_SETUP / HGATP_SETUP
    lines: list[str] = []  # prologue assembly for one twin
    lines.extend(emit_va_gpa_sets(paging, with_data=with_data))  # .set va_code / gpa_* symbols
    lines.extend(
        emit_two_stage_maps(
            paging,  # Sv32 or Sv39 map shape
            code_pte=code_pte,  # VS-stage code leaf flags
            data_pte=data_pte,  # VS-stage data leaf flags
            g_data_pte=g_data_pte,  # G-stage data leaf flags
            with_data=with_data,  # False skips data walks
        )
    )
    lines.extend(emit_enable_and_fence(vs_mode, g_mode))  # vsatp + hgatp + both hences
    return lines


def twin_data_section(paging: Paging, *, mismatch_strings: list[str] | None = None) -> list[str]:
    """Data section for one paging twin. Sv39 includes LEVEL1 table pages."""
    need_hlvl1 = paging == "sv39"  # G-stage L1 table exists only for Sv39x4
    need_vlvl1 = paging == "sv39"  # VS-stage L1 table exists only for Sv39
    return emit_data_section(
        need_hlvl1=need_hlvl1,  # allocate rvtest_hlvl1_pg_tbl when Sv39
        need_vlvl1=need_vlvl1,  # allocate rvtest_vlvl1_pg_tbl when Sv39
        mismatch_strings=mismatch_strings,  # optional SIGUPD mismatch .string list
    )
