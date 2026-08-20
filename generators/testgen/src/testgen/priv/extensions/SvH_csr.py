##################################
# priv/extensions/SvH_csr.py
#
# SvH CSR family - true Python emitters, no runtime seed I/O.
# SPDX-License-Identifier: Apache-2.0
##################################

"""hgatp, vsatp, and satp field coverage. Three ``generate_*`` functions, three files.

``_csr_write_read`` writes a CSR then SIGUPD. ``_mode_walk`` writes MODE 0..15
from Bare and from a legal mode. ``_ppn_walk`` writes walking-1 PPN bits.

hgatp/vsatp files contain Sv32 and Sv39 under ifdefs. satp MODE walk is
RV64/Sv39 only and uses assembly loops so the guest remains mapped.
"""

from __future__ import annotations  # postpone evaluation of type hints

from testgen.asm.helpers import comment_banner  # file-level assembly banner
from testgen.data.state import TestData  # open TestChunk (SIGUPD / testcase counters)
from testgen.priv.extensions.SvHCommon import (
    CG,  # "SvH_cg" covergroup name
    emit_goto_mmode,  # RVTEST_GOTO_MMODE after HS CSR walks
    emit_sigupd_csr,  # csrr + SIGUPD helper
    emit_sigupd_gpr,  # GPR SIGUPD helper (satp alias dumps)
    Paging,  # "sv32" | "sv39"
    paging_modes,  # vsatp/hgatp MODE name pair
    wrap_sv32_sv39,  # #ifdef SV32 / SV39 wrappers
)

CHECK_CSR = 14  # a4 (x14); directed CSR SIGUPD dumps use this GPR


def _section(title: str) -> list[str]:
    """Emit an assembly section banner."""
    return ["", "// " + "-" * 128, f"// {title}", "// " + "-" * 128]  # blank line then 128-dash box


def _case(title: str, coverpoint: str | None = None) -> list[str]:
    """Emit a per-case assembly banner, including coverpoint ids when given."""
    lines = ["", "//" + "-" * 128, f"// {title} | Expected: Successful"]  # case header
    if coverpoint:  # some Sv32 vsatp cases omit a MODE coverpoint id
        lines.append(f"// Coverpoints: {coverpoint}")  # ids sampled by this case
    lines.append("//" + "-" * 128)  # close the banner
    return lines


def _rv64_sv39(lines: list[str]) -> list[str]:
    """Wrap ``lines`` in ``#ifdef SV39_SUPPORTED`` (RV64-only satp walk)."""
    return ["#ifdef SV39_SUPPORTED", *lines, "#endif  // SV39_SUPPORTED"]  # RV32 preprocessor drops this


def _sigupd_count(test_data: TestData) -> int:
    """Current chunk SIGUPD count, or 0 if no chunk is open."""
    return test_data.test_chunk.sigupd_count if test_data.test_chunk is not None else 0


def _set_sigupd_count(test_data: TestData, value: int) -> None:
    """Overwrite the chunk SIGUPD count (used to take max of Sv32/Sv39)."""
    if test_data.test_chunk is not None:  # make_svh always has a chunk
        test_data.test_chunk.sigupd_count = value  # rewind or commit max(sv32, sv39)


def _csr_write_read(
    test_data: TestData,
    *,
    csr: str,
    value: str | None,
    bin_name: str,
    coverpoint: str,
    note: str,
    setup: list[str] | None = None,
) -> list[str]:
    """Write ``csr`` (or run ``setup``), then emit a CSR SIGUPD into a4.

    ``value=None`` writes x0 (Bare). ``setup`` replaces the default LI/csrw.
    """
    lines: list[str] = []  # write sequence then SIGUPD
    if setup:  # caller supplied a multi-instruction write (MODE walk previous-value)
        lines.extend(setup)
    elif value is None:  # Bare: write zero
        lines.append(f"  csrw {csr}, x0                                // {note}")
    else:  # LI immediate then csrw
        lines.extend([f"  LI(t0, {value})", f"  csrw {csr}, t0                                // {note}"])
    lines.extend(emit_sigupd_csr(test_data, CHECK_CSR, csr, bin_name, coverpoint, covergroup=CG))  # dump csr into a4
    return lines


def _mode_walk(
    test_data: TestData,
    *,
    csr: str,
    shift: int,
    legal_mode: str,
    legal_name: str,
    bin_prefix: str,
    coverpoint: str,
) -> list[str]:
    """WARL MODE walk: encodings 0..15 from Bare, then from ``legal_mode``."""
    lines = _case(f"{csr}.MODE walk 0..15 starting Bare", coverpoint)  # first walk banner
    for mode in range(16):  # encodings 0 through 15 inclusive
        lines.extend(
            _csr_write_read(
                test_data,
                csr=csr,  # hgatp or vsatp
                value=f"({mode} << {shift})",  # unused when setup is provided
                bin_name=f"{bin_prefix}_bare_{mode:02x}",  # unique bin per encoding
                coverpoint=coverpoint,  # cp_*_mode_field
                note=f"try MODE={mode} from Bare",
                setup=[
                    f"  csrw {csr}, x0                                // force previous MODE=Bare",
                    f"  LI(t0, ({mode} << {shift}))",  # candidate MODE in the MODE field
                    f"  csrw {csr}, t0                                // try MODE={mode}",
                ],
            )
        )

    lines.extend(_case(f"{csr}.MODE walk 0..15 starting {legal_name}", coverpoint))  # second walk banner
    for mode in range(16):  # same encodings, previous value is the legal MODE
        lines.extend(
            _csr_write_read(
                test_data,
                csr=csr,
                value=f"({mode} << {shift})",
                bin_name=f"{bin_prefix}_{legal_name.lower()}_{mode:02x}",
                coverpoint=coverpoint,
                note=f"try MODE={mode} from {legal_name}",
                setup=[
                    f"  LI(t0, ({legal_mode} << {shift}))",  # restore legal MODE (Sv39 / Sv39x4)
                    f"  csrw {csr}, t0                                // force previous MODE={legal_name}",
                    f"  LI(t0, ({mode} << {shift}))",  # candidate encoding
                    f"  csrw {csr}, t0                                // try MODE={mode}",
                ],
            )
        )
    return lines  # both walks, 32 SIGUPD sites


def _ppn_walk(
    test_data: TestData,
    *,
    csr: str,
    mode_expr: str,
    bit_start: int,
    bit_stop: int,
    bin_prefix: str,
    coverpoint: str,
) -> list[str]:
    """Walking-1 writes on ``csr``.PPN bits ``[bit_start, bit_stop)``, one SIGUPD each."""
    lines = _case(f"Walking ones on {csr}.PPN bits [{bit_stop - 1}:{bit_start}]", coverpoint)
    for bit in range(bit_start, bit_stop):  # one write per PPN bit
        lines.extend(
            _csr_write_read(
                test_data,
                csr=csr,
                value=f"({mode_expr}) | 0x{1 << bit:x}",  # legal MODE OR walking-1 in PPN
                bin_name=f"{bin_prefix}_ppn_bit_{bit:02d}",
                coverpoint=coverpoint,
                note=f"write walking-1 PPN bit {bit}",
            )
        )
    return lines


def _hgatp_body(test_data: TestData, paging: Paging) -> list[str]:
    """HS-mode hgatp MODE, VMID, and PPN field stimulus for one paging twin."""
    _, hgatp_mode = paging_modes(paging)  # "sv32x4" or "sv39x4"
    is_sv32 = paging == "sv32"  # True → skip RV64-only MODE 0..15 walk
    shift = 31 if is_sv32 else 60  # MODE field bit position in hgatp
    mode_const = f"HGATP_MODE_{hgatp_mode.upper()}"  # assembler symbol for legal MODE
    ppn_bits = 22 if is_sv32 else 44  # exclusive upper bound for walking-1
    ppn_start = 2  # Sv32x4/Sv39x4 PPN alignment: bits [1:0] not independently writable
    ppn_ones = "0x3fffff" if is_sv32 else f"0x{(((1 << 44) - 1) & ~0x3):x}"  # all writable PPN bits
    vmid_mask = "HGATP32_VMID" if is_sv32 else "HGATP64_VMID"  # all-ones VMID field
    suffix = "sv32" if is_sv32 else "sv39"  # bin-name suffix so twins do not collide

    # Isolate hgatp: VS Bare, then enter HS (identity; T-SBI).
    lines = [
        "  csrw vsatp, x0                                // VS Bare; isolate hgatp field bins",
        "  hfence.vvma                                   // flush VS-stage TLB after vsatp clear",
        "  RVTEST_TSBI_GOTO_SMODE                       // M->HS (T-SBI)",
    ]
    lines.extend(_section("Test Cases Start from here"))  # case list begins
    if is_sv32:  # RV32: explicit Bare sample before Sv32x4
        lines.extend(_case("Set hgatp.MODE=Bare", "cp_hgatp_mode_field"))
        lines.extend(
            _csr_write_read(
                test_data,
                csr="hgatp",
                value=None,  # csrw hgatp, x0
                bin_name="mode_bare_sv32",
                coverpoint="cp_hgatp_mode_field",
                note="write Bare MODE",
            )
        )
    lines.extend(_case(f"Set hgatp.MODE={hgatp_mode}, PPN=0", "cp_hgatp_mode_field"))
    lines.extend(
        _csr_write_read(
            test_data,
            csr="hgatp",
            value=f"({mode_const} << {shift})",  # legal MODE, PPN=0
            bin_name=f"mode_{hgatp_mode}_{suffix}",
            coverpoint="cp_hgatp_mode_field",
            note=f"write {hgatp_mode} with PPN=0",
        )
    )
    if not is_sv32:  # RV64: WARL walk of MODE 0..15 plus unsupported MODE=1
        lines.extend(
            _mode_walk(
                test_data,
                csr="hgatp",
                shift=shift,  # bit 60
                legal_mode=mode_const,  # HGATP_MODE_SV39X4
                legal_name=hgatp_mode,  # "sv39x4"
                bin_prefix="mode",
                coverpoint="cp_hgatp_mode_field",
            )
        )
        lines.extend(_case("Set hgatp.MODE=1 sample", "cp_hgatp_mode_field"))
        lines.extend(
            _csr_write_read(
                test_data,
                csr="hgatp",
                value=f"(1 << {shift})",  # encoding 1 is not a legal G-stage MODE
                bin_name="mode_1_sv39",
                coverpoint="cp_hgatp_mode_field",
                note="write unsupported MODE=1 sample",
            )
        )
    lines.extend(_case("hgatp.VMID = all ones", "cp_hgatp_vmidlen_detect cp_hgatp_vmid_scoping"))
    for readback in ("vmidlen", "scoping"):  # two SIGUPD of the same write (two coverpoints)
        lines.extend(
            _csr_write_read(
                test_data,
                csr="hgatp",
                value=f"({mode_const} << {shift}) | {vmid_mask}",  # legal MODE + all VMID bits
                bin_name=f"{readback}_{suffix}",
                coverpoint="cp_hgatp_vmidlen_detect" if readback == "vmidlen" else "cp_hgatp_vmid_scoping",
                note=f"write all VMID bits for {readback} readback",
            )
        )
    lines.extend(_case("hgatp.PPN = all ones", "cp_hgatp_ppn_field"))
    lines.extend(
        _csr_write_read(
            test_data,
            csr="hgatp",
            value=f"({mode_const} << {shift}) | {ppn_ones}",  # legal MODE + all writable PPN bits
            bin_name=f"ppn_ones_{suffix}",
            coverpoint="cp_hgatp_ppn_field",
            note="write PPN all-ones pattern",
        )
    )
    lines.extend(
        _ppn_walk(
            test_data,
            csr="hgatp",
            mode_expr=f"{mode_const} << {shift}",  # keep MODE legal while walking PPN
            bit_start=ppn_start,  # skip bits [1:0]
            bit_stop=ppn_bits,  # 22 or 44
            bin_prefix=suffix,
            coverpoint="cp_hgatp_ppn_field",
        )
    )
    lines.extend(emit_goto_mmode())  # SIGUPD of hgatp already ran in HS; return to M
    return lines


def _vsatp_body(test_data: TestData, paging: Paging) -> list[str]:
    """HS-mode vsatp MODE, ASID, and PPN field stimulus for one paging twin."""
    vs_mode, _ = paging_modes(paging)  # "sv32" or "sv39"
    is_sv32 = paging == "sv32"  # True → skip RV64-only MODE walk
    shift = 31 if is_sv32 else 60  # MODE field bit position in vsatp/satp
    mode_const = f"SATP_MODE_{vs_mode.upper()}"  # SATP_MODE_SV32 or SATP_MODE_SV39
    ppn_bits = 22 if is_sv32 else 44  # exclusive upper bound for walking-1
    ppn_ones = "0x3fffff" if is_sv32 else f"0x{(1 << 44) - 1:x}"  # all PPN bits
    asid_mask = "SATP32_ASID" if is_sv32 else "SATP64_ASID"  # all-ones ASID field
    suffix = "sv32" if is_sv32 else "sv39"  # bin-name suffix

    lines = [
        "  csrw hgatp, x0                                // G-stage Bare; isolate vsatp field bins",
        "  hfence.gvma                                   // flush old G-stage TLB after hgatp clear",
        "  RVTEST_TSBI_GOTO_SMODE                       // M->HS (T-SBI)",
    ]
    lines.extend(_section("Test Cases Start from here"))
    lines.extend(_case(f"Set vsatp.MODE={vs_mode}, PPN=0", "cp_vsatp_mode_field" if not is_sv32 else None))
    lines.extend(
        _csr_write_read(
            test_data,
            csr="vsatp",
            value=f"({mode_const} << {shift})",  # legal MODE, PPN=0
            bin_name=f"mode_{vs_mode}_{suffix}",
            coverpoint="cp_vsatp_mode_field" if not is_sv32 else "cp_vsatp_ppn_field",  # RV32 has no MODE walk cp
            note=f"write {vs_mode} with PPN=0",
        )
    )
    if not is_sv32:  # RV64: WARL MODE 0..15 plus unsupported MODE=1
        lines.extend(
            _mode_walk(
                test_data,
                csr="vsatp",
                shift=shift,
                legal_mode=mode_const,
                legal_name=vs_mode,
                bin_prefix="mode",
                coverpoint="cp_vsatp_mode_field",
            )
        )
        lines.extend(_case("Set vsatp.MODE=1 sample", "cp_vsatp_mode_field"))
        lines.extend(
            _csr_write_read(
                test_data,
                csr="vsatp",
                value=f"(1 << {shift})",
                bin_name="mode_1_sv39",
                coverpoint="cp_vsatp_mode_field",
                note="write unsupported MODE=1 sample",
            )
        )
    lines.extend(_case("vsatp.ASID = all ones", "cp_vsatp_asidlen_detect"))
    lines.extend(
        _csr_write_read(
            test_data,
            csr="vsatp",
            value=f"({mode_const} << {shift}) | {asid_mask}",  # legal MODE + all ASID bits
            bin_name=f"asid_ones_{suffix}",
            coverpoint="cp_vsatp_asidlen_detect",
            note="write all ASID bits",
        )
    )
    lines.extend(_case("vsatp.PPN = all ones", "cp_vsatp_ppn_field"))
    lines.extend(
        _csr_write_read(
            test_data,
            csr="vsatp",
            value=f"({mode_const} << {shift}) | {ppn_ones}",
            bin_name=f"ppn_ones_{suffix}",
            coverpoint="cp_vsatp_ppn_field",
            note="write PPN all-ones pattern",
        )
    )
    lines.extend(
        _ppn_walk(
            test_data,
            csr="vsatp",
            mode_expr=f"{mode_const} << {shift}",
            bit_start=0,  # vsatp PPN is not forced 4-aligned like hgatp x4
            bit_stop=ppn_bits,
            bin_prefix=suffix,
            coverpoint="cp_vsatp_ppn_field",
        )
    )
    lines.extend(emit_goto_mmode())  # return to M after HS CSR dumps
    return lines


def _satp_read_sig(test_data: TestData, reg: int, bin_name: str) -> list[str]:
    """GPR SIGUPD of ``reg`` against ``cp_satp_mode_field``."""
    return emit_sigupd_gpr(test_data, reg, bin_name, "cp_satp_mode_field", covergroup=CG)


def _satp_mode_body(test_data: TestData) -> list[str]:
    """RV64/Sv39 VS satp.MODE walk — stay mapped: restore safe MODE before each GOTO_MMODE."""
    lines = [
        "  .set va_code, 0x0000000080000000              // GVA where VS executes this test code",
        "",
        "  VS_PTE_SETUP(sv39, PA, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_W | PTE_V), va_code, LEVEL2)",
        "  csrr a0, mscratch                             // a0 = M save-area pointer",
        "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL2)",
        "",
        "  VSATP_SETUP(sv39, PA)                         // vsatp ON; hgatp stays Bare",
        "  csrw hgatp, x0",  # G-stage Bare so VS leaves are PAs
        "  hfence.vvma",  # flush VS-stage TLB
        "  hfence.gvma",  # flush G-stage TLB
    ]
    lines.extend(_section("Test Cases Start from here"))
    lines.extend(_case("Read satp/vsatp alias with MODE=Sv39", "cp_satp_mode_field"))
    lines.extend(
        [
            "  RVTEST_GOTO_LOWER_MODE VSmode                 // M->VS (VA!=PA relocate)",
            "  csrr a3, satp                                 // guest sees satp",
            "  csrr a4, vsatp                                // vsatp must match satp alias",
            *emit_goto_mmode(),  # dump from M (signature not guest-mapped)
            *_satp_read_sig(test_data, 13, "satp_alias_sv39"),  # SIGUPD a3 (x13)
            *_satp_read_sig(test_data, 14, "vsatp_alias_sv39"),  # SIGUPD a4 (x14)
        ]
    )
    # Asm loops like the seed: one SIGUPD label reused; restore Bare/Sv39 before each hop.
    lines.extend(_case("Walk satp.MODE 0..15 starting Bare", "cp_satp_mode_field"))
    lines.extend(
        [
            "  RVTEST_GOTO_LOWER_MODE VSmode",  # enter VS for the walk
            "  csrw satp, x0",  # start from Bare
            "  LI(t3, 0)",  # loop index = candidate MODE
            "bare_mode_walk:",  # top of 0..15 loop
            "  csrw satp, x0",  # previous value Bare
            "  sll  t0, t3, 60",  # t0 = MODE << 60
            "  csrw satp, t0",  # try this encoding
            "  csrr a5, satp",  # WARL readback
            "  csrw satp, x0                                 // restore Bare before M hop",
            *emit_goto_mmode(),  # dump a5 from M
            *_satp_read_sig(test_data, 15, "bare_mode_walk"),  # one Python SIGUPD; loop reuses it 16 times
            "  RVTEST_GOTO_LOWER_MODE VSmode",  # re-enter VS for the next encoding
            "  addi t3, t3, 1",  # next MODE
            "  LI(t4, 16)",  # loop limit
            "  blt  t3, t4, bare_mode_walk",  # continue while t3 < 16
            *emit_goto_mmode(),  # done with Bare walk
        ]
    )
    # Account for 15 extra SIGUPDs performed by the loop (first counted by emit_sigupd).
    if test_data.test_chunk is not None:  # 16 hardware dumps, 1 counted above
        test_data.test_chunk.sigupd_count += 15

    lines.extend(_case("Walk satp.MODE 0..15 starting Sv39", "cp_satp_mode_field"))
    lines.extend(
        [
            "  RVTEST_GOTO_LOWER_MODE VSmode",
            "  csrr t2, satp",  # keep PPN/ASID; only MODE field changes
            "  li   t0, ~((0xF) << 60)",  # mask to clear MODE
            "  and  t2, t2, t0",  # t2 = satp with MODE=0
            "  li   t0, (SATP_MODE_SV39 << 60)",  # legal MODE
            "  or   t1, t2, t0",  # t1 = Sv39 | original PPN
            "  csrw satp, t1",  # previous value = Sv39
            "  LI(t3, 0)",  # loop index
            "sv39_mode_walk:",
            "  sll  t0, t3, 60",  # candidate MODE
            "  or   t1, t2, t0",  # overlay onto PPN
            "  csrw satp, t1",
            "  csrr a5, satp",
            "  li   t0, (SATP_MODE_SV39 << 60)",
            "  or   t1, t2, t0",
            "  csrw satp, t1                                 // restore Sv39 before M hop",
            *emit_goto_mmode(),
            *_satp_read_sig(test_data, 15, "sv39_mode_walk"),
            "  RVTEST_GOTO_LOWER_MODE VSmode",
            "  li   t0, (SATP_MODE_SV39 << 60)",  # restore mapping so the next hop is legal
            "  or   t1, t2, t0",
            "  csrw satp, t1",
            "  addi t3, t3, 1",
            "  LI(t4, 16)",
            "  blt  t3, t4, sv39_mode_walk",
            *emit_goto_mmode(),
        ]
    )
    if test_data.test_chunk is not None:  # 15 extra loop dumps
        test_data.test_chunk.sigupd_count += 15

    lines.extend(_case("Final satp read after MODE walks", "cp_satp_mode_field"))
    lines.extend(
        [
            "  RVTEST_GOTO_LOWER_MODE VSmode",
            "  csrr a6, satp",  # final WARL value
            *emit_goto_mmode(),
            *_satp_read_sig(test_data, 16, "final_satp_sv39"),  # SIGUPD a6 (x16)
        ]
    )
    return lines


def generate_csr_hgatp_fields_HSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_csr_hgatp_fields_HSmode-00.S``.

    Builds Sv32 and Sv39 bodies. ``SIGUPD_COUNT`` is max(sv32, sv39) because
    only one ifdef is live after preprocess.
    """
    start = _sigupd_count(test_data)  # count before either twin
    sv32 = _hgatp_body(test_data, "sv32")  # increments counters for Sv32
    sv32_delta = _sigupd_count(test_data) - start  # SIGUPDs in the Sv32 body
    _set_sigupd_count(test_data, start)  # rewind so Sv39 does not add on top
    sv39 = _hgatp_body(test_data, "sv39")  # increments from ``start``
    sv39_delta = _sigupd_count(test_data) - start  # SIGUPDs in the Sv39 body
    _set_sigupd_count(test_data, start + max(sv32_delta, sv39_delta))  # keep the larger twin
    return [
        comment_banner("csr_hgatp_fields_HSmode", "SvH CSR field coverage"),
        *wrap_sv32_sv39(sv32, sv39),  # both bodies, one live per XLEN
    ]


def generate_csr_satp_mode_VSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_csr_satp_mode_VSmode-00.S`` (RV64/Sv39 only)."""
    return [
        comment_banner("csr_satp_mode_VSmode", "SvH CSR field coverage"),
        *_rv64_sv39(_satp_mode_body(test_data)),  # entire file inside SV39_SUPPORTED
    ]


def generate_csr_vsatp_fields_HSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_csr_vsatp_fields_HSmode-00.S``. Twin SIGUPD count same as hgatp."""
    start = _sigupd_count(test_data)  # count before either twin
    sv32 = _vsatp_body(test_data, "sv32")
    sv32_delta = _sigupd_count(test_data) - start
    _set_sigupd_count(test_data, start)  # rewind for Sv39
    sv39 = _vsatp_body(test_data, "sv39")
    sv39_delta = _sigupd_count(test_data) - start
    _set_sigupd_count(test_data, start + max(sv32_delta, sv39_delta))  # max of the two twins
    return [
        comment_banner("csr_vsatp_fields_HSmode", "SvH CSR field coverage"),
        *wrap_sv32_sv39(sv32, sv39),
    ]


# SvH.py iterates this list.
ALL_GENERATORS = [
    generate_csr_hgatp_fields_HSmode,  # tests/priv/SvH/SvH_csr_hgatp_fields_HSmode-00.S
    generate_csr_satp_mode_VSmode,  # RV64 satp.MODE walk
    generate_csr_vsatp_fields_HSmode,  # vsatp MODE/ASID/PPN
]
