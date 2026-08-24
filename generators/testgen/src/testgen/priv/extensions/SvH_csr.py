##################################
# priv/extensions/SvH_csr.py
#
# SvH CSR family - true Python emitters, no runtime seed I/O.
# SPDX-License-Identifier: Apache-2.0
##################################

"""hgatp, vsatp, and satp field coverage. Three ``generate_*`` functions, three files.

``_write_csr_then_sigupd`` writes a CSR then SIGUPD. ``_walk_mode_field`` writes MODE 0..15
from Bare and from a legal mode. ``_walk_ppn_bits`` writes walking-1 PPN bits.

hgatp/vsatp files contain Sv32 and Sv39 under ifdefs. satp MODE walk is
RV64/Sv39 only and uses assembly loops so the guest remains mapped.
"""

from __future__ import annotations  # postpone evaluation of type hints

from testgen.asm.helpers import comment_banner  # file-level assembly banner
from testgen.data.state import TestData  # open TestChunk (SIGUPD / testcase counters)
from testgen.priv.extensions.SvHCommon import (  # shared SvH asm helpers
    CG,  # "SvH_cg" covergroup name
    goto_mmode,  # RVTEST_GOTO_MMODE after HS CSR walks
    sigupd_csr,  # csrr + SIGUPD helper
    sigupd_gpr,  # GPR SIGUPD helper (satp alias dumps)
    Paging,  # "sv32" | "sv39"
    mode_names,  # vsatp/hgatp MODE name pair
    build_twins,  # Sv32 + Sv39 ifdefs; SIGUPD_COUNT = max twin
)  # end SvHCommon imports

CHECK_CSR = 14  # a4 (x14); directed CSR SIGUPD dumps use this GPR


def _section(title: str) -> list[str]:  # emit // ---- section banner lines
    """Emit an assembly section banner."""
    return ["", "// " + "-" * 128, f"// {title}", "// " + "-" * 128]  # blank + three // lines


def _case(title: str, coverpoint: str | None = None) -> list[str]:  # per-case // banner
    """Emit a per-case assembly banner, including coverpoint ids when given."""
    lines = ["", "//" + "-" * 128, f"// {title} | Expected: Successful"]  # start case banner
    if coverpoint:  # optional Coverpoints: line
        lines.append(f"// Coverpoints: {coverpoint}")  # list cp_* ids for this case
    lines.append("//" + "-" * 128)  # close banner
    return lines  # ready to extend into asm body


def _wrap_sv39_only(lines: list[str]) -> list[str]:  # RV64 satp walk guard
    """Wrap ``lines`` in ``#ifdef SV39_SUPPORTED`` (RV64-only satp walk)."""
    return ["#ifdef SV39_SUPPORTED", *lines, "#endif  // SV39_SUPPORTED"]  # ifndef out on RV32


def _write_csr_then_sigupd(  # write CSR (or setup), then SIGUPD into a4
    test_data: TestData,  # live chunk / SIGUPD counters
    *,  # force keyword args below
    csr: str,  # CSR name, e.g. hgatp / vsatp
    value: str | None,  # LI immediate; None means write x0 (Bare)
    bin_name: str,  # coverpoint bin label
    coverpoint: str,  # cp_* name
    note: str,  # short // note on the csrw line
    setup: list[str] | None = None,  # optional multi-instr write replacing LI/csrw
) -> list[str]:  # returns asm lines for this sample
    """Write ``csr`` (or run ``setup``), then emit a CSR SIGUPD into a4.

    ``value=None`` writes x0 (Bare). ``setup`` replaces the default LI/csrw.
    """
    lines: list[str] = []  # write sequence then SIGUPD
    if setup:  # caller supplied a multi-instruction write (MODE walk previous-value)
        lines.extend(setup)  # use custom Bare/legal then try sequence
    elif value is None:  # Bare: write zero
        lines.append(f"  csrw {csr}, x0                                // {note}")  # clear CSR
    else:  # LI immediate then csrw
        lines.extend([f"  LI(t0, {value})", f"  csrw {csr}, t0                                // {note}"])  # load then write
    lines.extend(sigupd_csr(test_data, CHECK_CSR, csr, bin_name, coverpoint, covergroup=CG))  # dump csr into a4
    return lines  # one sample's asm


def _walk_mode_field(  # WARL MODE encodings 0..15 from two previous values
    test_data: TestData,  # live chunk
    *,  # keyword-only
    csr: str,  # hgatp or vsatp
    shift: int,  # MODE field bit position (31 or 60)
    legal_mode: str,  # assembler symbol for legal MODE
    legal_name: str,  # human name for bins / notes (sv39 / sv39x4)
    bin_prefix: str,  # bin name prefix, usually "mode"
    coverpoint: str,  # cp_*_mode_field
) -> list[str]:  # both walks as asm lines
    """WARL MODE walk: encodings 0..15 from Bare, then from ``legal_mode``."""
    lines = _case(f"{csr}.MODE walk 0..15 starting Bare", coverpoint)  # first walk banner
    for mode in range(16):  # encodings 0 through 15 inclusive
        lines.extend(  # append one Bare→try sample
            _write_csr_then_sigupd(  # write CSR then SIGUPD
                test_data,  # shared TestData
                csr=csr,  # hgatp or vsatp
                value=f"({mode} << {shift})",  # unused when setup is provided
                bin_name=f"{bin_prefix}_bare_{mode:02x}",  # unique bin per encoding
                coverpoint=coverpoint,  # cp_*_mode_field
                note=f"try MODE={mode} from Bare",  # // note text
                setup=[  # force Bare, then write candidate MODE
                    f"  csrw {csr}, x0                                // force previous MODE=Bare",  # previous=Bare
                    f"  LI(t0, ({mode} << {shift}))",  # candidate MODE in the MODE field
                    f"  csrw {csr}, t0                                // try MODE={mode}",  # WARL write
                ],  # end list
            )  # end call
        )  # end Bare walk sample

    lines.extend(_case(f"{csr}.MODE walk 0..15 starting {legal_name}", coverpoint))  # second walk banner
    for mode in range(16):  # same encodings, previous value is the legal MODE
        lines.extend(  # append one legal→try sample
            _write_csr_then_sigupd(  # write CSR then SIGUPD
                test_data,  # shared TestData
                csr=csr,  # same CSR
                value=f"({mode} << {shift})",  # unused with setup
                bin_name=f"{bin_prefix}_{legal_name.lower()}_{mode:02x}",  # bin keyed by legal start
                coverpoint=coverpoint,  # same cp
                note=f"try MODE={mode} from {legal_name}",  # // note
                setup=[  # restore legal, then try encoding
                    f"  LI(t0, ({legal_mode} << {shift}))",  # restore legal MODE (Sv39 / Sv39x4)
                    f"  csrw {csr}, t0                                // force previous MODE={legal_name}",  # previous=legal
                    f"  LI(t0, ({mode} << {shift}))",  # candidate encoding
                    f"  csrw {csr}, t0                                // try MODE={mode}",  # WARL write
                ],  # end list
            )  # end call
        )  # end legal walk sample
    return lines  # both walks, 32 SIGUPD sites


def _walk_ppn_bits(  # walking-1 across PPN field
    test_data: TestData,  # live chunk
    *,  # keyword-only
    csr: str,  # hgatp or vsatp
    mode_expr: str,  # legal MODE expression ORed with each bit
    bit_start: int,  # inclusive first PPN bit
    bit_stop: int,  # exclusive last PPN bit
    bin_prefix: str,  # bin prefix (often sv32/sv39)
    coverpoint: str,  # cp_*_ppn_field
) -> list[str]:  # one SIGUPD per bit
    """Walking-1 writes on ``csr``.PPN bits ``[bit_start, bit_stop)``, one SIGUPD each."""
    lines = _case(f"Walking ones on {csr}.PPN bits [{bit_stop - 1}:{bit_start}]", coverpoint)  # case banner
    for bit in range(bit_start, bit_stop):  # one write per PPN bit
        lines.extend(  # MODE | (1 << bit), then SIGUPD
            _write_csr_then_sigupd(  # write CSR then SIGUPD
                test_data,  # shared TestData
                csr=csr,  # target CSR
                value=f"({mode_expr}) | 0x{1 << bit:x}",  # legal MODE OR walking-1 in PPN
                bin_name=f"{bin_prefix}_ppn_bit_{bit:02d}",  # per-bit bin
                coverpoint=coverpoint,  # ppn coverpoint
                note=f"write walking-1 PPN bit {bit}",  # // note
            )  # end call
        )  # end one bit sample
    return lines  # full walking-1 sequence


def _asm_hgatp(test_data: TestData, paging: Paging) -> list[str]:  # HS hgatp field stimulus
    """HS-mode hgatp MODE, VMID, and PPN field stimulus for one paging twin."""
    _, hgatp_mode = mode_names(paging)  # "sv32x4" or "sv39x4"
    is_sv32 = paging == "sv32"  # True → skip RV64-only MODE 0..15 walk
    shift = 31 if is_sv32 else 60  # MODE field bit position in hgatp
    mode_const = f"HGATP_MODE_{hgatp_mode.upper()}"  # assembler symbol for legal MODE
    ppn_bits = 22 if is_sv32 else 44  # exclusive upper bound for walking-1
    ppn_start = 2  # Sv32x4/Sv39x4 PPN alignment: bits [1:0] not independently writable
    ppn_ones = "0x3fffff" if is_sv32 else f"0x{(((1 << 44) - 1) & ~0x3):x}"  # all writable PPN bits
    vmid_mask = "HGATP32_VMID" if is_sv32 else "HGATP64_VMID"  # all-ones VMID field
    suffix = "sv32" if is_sv32 else "sv39"  # bin-name suffix so twins do not collide

    # Isolate hgatp: VS Bare, then enter HS (identity; T-SBI).
    lines = [  # prelude before case banners
        "  csrw vsatp, x0                                // VS Bare; isolate hgatp field bins",  # clear VS paging
        "  hfence.vvma                                   // flush VS-stage TLB after vsatp clear",  # TLB sync
        "  RVTEST_TSBI_GOTO_SMODE                       // M->HS (T-SBI)",  # enter HS
    ]  # end prelude
    lines.extend(_section("Test Cases Start from here"))  # case list begins
    if is_sv32:  # RV32: explicit Bare sample before Sv32x4
        lines.extend(_case("Set hgatp.MODE=Bare", "cp_hgatp_mode_field"))  # Bare case banner
        lines.extend(  # Bare write + SIGUPD
            _write_csr_then_sigupd(  # write CSR then SIGUPD
                test_data,  # shared TestData
                csr="hgatp",  # G-stage ATP
                value=None,  # csrw hgatp, x0
                bin_name="mode_bare_sv32",  # Bare bin for Sv32 twin
                coverpoint="cp_hgatp_mode_field",  # MODE coverpoint
                note="write Bare MODE",  # // note
            )  # end call
        )  # end Bare sample
    lines.extend(_case(f"Set hgatp.MODE={hgatp_mode}, PPN=0", "cp_hgatp_mode_field"))  # legal MODE banner
    lines.extend(  # legal MODE, PPN=0 sample
        _write_csr_then_sigupd(  # write CSR then SIGUPD
            test_data,  # shared TestData
            csr="hgatp",  # G-stage ATP
            value=f"({mode_const} << {shift})",  # legal MODE, PPN=0
            bin_name=f"mode_{hgatp_mode}_{suffix}",  # legal-mode bin
            coverpoint="cp_hgatp_mode_field",  # MODE coverpoint
            note=f"write {hgatp_mode} with PPN=0",  # // note
        )  # end call
    )  # end legal MODE sample
    if not is_sv32:  # RV64: WARL walk of MODE 0..15 plus unsupported MODE=1
        lines.extend(  # full MODE WARL walks
            _walk_mode_field(  # MODE field WARL walk
                test_data,  # shared TestData
                csr="hgatp",  # G-stage ATP
                shift=shift,  # bit 60
                legal_mode=mode_const,  # HGATP_MODE_SV39X4
                legal_name=hgatp_mode,  # "sv39x4"
                bin_prefix="mode",  # bin prefix
                coverpoint="cp_hgatp_mode_field",  # MODE coverpoint
            )  # end call
        )  # end MODE walks
        lines.extend(_case("Set hgatp.MODE=1 sample", "cp_hgatp_mode_field"))  # unsupported-1 banner
        lines.extend(  # MODE=1 sample
            _write_csr_then_sigupd(  # write CSR then SIGUPD
                test_data,  # shared TestData
                csr="hgatp",  # G-stage ATP
                value=f"(1 << {shift})",  # encoding 1 is not a legal G-stage MODE
                bin_name="mode_1_sv39",  # unsupported bin
                coverpoint="cp_hgatp_mode_field",  # MODE coverpoint
                note="write unsupported MODE=1 sample",  # // note
            )  # end call
        )  # end MODE=1 sample
    lines.extend(_case("hgatp.VMID = all ones", "cp_hgatp_vmidlen_detect cp_hgatp_vmid_scoping"))  # VMID banner
    for readback in ("vmidlen", "scoping"):  # two SIGUPD of the same write (two coverpoints)
        lines.extend(  # all-ones VMID write + dump
            _write_csr_then_sigupd(  # write CSR then SIGUPD
                test_data,  # shared TestData
                csr="hgatp",  # G-stage ATP
                value=f"({mode_const} << {shift}) | {vmid_mask}",  # legal MODE + all VMID bits
                bin_name=f"{readback}_{suffix}",  # per-coverpoint bin
                coverpoint="cp_hgatp_vmidlen_detect" if readback == "vmidlen" else "cp_hgatp_vmid_scoping",  # pick cp
                note=f"write all VMID bits for {readback} readback",  # // note
            )  # end call
        )  # end one VMID readback
    lines.extend(_case("hgatp.PPN = all ones", "cp_hgatp_ppn_field"))  # PPN all-ones banner
    lines.extend(  # PPN all-ones sample
        _write_csr_then_sigupd(  # write CSR then SIGUPD
            test_data,  # shared TestData
            csr="hgatp",  # G-stage ATP
            value=f"({mode_const} << {shift}) | {ppn_ones}",  # legal MODE + all writable PPN bits
            bin_name=f"ppn_ones_{suffix}",  # all-ones bin
            coverpoint="cp_hgatp_ppn_field",  # PPN coverpoint
            note="write PPN all-ones pattern",  # // note
        )  # end call
    )  # end PPN ones
    lines.extend(  # walking-1 on PPN
        _walk_ppn_bits(  # walking-1 on PPN
            test_data,  # shared TestData
            csr="hgatp",  # G-stage ATP
            mode_expr=f"{mode_const} << {shift}",  # keep MODE legal while walking PPN
            bit_start=ppn_start,  # skip bits [1:0]
            bit_stop=ppn_bits,  # 22 or 44
            bin_prefix=suffix,  # twin suffix
            coverpoint="cp_hgatp_ppn_field",  # PPN coverpoint
        )  # end call
    )  # end PPN walk
    lines.extend(goto_mmode())  # SIGUPD of hgatp already ran in HS; return to M
    return lines  # full hgatp twin body


def _asm_vsatp(test_data: TestData, paging: Paging) -> list[str]:  # HS vsatp field stimulus
    """HS-mode vsatp MODE, ASID, and PPN field stimulus for one paging twin."""
    vs_mode, _ = mode_names(paging)  # "sv32" or "sv39"
    is_sv32 = paging == "sv32"  # True → skip RV64-only MODE walk
    shift = 31 if is_sv32 else 60  # MODE field bit position in vsatp/satp
    mode_const = f"SATP_MODE_{vs_mode.upper()}"  # SATP_MODE_SV32 or SATP_MODE_SV39
    ppn_bits = 22 if is_sv32 else 44  # exclusive upper bound for walking-1
    ppn_ones = "0x3fffff" if is_sv32 else f"0x{(1 << 44) - 1:x}"  # all PPN bits
    asid_mask = "SATP32_ASID" if is_sv32 else "SATP64_ASID"  # all-ones ASID field
    suffix = "sv32" if is_sv32 else "sv39"  # bin-name suffix

    lines = [  # prelude: Bare G-stage, enter HS
        "  csrw hgatp, x0                                // G-stage Bare; isolate vsatp field bins",  # clear G paging
        "  hfence.gvma                                   // flush old G-stage TLB after hgatp clear",  # TLB sync
        "  RVTEST_TSBI_GOTO_SMODE                       // M->HS (T-SBI)",  # enter HS
    ]  # end prelude
    lines.extend(_section("Test Cases Start from here"))  # case list begins
    lines.extend(_case(f"Set vsatp.MODE={vs_mode}, PPN=0", "cp_vsatp_mode_field" if not is_sv32 else None))  # MODE banner
    lines.extend(  # legal MODE, PPN=0
        _write_csr_then_sigupd(  # write CSR then SIGUPD
            test_data,  # shared TestData
            csr="vsatp",  # VS-stage ATP
            value=f"({mode_const} << {shift})",  # legal MODE, PPN=0
            bin_name=f"mode_{vs_mode}_{suffix}",  # legal-mode bin
            coverpoint="cp_vsatp_mode_field" if not is_sv32 else "cp_vsatp_ppn_field",  # RV32 has no MODE walk cp
            note=f"write {vs_mode} with PPN=0",  # // note
        )  # end call
    )  # end legal MODE sample
    if not is_sv32:  # RV64: WARL MODE 0..15 plus unsupported MODE=1
        lines.extend(  # full MODE WARL walks
            _walk_mode_field(  # MODE field WARL walk
                test_data,  # shared TestData
                csr="vsatp",  # VS-stage ATP
                shift=shift,  # bit 60
                legal_mode=mode_const,  # SATP_MODE_SV39
                legal_name=vs_mode,  # "sv39"
                bin_prefix="mode",  # bin prefix
                coverpoint="cp_vsatp_mode_field",  # MODE coverpoint
            )  # end call
        )  # end MODE walks
        lines.extend(_case("Set vsatp.MODE=1 sample", "cp_vsatp_mode_field"))  # unsupported-1 banner
        lines.extend(  # MODE=1 sample
            _write_csr_then_sigupd(  # write CSR then SIGUPD
                test_data,  # shared TestData
                csr="vsatp",  # VS-stage ATP
                value=f"(1 << {shift})",  # unsupported encoding
                bin_name="mode_1_sv39",  # unsupported bin
                coverpoint="cp_vsatp_mode_field",  # MODE coverpoint
                note="write unsupported MODE=1 sample",  # // note
            )  # end call
        )  # end MODE=1 sample
    lines.extend(_case("vsatp.ASID = all ones", "cp_vsatp_asidlen_detect"))  # ASID banner
    lines.extend(  # all-ones ASID sample
        _write_csr_then_sigupd(  # write CSR then SIGUPD
            test_data,  # shared TestData
            csr="vsatp",  # VS-stage ATP
            value=f"({mode_const} << {shift}) | {asid_mask}",  # legal MODE + all ASID bits
            bin_name=f"asid_ones_{suffix}",  # ASID bin
            coverpoint="cp_vsatp_asidlen_detect",  # ASID coverpoint
            note="write all ASID bits",  # // note
        )  # end call
    )  # end ASID sample
    lines.extend(_case("vsatp.PPN = all ones", "cp_vsatp_ppn_field"))  # PPN ones banner
    lines.extend(  # PPN all-ones sample
        _write_csr_then_sigupd(  # write CSR then SIGUPD
            test_data,  # shared TestData
            csr="vsatp",  # VS-stage ATP
            value=f"({mode_const} << {shift}) | {ppn_ones}",  # MODE | all PPN bits
            bin_name=f"ppn_ones_{suffix}",  # all-ones bin
            coverpoint="cp_vsatp_ppn_field",  # PPN coverpoint
            note="write PPN all-ones pattern",  # // note
        )  # end call
    )  # end PPN ones
    lines.extend(  # walking-1 on PPN
        _walk_ppn_bits(  # walking-1 on PPN
            test_data,  # shared TestData
            csr="vsatp",  # VS-stage ATP
            mode_expr=f"{mode_const} << {shift}",  # keep MODE legal
            bit_start=0,  # vsatp PPN is not forced 4-aligned like hgatp x4
            bit_stop=ppn_bits,  # 22 or 44
            bin_prefix=suffix,  # twin suffix
            coverpoint="cp_vsatp_ppn_field",  # PPN coverpoint
        )  # end call
    )  # end PPN walk
    lines.extend(goto_mmode())  # return to M after HS CSR dumps
    return lines  # full vsatp twin body


def _sigupd_satp_read(test_data: TestData, reg: int, bin_name: str) -> list[str]:  # GPR dump helper
    """GPR SIGUPD of ``reg`` against ``cp_satp_mode_field``."""
    return sigupd_gpr(test_data, reg, bin_name, "cp_satp_mode_field", covergroup=CG)  # dump GPR bin


def _asm_satp_mode(test_data: TestData) -> list[str]:  # RV64 VS satp.MODE walks
    """RV64/Sv39 VS satp.MODE walk — stay mapped: restore safe MODE before each GOTO_MMODE."""
    lines = [  # map guest code, turn on vsatp, Bare hgatp
        "  .set va_code, 0x0000000080000000              // GVA where VS executes this test code",  # guest VA
        "",  # blank for readability
        "  VS_PTE_SETUP(sv39, PA, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_W | PTE_V), va_code, LEVEL2)",  # map code
        "  csrr a0, mscratch                             // a0 = M save-area pointer",  # save-area base
        "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL2)",  # trap save area
        "",  # blank
        "  VSATP_SETUP(sv39, PA)                         // vsatp ON; hgatp stays Bare",  # enable VS paging
        "  csrw hgatp, x0",  # G-stage Bare so VS leaves are PAs
        "  hfence.vvma",  # flush VS-stage TLB
        "  hfence.gvma",  # flush G-stage TLB
    ]  # end setup
    lines.extend(_section("Test Cases Start from here"))  # case list begins
    lines.extend(_case("Read satp/vsatp alias with MODE=Sv39", "cp_satp_mode_field"))  # alias banner
    lines.extend(  # enter VS, read both names, dump from M
        [  # start asm list
            "  RVTEST_GOTO_LOWER_MODE VSmode                 // M->VS (VA!=PA relocate)",  # enter VS
            "  csrr a3, satp                                 // guest sees satp",  # read satp alias
            "  csrr a4, vsatp                                // vsatp must match satp alias",  # read vsatp
            *goto_mmode(),  # dump from M (signature not guest-mapped)
            *_sigupd_satp_read(test_data, 13, "satp_alias_sv39"),  # SIGUPD a3 (x13)
            *_sigupd_satp_read(test_data, 14, "vsatp_alias_sv39"),  # SIGUPD a4 (x14)
        ]  # end asm list
    )  # end alias sample
    # Asm loops like the seed: one SIGUPD label reused; restore Bare/Sv39 before each hop.
    lines.extend(_case("Walk satp.MODE 0..15 starting Bare", "cp_satp_mode_field"))  # Bare walk banner
    lines.extend(  # asm loop: try MODE 0..15 from Bare
        [  # start asm list
            "  RVTEST_GOTO_LOWER_MODE VSmode",  # enter VS for the walk
            "  csrw satp, x0",  # start from Bare
            "  LI(t3, 0)",  # loop index = candidate MODE
            "bare_mode_walk:",  # top of 0..15 loop
            "  csrw satp, x0",  # previous value Bare
            "  sll  t0, t3, 60",  # t0 = MODE << 60
            "  csrw satp, t0",  # try this encoding
            "  csrr a5, satp",  # WARL readback
            "  csrw satp, x0                                 // restore Bare before M hop",  # stay mappable
            *goto_mmode(),  # dump a5 from M
            *_sigupd_satp_read(test_data, 15, "bare_mode_walk"),  # one Python SIGUPD; loop reuses it 16 times
            "  RVTEST_GOTO_LOWER_MODE VSmode",  # re-enter VS for the next encoding
            "  addi t3, t3, 1",  # next MODE
            "  LI(t4, 16)",  # loop limit
            "  blt  t3, t4, bare_mode_walk",  # continue while t3 < 16
            *goto_mmode(),  # done with Bare walk
        ]  # end asm list
    )  # end Bare walk asm
    # Account for 15 extra SIGUPDs performed by the loop (first counted by emit_sigupd).
    if test_data.test_chunk is not None:  # 16 hardware dumps, 1 counted above
        test_data.test_chunk.sigupd_count += 15  # add the other 15 loop iterations

    lines.extend(_case("Walk satp.MODE 0..15 starting Sv39", "cp_satp_mode_field"))  # Sv39 walk banner
    lines.extend(  # asm loop: try MODE 0..15 from Sv39
        [  # start asm list
            "  RVTEST_GOTO_LOWER_MODE VSmode",  # enter VS
            "  csrr t2, satp",  # keep PPN/ASID; only MODE field changes
            "  li   t0, ~((0xF) << 60)",  # mask to clear MODE
            "  and  t2, t2, t0",  # t2 = satp with MODE=0
            "  li   t0, (SATP_MODE_SV39 << 60)",  # legal MODE
            "  or   t1, t2, t0",  # t1 = Sv39 | original PPN
            "  csrw satp, t1",  # previous value = Sv39
            "  LI(t3, 0)",  # loop index
            "sv39_mode_walk:",  # top of Sv39 walk loop
            "  sll  t0, t3, 60",  # candidate MODE
            "  or   t1, t2, t0",  # overlay onto PPN
            "  csrw satp, t1",  # try encoding
            "  csrr a5, satp",  # WARL readback
            "  li   t0, (SATP_MODE_SV39 << 60)",  # rebuild Sv39
            "  or   t1, t2, t0",  # Sv39 | PPN
            "  csrw satp, t1                                 // restore Sv39 before M hop",  # stay mapped
            *goto_mmode(),  # dump a5 from M
            *_sigupd_satp_read(test_data, 15, "sv39_mode_walk"),  # reused SIGUPD label
            "  RVTEST_GOTO_LOWER_MODE VSmode",  # back to VS
            "  li   t0, (SATP_MODE_SV39 << 60)",  # restore mapping so the next hop is legal
            "  or   t1, t2, t0",  # Sv39 | PPN again
            "  csrw satp, t1",  # write safe MODE
            "  addi t3, t3, 1",  # next MODE
            "  LI(t4, 16)",  # loop limit
            "  blt  t3, t4, sv39_mode_walk",  # continue while t3 < 16
            *goto_mmode(),  # done with Sv39 walk
        ]  # end asm list
    )  # end Sv39 walk asm
    if test_data.test_chunk is not None:  # 15 extra loop dumps
        test_data.test_chunk.sigupd_count += 15  # account for loop reuse

    lines.extend(_case("Final satp read after MODE walks", "cp_satp_mode_field"))  # final banner
    lines.extend(  # one last satp read from VS
        [  # start asm list
            "  RVTEST_GOTO_LOWER_MODE VSmode",  # enter VS
            "  csrr a6, satp",  # final WARL value
            *goto_mmode(),  # dump from M
            *_sigupd_satp_read(test_data, 16, "final_satp_sv39"),  # SIGUPD a6 (x16)
        ]  # end asm list
    )  # end final sample
    return lines  # full satp MODE body


def generate_csr_hgatp_fields_HSmode(test_data: TestData) -> list[str]:  # public emitter
    """Output ``SvH_csr_hgatp_fields_HSmode-00.S``."""
    return [  # banner + Sv32/Sv39 twins
        comment_banner("csr_hgatp_fields_HSmode", "SvH CSR field coverage"),  # // file banner
        *build_twins(test_data, _asm_hgatp),  # emit both paging twins under ifdefs
    ]  # end return


def generate_csr_satp_mode_VSmode(test_data: TestData) -> list[str]:  # public emitter
    """Output ``SvH_csr_satp_mode_VSmode-00.S`` (RV64/Sv39 only)."""
    return [  # banner + SV39-only wrap
        comment_banner("csr_satp_mode_VSmode", "SvH CSR field coverage"),  # // file banner
        *_wrap_sv39_only(_asm_satp_mode(test_data)),  # ifdef SV39_SUPPORTED body
    ]  # end return


def generate_csr_vsatp_fields_HSmode(test_data: TestData) -> list[str]:  # public emitter
    """Output ``SvH_csr_vsatp_fields_HSmode-00.S``."""
    return [  # banner + Sv32/Sv39 twins
        comment_banner("csr_vsatp_fields_HSmode", "SvH CSR field coverage"),  # // file banner
        *build_twins(test_data, _asm_vsatp),  # emit both paging twins under ifdefs
    ]  # end return
