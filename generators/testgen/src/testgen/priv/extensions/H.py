##################################
# H.py
#
# H hypervisor extension test generator.
# SPDX-License-Identifier: Apache-2.0
##################################

"""H hypervisor privileged extension test generator."""

from testgen.asm.csr import csr_access_test, csr_walk_test, gen_csr_read_sigupd, gen_csr_write_sigupd
from testgen.asm.helpers import comment_banner, write_sigupd
from testgen.constants import INDENT
from testgen.data.state import TestData
from testgen.data.test_chunk import TestChunk
from testgen.priv.registry import add_priv_test_generator

from testgen.priv.extensions.Common_H import (
    M_ONLY_H_CSRS,
    HS_VS_H_CSRS,
    HS_VS_H_CSRS_RO,
    HS_VS_H_CSRS_32H,
    S_CSRS_WITH_REPLICA,
    S_CSRS_NO_REPLICA,
    CSR_HENCVCFG,
)

def _generate_vscause_tests(test_data: TestData, covergroup: str) -> list[str]:
    """cp_vscause_write validates that vscause and scause behave the same for
    legal values, and that the WLRL behavior matches the S-mode CSR contract.

    PRECONDITION: caller must be in a mode where both `scause` and `vscause`
    resolve to their real (non-redirected) registers -- i.e. M-mode or
    HS-mode. Do NOT call this while V=1 (VS/VU), since `scause` there is
    trap-and-emulate redirected to vscause and the comparison becomes
    meaningless.
    """
    
    ######################################
    coverpoint = "cp_vscause_write"
    interrupt_coverpoint = "cp_vscause_write_interrupt"
    ######################################
    save_s, save_vs, check_reg, temp_reg = test_data.int_regs.get_registers(4)
    lines = [
        comment_banner(coverpoint, "vscause WLRL fields writable: scause and vscause must accept identical legal values"),
        f"csrr x{save_s}, scause     # save scause",
        f"csrr x{save_vs}, vscause   # save vscause",
    ]

    gated_exceptions = [(14, "RESERVED"), (17, "RESERVED"), (18, "#if defined(ZICFILP_SUPPORTED) || defined(ZICFISS_SUPPORTED)")]
    for i in range(24):
        gated = next((g for g in gated_exceptions if g[0] == i), None)
        if gated is not None and gated[1] == "RESERVED":
            lines.append(f"\n# Exception cause {i} is reserved")
            continue
        if gated is not None:
            lines.append(gated[1])
        lines.extend(
            [
                "",
                f"# Testcase: set scause/vscause to exception cause {i}",
                f"LI(x{check_reg}, {i})",
                f"csrw scause, x{check_reg}",
                f"csrw vscause, x{check_reg}",
                test_data.add_testcase(f"b_{i}", coverpoint, covergroup),
                f"csrr x{temp_reg}, scause",
                f"csrr x{check_reg}, vscause",
                f"xor x{check_reg}, x{check_reg}, x{temp_reg}   # 0 if scause and vscause match",
                f"seqz x{check_reg}, x{check_reg}",
                write_sigupd(check_reg, test_data),
            ]
        )
        if gated is not None:
            lines.append("#endif")

    lines.extend(
        [
            comment_banner(f"{coverpoint}_interrupt", "with interrupt = 1: same check for each interrupt cause"),
            f"SET_MSB(x{temp_reg})  # x{temp_reg} msb=1 for interrupt tests",
        ]
    )
    for i in range(14):
        if i in {0, 4, 8}:
            continue
        lines.extend(
            [
                "",
                f"# Testcase: set scause/vscause to interrupt cause {i}",
                f"LI(x{check_reg}, {i})",
                f"or x{check_reg}, x{check_reg}, x{temp_reg}",
                f"csrw scause, x{check_reg}",
                f"csrw vscause, x{check_reg}",
                test_data.add_testcase(f"b_{i}", interrupt_coverpoint, covergroup),
                f"csrr x{temp_reg}, scause",
                f"csrr x{check_reg}, vscause",
                f"xor x{check_reg}, x{check_reg}, x{temp_reg}",
                f"seqz x{check_reg}, x{check_reg}",
                write_sigupd(check_reg, test_data),
                f"SET_MSB(x{temp_reg})  # restore msb marker for next iteration",
            ]
        )

    lines.extend([f"\ncsrw scause, x{save_s}     # restore scause", f"csrw vscause, x{save_vs}   # restore vscause"])
    test_data.int_regs.return_registers([save_s, save_vs, check_reg, temp_reg])
    return lines


# ---------------------------------------------------------------------------
# H_hscsr_cg: Tests executed in HS-mode
# ---------------------------------------------------------------------------


def _generate_hs_hcsr_tests(test_data: TestData) -> list[str]:
    """PRECONDITION: caller must already be in HS-mode."""
    covergroup = "H_hscsr_cg"

    ######################################
    coverpoint = "cp_hcsr_access"
    ######################################
    lines = [comment_banner(coverpoint, "read/write/set/clear sweep executed from HS-mode")]
    for csr in HS_VS_H_CSRS:
        lines.extend(csr_access_test(test_data, csr, covergroup, coverpoint))
    for csr in HS_VS_H_CSRS_RO:
        lines.extend(csr_access_test(test_data, csr, covergroup, coverpoint))

    lines.extend(["", "#ifndef S1P11P0_SUPPORTED"])
    lines.extend(csr_access_test(test_data, CSR_HENCVCFG, covergroup, coverpoint))
    lines.extend(["", "#endif"])

    lines.extend(["", "#if __riscv_xlen == 32"])
    for csr in HS_VS_H_CSRS_32H:
        lines.extend(csr_access_test(test_data, csr, covergroup, coverpoint))
    lines.append("#endif")

    ######################################
    coverpoint = "cp_hcsrwalk"
    ######################################
    lines.append(comment_banner(coverpoint, "Set/clear each bit of each HS/VS H-extension CSR, executed from HS-mode"))
    for csr in HS_VS_H_CSRS:
        lines.extend(csr_walk_test(test_data, csr, covergroup, coverpoint))
    
    lines.extend(["", "#ifndef S1P11P0_SUPPORTED"])
    lines.extend(csr_walk_test(test_data, CSR_HENCVCFG, covergroup, coverpoint))
    lines.extend(["", "#endif"])
    
    lines.extend(["// RV32-only h CSRs", "#if __riscv_xlen == 32"])
    for csr in HS_VS_H_CSRS_32H:
        lines.extend(csr_walk_test(test_data, csr, covergroup, coverpoint))
    lines.append("#endif")

    return lines


def _generate_hs_inaccessible_test(test_data: TestData) -> list[str]:
    """cp_hcsr_inaccessible (HS-mode), CSR set is mtval2/mtinst, the only H CSRs that are Machine-only.

    PRECONDITION: caller must already be in HS-mode.
    """
    covergroup = "H_hscsr_cg"

    ######################################
    coverpoint = "cp_hcsr_inaccessible"
    ######################################
    
    lines = [comment_banner(coverpoint, "M-mode H-extension registers (mtval2, mtinst) are inaccessible from HS-mode")]
    for name, _mask in M_ONLY_H_CSRS:
        lines.extend(
            [
                "",
                test_data.add_testcase(name, coverpoint, covergroup),
                f"csrr t0, {name}    # attempt access; trap handler records illegal instruction fault",
            ]
        )
    return lines


def _generate_hstatus_vgein_test(test_data: TestData) -> list[str]:
    """cp_hstatus_vgein --  GEILEN isn't known at generation time, so this
    discovers the legal max at runtime (write all-1s to VGEIN, read back) rather than testing the
    literal {GEILEN-1, GEILEN, GEILEN+1} values from the testplan.

    PRECONDITION: caller must already be in HS-mode.
    """
    covergroup = "H_hscsr_cg"

    ######################################
    coverpoint = "cp_hstatus_vgein"
    ######################################
    save_reg, mask_reg, max_reg, check_reg, tmp = test_data.int_regs.get_registers(5)
    lines = [
        comment_banner(
            coverpoint,
            "VGEIN (hstatus[17:12]) can only hold legal values 0..GEILEN. GEILEN is runtime-discovered here "
            "(write all-1s, read back) since it isn't known at test-generation time.",
        ),
        f"csrr x{save_reg}, hstatus       # save hstatus",
        f"LI(x{mask_reg}, 0x3F000)        # VGEIN field mask, bits [17:12]",
        f"csrs hstatus, x{mask_reg}       # set all 1s in VGEIN",
        f"csrr x{max_reg}, hstatus",
        f"and x{max_reg}, x{max_reg}, x{mask_reg}   # x{max_reg} = discovered legal max (still in position)",
    ]
    for label, value_expr in (
        ("vgein_0", "0"),
        ("vgein_1", f"1 << 12"),
        ("vgein_max", f"x{max_reg}"),
        ("vgein_63", "0x3F000"),
    ):
        lines.extend(
            [
                "",
                f"# Testcase: write VGEIN = {label}",
                f"csrc hstatus, x{mask_reg}       # clear VGEIN field first",
            ]
        )
        if value_expr.startswith("x"):
            lines.append(f"csrs hstatus, {value_expr}")
        else:
            lines.append(f"LI(x{check_reg}, {value_expr})")
            lines.append(f"csrs hstatus, x{check_reg}")
        lines.extend(
            [
                test_data.add_testcase(label, coverpoint, covergroup),
                f"csrr x{check_reg}, hstatus",
                f"and x{check_reg}, x{check_reg}, x{mask_reg}   # isolate VGEIN readback",
                f"sltu x{tmp}, x{max_reg}, x{check_reg}          # 1 if readback > discovered max (illegal)",
                f"xori x{tmp}, x{tmp}, 1                          # 1 = legal (readback <= max), matches ref model",
                write_sigupd(tmp, test_data),
            ]
        )

    lines.append(f"\ncsrw hstatus, x{save_reg}    # restore hstatus")
    test_data.int_regs.return_registers([save_reg, mask_reg, max_reg, check_reg, tmp])
    return lines


# ---------------------------------------------------------------------------
# H_vscsr_cg: Tests executed in VS-mode
# ---------------------------------------------------------------------------


def _generate_vs_inaccessible_tests(test_data: TestData) -> list[str]:
    """In VS mode, Machine-only H CSRs must not be accessible and should give illegal instruction fault.

    PRECONDITION: caller must already be in VS-mode.
    """
    covergroup = "H_vscsr_cg"

    ######################################
    coverpoint = "cp_hcsr_inaccessible"
    ######################################
    
    save_reg, temp_reg = test_data.int_regs.get_registers(2)
    lines = [
        comment_banner(
            coverpoint,
            "All H-extension CSRs are inaccessible from VS-mode",
        ),
        "",
        "# Setup",
        "# Setup: switch to M-mode to disable illegal-instruction delegation",
        "RVTEST_TSBI_GOTO_MMODE",
        f"csrr x{save_reg}, medeleg        # save current medeleg",
        f"LI(x{temp_reg}, 1 << 2)",
        f"csrc medeleg, x{temp_reg}         # disable delegation of illegal instruction exceptions",
        "RVTEST_TSBI_GOTO_VSMODE            # enter VS-mode with illegal instructions trapped to M-mode",
    ]
    for name, _mask in M_ONLY_H_CSRS:
        lines.extend(
            [
                "",
                test_data.add_testcase(name, coverpoint, covergroup),
                f"csrr t0, {name}    # attempt access; trap handler records illegal instruction fault",
            ]
        )
    lines.extend(
        [
            "",
            "# Return to M-mode and restore original delegation",
            "RVTEST_TSBI_GOTO_MMODE",
            f"csrw medeleg, x{save_reg}",
        ]
    )
    test_data.int_regs.return_registers([save_reg, temp_reg])
    return lines

def _generate_vs_virtualfault_tests(test_data: TestData) -> list[str]:
    """HS/VS-scope CSRs from VS-mode must raise a
    virtual-instruction fault rather than illegal instruction.

    PRECONDITION: caller must already be in VS-mode.
    """
    covergroup = "H_vscsr_cg"

    ######################################
    coverpoint = "cp_hcsr_virtualinstructionfault"
    ######################################
    lines = [comment_banner(coverpoint, "HS and VS H-extension CSRs raise a virtual-instruction fault (not illegal instruction) from VS-mode")]
    for name, _mask in HS_VS_H_CSRS + HS_VS_H_CSRS_RO:
        lines.extend(
            [
                "",
                test_data.add_testcase(name, coverpoint, covergroup),
                f"csrr t0, {name}    # attempt access; trap handler records virtual-instruction fault",
            ]
        )
    return lines


def _generate_virtual_instruction_high_cause_test(test_data: TestData) -> list[str]:
    """Simple fault loop over the high-half counter CSRs.

    PRECONDITION: caller must already be in VS-mode.
    """
    covergroup = "H_vscsr_cg"
    
    ######################################
    coverpoint = "cp_virtual_instruction_high_cause"
    ######################################
    lines = ["#if __riscv_xlen == 32", comment_banner(coverpoint, "RV32, V=1: high-half CSR access raises virtual-instruction (not illegal instruction) when the low half is HS-qualified")]
    names = ["cycleh", "timeh", "instreth"] + [f"hpmcounter{i}h" for i in range(3, 32)]
    for name in names:
        lines.extend(
            [
                "",
                test_data.add_testcase(name, coverpoint, covergroup),
                f"csrr t0, {name}    # attempt access; trap handler records virtual-instruction fault",
            ]
        )
    lines.append("#endif")
    return lines


def _generate_illegalupper_test(test_data: TestData, covergroup: str) -> list[str]:
    """fault loop over the RV32-only h-suffixed CSRs.

    PRECONDITION: no mode dependency -- the h-suffixed CSRs don't exist on
    RV64 regardless of privilege mode, so this can run in whatever mode the
    caller is already in for that covergroup.
    """

    ######################################
    coverpoint = "cp_illegalupper"
    ######################################
    lines = ["", comment_banner(coverpoint, "RV64: the h half of H-extension CSRs does not exist and must fault"), "#if __riscv_xlen == 64"]
    for name in range(0x602, 0x60A, 0x605):
        lines.extend(
            [
                "", 
                test_data.add_testcase(name, coverpoint, covergroup),
                f"csrr t0, {name}    # shouldn't exist -- illegal instruction expected",
            ]
        )
        
    lines.append("#endif")
    return lines


def _generate_vsstatus_sd_test(test_data: TestData) -> list[str]:
    """sstatus.FS changes (from M-mode, real S CSR) don't leak into vsstatus.SD. cp_vsstatus_sd_write exercises the
    interaction between vsstatus and sstatus across the VS/M privilege boundary.

    PRECONDITION: caller must already be in VS-mode.
    NOTE: currently unused (disabled in make_h) -- see the caller for why:
    while V=1, the `sstatus` CSR name is trap-and-emulate redirected to
    vsstatus, so writing "sstatus" from inside VS-mode does NOT reach the
    real S-mode sstatus this test is trying to compare against. That
    redirect issue needs to be resolved before this is re-enabled; it is
    independent of the mode-switch refactor.
    """
    covergroup = "H_vscsr_cg"
   
    ######################################
    coverpoint = "cp_vsstatus_sd_write"
    ######################################

    save_reg_vs, save_reg_s, check_reg, reg1, reg2, reg3 = test_data.int_regs.get_registers(6)
    lines = [
        comment_banner(
            coverpoint,
            "Write all combinations of vsstatus.SD={0/1}, "
            "FS={00,01,10,11}, VS={00,01,10,11}, "
            "and sstatus.FS={00,01,10,11}. "
            "Verify that vsstatus.SD depends only on "
            "vsstatus.FS/VS and is unaffected by sstatus.FS.",
        ),
        f"SET_MSB(x{reg1})",
        f"csrr x{save_reg_vs}, vsstatus",
        f"csrr x{save_reg_s}, sstatus",
        f"not x{reg2}, x{reg1}",
        f"and x{reg3}, x{save_reg_vs}, x{reg2}",
        f"LI(x{reg2}, 0x6600)          # FS/VS bits",
        f"not x{reg2}, x{reg2}",
        f"and x{reg3}, x{reg3}, x{reg2}",
    ]

    for sfs in range(4):
        for sd in (0, 1):
            for fs in range(4):
                for vs in range(4):

                    base = (
                        f"sfs_{sfs:02b}_"
                        f"sd_{sd}_"
                        f"fs_{fs:02b}_"
                        f"vs_{vs:02b}"
                    )

                    vs_fields = (fs << 13) | (vs << 9)

                # Build vsstatus value and write it 
                    lines.extend(
                        [
                            "",
                            f"# sstatus.fs={sfs:02b} "
                            f"vsstatus.fs={fs:02b} "
                            f"vsstatus.vs={vs:02b}",
                            f"LI(x{check_reg}, 0x{vs_fields:08x})",
                        ]
                    )

                    if sd:
                        lines.append(
                            f"or x{check_reg}, x{check_reg}, x{reg1}"
                        )

                    lines.append(
                            f"or x{check_reg}, x{check_reg}, x{reg3}"
                    )
                    lines.extend(
                        [
                            test_data.add_testcase(f"{base}_vs_wval", coverpoint, covergroup),
                            gen_csr_write_sigupd( check_reg, "vsstatus", test_data),
                        ]
                    )

                # Build sstatus value and write it (to verify that vsstatus.SD is unaffected by sstatus.FS) 
                    lines.extend(
                        [
                            "",
                            f"LI(x{reg2}, 0x00006000)",
                            f"not x{reg2}, x{reg2}",
                            f"and x{check_reg}, x{save_reg_s}, x{reg2}",
                            f"LI(x{reg2}, 0x{sfs << 13:08x})",
                            f"or x{check_reg}, x{check_reg}, x{reg2}",
                        ]
                    )
                    lines.extend(
                        [
                            test_data.add_testcase(f"{base}_s_wval", coverpoint, covergroup),
                            gen_csr_write_sigupd(check_reg, "sstatus", test_data),
                        ]
                    )

                # Test 3 : verify vsstatus unchanged 
                    lines.extend(
                        [
                            test_data.add_testcase(f"{base}_vs_rval", coverpoint, covergroup),
                            gen_csr_read_sigupd(check_reg, ("vsstatus", None), test_data),
                        ]
                    )

    lines.extend(
        [
            "",
            f"csrw sstatus, x{save_reg_s}",
            f"csrw vsstatus, x{save_reg_vs}",
        ]
    )

    test_data.int_regs.return_registers([ save_reg_vs, save_reg_s, check_reg, reg1, reg2, reg3])
    return lines

# ---------------------------------------------------------------------------
# H_ucsr_cg: Tests executed in U-mode / H_vucsr_cg: Tests executed in VU-mode
# ---------------------------------------------------------------------------
def _generate_u_inaccessible_tests(test_data: TestData) -> list[str]:
    """All H CSRs (Machine/HS/VS) inaccessible from U-mode.

    PRECONDITION: caller must already be in U-mode.
    """
    covergroup = "H_ucsr_cg"

    ######################################
    coverpoint = "cp_hcsr_inaccessible"
    ######################################
    save_reg, temp_reg = test_data.int_regs.get_registers(2)

    lines = [
        comment_banner(
            coverpoint,
            "All H-extension CSRs are inaccessible from U-mode",
        ),
        "",
        "# Setup: switch to M-mode to disable illegal-instruction delegation",
        "RVTEST_TSBI_GOTO_MMODE",
        f"csrr x{save_reg}, medeleg        # save current medeleg",
        f"LI(x{temp_reg}, 1 << 2)",
        f"csrc medeleg, x{temp_reg}         # disable delegation of illegal instruction exceptions",
        "",
        "# Return to U-mode with illegal instructions directed to M-mode",
        "RVTEST_TSBI_GOTO_UMODE",
    ]

    for name, _mask in M_ONLY_H_CSRS + HS_VS_H_CSRS + HS_VS_H_CSRS_RO:
        lines.extend(
            [
                "",
                test_data.add_testcase(name, coverpoint, covergroup),
                f"csrr t0, {name}    # attempt access; trap handler records illegal instruction fault",
            ]
        )

    lines.extend(
        [
            "",
            "# Return to M-mode and restore original delegation",
            "RVTEST_TSBI_GOTO_MMODE",
            f"csrw medeleg, x{save_reg}",
        ]
    )

    test_data.int_regs.return_registers([save_reg, temp_reg])
    return lines


def _generate_vu_inaccessible_tests(test_data: TestData) -> list[str]:
    """VU-mode should not be able to access any H-extension CSRs either.

    PRECONDITION: caller must already be in VU-mode.
    """
    covergroup = "H_vucsr_cg" 

    ######################################
    coverpoint = "cp_hcsr_inaccessible"
    ######################################
    save_reg, temp_reg = test_data.int_regs.get_registers(2)
    lines = [
        comment_banner(
            coverpoint,
            "All H-extension CSRs are inaccessible from VU-mode",
        ),
        "",
        "# Setup",
        "# Setup: switch to M-mode to disable illegal-instruction delegation",
        "RVTEST_TSBI_GOTO_MMODE",
        f"csrr x{save_reg}, medeleg        # save current medeleg",
        f"LI(x{temp_reg}, 1 << 2)",
        f"csrc medeleg, x{temp_reg}         # disable delegation of illegal instruction exceptions",
        "RVTEST_TSBI_GOTO_VUMODE            # enter VU-mode with illegal instructions trapped to M-mode",
    ]
    for name, _mask in M_ONLY_H_CSRS + HS_VS_H_CSRS + HS_VS_H_CSRS_RO:
        lines.extend(
            [
                "",
                test_data.add_testcase(name, coverpoint, covergroup),
                f"csrr t0, {name}    # attempt access; trap handler records illegal instruction fault",
            ]
        )
    lines.extend(
        [
            "",
            "RVTEST_TSBI_GOTO_MMODE",              # return to M-mode",
            f"csrw medeleg, x{save_reg}         # restore original medeleg",
        ]
    )

    test_data.int_regs.return_registers([save_reg, temp_reg])
    return lines


def _generate_vu_scsr_test(test_data: TestData) -> list[str]:
    """virtual instruction faults expected for HS/VS/S CSRs.

    PRECONDITION: caller must already be in VU-mode.
    """
    covergroup = "H_vucsr_cg" 

    ######################################
    coverpoint = "cp_scsr"
    ######################################
    lines = [comment_banner(coverpoint, "HS/VS/S CSRs raise a virtual-instruction fault (not illegal instruction) from VU-mode")]
    for name, _mask in [(s, None) for s, _vs, _m in S_CSRS_WITH_REPLICA] + HS_VS_H_CSRS:
        lines.extend(
            [
                "",
                test_data.add_testcase(name, coverpoint, covergroup),
                f"csrr t0, {name}    # attempt access; trap handler records whatever fault occurs",
            ]
        )
    return lines

@add_priv_test_generator("H", required_extensions=["H"], extra_defines=["#define RVTEST_HYPERVISOR"],)
def make_h(test_data: TestData) -> list[TestChunk]:
    """Generate tests for the H hypervisor-extension testsuite.
    """
    
    test_chunks: list[TestChunk] = []

    # ---- H_hscsr_cg: HS-mode ----
    tc = test_data.begin_test_chunk("hcsr_hs")
    tc.code.append("RVTEST_TSBI_GOTO_SMODE      # -> HS-mode (V=0)")
    tc.code.extend(_generate_hs_hcsr_tests(test_data))
    tc.code.extend(_generate_hs_inaccessible_test(test_data))
    tc.code.extend(_generate_hstatus_vgein_test(test_data))
    # scause/vscause must be compared while V=0, so this runs here in
    # HS-mode, not in H_mcsr_cg -- see _generate_vscause_tests' precondition.
    tc.code.extend(_generate_vscause_tests(test_data, "H_hscsr_cg"))
    test_chunks.append(test_data.end_test_chunk())
 
    # ---- H_vscsr_cg: VS-mode ----
    tc = test_data.begin_test_chunk("hcsr_vs")
    tc.code.append("RVTEST_TSBI_GOTO_VSMODE     # -> VS-mode (V=1)")
    tc.code.extend(_generate_vs_inaccessible_tests(test_data))
    tc.code.extend(_generate_vs_virtualfault_tests(test_data))
    tc.code.extend(_generate_virtual_instruction_high_cause_test(test_data))
    tc.code.extend(_generate_illegalupper_test(test_data,"H_vscsr_cg"))
    #tc.code.extend(_generate_vsstatus_sd_test(test_data))  # disabled: sstatus/vsstatus redirect issue, see docstring
    test_chunks.append(test_data.end_test_chunk())
 
    # ---- H_ucsr_cg (U-mode) + H_vucsr_cg (VU-mode) ----
    tc = test_data.begin_test_chunk("hcsr_u_vu")
    tc.code.append("RVTEST_TSBI_GOTO_UMODE      # -> U-mode")
    tc.code.extend(_generate_u_inaccessible_tests(test_data))
    tc.code.extend(_generate_illegalupper_test(test_data,"H_ucsr_cg"))
    # T-SBI dispatches off the live a0 regardless of current mode, so this
    # can go straight from U-mode to VU-mode -- no M-mode bounce needed.
    tc.code.append("RVTEST_TSBI_GOTO_VUMODE     # -> VU-mode (V=1, U-mode)")
    tc.code.extend(_generate_vu_inaccessible_tests(test_data))
    tc.code.extend(_generate_illegalupper_test(test_data,"H_vucsr_cg"))
    
    tc.code.extend(_generate_vu_scsr_test(test_data))
    test_chunks.append(test_data.end_test_chunk())
 
    return test_chunks