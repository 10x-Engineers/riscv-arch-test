##################################
# priv/extensions/SvH.py
#
# SvH (Hypervisor + two-stage VM) privileged test generator.
# SPDX-License-Identifier: Apache-2.0
##################################

"""SvH privileged test generator (same pattern as ExceptionsSm / ZawrsS).

make testgen EXTENSIONS=SvH calls make_svh().
Shared helpers live in SvHCommon.
Each generate_* below becomes one tests/priv/SvH/SvH_<name>-00.S file.
"""

# testgen core: assembly banners, mutable generator state, and per-.S output chunks
from testgen.asm.helpers import comment_banner
from testgen.data.state import TestData
from testgen.data.test_chunk import TestChunk

# SvH_csr: hgatp / vsatp / satp CSR field walks and WARL behavior
from testgen.priv.extensions.SvH_csr import (
    generate_csr_hgatp_fields_HSmode,
    generate_csr_satp_mode_VSmode,
    generate_csr_vsatp_fields_HSmode,
)

# SvH_fault: invalid PTE and guest-page fault matrices under two-stage paging
from testgen.priv.extensions.SvH_fault import (
    generate_hgatp_fault_VSmode,
    generate_twostage_invalid_VSmode,
    generate_vsatp_fault_VSmode,
)

# SvH_misc: HFENCE, MPRV, TVM, PTE attributes, endianness, GPA width
from testgen.priv.extensions.SvH_misc import (
    generate_g_adbit_VSmode,
    generate_g_pte_attr_VSmode,
    generate_g_struct_HSmode,
    generate_gpa_width_VSmode,
    generate_hfence_gvma_mode_HSmode,
    generate_hfence_gvma_ops_HSmode,
    generate_hfence_vvma_HSmode,
    generate_mprv_hgatp_Mmode,
    generate_mprv_sum_two_stage_Mmode,
    generate_mprv_vsatp_Mmode,
    generate_tvm_hgatp_HSmode,
    generate_vs_pte_attr_VSmode,
    generate_vsbe_endian_VSmode,
)

# SvH_perm: page permissions, MXR, SUM, U-bit, and execute-only leaf behavior
from testgen.priv.extensions.SvH_perm import (
    generate_g_perm_VSmode,
    generate_g_perm_VUmode,
    generate_g_u_bit_HSmode,
    generate_sum_Upages_VSmode,
    generate_vs_perm_VSmode,
    generate_vs_perm_VUmode,
    generate_vsstatus_mxr_sum_VSmode,
    generate_vsstatus_mxr_sum_VUmode,
    generate_vu_rwx_two_stage_VUmode,
    generate_xonly_mxr0_gstage_HSmode,
    generate_xonly_mxr0_HSmode,
    generate_xonly_mxr0_VSmode,
    generate_xonly_mxr0_VUmode,
)

# SvH_twostage: paging on/off, ifetch, MXR, and basic two-stage read/write
from testgen.priv.extensions.SvH_twostage import (
    generate_g_walk_vs_pt_VSmode,
    generate_hgatp_bare_trans_VSmode,
    generate_stage_both_bare_VSmode,
    generate_two_stage_ifetch_VSmode,
    generate_two_stage_mxr_VSmode,
    generate_two_stage_mxr_VUmode,
    generate_two_stage_rw_VSmode,
)

# priv registry hook: registers make_svh under EXTENSIONS=SvH
from testgen.priv.registry import add_priv_test_generator


def _emit(test_data: TestData, file_stem: str, generate_fn) -> TestChunk:
    """Open one output chunk, run a scenario generator, return the finished chunk."""
    chunk = test_data.begin_test_chunk(file_stem)  # open SvH_<file_stem>-00.S chunk
    chunk.section_header = comment_banner(file_stem, "SvH coverpoint stimulus")  # banner at top of .S
    chunk.sigupd_count = 0  # SIGUPD slots start at zero for this file
    chunk.num_testcases = 0  # testcase counter starts at zero for this file
    chunk.code.extend(generate_fn(test_data))  # append scenario assembly from generator fn
    if chunk.num_testcases < 1:
        chunk.num_testcases = 1  # header must declare at least one testcase slot
    return test_data.end_test_chunk()  # finalize chunk and return it to caller


@add_priv_test_generator(
    "SvH",
    required_extensions=["I", "H"],
    march_extensions=["I", "H"],
    extra_defines=[
        "#define RVTEST_HYPERVISOR",
        "#define TRAP_SIGUPD_COUNT 4096",
    ],
)
def make_svh(test_data: TestData) -> list[TestChunk]:
    """Emit all 39 SvH scenarios — one TestChunk (.S file) each."""
    test_chunks: list[TestChunk] = [
        # SvH_twostage.py — paging on/off, ifetch, MXR
        _emit(test_data, "g_walk_vs_pt_VSmode", generate_g_walk_vs_pt_VSmode),  # G-stage walk via VS page tables
        _emit(test_data, "hgatp_bare_trans_VSmode", generate_hgatp_bare_trans_VSmode),  # hgatp Bare with VS paging on
        _emit(test_data, "stage_both_bare_VSmode", generate_stage_both_bare_VSmode),  # both stages Bare (identity map)
        _emit(test_data, "two_stage_ifetch_VSmode", generate_two_stage_ifetch_VSmode),  # instruction fetch through two stages
        _emit(test_data, "two_stage_mxr_VSmode", generate_two_stage_mxr_VSmode),  # MXR on two-stage loads in VS
        _emit(test_data, "two_stage_mxr_VUmode", generate_two_stage_mxr_VUmode),  # MXR on two-stage loads in VU
        _emit(test_data, "two_stage_rw_VSmode", generate_two_stage_rw_VSmode),  # basic two-stage load/store in VS
        # SvH_csr.py — hgatp / vsatp / satp field walks
        _emit(test_data, "csr_hgatp_fields_HSmode", generate_csr_hgatp_fields_HSmode),  # hgatp MODE/PPN/VMID WARL in HS
        _emit(test_data, "csr_satp_mode_VSmode", generate_csr_satp_mode_VSmode),  # satp.MODE unsupported/ignored in VS
        _emit(test_data, "csr_vsatp_fields_HSmode", generate_csr_vsatp_fields_HSmode),  # vsatp fields read/written from HS
        # SvH_perm.py — permissions, MXR, SUM
        _emit(test_data, "g_perm_VSmode", generate_g_perm_VSmode),  # G-stage leaf permissions from VS
        _emit(test_data, "g_perm_VUmode", generate_g_perm_VUmode),  # G-stage leaf permissions from VU
        _emit(test_data, "g_u_bit_HSmode", generate_g_u_bit_HSmode),  # G-stage U-bit effect from HS (HLV/HSV)
        _emit(test_data, "sum_Upages_VSmode", generate_sum_Upages_VSmode),  # SUM allows VS to access U=1 pages
        _emit(test_data, "vs_perm_VSmode", generate_vs_perm_VSmode),  # VS-stage leaf R/W/X matrix in VS
        _emit(test_data, "vs_perm_VUmode", generate_vs_perm_VUmode),  # VS-stage leaf R/W/X matrix in VU
        _emit(test_data, "vsstatus_mxr_sum_VSmode", generate_vsstatus_mxr_sum_VSmode),  # vsstatus MXR+SUM in VS
        _emit(test_data, "vsstatus_mxr_sum_VUmode", generate_vsstatus_mxr_sum_VUmode),  # vsstatus MXR+SUM in VU
        _emit(test_data, "vu_rwx_two_stage_VUmode", generate_vu_rwx_two_stage_VUmode),  # VU rwx leaf under two-stage
        _emit(test_data, "xonly_mxr0_HSmode", generate_xonly_mxr0_HSmode),  # execute-only leaf, MXR=0, from HS
        _emit(test_data, "xonly_mxr0_VSmode", generate_xonly_mxr0_VSmode),  # execute-only leaf, MXR=0, from VS
        _emit(test_data, "xonly_mxr0_VUmode", generate_xonly_mxr0_VUmode),  # execute-only leaf, MXR=0, from VU
        _emit(test_data, "xonly_mxr0_gstage_HSmode", generate_xonly_mxr0_gstage_HSmode),  # x-only G-stage leaf, MXR=0, HS
        # SvH_fault.py — invalid PTE / fault matrix
        _emit(test_data, "hgatp_fault_VSmode", generate_hgatp_fault_VSmode),  # G-stage invalid PTE guest-page faults
        _emit(test_data, "twostage_invalid_VSmode", generate_twostage_invalid_VSmode),  # invalid VS+G PTE fault combinations
        _emit(test_data, "vsatp_fault_VSmode", generate_vsatp_fault_VSmode),  # VS-stage invalid PTE page faults
        # SvH_misc.py — HFENCE, MPRV, TVM, PTE attrs, VSBE
        _emit(test_data, "g_adbit_VSmode", generate_g_adbit_VSmode),  # G-stage A/D bit behavior on access
        _emit(test_data, "g_pte_attr_VSmode", generate_g_pte_attr_VSmode),  # G-stage PTE attribute bits (non-perm)
        _emit(test_data, "g_struct_HSmode", generate_g_struct_HSmode),  # G-stage page-table structure from HS
        _emit(test_data, "gpa_width_VSmode", generate_gpa_width_VSmode),  # GPA width / high-bit behavior
        _emit(test_data, "hfence_gvma_mode_HSmode", generate_hfence_gvma_mode_HSmode),  # HFENCE.GVMA legal modes in HS
        _emit(test_data, "hfence_gvma_ops_HSmode", generate_hfence_gvma_ops_HSmode),  # HFENCE.GVMA operand variants
        _emit(test_data, "hfence_vvma_HSmode", generate_hfence_vvma_HSmode),  # HFENCE.VVMA from HS with TVM checks
        _emit(test_data, "mprv_hgatp_Mmode", generate_mprv_hgatp_Mmode),  # MPRV load/store with hgatp from M
        _emit(test_data, "mprv_sum_two_stage_Mmode", generate_mprv_sum_two_stage_Mmode),  # MPRV+SUM under two-stage from M
        _emit(test_data, "mprv_vsatp_Mmode", generate_mprv_vsatp_Mmode),  # MPRV load/store with vsatp from M
        _emit(test_data, "tvm_hgatp_HSmode", generate_tvm_hgatp_HSmode),  # TVM blocks hgatp writes from VS
        _emit(test_data, "vs_pte_attr_VSmode", generate_vs_pte_attr_VSmode),  # VS-stage PTE attribute bits (non-perm)
        _emit(test_data, "vsbe_endian_VSmode", generate_vsbe_endian_VSmode),  # hstatus.VSBE guest endian behavior
    ]

    if not test_chunks:
        raise RuntimeError("SvH generator produced zero chunks")  # registry wiring must always emit files
    return test_chunks
