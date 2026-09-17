///////////////////////////////////////////
//
// RISC-V Architectural Functional Coverage Covergroups
// H (Hypervisor) Extension
//
// SPDX-License-Identifier: Apache-2.0
//
////////////////////////////////////////////////////////////////////////////////////////////////

`define COVER_H

// ---------------------------------------------------------------------------
// H_hscsr_cg : HS-mode (_generate_hs_hcsr_tests, _generate_hs_inaccessible_test,
//              _generate_hstatus_vgein_test, _generate_vscause_tests)
// ---------------------------------------------------------------------------
covergroup H_hscsr_cg with function sample(ins_t ins);
    option.per_instance = 0;
    `include "general/RISCV_coverage_standard_coverpoints.svh"

    hcsrname_hs: coverpoint ins.current.insn[31:20] {
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
    hcsrname_hs_ro: coverpoint ins.current.insn[31:20] {
        bins hgeip = {CSR_HGEIP};
    }
    `ifdef UDB_MXLEN_32
        hcsrname_hs_32h: coverpoint ins.current.insn[31:20] {
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

    cp_hcsr_access:    cross priv_mode_hs, hcsrname_hs, csraccesses;
    cp_hcsr_access_ro: cross priv_mode_hs, hcsrname_hs_ro, csraccesses;
    cp_hcsrwalk:       cross priv_mode_hs, hcsrname_hs, csrop, walking_ones;
    `ifdef UDB_MXLEN_32
        cp_hcsr_access_32h: cross priv_mode_hs, hcsrname_hs_32h, csraccesses;
        cp_hcsrwalk_32h:    cross priv_mode_hs, hcsrname_hs_32h, csrop, walking_ones;
    `endif

    hcsrname_monly: coverpoint ins.current.insn[31:20] {
        bins mtval2 = {CSR_MTVAL2};
        bins mtinst = {CSR_MTINST};
    }
    csrr: coverpoint ins.current.insn {
        wildcard bins csrr = {CSRR};
    }
    cp_hcsr_inaccessible: cross priv_mode_hs, csrr, hcsrname_monly;

    hstatus_wr: coverpoint ins.current.insn[31:20] {
        bins hstatus = {CSR_HSTATUS};
    }
    vgein_field: coverpoint (ins.current.rs1_val & 64'h3F000) {
        bins vgein_0   = {64'h0};
        bins vgein_1   = {64'h1000};
        bins vgein_63  = {64'h3F000};
        bins vgein_mid = default; // runtime-discovered GEILEN max, 0 < max < 63
    }
    csrs: coverpoint ins.current.insn {
        wildcard bins csrs = {CSRRS};
    }
    cp_hstatus_vgein: cross priv_mode_hs, csrs, hstatus_wr, vgein_field;

    // cp_vscause_write / cp_vscause_write_interrupt
    // b_16 (double-trap) and b_19 (hardware error) now gated to match the
    // planned H.py fix: b_16 requires SMDBLTRP_SUPPORTED; b_19 is dropped
    // entirely (no reliable trigger mechanism), matching Sm_coverage.svh's
    // treatment of the same cause in Sm_mcause_cg.
    vscause_csr: coverpoint ins.current.insn[31:20] {
        bins vscause = {CSR_VSCAUSE};
    }
    vscause_exception_values: coverpoint ins.current.rs1_val[`UDB_MXLEN-2:0] {
        bins b_0  = {0};
        bins b_1  = {1};
        bins b_2  = {2};
        bins b_3  = {3};
        bins b_4  = {4};
        bins b_5  = {5};
        bins b_6  = {6};
        bins b_7  = {7};
        bins b_8  = {8};
        bins b_9  = {9};
        bins b_10 = {10};
        bins b_11 = {11};
        bins b_12 = {12};
        bins b_13 = {13};
        // b_14 reserved
        bins b_15 = {15};
        `ifdef SMDBLTRP_SUPPORTED
            bins b_16 = {16};
        `endif
        // b_17 reserved
        `ifdef SOFTWARE_CHECK_SUPPORTED
            bins b_18 = {18};
        `endif
        // b_19 hardware error -- excluded, no reliable trigger mechanism
        bins b_20 = {20};
        bins b_21 = {21};
        bins b_22 = {22};
        bins b_23 = {23};
    }
    vscause_interrupt_values: coverpoint ins.current.rs1_val[`UDB_MXLEN-2:0] {
        bins b_1  = {1};
        bins b_2  = {2};
        bins b_3  = {3};
        bins b_5  = {5};
        bins b_6  = {6};
        bins b_7  = {7};
        bins b_9  = {9};
        bins b_10 = {10};
        bins b_11 = {11};
        bins b_12 = {12};
        bins b_13 = {13};
    }
    vscause_exception: coverpoint ins.current.rs1_val[`UDB_MXLEN-1] {
        bins exception = {0};
    }
    vscause_interrupt: coverpoint ins.current.rs1_val[`UDB_MXLEN-1] {
        bins interrupt = {1};
    }
    cp_vscause_write:           cross priv_mode_hs, csrs, vscause_csr, vscause_exception_values, vscause_exception;
    cp_vscause_write_interrupt: cross priv_mode_hs, csrs, vscause_csr, vscause_interrupt_values, vscause_interrupt;

endgroup

// ---------------------------------------------------------------------------
// H_vscsr_cg : VS-mode (_generate_vs_inaccessible_tests,
//              _generate_vs_virtualfault_tests, _generate_virtual_instruction_high_cause_test,
//              _generate_illegalupper_test, _generate_vsstatus_sd_test)
// ---------------------------------------------------------------------------
covergroup H_vscsr_cg with function sample(ins_t ins);
    option.per_instance = 0;
    `include "general/RISCV_coverage_standard_coverpoints.svh"

    hcsrname_monly: coverpoint ins.current.insn[31:20] {
        bins mtval2 = {CSR_MTVAL2};
        bins mtinst = {CSR_MTINST};
    }
    csrr: coverpoint ins.current.insn {
        wildcard bins csrr = {CSRR};
    }
    cp_hcsr_inaccessible: cross priv_mode_vs, csrr, hcsrname_monly;

    virt_inst_fault: coverpoint (ins.current.csr[CSR_MCAUSE][31:0] == 32'd22) {
        // auto fill 0/1
    }
    // cp_hcsr_virtualinstructionfault: HS/VS-scope CSRs from VS-mode raise
    // virtual-instruction fault, not illegal instruction.
    hcsrname_hsvs_fault: coverpoint ins.current.insn[31:20] {
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
        bins hgeip       = {CSR_HGEIP};
    }
    cp_hcsr_virtualinstructionfault: cross priv_mode_vs, hcsrname_hsvs_fault, virt_inst_fault;

    `ifdef UDB_MXLEN_32
        hcntrname_high: coverpoint ins.current.insn[31:20] {
            bins cycleh          = {CSR_CYCLEH};
            bins timeh           = {CSR_TIMEH};
            bins instreth        = {CSR_INSTRETH};
            bins hpmcounter3h[]  = {[CSR_HPMCOUNTER3H:CSR_HPMCOUNTER31H]};
        }
        cp_virtual_instruction_high_cause: cross priv_mode_vs, csrr, hcntrname_high;
    `endif

    `ifdef UDB_MXLEN_64
        hcsrname_32h_only: coverpoint ins.current.insn[31:20] {
            bins hedelegh    = {CSR_HEDELEGH};
            bins htimedeltah = {CSR_HTIMEDELTAH};
            bins henvcfgh    = {CSR_HENVCFGH};
        }
        cp_illegalupper: cross priv_mode_vs, csrr, hcsrname_32h_only;
    `endif

    vsstatus_csr: coverpoint ins.current.insn[31:20] {
        bins vsstatus = {CSR_VSSTATUS};
    }
    sstatus_csr: coverpoint ins.current.insn[31:20] {
        bins sstatus = {CSR_SSTATUS};
    }
    csrrw: coverpoint ins.current.insn {
        wildcard bins csrrw = {CSRRW};
    }
    vsstatus_sd: coverpoint ins.current.rs1_val[`UDB_MXLEN-1] {
    }
    vsstatus_fs: coverpoint ins.current.rs1_val[14:13] {
    }
    vsstatus_vs: coverpoint ins.current.rs1_val[10:9] {
    }
    sstatus_fs: coverpoint ins.current.rs1_val[14:13] {
    }
    cp_vsstatus_sd_write: cross priv_mode_vs, csrrw, vsstatus_csr, vsstatus_sd, vsstatus_fs, vsstatus_vs;
    cp_sstatus_fs_write:  cross priv_mode_vs, csrrw, sstatus_csr, sstatus_fs;

endgroup

// ---------------------------------------------------------------------------
// H_ucsr_cg : U-mode (_generate_u_inaccessible_tests, _generate_illegalupper_test)
// ---------------------------------------------------------------------------
covergroup H_ucsr_cg with function sample(ins_t ins);
    option.per_instance = 0;
    `include "general/RISCV_coverage_standard_coverpoints.svh"

    hcsrname_all: coverpoint ins.current.insn[31:20] {
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
        bins hgeip       = {CSR_HGEIP};
    }
    csrr: coverpoint ins.current.insn {
        wildcard bins csrr = {CSRR};
    }
    cp_hcsr_inaccessible: cross priv_mode_u, csrr, hcsrname_all;

    `ifdef UDB_MXLEN_64
        hcsrname_32h_only: coverpoint ins.current.insn[31:20] {
            bins hedelegh    = {CSR_HEDELEGH};
            bins htimedeltah = {CSR_HTIMEDELTAH};
            bins henvcfgh    = {CSR_HENVCFGH};
        }
        cp_illegalupper: cross priv_mode_u, csrr, hcsrname_32h_only;
    `endif

endgroup

// ---------------------------------------------------------------------------
// H_vucsr_cg : VU-mode (_generate_vu_inaccessible_tests, _generate_illegalupper_test,
//              _generate_vu_scsr_test)
// ---------------------------------------------------------------------------
covergroup H_vucsr_cg with function sample(ins_t ins);
    option.per_instance = 0;
    `include "general/RISCV_coverage_standard_coverpoints.svh"

    hcsrname_all: coverpoint ins.current.insn[31:20] {
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
        bins hgeip       = {CSR_HGEIP};
    }
    csrr: coverpoint ins.current.insn {
        wildcard bins csrr = {CSRR};
    }
    cp_hcsr_inaccessible: cross priv_mode_vu, csrr, hcsrname_all;

    `ifdef UDB_MXLEN_64
        hcsrname_32h_only: coverpoint ins.current.insn[31:20] {
            bins hedelegh    = {CSR_HEDELEGH};
            bins htimedeltah = {CSR_HTIMEDELTAH};
            bins henvcfgh    = {CSR_HENVCFGH};
        }
        cp_illegalupper: cross priv_mode_vu, csrr, hcsrname_32h_only;
    `endif

    scsrname: coverpoint ins.current.insn[31:20] {
        bins sstatus     = {CSR_SSTATUS};
        bins sie         = {CSR_SIE};
        bins stvec       = {CSR_STVEC};
        bins sscratch    = {CSR_SSCRATCH};
        bins sepc        = {CSR_SEPC};
        bins stval       = {CSR_STVAL};
        bins sip         = {CSR_SIP};
        bins satp        = {CSR_SATP};
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
    cp_scsr: cross priv_mode_vu, csrr, scsrname;

endgroup

function void h_sample(int hart, int issue, ins_t ins);
    H_hscsr_cg.sample(ins);
    H_vscsr_cg.sample(ins);
    H_ucsr_cg.sample(ins);
    H_vucsr_cg.sample(ins);
endfunction
