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

@add_priv_test_generator("SmH", required_extensions=["H", "Sm"])
def make_h(test_data: TestData) -> list[TestChunk]:
    """Generate tests for the H hypervisor-extension testsuite.
    """
    
    test_chunks: list[TestChunk] = []
 
    # ---- H_mcsr_cg: M-mode (boot default, no switch needed) ----
    tc = test_data.begin_test_chunk("hcsr_m")
    tc.code.extend(_generate_hcsr_tests(test_data))
    tc.code.extend(_generate_mtvala_test(test_data))
    test_chunks.append(test_data.end_test_chunk())

    return test_chunks
