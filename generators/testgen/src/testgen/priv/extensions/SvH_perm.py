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

from __future__ import annotations  # allow list[str] / Paging without quoted forward refs

from dataclasses import dataclass  # PermBits / SigCase frozen records
from typing import Literal  # string unions for paging / guest / access kind

from testgen.asm.helpers import comment_banner  # file-level // banner in the .S
from testgen.data.state import TestData  # open TestChunk (SIGUPD / testcase counters)
from testgen.priv.extensions.SvHCommon import (  # shared SvH asm helpers
    PTE_CODE_G,  # G-stage code leaf (U=1 X R V)
    PTE_DATA_G,  # G-stage R/W data leaf (U=1)
    PTE_PT_G,  # G leaf covering a VS page-table page
    PTE_V_ONLY,  # non-leaf pointer: V=1 only
    data_section,  # .pushsection .data (some single-path helpers)
    enable_two_stage,  # vsatp + hgatp + fences
    enable_vs_only,  # vsatp ON, hgatp Bare
    set_g_data_leaf,  # rewrite G-stage data LEVEL0 leaf only
    goto_hs,  # hop to HS
    goto_mmode,  # return to M before SIGUPD
    goto_vs,  # hop to VS
    goto_vu,  # hop to VU
    fence_both_stages,  # hfence.vvma + hfence.gvma
    load_guest_va,  # LI(reg, va_data) or similar
    sigupd_labeled,  # RVTEST_SIGUPD with a label
    mismatch_string,  # .string for mismatch text
    preload_spa,  # M-mode store into test_region
    set_vs_data_leaf,  # rewrite VS-stage data LEVEL0 leaf only
    mode_names,  # MODE name pair for macros
    pte_bits,  # build "(PTE_D | …)" from bools
    twin_data,  # .data for one twin
    build_twins,  # Sv32 + Sv39 ifdefs; SIGUPD_COUNT = max twin
)  # end SvHCommon import

Paging = Literal["sv32", "sv39"]  # which paging twin the body is emitting
Guest = Literal["VS", "VU", "HS"]  # which privilege performs the access
Stage = Literal["vs", "g"]  # which stage's leaf we are editing
Access = Literal["lw", "sw", "jalr", "swlw", "hlv", "hsvhlv"]  # access kind in case builders

    # Round-robin GPRs so consecutive cases dump different registers (signature clarity).
LOAD_REGS = ("a3", "a4", "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11")  # round-robin load dump regs
STORE_REGS = ("s2", "s3", "s4", "s5", "s6", "s7", "a3", "a4", "a6", "a7")  # round-robin store dump regs


@dataclass(frozen=True)  # immutable dataclass
class PermBits:  # X/W/R/U permission bits
    """One permission combination: X/W/R plus U (user) vs S (supervisor) page."""

    x: bool  # execute permission
    w: bool  # write permission
    r: bool  # read permission
    u: bool  # U=1 user page vs U=0 supervisor page

    @property  # derived attribute
    def name(self) -> str:  # emit name
        """Short token for labels, e.g. ``110_u`` for XWR=110 U=1."""
        return f"{int(self.x)}{int(self.w)}{int(self.r)}_{'u' if self.u else 's'}"  # name like 110_u

    @property  # derived attribute
    def desc(self) -> str:  # emit desc
        """Human text for case banners, e.g. ``U page XWR=110``."""
        return f"{'U' if self.u else 'S'} page XWR={int(self.x)}{int(self.w)}{int(self.r)}"  # desc like U page XWR=110

    def flags(self, *, g_stage: bool = False, g_bit: bool = False) -> str:  # emit flags
        """Assembler PTE flag expression for ``G_PTE_SETUP`` / ``VS_PTE_SETUP``."""
        base = pte_bits(x=self.x, w=self.w, r=self.r, u=self.u, d=True, a=True, v=True)  # A=D=V=1
        if g_bit:  # append PTE_G inside the parentheses
            return base[:-1] + " | PTE_G)"  # add PTE_G into flags
        if g_stage and not self.u:  # G-stage U=0 stays U=0
    # Keep G-stage "bad U" leaves as exactly U=0; success leaves normally set U
    # because the hypervisor walks G-stage as user accesses.
            return base  # flags unchanged
        return base  # flags unchanged


@dataclass(frozen=True)  # immutable dataclass
class SigCase:  # one numbered test case
    """One numbered permission case: banner metadata + which GPR to dump."""

    num: str  # "1", "2", … printed in the .S banner
    title: str  # human title after the case number
    label: str  # SIGUPD label / mismatch-string stem
    check_reg: str  # GPR name to dump (a3, s2, …)
    message: str  # mismatch string text
    coverpoint: str  # SvH_cg coverpoint id(s) for this case
    expected: str = "Expected Fault"  # or "Successful" for allow cases


def _banner(title: str) -> list[str]:  # section // banner
    """Emit a section banner in the generated assembly."""
    return ["", "// " + "-" * 128, f"// {title}", "// " + "-" * 128]  # return asm/list


def _case_banner(case: SigCase) -> list[str]:  # per-case // header
    """Emit the per-case header: number, title, expected result, coverpoint ids."""
    return [  # return asm/list
        "//" + "-" * 128,  # top rule
        f"// Test case {case.num}: {case.title} | Expected: {case.expected}",  # title line
        f"// Coverpoints: {case.coverpoint}",  # which SvH_cg bins this case hits
        "//" + "-" * 128,  # bottom rule
    ]  # list end


def _sig(test_data: TestData, case: SigCase) -> list[str]:  # count + emit SIGUPD
    """Count one SIGUPD and emit ``RVTEST_SIGUPD`` for ``case.check_reg``."""
    if test_data.test_chunk is not None:  # make_svh always opens a chunk
        test_data.test_chunk.sigupd_count += 1  # header SIGUPD_COUNT
        test_data.test_chunk.num_testcases += 1  # header testcase table length
    return sigupd_labeled(case.label, case.check_reg)  # dump check_reg at label


def _write_mxr_sum(mxr: int, sum_: int) -> list[str]:  # set MXR/SUM in status CSRs
    """Set vsstatus/sstatus MXR and SUM to the requested combination.

    When both bits are 1, OR them in with a single csrs (seed case 24 style) so we
    do not clear SUM between related cases. Otherwise clear both then set the ones
    that should be 1.
    """
    if mxr and sum_:  # both on: one OR into sstatus and vsstatus
        return [  # return asm/list
            "  LI(t0, SSTATUS_MXR | SSTATUS_SUM)",  # both bit masks
            "  csrs sstatus, t0",  # set in sstatus
            "  csrs vsstatus, t0",  # set in vsstatus (guest view)
            "  hfence.vvma",  # publish status-bit effect on TLB/perms
        ]  # list end
    lines = ["  LI(t0, SSTATUS_MXR | SSTATUS_SUM)", "  csrc sstatus, t0", "  csrc vsstatus, t0"]  # clear both first
    if mxr:  # turn only MXR on
        lines.extend(["  LI(t0, SSTATUS_MXR)", "  csrs sstatus, t0", "  csrs vsstatus, t0"])  # set MXR only
    if sum_:  # turn only SUM on
        lines.extend(["  LI(t0, SSTATUS_SUM)", "  csrs sstatus, t0", "  csrs vsstatus, t0"])  # set SUM only
    lines.append("  hfence.vvma")  # publish
    return lines  # finished asm lines


def _enter_guest(mode: Guest, *, relocated: bool) -> list[str]:  # hop into VS/VU/HS
    """Enter VS, VU, or HS. ``relocated=True`` uses GOTO_LOWER_MODE (VA != PA)."""
    if relocated:  # two-stage / VA!=PA: use framework relocate hop
        if mode == "VU":  # VU path
            return goto_vu()  # hop VU (relocated)
        if mode == "VS":  # VS path
            return goto_vs()  # hop VS (relocated)
        return goto_hs()  # hop HS (relocated)
    # Bare / identity: T-SBI hops keep PA==VA
    if mode == "VU":  # VU path
        return ["  RVTEST_TSBI_GOTO_VUMODE"]  # TSBI hop to VU
    if mode == "VS":  # VS path
        return ["  RVTEST_TSBI_GOTO_VSMODE"]  # TSBI hop to VS
    return ["  RVTEST_TSBI_GOTO_SMODE"]  # TSBI hop to HS


def _leave_guest() -> list[str]:  # return to M-mode
    """Return to M-mode before SIGUPD."""
    return goto_mmode()  # return to M-mode


def _map_vs_code(paging: Paging, *, code_u: bool) -> list[str]:  # map VS code + save area
    """VS-stage code superpage plus ``V_SAVE_AREA_SETUP``. ``code_u`` sets PTE_U."""
    vs_mode, _ = mode_names(paging)  # VS MODE token
    code_flags = pte_bits(x=True, r=True, u=code_u)  # VU needs U=1 on code leaf
    if paging == "sv39":  # Sv39 three-level
        return [  # return asm/list
            f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_code, LEVEL2)",  # L2
            f"  SUPERPAGE_VS_PTE_SETUP({vs_mode}, rvtest_code_begin, {code_flags}, va_code, LEVEL1)",  # code SPA
            "  csrr a0, mscratch",  # save-area base
            "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate save area
        ]  # list end
    return [  # return asm/list
        f"  SUPERPAGE_VS_PTE_SETUP({vs_mode}, rvtest_code_begin, {code_flags}, va_code, LEVEL1)",  # VS code superpage
        "  csrr a0, mscratch",  # a0 = save-area base
        "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate save area
    ]  # list end


def _vs_leaf_map(paging: Paging, *, va: str, pa: str, flags: str) -> list[str]:  # VS data leaf walk
    """VS-stage data walk to ``va`` with leaf PPN ``pa`` (PA, hgatp Bare)."""
    vs_mode, _ = mode_names(paging)  # VS MODE token
    if paging == "sv39":  # Sv39 three-level
        return [  # return asm/list
            f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL2)",  # VS L2 non-leaf
            f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL1)",  # VS L1 non-leaf
            f"  VS_PTE_SETUP({vs_mode}, PA, {pa}, {flags}, {va}, LEVEL0)",  # leaf
        ]  # list end
    return [  # return asm/list
        f"  VS_PTE_SETUP({vs_mode}, PA, rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, {va}, LEVEL1)",  # VS L1 non-leaf
        f"  VS_PTE_SETUP({vs_mode}, PA, {pa}, {flags}, {va}, LEVEL0)",  # VS data leaf
    ]  # list end


def _g_only_setup(paging: Paging, *, g_flags: str = PTE_DATA_G) -> list[str]:  # Bare vsatp + hgatp maps
    """vsatp Bare + hgatp ON: code GPA must identity-map PA (~0x80000000) for TSBI hops."""
    _, g_mode = mode_names(paging)  # G MODE token
    gpa_data = "0x0000000000C002000" if paging == "sv39" else "0x00C002000"  # data GPA constant
    lines = [  # asm output buffer
        "  .set gpa_code, 0x80000000",  # code GPA symbol
        f"  .set gpa_data, {gpa_data}",  # data GPA symbol
        "  csrw vsatp, x0",  # Bare vsatp (G-only)
    ]  # list end
    if paging == "sv39":  # Sv39 three-level
        lines.extend(  # extend with following list
            [  # list begin
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_code, LEVEL2)",  # G L2 non-leaf
                f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {PTE_CODE_G}, gpa_code, LEVEL2)",  # G code superpage
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL2)",  # G L2 non-leaf
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)",  # G non-leaf
            ]  # list end
        )  # end paren
    else:  # alternate path
        lines.extend(  # extend with following list
            [  # list begin
                f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {PTE_CODE_G}, gpa_code, LEVEL1)",  # G code superpage
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)",  # G non-leaf
            ]  # list end
        )  # end paren
    lines.extend([f"  G_PTE_SETUP({g_mode}, test_region, {g_flags}, gpa_data, LEVEL0)", f"  HGATP_SETUP({g_mode})"])  # G data leaf + hgatp
    lines.extend(fence_both_stages())  # append fences
    return lines  # finished asm lines


def _vs_only_setup(paging: Paging, *, code_u: bool, data_flags: str) -> list[str]:  # vsatp ON + Bare hgatp
    """VS-stage on, hgatp Bare: code map, data leaf, enable vsatp."""
    vs_mode, _ = mode_names(paging)  # VS MODE token
    va_data = "0x0000000080010000" if paging == "sv39" else "0x08001000"  # data VA constant
    return [  # return asm/list
        "  .set va_code, 0x90000000",  # code VA symbol
        f"  .set va_data, {va_data}",  # data VA symbol
        *_map_vs_code(paging, code_u=code_u),  # VS code map
        *_vs_leaf_map(paging, va="va_data", pa="test_region", flags=data_flags),  # VS data leaf map
        *enable_vs_only(vs_mode),  # enable VS-only
    ]  # list end


def _asm_load_case(  # guest load + SIGUPD
    test_data: TestData,  # test counters / chunk
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    va: str,  # guest VA symbol
    check_reg: str,  # GPR dumped by SIGUPD
    relocated: bool = True,  # use VA!=PA hops
) -> list[str]:  # label
    return [  # return asm/list
        *_case_banner(case),  # case banner lines
        *load_guest_va("a5", va),  # a5 = guest VA
        f"  LI({check_reg}, 0)",  # load immediate
        *_enter_guest(mode, relocated=relocated),  # enter guest
        f"  lw {check_reg}, 0(a5)",  # load word
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        *_sig(test_data, case),  # SIGUPD
        "",  # blank line in asm
    ]  # list end


def _asm_store_case(  # guest store + SPA readback
    test_data: TestData,  # test counters / chunk
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    va: str,  # guest VA symbol
    spa: str,  # SPA for store readback
    check_reg: str,  # GPR dumped by SIGUPD
    payload: int = 0xBAD00FAD,  # store data pattern
    relocated: bool = True,  # use VA!=PA hops
) -> list[str]:  # label
    return [  # return asm/list
        *_case_banner(case),  # case banner lines
        *load_guest_va("a5", va),  # a5 = guest VA
        f"  LI(t0, {hex(payload)})",  # load immediate
        *_enter_guest(mode, relocated=relocated),  # enter guest
        "  sw t0, 0(a5)",  # store word
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        f"  la t1, {spa}",  # SPA address into t1
        f"  lw {check_reg}, 0(t1)",  # load word
        *_sig(test_data, case),  # SIGUPD
        "",  # blank line in asm
    ]  # list end


def _asm_store_load_case(  # guest store then load
    test_data: TestData,  # test counters / chunk
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    va: str,  # guest VA symbol
    check_reg: str,  # GPR dumped by SIGUPD
    payload: int,  # store/preload pattern
    relocated: bool = True,  # use VA!=PA hops
) -> list[str]:  # label
    return [  # return asm/list
        *_case_banner(case),  # case banner lines
        *load_guest_va("a5", va),  # a5 = guest VA
        f"  LI(t0, {hex(payload)})",  # load immediate
        *_enter_guest(mode, relocated=relocated),  # enter guest
        "  sw t0, 0(a5)",  # store word
        "  nop",  # delay slot / pad
        f"  lw {check_reg}, 0(a5)",  # load word
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        *_sig(test_data, case),  # SIGUPD
        "",  # blank line in asm
    ]  # list end


def _asm_jalr_case(  # guest jalr success path
    test_data: TestData,  # test counters / chunk
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    va: str,  # guest VA symbol
    check_reg: str,  # GPR dumped by SIGUPD
    marker: int,  # success marker immediate
    relocated: bool = True,  # use VA!=PA hops
) -> list[str]:  # label
    return [  # return asm/list
        *_case_banner(case),  # case banner lines
        *load_guest_va("a5", va),  # a5 = guest VA
        f"  LI({check_reg}, 0)",  # load immediate
        *_enter_guest(mode, relocated=relocated),  # enter guest
        "  nop",  # delay slot / pad
        "  jalr ra, a5, 0",  # ifetch via jalr
        f"  LI({check_reg}, {hex(marker)})",  # load immediate
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        *_sig(test_data, case),  # SIGUPD
        "",  # blank line in asm
    ]  # list end


def _jalr_fault_case(  # guest jalr fault path
    test_data: TestData,  # test counters / chunk
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    va: str,  # guest VA symbol
    check_reg: str,  # GPR dumped by SIGUPD
    relocated: bool = True,  # use VA!=PA hops
) -> list[str]:  # label
    return [  # return asm/list
        *_case_banner(case),  # case banner lines
        *load_guest_va("a5", va),  # a5 = guest VA
        f"  LI({check_reg}, 0)",  # load immediate
        *_enter_guest(mode, relocated=relocated),  # enter guest
        "  nop",  # delay slot / pad
        "  jalr ra, a5, 0",  # ifetch via jalr
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        *_sig(test_data, case),  # SIGUPD
        "",  # blank line in asm
    ]  # list end


def _regions(names: list[str], *, xonly_exec: bool = False) -> list[str]:  # aligned spare SPA pages
    lines: list[str] = []  # asm output buffer
    for name in names:  # each named data region
        lines.extend([".p2align 12", f"{name}:", "  .word 0", "  .word 0", "  .word 0", "  .word 0"])  # emit aligned region words
    if xonly_exec:  # add xonly stub page
        lines.extend(  # extend with following list
            [  # list begin
                ".p2align 12",  # 4KiB align
                "xonly_exec_page:",  # label
                "  LI(a3, 0x257A040E)",  # load immediate
                "  jalr x0, ra, 0",  # return from xonly stub
                "  nop",  # delay slot / pad
                "  nop",  # delay slot / pad
            ]  # list end
        )  # end paren
    return lines  # finished asm lines


def _data(paging: Paging, *, regions: list[str] | None = None, strings: list[str] | None = None, xonly_exec: bool = False) -> list[str]:  # choose twin or custom .data
    if regions is None:  # default twin data
        return twin_data(paging, mismatch_strings=strings)  # twin .data section
    return data_section(  # .data section
        need_test_region=False,  # include test_region?
        need_hlvl0=False,  # page-table pages needed
        need_vlvl0=True,  # page-table pages needed
        need_hlvl1=False,  # page-table pages needed
        need_vlvl1=paging == "sv39",  # page-table pages needed
        extra_regions=_regions(regions, xonly_exec=xonly_exec),  # extra named regions
        mismatch_strings=strings,  # mismatch .string list
    )  # end paren


def _strings(cases: list[SigCase]) -> list[str]:  # mismatch strings for cases
    return [mismatch_string(c.label, c.message) for c in cases]  # return asm/list


def _permission_matrix(*, include_invalid_wr: bool = False, u_values: tuple[bool, ...] = (False, True)) -> list[PermBits]:  # XWR×U PermBits list
    combos = [(False, False, False), (True, False, False), (False, False, True), (True, False, True), (False, True, True), (True, True, True)]  # XWR permission combos
    if include_invalid_wr:  # include W-without-R
        combos.extend([(False, True, False), (True, True, False)])  # add invalid W-only combos
    return [PermBits(x=x, w=w, r=r, u=u) for u in u_values for x, w, r in combos]  # build PermBits matrix


def _access_allowed(*, mode: Guest, bits: PermBits, access: Literal["read", "write", "exec"], mxr: int = 0, sum_: int = 0) -> bool:  # VS/VU allow? (MXR/SUM)
    if mode == "VU" and not bits.u:  # VU path
        return False  # not allowed
    if mode == "VS" and bits.u and not sum_:  # VS path
        return False  # not allowed
    if access == "read":  # read check
        return bits.r or (mxr == 1 and bits.x)  # R or (MXR and X)
    if access == "write":  # write check
        return bits.w and bits.r  # need W and R
    return bits.x  # need X


def _g_access_allowed(bits: PermBits, access: Literal["read", "write"], *, mxr: int = 0) -> bool:  # G-stage allow? (needs U)
    if not bits.u:  # G-stage needs U=1
        return False  # not allowed
    if access == "read":  # read check
        return bits.r or (mxr == 1 and bits.x)  # R or (MXR and X)
    return bits.w and bits.r  # need W and R


def _asm_vs_seed_case(  # rewrite VS leaf + access
    test_data: TestData,  # test counters / chunk
    paging: Paging,  # Sv32 or Sv39
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    flags: str,  # PTE flag expression
    access: Access,  # lw / sw / jalr / …
    mxr: int = 0,  # MXR bit (0/1)
    sum_: int = 0,  # SUM bit (0/1)
    payload: int = 0x257A0400,  # signature pattern
    exec_page: bool = False,  # map xonly exec page
    va: str = "va_data",  # guest VA (default va_data)
    pa: str | None = None,  # SPA name or None
) -> list[str]:  # label
    if pa is None:  # default SPA
        pa = "xonly_exec_page" if exec_page else "test_region"  # physical page name
    lines = [*_write_mxr_sum(mxr, sum_), *set_vs_data_leaf(paging, flags, ppn_kind="PA", ppn=pa, va=va)]  # asm output buffer
    lines.extend(fence_both_stages())  # append fences
    lines.extend(preload_spa(0x00008067 if access == "jalr" else payload, dest=pa))  # preload SPA pattern
    if access == "lw":  # load access
        lines.extend(_asm_load_case(test_data, case=case, mode=mode, va=va, check_reg=case.check_reg))  # append case asm
    elif access == "sw":  # store access
        lines.extend(_asm_store_case(test_data, case=case, mode=mode, va=va, spa=pa, check_reg=case.check_reg))  # append case asm
    elif access == "swlw":  # store+load access
        lines.extend(_asm_store_load_case(test_data, case=case, mode=mode, va=va, check_reg=case.check_reg, payload=payload))  # append case asm
    else:  # alternate path
        if case.expected == "Successful":  # expect success
            lines.extend(_asm_jalr_case(test_data, case=case, mode=mode, va=va, check_reg=case.check_reg, marker=payload))  # append case asm
        else:  # alternate path
            lines.extend(_jalr_fault_case(test_data, case=case, mode=mode, va=va, check_reg=case.check_reg))  # append asm lines
    return lines  # finished asm lines


def _asm_g_seed_case(  # rewrite G leaf + access
    test_data: TestData,  # test counters / chunk
    paging: Paging,  # Sv32 or Sv39
    *,  # splice lines
    case: SigCase,  # this case record
    mode: Guest,  # VS / VU / HS
    flags: str,  # PTE flag expression
    access: Access,  # lw / sw / jalr / …
    payload: int,  # store/preload pattern
) -> list[str]:  # label
    lines = [*set_g_data_leaf(paging, flags), "  hfence.gvma"]  # asm output buffer
    lines.extend(preload_spa(payload))  # preload SPA pattern
    if access == "lw":  # load access
        lines.extend(_asm_load_case(test_data, case=case, mode=mode, va="gpa_data", check_reg=case.check_reg, relocated=False))  # append case asm
    elif access == "sw":  # store access
        lines.extend(_asm_store_case(test_data, case=case, mode=mode, va="gpa_data", spa="test_region", check_reg=case.check_reg, relocated=False))  # append case asm
    else:  # alternate path
        lines.extend(_asm_store_load_case(test_data, case=case, mode=mode, va="gpa_data", check_reg=case.check_reg, payload=payload, relocated=False))  # append case asm
    return lines  # finished asm lines


def _asm_g_perm(test_data: TestData, paging: Paging, *, mode: Guest) -> list[str]:  # G-stage perm matrix body
    lines = [*_g_only_setup(paging, g_flags=pte_bits(x=True, w=True, r=True, u=True)[:-1] + " | PTE_G)")]  # asm output buffer
    if mode == "VS":  # VS path
        specs = [  # packed case table
            ("1", "G leaf U=1 XWR=111+G VS sw/lw", "test1_u1_rwx", "a3", "Mismatch on VS sw/lw with G U=1 XWR=111+G in Test Case 1!", pte_bits(x=True, w=True, r=True, u=True)[:-1] + " | PTE_G)", "swlw", "Successful"),  # case 1: G leaf U=1 XWR=111+G VS sw/lw
            ("2", "G leaf U=0 XWR=111+G VS lw", "test2_u0_lw", "a4", "Mismatch on VS lw with G U=0 XWR=111 (expect fault) in Test Case 2!", pte_bits(x=True, w=True, r=True)[:-1] + " | PTE_G)", "lw", "Expected Fault"),  # case 2: G leaf U=0 XWR=111+G VS lw
            ("3", "G leaf U=0 XWR=111+G VS sw", "test3_u0_sw", "s2", "Mismatch on VS sw with G U=0 XWR=111 (expect SPA unchanged) in Test Case 3!", pte_bits(x=True, w=True, r=True)[:-1] + " | PTE_G)", "sw", "Expected Fault"),  # case 3: G leaf U=0 XWR=111+G VS sw
            ("4", "G leaf U=1 X-only", "test4_xonly", "a6", "Mismatch on VS lw with G X-only (expect fault) in Test Case 4!", pte_bits(x=True, u=True)[:-1] + " | PTE_G)", "lw", "Expected Fault"),  # case 4: G leaf U=1 X-only
            ("5", "G leaf U=1 V-only (XWR=000)", "test5_vonly_u1", "s3", "Mismatch on VS lw with G U=1 V-only (expect fault) in Test Case 5!", pte_bits(u=True)[:-1] + " | PTE_G)", "lw", "Expected Fault"),  # case 5: G leaf U=1 V-only (XWR=000)
            ("6", "Restore U=1 XWR=111+G VS lw", "test6_restore", "a7", "Mismatch on VS lw after G perm restore in Test Case 6!", pte_bits(x=True, w=True, r=True, u=True)[:-1] + " | PTE_G)", "lw", "Successful"),  # case 6: Restore U=1 XWR=111+G VS lw
            ("9", "G leaf U=1 V-only VS sw", "test9_vonly_u1_sw", "s6", "Mismatch on VS sw with G U=1 V-only (expect SPA unchanged) in Test Case 9!", pte_bits(u=True)[:-1] + " | PTE_G)", "sw", "Expected Fault"),  # case 9: G leaf U=1 V-only VS sw
            ("10", "G leaf U=0 V-only VS sw", "test10_vonly_u0_sw", "s7", "Mismatch on VS sw with G U=0 V-only (expect SPA unchanged) in Test Case 10!", pte_bits()[:-1] + " | PTE_G)", "sw", "Expected Fault"),  # case 10: G leaf U=0 V-only VS sw
        ]  # list end
    else:  # alternate path
        specs = [  # packed case table
            ("1", "G leaf U=1 XWR=111+G VU sw/lw", "test1_u1_rwx", "a3", "Mismatch on VU sw/lw with G U=1 XWR=111+G in Test Case 1!", pte_bits(x=True, w=True, r=True, u=True)[:-1] + " | PTE_G)", "swlw", "Successful"),  # case 1: G leaf U=1 XWR=111+G VU sw/lw
            ("2", "G leaf U=0 XWR=111+G VU lw", "test2_u0_lw", "a4", "Mismatch on VU lw with G U=0 XWR=111 (expect fault) in Test Case 2!", pte_bits(x=True, w=True, r=True)[:-1] + " | PTE_G)", "lw", "Expected Fault"),  # case 2: G leaf U=0 XWR=111+G VU lw
            ("3", "G leaf U=0 XWR=111+G VU sw", "test3_u0_sw", "s2", "Mismatch on VU sw with G U=0 XWR=111 (expect SPA unchanged) in Test Case 3!", pte_bits(x=True, w=True, r=True)[:-1] + " | PTE_G)", "sw", "Expected Fault"),  # case 3: G leaf U=0 XWR=111+G VU sw
            ("4", "G leaf U=1 X-only", "test4_xonly", "a6", "Mismatch on VU lw with G X-only (expect fault) in Test Case 4!", pte_bits(x=True, u=True)[:-1] + " | PTE_G)", "lw", "Expected Fault"),  # case 4: G leaf U=1 X-only
            ("5", "G leaf U=1 V-only", "test5_vonly_u1", "s3", "Mismatch on VU lw with G U=1 V-only (expect fault) in Test Case 5!", pte_bits(u=True)[:-1] + " | PTE_G)", "lw", "Expected Fault"),  # case 5: G leaf U=1 V-only
            ("6", "Restore U=1 XWR=111+G VU lw", "test6_restore", "a7", "Mismatch on VU lw after G perm restore in Test Case 6!", pte_bits(x=True, w=True, r=True, u=True)[:-1] + " | PTE_G)", "lw", "Successful"),  # case 6: Restore U=1 XWR=111+G VU lw
            ("7", "G leaf U=1 V-only VU sw", "test7_vonly_u1_sw", "s6", "Mismatch on VU sw with G U=1 V-only (expect SPA unchanged) in Test Case 7!", pte_bits(u=True)[:-1] + " | PTE_G)", "sw", "Expected Fault"),  # case 7: G leaf U=1 V-only VU sw
            ("8", "G leaf U=0 V-only VU sw", "test8_vonly_u0_sw", "s7", "Mismatch on VU sw with G U=0 V-only (expect SPA unchanged) in Test Case 8!", pte_bits()[:-1] + " | PTE_G)", "sw", "Expected Fault"),  # case 8: G leaf U=0 V-only VU sw
            ("9", "G leaf U=0 V-only VU lw", "test9_vonly_u0_lw", "s4", "Mismatch on VU lw with G U=0 V-only (expect fault) in Test Case 9!", pte_bits()[:-1] + " | PTE_G)", "lw", "Expected Fault"),  # case 9: G leaf U=0 V-only VU lw
        ]  # list end
    cases = [  # SigCase list
        SigCase(num, title, label, reg, msg, "cp_hgatp_perm_checks", expected)  # SigCase record
        for num, title, label, reg, msg, _flags, _access, expected in specs  # unpack case fields
    ]  # list end
    def emit_g_specs(selected_specs: list[tuple[str, str, str, str, str, str, str, str]]) -> None:  # emit emit_g_specs
        selected_cases = [  # subset SigCases
            SigCase(num, title, label, reg, msg, "cp_hgatp_perm_checks", expected)  # SigCase record
            for num, title, label, reg, msg, _flags, _access, expected in selected_specs  # unpack case fields
        ]  # list end
        for spec, case in zip(selected_specs, selected_cases):  # each packed case
            payload = 0x257A0200 + int(case.num) if mode == "VS" else 0x257A0300 + int(case.num)  # unique data pattern
            lines.extend(_asm_g_seed_case(test_data, paging, case=case, mode=mode, flags=spec[5], access=spec[6], payload=payload))  # append case asm

    if mode == "VS":  # VS path
        emit_g_specs(specs[:6])  # emit those G cases
        hs_cases = [  # HS HLV/HSV cases
            SigCase("7", "HS HLV of G leaf with G=1 XWR=111", "test7_hlv_g", "s4", "Mismatch on HS HLV of G leaf with G=1 in Test Case 7!", "cp_hgatp_pte_g_bit_rw", "Successful"),  # case 7: HS HLV of G leaf with G=1 XWR=111
            SigCase("8", "HS HSV of G leaf with G=1 XWR=111", "test8_hsv_g", "s5", "Mismatch on HS HSV of G leaf with G=1 in Test Case 8!", "cp_hgatp_pte_g_bit_rw", "Successful"),  # case 8: HS HSV of G leaf with G=1 XWR=111
        ]  # list end
        lines.extend(  # extend with following list
            [  # list begin
                *set_g_data_leaf(paging, pte_bits(x=True, w=True, r=True, u=True)[:-1] + " | PTE_G)"),  # rewrite G leaf
                "  hfence.gvma",  # G-stage fence
                *_case_banner(hs_cases[0]),  # case banner lines
                "  LI(t1, gpa_data)",  # pointer for access
                "  LI(s4, 0)",  # clear check reg
                *_enter_guest("HS", relocated=False),  # enter guest
                "  hlv.w s4, (t1)",  # hypervisor load
                "  nop",  # delay slot / pad
                *_leave_guest(),  # leave to M
                *_sig(test_data, hs_cases[0]),  # SIGUPD
                *_case_banner(hs_cases[1]),  # case banner lines
                "  LI(t1, gpa_data)",  # pointer for access
                "  LI(t0, 0x257A0208)",  # load immediate
                *_enter_guest("HS", relocated=False),  # enter guest
                "  hsv.w t0, (t1)",  # hypervisor store
                "  nop",  # delay slot / pad
                "  hfence.gvma",  # G-stage fence
                "  LI(s5, 0)",  # clear check reg
                "  hlv.w s5, (t1)",  # hypervisor load
                "  nop",  # delay slot / pad
                *_leave_guest(),  # leave to M
                *_sig(test_data, hs_cases[1]),  # SIGUPD
            ]  # list end
        )  # end paren
        cases[6:6] = hs_cases  # splice HS cases at index 6
        emit_g_specs(specs[6:])  # emit those G cases
    else:  # alternate path
        emit_g_specs(specs)  # emit those G cases
    lines.extend(twin_data(paging, mismatch_strings=_strings(cases)))  # append asm lines
    return lines  # finished asm lines


def generate_g_perm_VSmode(test_data: TestData) -> list[str]:  # public generator entry
    """Output ``SvH_g_perm_VSmode-00.S``: G-stage permission checks from VS, plus HS HLV/HSV."""
    return [comment_banner("g_perm_VSmode", "SvH G-stage permission stimulus"), *build_twins(test_data, lambda td, p: _asm_g_perm(td, p, mode="VS"))]  # banner + twins (g_perm_VSmode)


def generate_g_perm_VUmode(test_data: TestData) -> list[str]:  # public generator entry
    """Output ``SvH_g_perm_VUmode-00.S``: G-stage permission checks from VU."""
    return [comment_banner("g_perm_VUmode", "SvH G-stage permission stimulus"), *build_twins(test_data, lambda td, p: _asm_g_perm(td, p, mode="VU"))]  # banner + twins (g_perm_VUmode)


def _asm_g_u_bit(test_data: TestData, paging: Paging) -> list[str]:  # G-stage U-bit HLV/HSV body
    cases = [  # SigCase list
        SigCase("1", "G leaf U=1 XWR=111 HS HLV", "test1_u1_hlv", "a3", "Mismatch on HS HLV with G U=1!", "cp_hgatp_u_mode_access_rw", "Successful"),  # case 1: G leaf U=1 XWR=111 HS HLV
        SigCase("2", "G leaf U=1 XWR=111 HS HSV+HLV", "test2_u1_hsv", "a6", "Mismatch on HS HSV/HLV with G U=1!", "cp_hgatp_u_mode_access_rw", "Successful"),  # case 2: G leaf U=1 XWR=111 HS HSV+HLV
        SigCase("3", "G leaf U=0 XWR=111 HS HLV", "test3_u0_hlv", "a4", "Mismatch on HS HLV with G U=0!", "cp_hgatp_u_mode_access_rw"),  # case 3: G leaf U=0 XWR=111 HS HLV
        SigCase("4", "G leaf U=0 XWR=111 HS HSV", "test4_u0_hsv", "s3", "Mismatch on HS HSV with G U=0!", "cp_hgatp_u_mode_access_rw"),  # case 4: G leaf U=0 XWR=111 HS HSV
        SigCase("5", "Restore G leaf U=1 XWR=111 HS HLV", "test5_restore", "a7", "Mismatch after G U-bit restore!", "cp_hgatp_u_mode_access_rw", "Successful"),  # case 5: Restore G leaf U=1 XWR=111 HS HLV
    ]  # list end
    good = pte_bits(x=True, w=True, r=True, u=True)  # good G leaf U=1 RWX
    bad = pte_bits(x=True, w=True, r=True, u=False)  # bad G leaf U=0 RWX
    return [  # return asm/list
        *_g_only_setup(paging, g_flags=good),  # G-only paging setup
        *preload_spa(0x257A0231),  # preload SPA pattern
        "  LI(t1, gpa_data)",  # pointer for access
        *_enter_guest("HS", relocated=False),  # enter guest
        *_case_banner(cases[0]),  # case banner lines
        "  hfence.gvma",  # G-stage fence
        "  LI(a3, 0)",  # clear check reg
        "  hlv.w a3, (t1)",  # hypervisor load
        "  nop",  # delay slot / pad
        *_sig(test_data, cases[0]),  # SIGUPD
        *_case_banner(cases[1]),  # case banner lines
        "  hfence.gvma",  # G-stage fence
        "  LI(t0, 0x257A0232)",  # load immediate
        "  hsv.w t0, (t1)",  # hypervisor store
        "  nop",  # delay slot / pad
        "  hfence.gvma",  # G-stage fence
        "  LI(a6, 0)",  # clear check reg
        "  hlv.w a6, (t1)",  # hypervisor load
        "  nop",  # delay slot / pad
        *_sig(test_data, cases[1]),  # SIGUPD
        *_leave_guest(),  # leave to M
        *set_g_data_leaf(paging, bad),  # rewrite G leaf
        "  hfence.gvma",  # G-stage fence
        *_enter_guest("HS", relocated=False),  # enter guest
        *_case_banner(cases[2]),  # case banner lines
        "  LI(a4, 0)",  # clear check reg
        "  LI(t1, gpa_data)",  # pointer for access
        "  hlv.w a4, (t1)",  # hypervisor load
        "  nop",  # delay slot / pad
        *_sig(test_data, cases[2]),  # SIGUPD
        *_case_banner(cases[3]),  # case banner lines
        "  hfence.gvma",  # G-stage fence
        "  LI(s3, 0)",  # clear check reg
        "  LI(t0, 0xDEADBEEF)",  # load immediate
        "  hsv.w t0, (t1)",  # hypervisor store
        "  nop",  # delay slot / pad
        *_sig(test_data, cases[3]),  # SIGUPD
        *_leave_guest(),  # leave to M
        *set_g_data_leaf(paging, good),  # rewrite G leaf
        "  hfence.gvma",  # G-stage fence
        *_enter_guest("HS", relocated=False),  # enter guest
        *_case_banner(cases[4]),  # case banner lines
        "  LI(a7, 0)",  # clear check reg
        "  LI(t1, gpa_data)",  # pointer for access
        "  hlv.w a7, (t1)",  # hypervisor load
        "  nop",  # delay slot / pad
        *_sig(test_data, cases[4]),  # SIGUPD
        *_leave_guest(),  # leave to M
        *twin_data(paging, mismatch_strings=_strings(cases)),  # twin data section
    ]  # list end


def generate_g_u_bit_HSmode(test_data: TestData) -> list[str]:  # public generator entry
    """Output ``SvH_g_u_bit_HSmode-00.S``: G-stage U=0/U=1 HLV/HSV from HS (``cp_hgatp_u_mode_access_rw``)."""
    return [comment_banner("g_u_bit_HSmode", "SvH G-stage U-bit stimulus"), *build_twins(test_data, _asm_g_u_bit)]  # banner + twins (g_u_bit_HSmode)


def _asm_sum_upages(test_data: TestData, paging: Paging) -> list[str]:  # SUM U-page VS body
    cases = [  # SigCase list
        SigCase("1", "SUM=0 VS lw/sw of U=1 page", "test1_sum0_lw", "a3", "Mismatch on SUM=0 U-page load!", "cp_vsatp_sum_effects_rw"),  # case 1: SUM=0 VS lw/sw of U=1 page
        SigCase("2", "SUM=0 SPA unchanged", "test2_sum0_spa", "t2", "Mismatch on SUM=0 SPA readback!", "cp_vsatp_sum_effects_rw", "Successful"),  # case 2: SUM=0 SPA unchanged
        SigCase("3", "SUM=1 VS store then load U=1 page", "test3_sum1_lw", "a7", "Mismatch on SUM=1 U-page load!", "cp_vsatp_sum_effects_rw", "Successful"),  # case 3: SUM=1 VS store then load U=1 page
        SigCase("4", "SUM=1 SPA readback", "test4_sum1_spa", "t3", "Mismatch on SUM=1 SPA readback!", "vsatp_sum_set", "Successful"),  # case 4: SUM=1 SPA readback
    ]  # list end
    lines = [  # asm output buffer
        *_vs_only_setup(paging, code_u=False, data_flags=pte_bits(x=True, w=True, r=True, u=True)),  # VS-only paging setup
        *preload_spa(0xDEADBEEF),  # preload SPA pattern
        *load_guest_va("a5", "va_data"),  # a5 = guest VA
        *_write_mxr_sum(0, 0),  # set MXR/SUM
        *_case_banner(cases[0]),  # case banner lines
        "  LI(a3, 0)",  # clear check reg
        "  LI(a4, 0)",  # clear check reg
        *_enter_guest("VS", relocated=True),  # enter guest
        "  lw a3, 0(a5)",  # load word
        "  nop",  # delay slot / pad
        "  sw a4, 0(a5)",  # store word
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        *_sig(test_data, cases[0]),  # SIGUPD
        *_case_banner(cases[1]),  # case banner lines
        "  la t1, test_region",  # SPA address into t1
        "  lw t2, 0(t1)",  # load word
        *_sig(test_data, cases[1]),  # SIGUPD
        *_write_mxr_sum(0, 1),  # set MXR/SUM
        *_case_banner(cases[2]),  # case banner lines
        "  LI(a6, 0x257A0201)",  # load immediate
        *_enter_guest("VS", relocated=True),  # enter guest
        "  sw a6, 0(a5)",  # store word
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        "  hfence.vvma",  # VS-stage fence
        "  LI(a7, 0)",  # clear check reg
        *_enter_guest("VS", relocated=True),  # enter guest
        "  lw a7, 0(a5)",  # load word
        "  nop",  # delay slot / pad
        *_leave_guest(),  # leave to M
        *_sig(test_data, cases[2]),  # SIGUPD
        *_case_banner(cases[3]),  # case banner lines
        "  la t1, test_region",  # SPA address into t1
        "  lw t3, 0(t1)",  # load word
        *_sig(test_data, cases[3]),  # SIGUPD
        *twin_data(paging, mismatch_strings=_strings(cases)),  # twin data section
    ]  # list end
    return lines  # finished asm lines


def generate_sum_Upages_VSmode(test_data: TestData) -> list[str]:  # public generator entry
    """Output ``SvH_sum_Upages_VSmode-00.S``: VS SUM=0 fault then SUM=1 success on U=1 pages."""
    return [comment_banner("sum_Upages_VSmode", "SvH VS SUM U-page stimulus"), *build_twins(test_data, _asm_sum_upages)]  # banner + twins (sum_Upages_VSmode)


def _asm_vs_perm(test_data: TestData, paging: Paging, *, mode: Guest) -> list[str]:  # VS-stage perm matrix body
    code_u = mode == "VU"  # U=1 on code if VU
    lines = [  # asm output buffer
        *_vs_only_setup(paging, code_u=code_u, data_flags=pte_bits(x=True, w=True, r=True, u=code_u)),  # VS-only paging setup
        *_write_mxr_sum(0, 0),  # set MXR/SUM
    ]  # list end
    if mode == "VS":  # VS path
        cp = "cp_vsatp_spages_sum_rwx cp_vsatp_perm_checks"  # coverpoint id string
        specs = [  # packed case table
            ("1", "S-page XWR=111 VS sw+lw", "test1_rwx", "a3", "Mismatch on S-page R/W/X VS lw in Test Case 1!", pte_bits(x=True, w=True, r=True), "swlw", 0, 0, "Successful"),  # case 1: S-page XWR=111 VS sw+lw
            ("2", "S-page X-only VS lw", "test2_xonly_lw", "a4", "Mismatch on S-page X-only VS lw (expect fault) in Test Case 2!", pte_bits(x=True), "lw", 0, 0, "Expected Fault"),  # case 2: S-page X-only VS lw
            ("3", "S-page X-only VS sw", "test3_xonly_sw", "a3", "Mismatch on S-page X-only VS sw (expect fault) in Test Case 3!", pte_bits(x=True), "sw", 0, 0, "Expected Fault"),  # case 3: S-page X-only VS sw
            ("4", "S-page R-only VS lw", "test4_ronly", "a3", "Mismatch on S-page R-only VS lw in Test Case 4!", pte_bits(r=True), "lw", 0, 0, "Successful"),  # case 4: S-page R-only VS lw
            ("4b", "S-page R-only VS sw", "test4b_ronly_sw", "a4", "Mismatch on S-page R-only VS sw (expect fault) in Test Case 4b!", pte_bits(r=True), "sw", 0, 0, "Expected Fault"),  # case 4b: S-page R-only VS sw
            ("5", "S-page R/W (XWR=110) VS sw+lw", "test5_rw", "a3", "Mismatch on S-page R/W VS lw in Test Case 5!", pte_bits(w=True, r=True), "swlw", 0, 0, "Successful"),  # case 5: S-page R/W (XWR=110) VS sw+lw
            ("6", "S-page R/X VS lw", "test6_rx", "a3", "Mismatch on S-page R/X VS lw in Test Case 6!", pte_bits(x=True, r=True), "lw", 0, 0, "Successful"),  # case 6: S-page R/X VS lw
            ("6b", "S-page R/X VS sw", "test6b_rx_sw", "a4", "Mismatch on S-page R/X VS sw (expect fault) in Test Case 6b!", pte_bits(x=True, r=True), "sw", 0, 0, "Expected Fault"),  # case 6b: S-page R/X VS sw
            ("7", "U=1 XWR=111 SUM=0 VS lw", "test7_u_lw", "a6", "Mismatch on U=1 VS lw with SUM=0 (expect fault) in Test Case 7!", pte_bits(x=True, w=True, r=True, u=True), "lw", 0, 0, "Expected Fault"),  # case 7: U=1 XWR=111 SUM=0 VS lw
            ("8", "U=1 XWR=111 SUM=0 VS sw", "test8_u_sw", "a7", "Mismatch on U=1 VS sw with SUM=0 (expect fault) in Test Case 8!", pte_bits(x=True, w=True, r=True, u=True), "sw", 0, 0, "Expected Fault"),  # case 8: U=1 XWR=111 SUM=0 VS sw
            ("9", "U=1 V-only VS sw", "test9_u_vonly_sw", "a3", "Mismatch on U=1 V-only VS sw (expect fault) in Test Case 9!", pte_bits(u=True), "sw", 0, 0, "Expected Fault"),  # case 9: U=1 V-only VS sw
            ("9b", "U=1 V-only VS lw", "test9b_u_vonly_lw", "s8", "Mismatch on U=1 V-only VS lw (expect fault) in Test Case 9b!", pte_bits(u=True), "lw", 0, 0, "Expected Fault"),  # case 9b: U=1 V-only VS lw
            ("10", "U=0 V-only VS lw", "test10_s_vonly_lw", "s2", "Mismatch on U=0 V-only VS lw (expect fault) in Test Case 10!", pte_bits(), "lw", 0, 0, "Expected Fault"),  # case 10: U=0 V-only VS lw
            ("11", "SUM=1 S-page XWR=111 VS sw", "test11_sum1_rwx_sw", "a3", "Mismatch on SUM=1 S-page R/W/X VS sw in Test Case 11!", pte_bits(x=True, w=True, r=True), "sw", 0, 1, "Successful"),  # case 11: SUM=1 S-page XWR=111 VS sw
            ("12", "SUM=1 S-page R/W VS sw+lw", "test12_sum1_rw", "a3", "Mismatch on SUM=1 S-page R/W VS lw in Test Case 12!", pte_bits(w=True, r=True), "swlw", 0, 1, "Successful"),  # case 12: SUM=1 S-page R/W VS sw+lw
            ("13", "SUM=1 S-page R/X VS lw", "test13_sum1_rx", "a3", "Mismatch on SUM=1 S-page R/X VS lw in Test Case 13!", pte_bits(x=True, r=True), "lw", 0, 1, "Successful"),  # case 13: SUM=1 S-page R/X VS lw
            ("14", "SUM=1 S-page X-only ifetch", "test14_sum1_x_ifetch", "a3", "Mismatch on SUM=1 S-page X-only ifetch in Test Case 14!", pte_bits(x=True), "jalr", 0, 1, "Successful"),  # case 14: SUM=1 S-page X-only ifetch
            ("12b", "SUM=1 S-page R/W VS lw only", "test12b_sum1_rw_lw", "a3", "Mismatch on SUM=1 S-page R/W VS lw-only in Test Case 12b!", pte_bits(w=True, r=True), "lw", 0, 1, "Successful"),  # case 12b: SUM=1 S-page R/W VS lw only
            ("13b", "SUM=1 S-page R/X VS sw", "test13b_sum1_rx_sw", "a4", "Mismatch on SUM=1 S-page R/X VS sw (expect fault) in Test Case 13b!", pte_bits(x=True, r=True), "sw", 0, 1, "Expected Fault"),  # case 13b: SUM=1 S-page R/X VS sw
            ("15", "SUM=1 S-page R-only VS lw", "test15_sum1_ronly_lw", "a3", "Mismatch on SUM=1 S-page R-only VS lw in Test Case 15!", pte_bits(r=True), "lw", 0, 1, "Successful"),  # case 15: SUM=1 S-page R-only VS lw
            ("16", "SUM=1 S-page R-only VS sw", "test16_sum1_ronly_sw", "a4", "Mismatch on SUM=1 S-page R-only VS sw (expect fault) in Test Case 16!", pte_bits(r=True), "sw", 0, 1, "Expected Fault"),  # case 16: SUM=1 S-page R-only VS sw
            ("17", "SUM=1 S-page R-only VS jalr", "test17_sum1_ronly_jalr", "s2", "Mismatch on SUM=1 S-page R-only VS jalr (expect fault) in Test Case 17!", pte_bits(r=True), "jalr", 0, 1, "Expected Fault"),  # case 17: SUM=1 S-page R-only VS jalr
            ("18", "SUM=1 S-page R/W VS jalr", "test18_sum1_rw_jalr", "s3", "Mismatch on SUM=1 S-page R/W VS jalr (expect fault) in Test Case 18!", pte_bits(w=True, r=True), "jalr", 0, 1, "Expected Fault"),  # case 18: SUM=1 S-page R/W VS jalr
        ]  # list end
    else:  # alternate path
        cp = "cp_vsatp_perm_checks"  # coverpoint id string
        specs = [  # packed case table
            ("1", "U=1 XWR=111 VU sw+lw", "test1_urw_rwx", "a3", "Mismatch on U=1 RWX VU lw in Test Case 1!", pte_bits(x=True, w=True, r=True, u=True), "swlw", 0, 0, "Successful"),  # case 1: U=1 XWR=111 VU sw+lw
            ("2", "U=1 X-only VU lw", "test2_ux_lw", "a4", "Mismatch on U=1 X-only VU lw (expect fault) in Test Case 2!", pte_bits(x=True, u=True), "lw", 0, 0, "Expected Fault"),  # case 2: U=1 X-only VU lw
            ("3", "U=1 X-only VU sw", "test3_ux_sw", "a3", "Mismatch on U=1 X-only VU sw (expect fault) in Test Case 3!", pte_bits(x=True, u=True), "sw", 0, 0, "Expected Fault"),  # case 3: U=1 X-only VU sw
            ("4", "U=1 R-only VU lw OK, VU sw fault", "test4_ur_only", "a3", "Mismatch on U=1 R-only VU lw in Test Case 4!", pte_bits(r=True, u=True), "lw", 0, 0, "Successful"),  # case 4: U=1 R-only VU lw OK, VU sw fault
            ("5", "U=1 R/W VU sw+lw", "test5_urw", "a3", "Mismatch on U=1 R/W VU lw in Test Case 5!", pte_bits(w=True, r=True, u=True), "swlw", 0, 0, "Successful"),  # case 5: U=1 R/W VU sw+lw
            ("6", "U=1 R/X VU lw OK, VU sw fault", "test6_urx", "a3", "Mismatch on U=1 R/X VU lw in Test Case 6!", pte_bits(x=True, r=True, u=True), "lw", 0, 0, "Successful"),  # case 6: U=1 R/X VU lw OK, VU sw fault
            ("7", "U=0 XWR=111 VU lw", "test7_s_lw", "a6", "Mismatch on U=0 VU lw (expect fault) in Test Case 7!", pte_bits(x=True, w=True, r=True), "lw", 0, 0, "Expected Fault"),  # case 7: U=0 XWR=111 VU lw
            ("8", "U=1 V-only VU lw", "test8_uv_lw", "a7", "Mismatch on U=1 V-only VU lw (expect fault) in Test Case 8!", pte_bits(u=True), "lw", 0, 0, "Expected Fault"),  # case 8: U=1 V-only VU lw
            ("9", "U=0 XWR=111 VU sw", "test9_s_sw", "s2", "Mismatch on U=0 VU sw (expect fault) in Test Case 9!", pte_bits(x=True, w=True, r=True), "sw", 0, 0, "Expected Fault"),  # case 9: U=0 XWR=111 VU sw
            ("10", "U=0 V-only VU lw", "test10_sv_lw", "s3", "Mismatch on U=0 V-only VU lw (expect fault) in Test Case 10!", pte_bits(), "lw", 0, 0, "Expected Fault"),  # case 10: U=0 V-only VU lw
            ("11", "U=0 V-only VU sw", "test11_sv_sw", "s4", "Mismatch on U=0 V-only VU sw (expect fault) in Test Case 11!", pte_bits(), "sw", 0, 0, "Expected Fault"),  # case 11: U=0 V-only VU sw
            ("12", "U=1 V-only VU sw", "test12_uv_sw", "s5", "Mismatch on U=1 V-only VU sw (expect fault) in Test Case 12!", pte_bits(u=True), "sw", 0, 0, "Expected Fault"),  # case 12: U=1 V-only VU sw
        ]  # list end
    cases = [SigCase(num, title, label, reg, msg, cp, expected) for num, title, label, reg, msg, _flags, _access, _mxr, _sum, expected in specs]  # SigCase list
    for spec, case in zip(specs, cases):  # each packed case
        payload = (0x257A0400 if mode == "VS" else 0x257A0700) + len(lines)  # unique data pattern
        lines.extend(  # extend with following list
            _asm_vs_seed_case(  # emit VS permission case
                test_data,  # pass test counters
                paging,  # pass paging twin
                case=case,  # this case
                mode=mode,  # guest mode
                flags=spec[5],  # PTE flags
                access=spec[6],  # access kind
                mxr=spec[7],  # MXR bit
                sum_=spec[8],  # SUM bit
                payload=payload,  # data pattern
                exec_page=case.label == "test14_sum1_x_ifetch",  # use xonly exec page?
            )  # end paren
        )  # end paren
    lines.extend(_data(paging, regions=["test_region"], strings=_strings(cases), xonly_exec=mode == "VS"))  # append asm lines
    return lines  # finished asm lines


def generate_vs_perm_VSmode(test_data: TestData) -> list[str]:  # public generator entry
    """Output ``SvH_vs_perm_VSmode-00.S``: VS XWR/U/SUM matrix (directed case count)."""
    return [comment_banner("vs_perm_VSmode", "SvH VS-stage permission stimulus"), *build_twins(test_data, lambda td, p: _asm_vs_perm(td, p, mode="VS"))]  # banner + twins (vs_perm_VSmode)


def generate_vs_perm_VUmode(test_data: TestData) -> list[str]:  # public generator entry
    """Output ``SvH_vs_perm_VUmode-00.S``: VU permission allow/deny on U vs S pages."""
    return [comment_banner("vs_perm_VUmode", "SvH VS-stage permission stimulus"), *build_twins(test_data, lambda td, p: _asm_vs_perm(td, p, mode="VU"))]  # banner + twins (vs_perm_VUmode)


def _asm_mxr_sum(test_data: TestData, paging: Paging, *, mode: Guest) -> list[str]:  # MXR×SUM case matrix body
    code_u = mode == "VU"  # U=1 on code if VU
    va_s_rw = "0x0000000080020000" if paging == "sv39" else "0x08002000"  # S-page RW VA (no TLB alias)
    lines = [  # asm output buffer
        *_vs_only_setup(paging, code_u=code_u, data_flags=pte_bits(x=True, w=True, r=True, u=code_u)),  # VS-only paging setup
        f"  .set va_s_rw, {va_s_rw}",  # S-page RW VA symbol
        *_vs_leaf_map(paging, va="va_s_rw", pa="test_region_s_rw", flags=pte_bits(x=True, w=True, r=True)),  # VS data leaf map
        *fence_both_stages(),  # both-stage fences
    ]  # list end
    x_s = pte_bits(x=True)  # S-page X-only
    x_u = pte_bits(x=True, u=True)  # U-page X-only
    rwx_s = pte_bits(x=True, w=True, r=True)  # S-page XWR=111
    rwx_u = pte_bits(x=True, w=True, r=True, u=True)  # U-page XWR=111
    if mode == "VS":  # VS path
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
        ]  # list end
        if paging == "sv39":  # Sv39 three-level
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
            ]  # list end
        )  # end paren
    else:  # alternate path
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
        ]  # list end
    cases = [  # SigCase list
        SigCase(num, title, label, reg, f"Mismatch on {title} in Test Case {num}!", "cp_vsstatus_mxr_sum", expected)  # SigCase record
        for num, title, label, reg, _flags, _access, _mxr, _sum, expected in specs  # unpack case fields
    ]  # list end
    for index, (spec, case) in enumerate(zip(specs, cases), start=1):  # each MXR/SUM case
        flags = spec[4]  # PTE flags for this case
    # Dedicated VA/PA for S-page RWX so MXR=1 SUM=1 reads are not TLB-aliased
    # with prior X-only walks on va_data (seed uses va_s_rw).
        use_s_rw = flags == rwx_s  # use va_s_rw / test_region_s_rw
        lines.extend(  # extend with following list
            _asm_vs_seed_case(  # emit VS permission case
                test_data,  # pass test counters
                paging,  # pass paging twin
                case=case,  # this case
                mode=mode,  # guest mode
                flags=flags,  # PTE flags
                access=spec[5],  # access kind
                mxr=spec[6],  # MXR bit
                sum_=spec[7],  # SUM bit
                payload=(0x257A0500 if mode == "VS" else 0x257A0600) + index,  # data pattern
                va="va_s_rw" if use_s_rw else "va_data",  # guest VA symbol
                pa="test_region_s_rw" if use_s_rw else None,  # physical page
            )  # end paren
        )  # end paren
    lines.extend(_data(paging, regions=["test_region", "test_region_s_rw"], strings=_strings(cases)))  # append asm lines
    return lines  # finished asm lines


def generate_vsstatus_mxr_sum_VSmode(test_data: TestData) -> list[str]:  # public generator entry
    """Output ``SvH_vsstatus_mxr_sum_VSmode-00.S``: VS MXR×SUM×S/U page accesses."""
    return [comment_banner("vsstatus_mxr_sum_VSmode", "SvH VS MXR/SUM matrix stimulus"), *build_twins(test_data, lambda td, p: _asm_mxr_sum(td, p, mode="VS"))]  # banner + twins (vsstatus_mxr_sum_VSmode)


def generate_vsstatus_mxr_sum_VUmode(test_data: TestData) -> list[str]:  # public generator entry
    """Output ``SvH_vsstatus_mxr_sum_VUmode-00.S``: VU MXR×SUM; SUM does not grant S-pages to VU."""
    return [comment_banner("vsstatus_mxr_sum_VUmode", "SvH VU MXR/SUM matrix stimulus"), *build_twins(test_data, lambda td, p: _asm_mxr_sum(td, p, mode="VU"))]  # banner + twins (vsstatus_mxr_sum_VUmode)


def _asm_vu_rwx(test_data: TestData, paging: Paging) -> list[str]:  # VU two-stage RWX allow/deny body
    """VU two-stage U=1 XWR=111 allow + U=0 deny — match seed VA/GPA and maps."""
    vs_mode, g_mode = mode_names(paging)  # VS and G MODE tokens
    cases = [  # SigCase list
        SigCase("1", "Both stages U=1 XWR=111 VU sw+lw", "test1_allow", "a3", "Mismatch on VU two-stage U=1 RWX!", "rwx_umode_pages_umode", "Successful"),  # case 1: Both stages U=1 XWR=111 VU sw+lw
        SigCase("2", "VS leaf U=0, G leaf U=1 VU lw", "test2_deny", "a4", "Mismatch on VU two-stage U=0 deny!", "rwx_umode_pages_umode"),  # case 2: VS leaf U=0, G leaf U=1 VU lw
    ]  # list end
    # Coverpoints need VS leaf 11?11111 (incl. W) on both data (_rw) and ifetch (_x).
    u_rwx = pte_bits(x=True, w=True, r=True, u=True)  # U=1 XWR=111
    s_rwx = pte_bits(x=True, w=True, r=True)  # U=0 deny leaf
    lines: list[str] = [  # asm output buffer
        "  .set va_data,                 0x008001000",  # data VA symbol
        "  .set va_deny,                 0x008002000",  # deny VA symbol
        "  .set va_code,                 0x90000000" if paging == "sv32" else "  .set va_code,                 0x0000000090000000",  # code VA symbol
        "  .set gpa_data,                0x00C002000",  # data GPA symbol
        "  .set gpa_deny,                0x00C003000",  # deny GPA symbol
        "  .set gpa_code,                0x012000000",  # code GPA symbol
        "  .set gpa_rvtest_Vroot_pg_tbl, 0x01000A000",  # VS root PT GPA
        "  .set gpa_rvtest_vlvl0_pg_tbl, 0x01000B000",  # VS L0 PT GPA
    ]  # list end
    if paging == "sv39":  # Sv39 three-level
        lines.append("  .set gpa_rvtest_vlvl1_pg_tbl, 0x000000001000C000")  # VS L1 PT GPA (Sv39)
        lines.extend(  # extend with following list
            [  # list begin
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl1_pg_tbl, {PTE_V_ONLY}, gpa_code, LEVEL2)",  # G L2 non-leaf
                f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {u_rwx}, gpa_code, LEVEL1)",  # G code superpage
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_rvtest_Vroot_pg_tbl, LEVEL1)",  # G non-leaf
                f"  G_PTE_SETUP({g_mode}, rvtest_Vroot_pg_tbl, {PTE_PT_G}, gpa_rvtest_Vroot_pg_tbl, LEVEL0)",  # G maps VS page-table page
                f"  G_PTE_SETUP({g_mode}, rvtest_vlvl1_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl1_pg_tbl, LEVEL0)",  # G maps VS page-table page
                f"  G_PTE_SETUP({g_mode}, rvtest_vlvl0_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)",  # G maps VS page-table page
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)",  # G non-leaf
                f"  G_PTE_SETUP({g_mode}, test_region, {u_rwx}, gpa_data, LEVEL0)",  # G data leaf
                f"  G_PTE_SETUP({g_mode}, test_region_deny, {u_rwx}, gpa_deny, LEVEL0)",  # G leaf for deny GPA
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_code, LEVEL2)",  # VS L2 non-leaf
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_code, {u_rwx}, va_code, LEVEL1)",  # VS PTE setup
                "  csrr a0, mscratch",  # a0 = save-area base
                "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate save area
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl1_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL2)",  # VS L2 non-leaf
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)",  # VS L1 non-leaf
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_data, {u_rwx}, va_data, LEVEL0)",  # VS data leaf
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_deny, {s_rwx}, va_deny, LEVEL0)",  # VS deny leaf U=0
            ]  # list end
        )  # end paren
    else:  # alternate path
        lines.extend(  # extend with following list
            [  # list begin
                f"  SUPERPAGE_G_PTE_SETUP({g_mode}, rvtest_code_begin, {u_rwx}, gpa_code, LEVEL1)",  # G code superpage
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_rvtest_Vroot_pg_tbl, LEVEL1)",  # G non-leaf
                f"  G_PTE_SETUP({g_mode}, rvtest_Vroot_pg_tbl, {PTE_PT_G}, gpa_rvtest_Vroot_pg_tbl, LEVEL0)",  # G maps VS page-table page
                f"  G_PTE_SETUP({g_mode}, rvtest_vlvl0_pg_tbl, {PTE_PT_G}, gpa_rvtest_vlvl0_pg_tbl, LEVEL0)",  # G maps VS page-table page
                f"  G_PTE_SETUP({g_mode}, rvtest_hlvl0_pg_tbl, {PTE_V_ONLY}, gpa_data, LEVEL1)",  # G non-leaf
                f"  G_PTE_SETUP({g_mode}, test_region, {u_rwx}, gpa_data, LEVEL0)",  # G data leaf
                f"  G_PTE_SETUP({g_mode}, test_region_deny, {u_rwx}, gpa_deny, LEVEL0)",  # G leaf for deny GPA
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_code, {u_rwx}, va_code, LEVEL1)",  # VS PTE setup
                "  csrr a0, mscratch",  # a0 = save-area base
                "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL1)",  # relocate save area
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_rvtest_vlvl0_pg_tbl, {PTE_V_ONLY}, va_data, LEVEL1)",  # VS L1 non-leaf
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_data, {u_rwx}, va_data, LEVEL0)",  # VS data leaf
                f"  VS_PTE_SETUP({vs_mode}, GPA, gpa_deny, {s_rwx}, va_deny, LEVEL0)",  # VS deny leaf U=0
            ]  # list end
        )  # end paren
    lines.extend(enable_two_stage(paging))  # enable vsatp+hgatp
    lines.extend(preload_spa(0x257A0B01))  # preload SPA pattern
    # Seed-style single VU hop: sw then lw (hits write+read with same U=1 XWR=111 leaf).
    # VU ifetch through VS code leaf XWR=111 hits rwx_umode_pages_umode_x.
    lines.extend(  # extend with following list
        [  # list begin
            *_case_banner(cases[0]),  # case banner lines
            "  LI(a5, va_data)",  # pointer for access
            "  LI(t0, 0x257A0B01)",  # load immediate
            *_enter_guest("VU", relocated=True),  # enter guest
            "  sw t0, 0(a5)",  # store word
            "  nop",  # delay slot / pad
            "  lw a3, 0(a5)",  # load word
            "  nop",  # delay slot / pad
            *_leave_guest(),  # leave to M
            *_sig(test_data, cases[0]),  # SIGUPD
            *_case_banner(cases[1]),  # case banner lines
            "  LI(a5, va_deny)",  # pointer for access
            "  LI(a4, 0)",  # clear check reg
            *_enter_guest("VU", relocated=True),  # enter guest
            "  lw a4, 0(a5)",  # load word
            "  nop",  # delay slot / pad
            *_leave_guest(),  # leave to M
            *_sig(test_data, cases[1]),  # SIGUPD
            *data_section(  # data section
                need_test_region=True,  # include test_region?
                need_hlvl0=True,  # page-table pages needed
                need_vlvl0=True,  # page-table pages needed
                need_hlvl1=paging == "sv39",  # page-table pages needed
                need_vlvl1=paging == "sv39",  # page-table pages needed
                extra_regions=_regions(["test_region_deny"]),  # extra named regions
                mismatch_strings=_strings(cases),  # mismatch .string list
            ),  # end paren
        ]  # list end
    )  # end paren
    return lines  # finished asm lines


def generate_vu_rwx_two_stage_VUmode(test_data: TestData) -> list[str]:  # public generator entry
    """Output ``SvH_vu_rwx_two_stage_VUmode-00.S``: VU on U=1 both stages, then U=0 deny."""
    return [comment_banner("vu_rwx_two_stage_VUmode", "SvH VU two-stage U-page stimulus"), *build_twins(test_data, _asm_vu_rwx)]  # banner + twins (vu_rwx_two_stage_VUmode)


def _asm_xonly_vs(test_data: TestData, paging: Paging, *, mode: Guest) -> list[str]:  # VS/VU xonly MXR=0 body
    code_u = mode == "VU"  # U=1 on code if VU
    cases = [  # SigCase list
        SigCase("1", f"{mode} load of X-only page with MXR=0", f"test1_mxr0_{mode.lower()}", "a3", f"Mismatch on {mode} X-only MXR=0 load!", f"xonly_mxr0_vs_{mode.lower()}"),  # SigCase record
    ]  # list end
    if mode == "VS":  # VS path
        cases.append(SigCase("2", "Control addi after VS ifetch", "test2_ctrl", "a4", "Mismatch on VS control addi!", "xonly_mxr0_vs_vs", "Successful"))  # bump control value
    lines = [  # asm output buffer
        *_vs_only_setup(paging, code_u=code_u, data_flags=pte_bits(x=True, u=code_u)),  # VS-only paging setup
        *preload_spa(0xDEADBEEF if mode == "VU" else 0x257A0801),  # preload SPA pattern
        *_write_mxr_sum(0, 0),  # set MXR/SUM
        *_asm_load_case(test_data, case=cases[0], mode=mode, va="va_data", check_reg="a3"),  # case asm body
    ]  # list end
    if mode == "VS":  # VS path
        lines.extend([*_case_banner(cases[1]), "  LI(a4, 0x257A0801)", "  addi a4, a4, 1", *_sig(test_data, cases[1])])  # append asm lines
    lines.extend(twin_data(paging, mismatch_strings=_strings(cases)))  # append asm lines
    return lines  # finished asm lines


def generate_xonly_mxr0_VSmode(test_data: TestData) -> list[str]:  # public generator entry
    """Output ``SvH_xonly_mxr0_VSmode-00.S``: VS load of execute-only with MXR=0 (fault)."""
    return [comment_banner("xonly_mxr0_VSmode", "SvH X-only MXR=0 stimulus"), *build_twins(test_data, lambda td, p: _asm_xonly_vs(td, p, mode="VS"))]  # banner + twins (xonly_mxr0_VSmode)


def generate_xonly_mxr0_VUmode(test_data: TestData) -> list[str]:  # public generator entry
    """Output ``SvH_xonly_mxr0_VUmode-00.S``: VU load of execute-only U=1 with MXR=0 (fault)."""
    return [comment_banner("xonly_mxr0_VUmode", "SvH X-only MXR=0 stimulus"), *build_twins(test_data, lambda td, p: _asm_xonly_vs(td, p, mode="VU"))]  # banner + twins (xonly_mxr0_VUmode)


def _asm_xonly_hs(test_data: TestData, paging: Paging) -> list[str]:  # HS HLV xonly MXR=0 body
    """HS hlv.w of a VS execute-only page with MXR=0 (expect fault)."""
    case = SigCase("1", "MXR=0 SPVP=1 VS X-only HS hlv.w", "test1_hlv", "a3", "Mismatch on HS HLV X-only MXR=0!", "xonly_mxr0_vs_hs")  # one SIGUPD
    return [  # return asm/list
        *_vs_only_setup(paging, code_u=False, data_flags=pte_bits(x=True)),  # vsatp ON, data leaf X-only
        *preload_spa(0x257A0811),  # pattern in the physical page
        *_write_mxr_sum(0, 0),  # MXR=0 so execute-only cannot be read
        "  LI(t0, HSTATUS_SPVP)",  # t0 = SPVP mask
        "  csrs hstatus, t0",  # SPVP=1: HLV walks VS-stage as VS
        *_case_banner(case),  # Test case 1 header
        *load_guest_va("a5", "va_data"),  # a5 = guest VA
        "  LI(a3, 0)",  # a3 stays 0 if HLV faults
        *_enter_guest("HS", relocated=False),  # T-SBI into HS
        "  hlv.w a3, (a5)",  # hypervisor load; expect fault
        "  nop",  # pad after the access
        *_leave_guest(),  # back to M-mode
        "  LI(t0, HSTATUS_SPVP)",  # t0 = SPVP mask
        "  csrc hstatus, t0",  # clear SPVP
        *_sig(test_data, case),  # dump a3
        *twin_data(paging, mismatch_strings=_strings([case])),  # tables + mismatch string
    ]  # list end


def generate_xonly_mxr0_HSmode(test_data: TestData) -> list[str]:  # public generator entry
    """Output ``SvH_xonly_mxr0_HSmode-00.S``: HS ``hlv.w`` of execute-only with MXR=0."""
    return [comment_banner("xonly_mxr0_HSmode", "SvH HS X-only MXR=0 stimulus"), *build_twins(test_data, _asm_xonly_hs)]  # banner + twins (xonly_mxr0_HSmode)


def _asm_xonly_gstage_hs(test_data: TestData, paging: Paging) -> list[str]:  # HS HLV G-stage xonly body
    """HS hlv.w of a G-stage execute-only GPA with MXR=0 (expect fault)."""
    case = SigCase("1", "G X-only U=1 MXR=0 HS hlv.w", "test1_g_xonly", "a3", "Mismatch on HS HLV G X-only MXR=0!", "xonly_mxr0_g_hs")  # one SIGUPD
    return [  # return asm/list
        *_g_only_setup(paging, g_flags=pte_bits(x=True, u=True)),  # vsatp Bare, hgatp ON, G leaf X-only U=1
        *preload_spa(0x257A0821),  # pattern in the physical page
        *_write_mxr_sum(0, 0),  # MXR=0 so execute-only cannot be read
        *_case_banner(case),  # Test case 1 header
        "  LI(t1, gpa_data)",  # t1 = GPA used as HLV pointer
        "  LI(a3, 0)",  # a3 stays 0 if HLV faults
        *_enter_guest("HS", relocated=False),  # T-SBI into HS
        "  hlv.w a3, (t1)",  # hypervisor load of GPA; expect fault
        "  nop",  # pad after the access
        *_leave_guest(),  # back to M-mode
        *_sig(test_data, case),  # dump a3
        *twin_data(paging, mismatch_strings=_strings([case])),  # tables + mismatch string
    ]  # list end


def generate_xonly_mxr0_gstage_HSmode(test_data: TestData) -> list[str]:  # public generator entry
    """Output ``SvH_xonly_mxr0_gstage_HSmode-00.S``: HS ``hlv.w`` of G-stage execute-only GPA."""
    return [comment_banner("xonly_mxr0_gstage_HSmode", "SvH G-stage X-only MXR=0 stimulus"), *build_twins(test_data, _asm_xonly_gstage_hs)]  # banner + twins (xonly_mxr0_gstage_HSmode)


