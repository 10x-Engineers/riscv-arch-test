##################################
# priv/extensions/SvH.py
#
# SvH (Hypervisor + two-stage VM) privileged test generator.
# SPDX-License-Identifier: Apache-2.0
##################################

"""SvH privileged test generator.

make testgen EXTENSIONS=SvH calls make_svh().
Shared helpers live in SvHCommon.
Each generate_* below becomes one tests/priv/SvH/SvH_<name>-00.S file.
"""

from testgen.asm.helpers import comment_banner  # builds // banner text at top of each .S
from testgen.data.state import TestData  # mutable generator state (open chunk, counters)
from testgen.data.test_chunk import TestChunk  # one output .S file worth of assembly
from testgen.priv.extensions.SvHCommon import delete_old_asm_files  # unlink old tests/priv/SvH/*.S
from testgen.priv.extensions.SvH_csr import (  # CSR field walk generators
    generate_csr_hgatp_fields_HSmode,  # → SvH_csr_hgatp_fields_HSmode-00.S
    generate_csr_satp_mode_VSmode,  # → SvH_csr_satp_mode_VSmode-00.S (RV64 only)
    generate_csr_vsatp_fields_HSmode,  # → SvH_csr_vsatp_fields_HSmode-00.S
)
from testgen.priv.extensions.SvH_perm import (  # permission / MXR / SUM generators
    generate_g_perm_VSmode,  # G-stage permission matrix from VS
    generate_g_perm_VUmode,  # G-stage permission matrix from VU
    generate_g_u_bit_HSmode,  # G U=0 vs U=1; HS HLV/HSV
    generate_sum_Upages_VSmode,  # SUM 0/1 on U=1 pages
    generate_vs_perm_VSmode,  # VS permission × SUM
    generate_vs_perm_VUmode,  # VS permission from VU
    generate_vsstatus_mxr_sum_VSmode,  # vsstatus MXR×SUM (VS)
    generate_vsstatus_mxr_sum_VUmode,  # vsstatus MXR×SUM (VU)
    generate_vu_rwx_two_stage_VUmode,  # VU R/W/X two-stage
    generate_xonly_mxr0_HSmode,  # X-only VS leaf from HS
    generate_xonly_mxr0_VSmode,  # X-only VS leaf from VS
    generate_xonly_mxr0_VUmode,  # X-only VS leaf from VU
    generate_xonly_mxr0_gstage_HSmode,  # X-only G leaf; HS HLV
)
from testgen.priv.extensions.SvH_twostage import (  # paging on/off / ifetch / MXR
    generate_g_walk_vs_pt_VSmode,  # G walk of VS page-table GPAs
    generate_hgatp_bare_trans_VSmode,  # VS on, hgatp Bare
    generate_stage_both_bare_VSmode,  # vsatp and hgatp Bare
    generate_two_stage_ifetch_VSmode,  # VS ifetch both stages
    generate_two_stage_mxr_VSmode,  # MXR on X-only pages (VS)
    generate_two_stage_mxr_VUmode,  # MXR on X-only pages (VU)
    generate_two_stage_rw_VSmode,  # VS sw/lw both stages
)
from testgen.priv.registry import add_priv_test_generator  # registers make_svh with testgen

# Each tuple is (file stem without SvH_ prefix, Python function that emits asm).
# Order here is the order .S files appear on disk after make testgen.
_SCENARIOS: list[tuple[str, object]] = [
    # --- SvH_twostage.py: paging on/off ---
    ("g_walk_vs_pt_VSmode", generate_g_walk_vs_pt_VSmode),  # G allows/denies VS PT walk
    ("hgatp_bare_trans_VSmode", generate_hgatp_bare_trans_VSmode),  # VS paging, G Bare
    ("stage_both_bare_VSmode", generate_stage_both_bare_VSmode),  # both Bare identity
    ("two_stage_ifetch_VSmode", generate_two_stage_ifetch_VSmode),  # ifetch both stages
    ("two_stage_mxr_VSmode", generate_two_stage_mxr_VSmode),  # MXR VS
    ("two_stage_mxr_VUmode", generate_two_stage_mxr_VUmode),  # MXR VU
    ("two_stage_rw_VSmode", generate_two_stage_rw_VSmode),  # sw/lw both stages
    # --- SvH_csr.py: hypervisor CSRs ---
    ("csr_hgatp_fields_HSmode", generate_csr_hgatp_fields_HSmode),  # hgatp MODE/VMID/PPN
    ("csr_satp_mode_VSmode", generate_csr_satp_mode_VSmode),  # satp.MODE walk RV64
    ("csr_vsatp_fields_HSmode", generate_csr_vsatp_fields_HSmode),  # vsatp MODE/ASID/PPN
    # --- SvH_perm.py: permissions / MXR / SUM ---
    ("g_perm_VSmode", generate_g_perm_VSmode),  # G perms from VS
    ("g_perm_VUmode", generate_g_perm_VUmode),  # G perms from VU
    ("g_u_bit_HSmode", generate_g_u_bit_HSmode),  # G U-bit HS HLV/HSV
    ("sum_Upages_VSmode", generate_sum_Upages_VSmode),  # SUM on U pages
    ("vs_perm_VSmode", generate_vs_perm_VSmode),  # VS perms from VS
    ("vs_perm_VUmode", generate_vs_perm_VUmode),  # VS perms from VU
    ("vsstatus_mxr_sum_VSmode", generate_vsstatus_mxr_sum_VSmode),  # MXR×SUM VS
    ("vsstatus_mxr_sum_VUmode", generate_vsstatus_mxr_sum_VUmode),  # MXR×SUM VU
    ("vu_rwx_two_stage_VUmode", generate_vu_rwx_two_stage_VUmode),  # VU U=1 allow / U=0 deny
    ("xonly_mxr0_HSmode", generate_xonly_mxr0_HSmode),  # X-only MXR=0 HS
    ("xonly_mxr0_VSmode", generate_xonly_mxr0_VSmode),  # X-only MXR=0 VS
    ("xonly_mxr0_VUmode", generate_xonly_mxr0_VUmode),  # X-only MXR=0 VU
    ("xonly_mxr0_gstage_HSmode", generate_xonly_mxr0_gstage_HSmode),  # X-only G HS HLV
]


@add_priv_test_generator(
    "SvH",  # suite directory name: tests/priv/SvH/
    required_extensions=["I", "H"],  # skip generation unless I and H are enabled
    march_extensions=["I", "H"],  # -march string passed to GCC for this suite
    extra_defines=[
        "#define RVTEST_HYPERVISOR",  # turn on hypervisor trap / hop macros in env headers
        "#define TRAP_SIGUPD_COUNT 4096",  # trap-handler SIGUPD budget for guest-page faults
    ],
)
def make_svh(test_data: TestData) -> list[TestChunk]:  # define make_svh
    """Main entry: one TestChunk (one .S file) per scenario."""
    delete_old_asm_files()  # drop stale .S so a renamed test cannot linger on disk

    test_chunks: list[TestChunk] = []  # list of finished chunks returned to the writer
    for file_stem, generate_fn in _SCENARIOS:  # walk every scenario in order
        chunk = test_data.begin_test_chunk(file_stem)  # open chunk → SvH_<file_stem>-00.S
        chunk.section_header = comment_banner(file_stem, "SvH coverpoint stimulus")  # // banner
        chunk.sigupd_count = 0  # reset; becomes #define SIGUPD_COUNT in the header
        chunk.num_testcases = 0  # reset; becomes testcase-string table length
        chunk.code.extend(generate_fn(test_data))  # append all assembly lines from the family fn
        if chunk.num_testcases < 1:  # writer rejects a zero testcase count
            chunk.num_testcases = 1  # floor at 1 when the body never called add_testcase
        test_chunks.append(test_data.end_test_chunk())  # freeze this chunk; next loop opens a new one

    if not test_chunks:  # empty _SCENARIOS would be a wiring bug
        raise RuntimeError("SvH generator produced zero chunks")
    return test_chunks  # framework writes each chunk to tests/priv/SvH/
