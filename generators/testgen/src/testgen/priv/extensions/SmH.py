##################################
# SmH.py
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


# ---------------------------------------------------------------------------
# H_mcsr_cg: Tests executed in M-mode
# ---------------------------------------------------------------------------


def _generate_hcsr_tests(test_data: TestData) -> list[str]:
    """Generate tests for H-extension CSRs in M-mode.

    PRECONDITION: caller must be in M-mode. This is the boot-default mode
    for a fresh test chunk, so no switch is emitted here.
    """
    covergroup = "H_mcsr_cg"
    # Include both Machine-only and HS/VS-scope H CSRs in the M-mode access test.
    csrs = M_ONLY_H_CSRS + HS_VS_H_CSRS

    ######################################
    coverpoint = "cp_hcsr_access"
    ######################################
    lines = [
        comment_banner(
            coverpoint,
            "Read, write all 1s, write all 0s, set all 1s, set all 0s, restore all Machine/HS/VS H-extension CSRs",
        ),
    ]
    for csr in csrs:
        lines.extend(csr_access_test(test_data, csr, covergroup, coverpoint))

    lines.append("\n// Read-Only CSRs")
    for csr in HS_VS_H_CSRS_RO:
        lines.extend(csr_access_test(test_data, csr, covergroup, coverpoint))
    
    lines.extend(["", "#ifndef S1P11P0_SUPPORTED"])
    lines.extend(csr_access_test(test_data, CSR_HENCVCFG, covergroup, coverpoint))
    lines.extend(["", "#endif"])

    lines.extend(["", "// RV32-only h CSRs", "#if __riscv_xlen == 32"])
    for csr in HS_VS_H_CSRS_32H:
        lines.extend(csr_access_test(test_data, csr, covergroup, coverpoint))
    lines.append("#endif")

    ######################################
    coverpoint = "cp_hcsrwalk"
    ######################################
    lines.append(
        comment_banner(
            coverpoint,
            "Set and clear each bit individually in all writable Machine/HS/VS H-extension CSRs",
        ),
    )
    for csr in csrs:
        lines.extend(csr_walk_test(test_data, csr, covergroup, coverpoint))
        
    lines.extend(["", "#ifndef S1P11P0_SUPPORTED"])
    lines.extend(csr_walk_test(test_data, CSR_HENCVCFG, covergroup, coverpoint))
    lines.extend(["", "#endif"])

    lines.extend(["// RV32-only h CSRs", "#if __riscv_xlen == 32"])
    for csr in HS_VS_H_CSRS_32H:
        lines.extend(csr_walk_test(test_data, csr, covergroup, coverpoint))
    lines.append("#endif")

    return lines


def _generate_mtvala_test(test_data: TestData) -> list[str]:
    """cp_mtvala validates mtval readback semantics. It writes a known bit
    pattern, reads it back, and signals the result to the signature.

    PRECONDITION: caller must be in M-mode (mtval is M-only).
    """
    covergroup = "H_mcsr_cg"

    ######################################
    coverpoint = "cp_mtvala"
    ######################################
    save_reg, check_reg = test_data.int_regs.get_registers(2)
    lines = [
        comment_banner(coverpoint, "mtval must not be read-only zero"),
        f"csrr x{save_reg}, mtval   # save mtval",
        f"LI(x{check_reg}, -1)      # all 1s",
        test_data.add_testcase("nonzero", coverpoint, covergroup),
        f"csrw mtval, x{check_reg}  # write all 1s to mtval",
        f"csrr x{check_reg}, mtval  # read back",
        f"snez x{check_reg}, x{check_reg}   # 1 if nonzero",
        write_sigupd(check_reg, test_data),
        f"csrw mtval, x{save_reg}   # restore mtval",
    ]
    test_data.int_regs.return_registers([save_reg, check_reg])
    return lines

def _add_independent_pair(
    reg_a: int,
    reg_b: int,
    val_a_reg: int,
    val_b_reg: int,
    s_csr: str,
    vs_csr: str,
    mask: int | None,
    coverpoint: str,
    covergroup: str,
    test_data: TestData,
) -> str:
    """ writing an S-mode CSR must NOT disturb its VS-mode counterpart, and vice versa. Checks independence."""
    return str.join(
        "\n",
        [
            "",
            f"# Testcase: {s_csr}/{vs_csr} replica independence (M-mode, V=0)",
            "LI(t0, 0xA5A5A5A5A5A5A5A5)",
            "LI(t1, 0x5A5A5A5A5A5A5A5A)",
            f"csrw {s_csr}, t0   # write distinct value to {s_csr}",
            f"csrw {vs_csr}, t1   # write different distinct value to {vs_csr}",
            test_data.add_testcase(f"{s_csr}_unaffected", coverpoint, covergroup),
            gen_csr_read_sigupd(reg_a, (s_csr, mask), test_data, val_a_reg if mask is not None else None),
            test_data.add_testcase(f"{vs_csr}_unaffected", coverpoint, covergroup),
            gen_csr_read_sigupd(reg_b, (vs_csr, mask), test_data, val_b_reg if mask is not None else None),
        ],
    )
 
 
def _generate_replica_m_tests(test_data: TestData) -> list[str]:
    """cp_replica (M-mode leg, V=0)"""
    ######################################
    covergroup = "H_mcsr_cg"
    coverpoint = "cp_replica"
    ######################################
    reg_a, reg_b = test_data.int_regs.get_registers(2, exclude_regs=[5, 6, 7])
    lines = [comment_banner(coverpoint, "Writing to S-mode CSRs doesn't affect the VS-mode replica, and vice versa (V=0)")]
 
    for s_csr, vs_csr, mask in S_CSRS_WITH_REPLICA:
        mask_regs = test_data.int_regs.get_registers(2, exclude_regs=[5, 6, 7]) if mask is not None else [None, None]
        lines.append(_add_independent_pair(reg_a, reg_b, mask_regs[0], mask_regs[1], s_csr, vs_csr, mask, coverpoint, covergroup, test_data))
        if mask is not None:
            test_data.int_regs.return_registers(mask_regs)
 
    test_data.int_regs.return_registers([reg_a, reg_b])
    return lines

@add_priv_test_generator("SmH", required_extensions=["H", "Sm"], )
def make_h(test_data: TestData) -> list[TestChunk]:
    """Generate tests for the H hypervisor-extension testsuite.
    """
    
    test_chunks: list[TestChunk] = []
 
    # ---- H_mcsr_cg: M-mode (boot default, no switch needed) ----
    tc = test_data.begin_test_chunk("hcsr_m")
    tc.code.extend(_generate_hcsr_tests(test_data))
    tc.code.extend(_generate_mtvala_test(test_data))
    tc.code.extend(_generate_replica_m_tests(test_data))
    test_chunks.append(test_data.end_test_chunk())

    return test_chunks
