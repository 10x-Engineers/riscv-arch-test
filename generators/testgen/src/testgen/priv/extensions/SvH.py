##################################
# priv/extensions/SvH.py
#
# SvH (Hypervisor + two-stage VM) privileged test generator.
# SPDX-License-Identifier: Apache-2.0
##################################

"""SvH privileged test generator entry point.

``make testgen EXTENSIONS=SvH`` loads this module through
``@add_priv_test_generator("SvH")`` and calls ``make_svh``.

This file does not emit page tables or guest loads/stores. It:

1. Deletes previously generated ``tests/priv/SvH/*.S`` files.
2. Collects every ``generate_*`` function from the five family modules.
3. Starts one ``TestChunk`` per function. The framework writer turns each
   chunk into ``tests/priv/SvH/SvH_<split_name>-00.S``.

Assembly lines are produced by the family modules using ``SvHCommon``.
"""

from __future__ import annotations  # allow list[str] / tuple[...] without quoting

from testgen.asm.helpers import comment_banner  # section header text for each .S file
from testgen.data.state import TestData  # mutable generator state (open chunk, SIGUPD)
from testgen.data.test_chunk import TestChunk  # one output file worth of assembly
from testgen.priv.extensions.SvHCommon import clean_svh_output_dir  # unlink tests/priv/SvH/*.S
from testgen.priv.extensions.SvH_csr import ALL_GENERATORS as CSR_GENS  # 3 CSR field generators
from testgen.priv.extensions.SvH_twostage import ALL_GENERATORS as TWOSTAGE_GENS  # paging on/off, MXR
from testgen.priv.registry import add_priv_test_generator  # registers make_svh with testgen

# Covergroup name stamped into SIGUPD / testcase strings (must match SvH_cg in coverpoints).
covergroup = "SvH_cg"


def _collect() -> list[tuple[str, object]]:
    """Build ``(split_name, generate_fn)`` for every family generator.

    Example: ``generate_two_stage_rw_VSmode`` → split name
    ``two_stage_rw_VSmode`` → file ``SvH_two_stage_rw_VSmode-00.S``.
    """
    scenarios: list[tuple[str, object]] = []  # (filename stem, generate_* callable)
    # Order of these tuples is the order of generated files on disk.
    for gens in (TWOSTAGE_GENS, CSR_GENS):
        for fn in gens:  # each public generate_* in that family
            name = fn.__name__  # Python function name, e.g. generate_two_stage_rw_VSmode
            if name.startswith("generate_"):  # strip prefix used only as a Python naming convention
                name = name[len("generate_") :]  # remainder is the split_name / file stem
            scenarios.append((name, fn))  # writer will emit SvH_<name>-00.S
    return scenarios  # full suite list for make_svh


@add_priv_test_generator(
    "SvH",  # suite directory name: tests/priv/SvH/
    required_extensions=["I", "H"],  # skip generation unless I and H are in the config
    march_extensions=["I", "H"],  # -march string for GCC when assembling this suite
    extra_defines=[
        "#define RVTEST_HYPERVISOR",  # enable hypervisor trap / hop macros in the env headers
        "#define TRAP_SIGUPD_COUNT 4096",  # trap-handler SIGUPD budget (guest-page / page faults)
    ],
)
def make_svh(test_data: TestData) -> list[TestChunk]:
    """Emit one test chunk for each family ``generate_*`` function."""
    # Drop stale .S files so a renamed scenario cannot linger as an extra test.
    clean_svh_output_dir()

    chunks: list[TestChunk] = []  # one TestChunk per generate_* (one .S file)
    for split_name, gen in _collect():  # split_name is the file stem after SvH_
        # Open a new chunk; the writer uses split_name in tests/priv/SvH/SvH_<split_name>-00.S.
        tc = test_data.begin_test_chunk(split_name)
        # Human-readable banner at the top of the generated assembly.
        tc.section_header = comment_banner(split_name, "SvH coverpoint stimulus (Python emitter)")
        # Family emitters increment these as they emit RVTEST_SIGUPD / add_testcase.
        tc.sigupd_count = 0  # becomes #define SIGUPD_COUNT in the test header
        tc.num_testcases = 0  # becomes the testcase-string table length
        # ``gen`` returns a list of assembly strings; append them to this chunk's code.
        tc.code.extend(gen(test_data))
        if tc.num_testcases < 1:  # writer requires a non-zero testcase count
            tc.num_testcases = 1  # single dummy count when the body never called add_testcase
        chunks.append(test_data.end_test_chunk())  # freeze this chunk; next loop opens a new one

    if not chunks:  # ALL_GENERATORS lists were empty — miswired family import
        raise RuntimeError("SvH generator produced zero chunks")
    return chunks  # framework writes each chunk to tests/priv/SvH/
