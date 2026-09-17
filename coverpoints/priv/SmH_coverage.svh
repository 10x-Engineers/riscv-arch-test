
///////////////////////////////////////////
//
// RISC-V Architectural Functional Coverage Covergroups
// H (Hypervisor) Extension
//
// SPDX-License-Identifier: Apache-2.0
//
////////////////////////////////////////////////////////////////////////////////////////////////

`define COVER_SmH
// ---------------------------------------------------------------------------
// H_mcsr_cg : M-mode (_generate_hcsr_tests, _generate_mtvala_test)
// ---------------------------------------------------------------------------
covergroup H_mcsr_cg with function sample(ins_t ins);
    option.per_instance = 0;
    `include "general/RISCV_coverage_standard_coverpoints.svh"

    hcsrname_m: coverpoint ins.current.insn[31:20] {
        bins mtval2      = {CSR_MTVAL2};
        bins mtinst      = {CSR_MTINST};
        bins hstatus     = {CSR_HSTATUS};
        bins hedeleg     = {CSR_HEDELEG};
        bins hideleg     = {CSR_HIDELEG};
        bins hie         = {CSR_HIE};
        bins hcounteren  = {CSR_HCOUNTEREN};
        bins htimedelta  = {CSR_HTIMEDELTA};
        bins htval       = {CSR_HTVAL};
        bins hip         = {CSR_HIP};
        bins hvip        = {CSR_HVIP};
        bins htinst      = {CSR_HTINST};
        bins henvcfg     = {CSR_HENVCFG};
        bins hgatp       = {CSR_HGATP};
        bins hgeie       = {CSR_HGEIE};
        bins vsstatus    = {CSR_VSSTATUS};
        bins vsie        = {CSR_VSIE};
        bins vstvec      = {CSR_VSTVEC};
        bins vsscratch   = {CSR_VSSCRATCH};
        bins vsepc       = {CSR_VSEPC};
        bins vstval      = {CSR_VSTVAL};
        bins vsip        = {CSR_VSIP};
        bins vsatp       = {CSR_VSATP};
    }
    hcsrname_m_ro: coverpoint ins.current.insn[31:20] {
        bins hgeip = {CSR_HGEIP};
    }
    `ifdef UDB_MXLEN_32
        hcsrname_m_32h: coverpoint ins.current.insn[31:20] {
            bins hedelegh    = {CSR_HEDELEGH};
            bins htimedeltah = {CSR_HTIMEDELTAH};
            bins henvcfgh    = {CSR_HENVCFGH};
        }
    `endif

    csraccesses: coverpoint ins.current.insn {
        wildcard bins csrrc_all = {CSRRC} iff (ins.current.rs1_val == '1);
        wildcard bins csrrw0    = {CSRRW} iff (ins.current.rs1_val ==  0);
        wildcard bins csrrw1    = {CSRRW} iff (ins.current.rs1_val == '1);
        wildcard bins csrrs_all = {CSRRS} iff (ins.current.rs1_val == '1);
        wildcard bins csrr      = {CSRR}  iff (ins.current.rs1_val ==  0);
    }
    csrop: coverpoint ins.current.insn {
        wildcard bins csrrs = {CSRRS};
        wildcard bins csrrc = {CSRRC};
    }
    walking_ones: coverpoint $clog2(ins.current.rs1_val) iff ($onehot(ins.current.rs1_val)) {
        bins b_1[] = { [0:`UDB_MXLEN-1] };
    }

    cp_hcsr_access:    cross priv_mode_m, hcsrname_m, csraccesses;
    cp_hcsr_access_ro: cross priv_mode_m, hcsrname_m_ro, csraccesses;
    cp_hcsrwalk:       cross priv_mode_m, hcsrname_m, csrop, walking_ones;
    `ifdef UDB_MXLEN_32
        cp_hcsr_access_32h: cross priv_mode_m, hcsrname_m_32h, csraccesses;
        cp_hcsrwalk_32h:    cross priv_mode_m, hcsrname_m_32h, csrop, walking_ones;
    `endif

    mtval_write: coverpoint ins.current.insn[31:20] {
        bins mtval = {CSR_MTVAL};
    }
    mtval_wval: coverpoint ins.current.rs1_val {
        bins allones = {'1};
    }
    csrw: coverpoint ins.current.insn {
        wildcard bins csrw = {CSRRW} iff (ins.current.rd == 0);
    }
    cp_mtvala: cross priv_mode_m, csrw, mtval_write, mtval_wval;

endgroup

function void h_sample(int hart, int issue, ins_t ins);
    H_mcsr_cg.sample(ins);
endfunction