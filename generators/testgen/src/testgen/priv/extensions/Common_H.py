##################################
# common_h.py
#
# Shared H-extension CSR groups and M-mode-only test generation logic.
# Factored out of H.py so that both the "H" testsuite (H.py, HS/VS/VU
# modes) and the "SmH" testsuite (Sm.py, M-mode only) can reuse the exact
# same M-mode H-extension CSR coverage without duplicating it.
#
# Location note: place this alongside the other priv-extension generators,
# e.g. testgen/priv/common_h.py, importable as
#     from testgen.priv.common_h import ...
# SPDX-License-Identifier: Apache-2.0
##################################

"""Shared H-extension M-mode CSR test logic (used by Sm.py and H.py)."""

from testgen.asm.csr import csr_access_test, csr_walk_test
from testgen.asm.helpers import comment_banner, write_sigupd
from testgen.data.state import TestData

# ---------------------------------------------------------------------------
# CSR groups shared across H-extension test generators
# ---------------------------------------------------------------------------

# Machine-only H-extension CSRs used to verify that lower privilege modes
# cannot access these M-only registers.
M_ONLY_H_CSRS = [("mtval2", None), ("mtinst", None)]

# HS/VS-scope H-extension CSRs.
# These are accessible from HS and M, but from VS they should fault as
# virtual-instruction exceptions rather than illegal instructions.
HS_VS_H_CSRS = [
    ("hstatus", 0x7003E0),                    # control bits 5-9 and 20-22; ignores the WARL VGEIN and RV64 VSXL fields.
    ("hedeleg", 0xFFFFFFFF),                  # 32 exception-delegation positions
    ("hideleg", 0x1444),                      # virtual interrupt bits 2, 6, 10, and 12
    ("hie", 0x1444),                          # virtual interrupt bits 2, 6, 10, and 12
    ("hcounteren", 0xFFFFFFFF),               # counter enable bits
    ("htimedelta", None),                     # value-bearing registers without reserved/WARL field
    ("htval", None),                          # value-bearing registers without reserved/WARL field
    ("hip", 0x1444),                          # virtual interrupt bits 2, 6, 10, and 12
    ("hvip", 0x444),                          # writable virtual interrupt-pending bits 2, 6, and 10
    ("htinst", None),                         # value-bearing registers without reserved/WARL field
    ("henvcfg", 0xC0000000000000F1),          # checks FIOM, CBCFE, CBZE, PBMTE, and STCE; omits the WARL CBIE encoding.
    ("hgatp", 0),                             # since useful fields are implementation-sized or WARL
    ("hgeie", 0),                             # since useful fields are implementation-sized or WARL
    ("vsstatus", 0xFFFFFFFFFF7FFFBF),         # matches the existing sstatus masking convention
    ("vsie", 0x3666),                         # standard supervisor interrupt-bit subset
    ("vstvec", 0b10),                         # only the legal vector-mode bit; the base address is not reliably comparable.
    ("vsscratch", None),                      # value-bearing registers without reserved/WARL field
    ("vsepc", None),                          # value-bearing registers without reserved/WARL field
    # vscause excluded: WLRL, handled separately by cp_vscause_write in H.py.
    ("vstval", None),                         # value-bearing registers without reserved/WARL field
    ("vsip", 0x3666),
    ("vsatp", 0),                             # since useful fields are implementation-sized or WARL
]
HS_VS_H_CSRS_RO = [("hgeip", 0)]              # since hgeip's useful fields are implementation-sized or WARL
HS_VS_H_CSRS_32H = [("hedelegh", 0xFFFFFFFF), ("htimedeltah", None), ("henvcfgh", 0xC0000000)]

# Representative S-mode CSR set, used for tests that verify VS replica
# semantics in the H hypervisor environment.
S_CSRS_WITH_REPLICA = [
    ("sstatus", "vsstatus", 0xCFFFFFFCF),
    ("sie", "vsie", 0x3666),
    ("stvec", "vstvec", None),
    ("sscratch", "vsscratch", None),
    ("sepc", "vsepc", None),
    ("stval", "vstval", None),
    ("sip", "vsip", 0x3666),
    ("satp", "vsatp", None),
]
 
# senvcfg/scounteren are S-mode CSRs with NO VS-mode replica. These are
# used to confirm that VS accesses to non-replicated S CSRs behave normally.
S_CSRS_NO_REPLICA = ["scounteren", "senvcfg"]
 