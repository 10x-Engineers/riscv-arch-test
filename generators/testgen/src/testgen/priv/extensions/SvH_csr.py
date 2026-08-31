##################################
# priv/extensions/SvH_csr.py
#
# SvH CSR family - true Python emitters, no runtime seed I/O.
# SPDX-License-Identifier: Apache-2.0
##################################

"""hgatp, vsatp, and satp field coverage. Three ``generate_*`` functions, three files.

``_write_csr_then_sigupd`` writes a CSR then SIGUPD. ``_walk_mode_field`` writes MODE 0..15
from Bare and from a legal mode. ``_walk_ppn_bits`` writes walking-1 PPN bits.

hgatp/vsatp files contain Sv32 and Sv39 under ifdefs. The satp MODE walk is
RV64/Sv39 only and runs from VS (so the ``cp_satp_mode_field`` cross samples
``priv_mode_vs``), restoring a legal vsatp before every M->VS re-entry and
forwarding the GOOD PPN from the Sv39 walk so winning WARL encodings cannot
leave a broken mapping alive across a mode transition.
"""

from __future__ import annotations  # allow forward references in type hints

from testgen.asm.csr import gen_csr_read_sigupd  # CSR read + SIGUPD into GPR
from testgen.asm.helpers import comment_banner, write_sigupd  # .S banner + GPR SIGUPD
from testgen.data.state import TestData  # ACT4 testcase registry
from testgen.priv.extensions.SvHCommon import (
    CG,  # "SvH_cg" covergroup name
    Paging,  # "sv32" | "sv39"
    build_twins,  # emit sv32 + sv39 ifdef twins
    GOTO_MMODE,  # RVTEST_GOTO_MMODE after HS CSR walks
    mode_names,  # vsatp/hgatp MODE name pair
)

CHECK_CSR = 14  # a4 (x14); directed CSR SIGUPD dumps use this GPR


def _section(title: str) -> list[str]:
    """Emit an assembly section banner."""
    return ["", "// " + "-" * 128, f"// {title}", "// " + "-" * 128]  # blank + three // lines


def _case(title: str, coverpoint: str | None = None) -> list[str]:
    """Emit a per-case assembly banner, including coverpoint ids when given."""
    lines = ["", "//" + "-" * 128, f"// {title} | Expected: Successful"]  # case header start
    if coverpoint:  # optional cp_* line for reviewers
        lines.append(f"// Coverpoints: {coverpoint}")  # list cp_* ids for this case
    lines.append("//" + "-" * 128)  # case header end rule
    return lines  # ready to extend into asm body


def _wrap_sv39_only(lines: list[str]) -> list[str]:
    """Wrap ``lines`` in ``#ifdef SV39_SUPPORTED`` (RV64-only satp walk)."""
    return ["#ifdef SV39_SUPPORTED", *lines, "#endif  // SV39_SUPPORTED"]  # ifndef out on RV32


def _write_csr_then_sigupd(
    test_data: TestData,
    *,  # force keyword args below
    csr: str,  # CSR name, e.g. hgatp / vsatp
    value: str | None,  # LI immediate; None means write x0 (Bare)
    bin_name: str,  # coverpoint bin label
    coverpoint: str,  # cp_* name
    note: str,  # short // note on the csrw line
    setup: list[str] | None = None,  # optional custom LI/csrw sequence (WARL previous-value)
) -> list[str]:
    """Write ``csr`` (or run ``setup``), then emit a CSR SIGUPD into a4.

    ``value=None`` writes x0 (Bare). ``setup`` replaces the default LI/csrw.
    """
    lines: list[str] = []  # accumulate asm + testcase metadata
    if setup:  # WARL walk: custom previous-value + candidate write
        lines.extend(setup)  # use custom Bare/legal then try sequence
    elif value is None:  # simple Bare write
        lines.append(f"  csrw {csr}, x0                                // {note}")  # write x0 → Bare MODE
    else:  # simple LI + csrw
        lines.extend([f"  LI(t0, {value})", f"  csrw {csr}, t0                                // {note}"])  # load + write CSR
    lines.extend(
        [
            test_data.add_testcase(bin_name, coverpoint, CG),  # register bin under coverpoint
            gen_csr_read_sigupd(CHECK_CSR, (csr, None), test_data),  # read CSR back into a4 + SIGUPD
        ]
    )
    return lines  # csrw stimulus + testcase + CSR SIGUPD


def _walk_mode_field(
    test_data: TestData,
    *,
    csr: str,  # hgatp or vsatp
    shift: int,  # MODE field bit position (31 or 60)
    legal_mode: str,  # assembler symbol for legal MODE
    legal_name: str,  # human name for bins / notes (sv39 / sv39x4)
    bin_prefix: str,  # bin stem prefix (e.g. "mode")
    coverpoint: str,  # cp_*_mode_field
) -> list[str]:
    """WARL MODE walk: encodings 0..15 from Bare, then from ``legal_mode``."""
    lines = _case(f"{csr}.MODE walk 0..15 starting Bare", coverpoint)  # first walk banner
    for mode in range(16):  # try every 4-bit MODE encoding from Bare previous value
        lines.extend(
            _write_csr_then_sigupd(
                test_data,
                csr=csr,  # hgatp or vsatp
                value=f"({mode} << {shift})",  # candidate MODE encoding
                bin_name=f"{bin_prefix}_bare_{mode:02x}",  # bin: mode_bare_00 .. mode_bare_0f
                coverpoint=coverpoint,  # cp_*_mode_field
                note=f"try MODE={mode} from Bare",  # asm // note on final csrw
                setup=[  # force Bare, then write candidate MODE
                    f"  csrw {csr}, x0                                // force previous MODE=Bare",  # previous=Bare
                    f"  LI(t0, ({mode} << {shift}))",  # load candidate encoding
                    f"  csrw {csr}, t0                                // try MODE={mode}",  # WARL write
                ],
            )
        )

    lines.extend(_case(f"{csr}.MODE walk 0..15 starting {legal_name}", coverpoint))  # second walk banner
    for mode in range(16):  # try every encoding from legal MODE previous value
        lines.extend(
            _write_csr_then_sigupd(
                test_data,
                csr=csr,  # hgatp or vsatp
                value=f"({mode} << {shift})",  # candidate MODE encoding
                bin_name=f"{bin_prefix}_{legal_name.lower()}_{mode:02x}",  # bin: mode_sv39x4_00 etc.
                coverpoint=coverpoint,  # cp_*_mode_field
                note=f"try MODE={mode} from {legal_name}",  # asm // note
                setup=[
                    f"  LI(t0, ({legal_mode} << {shift}))",  # load legal MODE
                    f"  csrw {csr}, t0                                // force previous MODE={legal_name}",  # previous=legal
                    f"  LI(t0, ({mode} << {shift}))",  # load candidate encoding
                    f"  csrw {csr}, t0                                // try MODE={mode}",  # WARL write
                ],
            )
        )
    return lines  # full MODE walk (32 SIGUPD sites per csr)


def _walk_ppn_bits(
    test_data: TestData,
    *,
    csr: str,  # hgatp or vsatp
    mode_expr: str,  # legal MODE expression OR'd into each walking-1 write
    bit_start: int,  # inclusive first PPN bit
    bit_stop: int,  # exclusive last PPN bit
    bin_prefix: str,  # bin stem prefix (twin suffix)
    coverpoint: str,  # cp_*_ppn_field
) -> list[str]:
    """Walking-1 writes on ``csr``.PPN bits ``[bit_start, bit_stop)``, one SIGUPD each."""
    lines = _case(f"Walking ones on {csr}.PPN bits [{bit_stop - 1}:{bit_start}]", coverpoint)  # PPN walk banner
    for bit in range(bit_start, bit_stop):  # one SIGUPD per writable PPN bit
        lines.extend(  # MODE | (1 << bit), then SIGUPD
            _write_csr_then_sigupd(
                test_data,
                csr=csr,  # hgatp or vsatp
                value=f"({mode_expr}) | 0x{1 << bit:x}",  # legal MODE + single PPN bit set
                bin_name=f"{bin_prefix}_ppn_bit_{bit:02d}",  # bin: sv32_ppn_bit_02 etc.
                coverpoint=coverpoint,  # ppn coverpoint
                note=f"write walking-1 PPN bit {bit}",  # asm // note
            )
        )
    return lines  # walking-1 PPN stimulus block


def _asm_hgatp(test_data: TestData, paging: Paging) -> list[str]:
    """HS-mode hgatp MODE, VMID, and PPN field stimulus for one paging twin."""
    _, hgatp_mode = mode_names(paging)  # "sv32x4" or "sv39x4"
    is_sv32 = paging == "sv32"  # True → skip RV64-only MODE 0..15 walk
    shift = 31 if is_sv32 else 60  # MODE field shift for this XLEN
    mode_const = f"HGATP_MODE_{hgatp_mode.upper()}"  # assembler symbol for legal MODE
    ppn_bits = 22 if is_sv32 else 44  # exclusive upper bound for walking-1
    ppn_start = 2  # Sv32x4/Sv39x4 PPN alignment: bits [1:0] not independently writable
    ppn_ones = "0x3fffff" if is_sv32 else f"0x{(((1 << 44) - 1) & ~0x3):x}"  # all writable PPN bits
    vmid_mask = "HGATP32_VMID" if is_sv32 else "HGATP64_VMID"  # all-ones VMID mask
    suffix = "sv32" if is_sv32 else "sv39"  # bin-name suffix so twins do not collide

    # Isolate hgatp: VS Bare, then enter HS (identity; T-SBI).
    lines = [  # prelude before case banners
        "  csrw vsatp, x0                                // VS Bare; isolate hgatp field bins",
        "  hfence.vvma                                   // flush VS-stage TLB after vsatp clear",  # TLB sync
        "  RVTEST_TSBI_GOTO_SMODE                       // M->HS (T-SBI)",
    ]
    lines.extend(_section("Test Cases Start from here"))  # case list begins
    if is_sv32:  # RV32: explicit Bare sample (no 0..15 walk)
        lines.extend(_case("Set hgatp.MODE=Bare", "cp_hgatp_mode_field"))  # Bare case banner
        lines.extend(  # Bare write + SIGUPD
            _write_csr_then_sigupd(
                test_data,
                csr="hgatp",  # target CSR
                value=None,  # csrw hgatp, x0
                bin_name="mode_bare_sv32",  # Bare bin for Sv32 twin
                coverpoint="cp_hgatp_mode_field",  # MODE coverpoint
                note="write Bare MODE",  # asm // note
            )
        )
    lines.extend(_case(f"Set hgatp.MODE={hgatp_mode}, PPN=0", "cp_hgatp_mode_field"))  # legal MODE banner
    lines.extend(
        _write_csr_then_sigupd(
            test_data,
            csr="hgatp",  # target CSR
            value=f"({mode_const} << {shift})",  # legal MODE, PPN=0
            bin_name=f"mode_{hgatp_mode}_{suffix}",  # legal-mode bin
            coverpoint="cp_hgatp_mode_field",  # MODE coverpoint
            note=f"write {hgatp_mode} with PPN=0",  # asm // note
        )
    )
    if not is_sv32:  # RV64: full MODE 0..15 WARL walk
        lines.extend(
            _walk_mode_field(
                test_data,
                csr="hgatp",  # hgatp MODE field
                shift=shift,  # bit 60
                legal_mode=mode_const,  # HGATP_MODE_SV39X4
                legal_name=hgatp_mode,  # "sv39x4"
                bin_prefix="mode",  # bin stem prefix
                coverpoint="cp_hgatp_mode_field",  # MODE coverpoint
            )
        )
        lines.extend(_case("Set hgatp.MODE=1 sample", "cp_hgatp_mode_field"))  # reserved MODE sample banner
        lines.extend(  # MODE=1 sample
            _write_csr_then_sigupd(
                test_data,
                csr="hgatp",  # target CSR
                value=f"(1 << {shift})",  # unsupported MODE=1
                bin_name="mode_1_sv39",  # single reserved-encoding bin
                coverpoint="cp_hgatp_mode_field",  # MODE coverpoint
                note="write unsupported MODE=1 sample",  # asm // note
            )
        )
    lines.extend(_case("hgatp.VMID = all ones", "cp_hgatp_vmidlen_detect cp_hgatp_vmid_scoping"))  # VMID banner
    for readback in ("vmidlen", "scoping"):  # two VMID readback coverpoints
        lines.extend(
            _write_csr_then_sigupd(
                test_data,
                csr="hgatp",  # target CSR
                value=f"({mode_const} << {shift}) | {vmid_mask}",  # legal MODE + all VMID bits
                bin_name=f"{readback}_{suffix}",  # vmidlen_sv39 / scoping_sv39
                coverpoint="cp_hgatp_vmidlen_detect" if readback == "vmidlen" else "cp_hgatp_vmid_scoping",  # cp pick
                note=f"write all VMID bits for {readback} readback",  # asm // note
            )
        )
    lines.extend(_case("hgatp.PPN = all ones", "cp_hgatp_ppn_field"))  # PPN all-ones banner
    lines.extend(  # PPN all-ones sample
        _write_csr_then_sigupd(
            test_data,
            csr="hgatp",  # target CSR
            value=f"({mode_const} << {shift}) | {ppn_ones}",  # legal MODE + all PPN bits
            bin_name=f"ppn_ones_{suffix}",  # ppn_ones_sv32 / ppn_ones_sv39
            coverpoint="cp_hgatp_ppn_field",  # PPN coverpoint
            note="write PPN all-ones pattern",  # asm // note
        )
    )
    lines.extend(
        _walk_ppn_bits(
            test_data,
            csr="hgatp",  # hgatp PPN field
            mode_expr=f"{mode_const} << {shift}",  # keep MODE legal while walking PPN
            bit_start=ppn_start,  # skip bits [1:0]
            bit_stop=ppn_bits,  # 22 or 44
            bin_prefix=suffix,  # twin suffix
            coverpoint="cp_hgatp_ppn_field",  # PPN coverpoint
        )
    )
    lines.extend(GOTO_MMODE)  # SIGUPD of hgatp already ran in HS; return to M
    return lines  # full hgatp twin body


def _asm_vsatp(test_data: TestData, paging: Paging) -> list[str]:
    """HS-mode vsatp MODE, ASID, and PPN field stimulus for one paging twin."""
    vs_mode, _ = mode_names(paging)  # "sv32" or "sv39"
    is_sv32 = paging == "sv32"  # True → skip RV64-only MODE walk
    shift = 31 if is_sv32 else 60  # MODE field shift
    mode_const = f"SATP_MODE_{vs_mode.upper()}"  # SATP_MODE_SV32 or SATP_MODE_SV39
    ppn_bits = 22 if is_sv32 else 44  # exclusive upper bound for walking-1
    ppn_ones = "0x3fffff" if is_sv32 else f"0x{(1 << 44) - 1:x}"  # all PPN bits
    asid_mask = "SATP32_ASID" if is_sv32 else "SATP64_ASID"  # all-ones ASID mask
    suffix = "sv32" if is_sv32 else "sv39"  # bin-name suffix

    lines = [  # prelude: Bare G-stage, enter HS
        "  csrw hgatp, x0                                // G-stage Bare; isolate vsatp field bins",
        "  hfence.gvma                                   // flush old G-stage TLB after hgatp clear",  # TLB sync
        "  RVTEST_TSBI_GOTO_SMODE                       // M->HS (T-SBI)",
    ]
    lines.extend(_section("Test Cases Start from here"))  # case list begins
    lines.extend(_case(f"Set vsatp.MODE={vs_mode}, PPN=0", "cp_vsatp_mode_field" if not is_sv32 else None))  # MODE banner
    lines.extend(
        _write_csr_then_sigupd(
            test_data,
            csr="vsatp",  # target CSR
            value=f"({mode_const} << {shift})",  # legal MODE, PPN=0
            bin_name=f"mode_{vs_mode}_{suffix}",  # legal-mode bin
            coverpoint="cp_vsatp_mode_field" if not is_sv32 else "cp_vsatp_ppn_field",  # RV32 has no MODE walk cp
            note=f"write {vs_mode} with PPN=0",  # asm // note
        )
    )
    if not is_sv32:  # RV64: full MODE 0..15 WARL walk
        lines.extend(
            _walk_mode_field(
                test_data,
                csr="vsatp",  # vsatp MODE field
                shift=shift,  # bit 60
                legal_mode=mode_const,  # SATP_MODE_SV39
                legal_name=vs_mode,  # "sv39"
                bin_prefix="mode",  # bin stem prefix
                coverpoint="cp_vsatp_mode_field",  # MODE coverpoint
            )
        )
        lines.extend(_case("Set vsatp.MODE=1 sample", "cp_vsatp_mode_field"))  # reserved MODE sample banner
        lines.extend(  # MODE=1 sample
            _write_csr_then_sigupd(
                test_data,
                csr="vsatp",  # target CSR
                value=f"(1 << {shift})",  # unsupported MODE=1
                bin_name="mode_1_sv39",  # single reserved-encoding bin
                coverpoint="cp_vsatp_mode_field",  # MODE coverpoint
                note="write unsupported MODE=1 sample",  # asm // note
            )
        )
    lines.extend(_case("vsatp.ASID = all ones", "cp_vsatp_asidlen_detect"))  # ASID banner
    lines.extend(
        _write_csr_then_sigupd(
            test_data,
            csr="vsatp",  # target CSR
            value=f"({mode_const} << {shift}) | {asid_mask}",  # legal MODE + all ASID bits
            bin_name=f"asid_ones_{suffix}",  # ASID bin
            coverpoint="cp_vsatp_asidlen_detect",  # ASID coverpoint
            note="write all ASID bits",  # asm // note
        )
    )
    lines.extend(_case("vsatp.PPN = all ones", "cp_vsatp_ppn_field"))  # PPN ones banner
    lines.extend(  # PPN all-ones sample
        _write_csr_then_sigupd(
            test_data,
            csr="vsatp",  # target CSR
            value=f"({mode_const} << {shift}) | {ppn_ones}",  # MODE | all PPN bits
            bin_name=f"ppn_ones_{suffix}",  # ppn_ones bin
            coverpoint="cp_vsatp_ppn_field",  # PPN coverpoint
            note="write PPN all-ones pattern",  # asm // note
        )
    )
    lines.extend(
        _walk_ppn_bits(
            test_data,
            csr="vsatp",  # vsatp PPN field
            mode_expr=f"{mode_const} << {shift}",  # keep MODE legal
            bit_start=0,  # vsatp PPN is not forced 4-aligned like hgatp x4
            bit_stop=ppn_bits,  # 22 or 44
            bin_prefix=suffix,  # twin suffix
            coverpoint="cp_vsatp_ppn_field",  # PPN coverpoint
        )
    )
    lines.extend(GOTO_MMODE)  # return to M after HS CSR walks
    return lines  # full vsatp twin body


def _sigupd_satp_read(test_data: TestData, reg: int, bin_name: str) -> list[str]:
    """ACT4 testcase + GPR SIGUPD for satp/vsatp MODE walk readbacks."""
    return [
        test_data.add_testcase(bin_name, "cp_satp_mode_field", CG),  # register bin under cp_satp_mode_field
        write_sigupd(reg, test_data),  # dump GPR (a3/a4/a5/a6/a7) into signature
    ]


def _asm_satp_mode(test_data: TestData) -> list[str]:
    """RV64/Sv39 VS satp.MODE walk — stay mapped: restore safe MODE before each GOTO_MMODE."""
    lines = [  # map guest code, turn on vsatp, Bare hgatp
        "  .set va_code, 0x0000000080000000              // GVA where VS executes this test code",
        "",  # blank for readability
        "  VS_PTE_SETUP(sv39, PA, rvtest_code_begin, (PTE_D | PTE_A | PTE_X | PTE_R | PTE_W | PTE_V), va_code, LEVEL2)",  # map test code
        "  csrr a0, mscratch                             // a0 = M save-area pointer",
        "  V_SAVE_AREA_SETUP(va_code, rvtest_code_begin, code, LEVEL2)",  # trap save area at mapped VA
        "",  # blank
        "  VSATP_SETUP(sv39, PA)                         // vsatp ON; hgatp stays Bare",
        "  csrw hgatp, x0",  # G-stage Bare — isolate VS satp alias walk
        "  hfence.vvma",  # flush VS TLB after setup
        "  hfence.gvma",  # flush G TLB (hgatp Bare)
    ]
    lines.extend(_section("Test Cases Start from here"))  # case list begins
    lines.extend(_case("Read satp/vsatp alias with MODE=Sv39", "cp_satp_mode_field"))  # alias banner
    lines.extend(
        [
            "  RVTEST_GOTO_LOWER_MODE VSmode                 // M->VS (VA!=PA relocate)",
            "  csrr a3, satp                                 // guest sees satp",  # read satp alias
            "  csrr a4, vsatp                                // vsatp must match satp alias",  # read vsatp
            *GOTO_MMODE,  # return to M for SIGUPD
            *_sigupd_satp_read(test_data, 13, "satp_alias_sv39"),  # SIGUPD a3 (x13) — satp alias readback
            *_sigupd_satp_read(test_data, 14, "vsatp_alias_sv39"),  # SIGUPD a4 (x14) — vsatp alias readback
        ]
    )
    # Walk satp.MODE while executing in VS: the aliased vsatp is the CSR that
    # the cross samples (priv_mode_vs + csrrw + satp + rs1[63:60]), so the walk
    # must run in VS, not M. vsatp must hold a legal mapping at every M->VS
    # re-entry, otherwise the trap handler livelocks (fetch-page-fault) by
    # restarting xEPC=ra from the canary on a broken translation. Each walk
    # restores its valid previous value before leaving VS, and the Sv39 walk
    # forwards the GOOD PPN (re-armed from M) into every candidate, so the
    # restore after a winning WARL write stays a legal Sv39 mapping. Reserved
    # encodings are WARL-ignored on write and simply read back the prior value.
    lines.extend(_case("Walk satp.MODE 0..15 starting Bare", "cp_satp_mode_field"))  # Bare walk banner
    for mode in range(16):  # WARL walk from Bare previous value
        lines.extend(  # Bare -> try MODE, WARL readback, restore Bare
            [
                "  RVTEST_GOTO_LOWER_MODE VSmode                 // enter VS — cross samples priv_mode_vs",
                "  csrw satp, x0",  # force previous MODE=Bare (also clears PPN)
                f"  LI(t0, ({mode} << 60))",  # candidate MODE encoding
                "  csrw satp, t0",  # try this encoding — WARL may ignore reserved values
                "  csrr a5, satp",  # read back WARL result into a5
                "  csrw satp, x0",  # restore Bare before leaving VS — avoid broken mapping livelock
                *GOTO_MMODE,  # return to M
                *_sigupd_satp_read(test_data, 15, f"bare_mode_walk_{mode:02x}"),  # SIGUPD a5 (x15) — WARL readback bin
            ]
        )

    # Re-arm a legal Sv39 vsatp before the Sv39 walk: the Bare walk leaves
    # vsatp=Bare, whose PPN is 0; the Sv39 walk must forward the GOOD PPN so
    # its previous-value and restore stay legal mappings across M->VS entries.
    lines.append("  VSATP_SETUP(sv39, PA)                         // re-arm vsatp = Sv39 | goodPPN (M)")

    lines.extend(_case("Walk satp.MODE 0..15 starting Sv39", "cp_satp_mode_field"))  # Sv39 walk banner
    for mode in range(16):  # WARL walk from Sv39 | goodPPN previous value
        lines.extend(
            [
                "  RVTEST_GOTO_LOWER_MODE VSmode                 // enter VS — must stay fetchable",
                "  csrr t2, satp",  # vsatp is Sv39 | goodPPN at entry — save full CSR
                "  srli t0, t2, 60",  # extract MODE field for a clean PPN
                "  slli t0, t0, 60",  # MODE bits only (to subtract from t2)
                "  xor t2, t2, t0",  # keep only the GOOD PPN in t2
                "  LI(t0, (SATP_MODE_SV39 << 60))",  # Sv39 MODE constant
                "  or t1, t2, t0",  # rebuild Sv39 | goodPPN
                "  csrw satp, t1",  # force previous MODE=Sv39 with good PPN — WARL setup
                f"  LI(t0, ({mode} << 60))",  # candidate MODE encoding
                "  or t1, t2, t0",  # MODE | good PPN (PPN preserved — avoids livelock)
                "  csrw satp, t1",  # try encoding — winning WARL keeps good PPN
                "  csrr a5, satp",  # read back WARL result
                "  LI(t0, (SATP_MODE_SV39 << 60))",  # rebuild Sv39 for restore
                "  or t1, t2, t0",  # Sv39 | goodPPN restore value
                "  csrw satp, t1",  # restore legal mapping before GOTO_MMODE
                *GOTO_MMODE,  # return to M
                *_sigupd_satp_read(test_data, 15, f"sv39_mode_walk_{mode:02x}"),  # SIGUPD a5 — WARL readback bin
            ]
        )

    lines.extend(_case("Final satp read after MODE walks", "cp_satp_mode_field"))  # final banner
    lines.extend(  # one last satp read from VS
        [
            "  RVTEST_GOTO_LOWER_MODE VSmode",  # enter VS for final read
            "  csrr a6, satp",  # final satp value after all walks
            *GOTO_MMODE,  # return to M
            *_sigupd_satp_read(test_data, 16, "final_satp_sv39"),  # SIGUPD a6 (x16) — final readback bin
        ]
    )
    return lines  # full satp MODE walk body (RV64/Sv39 only)


def generate_csr_hgatp_fields_HSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_csr_hgatp_fields_HSmode-00.S``."""
    return [
        comment_banner("csr_hgatp_fields_HSmode", "SvH CSR field coverage"),  # // file banner
        *build_twins(test_data, _asm_hgatp),  # sv32 + sv39 ifdef twins
    ]


def generate_csr_satp_mode_VSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_csr_satp_mode_VSmode-00.S`` (RV64/Sv39 only)."""
    return [
        comment_banner("csr_satp_mode_VSmode", "SvH CSR field coverage"),  # // file banner
        *_wrap_sv39_only(_asm_satp_mode(test_data)),  # wrap in #ifdef SV39_SUPPORTED
    ]


def generate_csr_vsatp_fields_HSmode(test_data: TestData) -> list[str]:
    """Output ``SvH_csr_vsatp_fields_HSmode-00.S``."""
    return [
        comment_banner("csr_vsatp_fields_HSmode", "SvH CSR field coverage"),  # // file banner
        *build_twins(test_data, _asm_vsatp),  # sv32 + sv39 ifdef twins
    ]
