///////////////////////////////////////////
//
// RISC-V Architectural Functional Coverage Covergroups
//
// Written: Angela Zheng, angela20061015@gmail.com, 10 September 2026
//
// Copyright (C) 2026 Harvey Mudd College, 10x Engineers, UET Lahore, Habib University
//
// SPDX-License-Identifier: Apache-2.0
//
////////////////////////////////////////////////////////////////////////////////////////////////
`define COVER_SDTRIGSM

covergroup SdtrigSm_trig_module_reg_cg with function sample(ins_t ins);
    option.per_instance = 0;
    `include "general/RISCV_coverage_standard_coverpoints.svh"
    `include "general/RISCV_coverage_sdtrig_coverpoints.svh"

    type_disabled: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_AFTER, "tdata1", "type")[3:0] {
        bins disabled = {4'd15};
    }
    tdata1_type_six: coverpoint ins.current.rs1_val[XLEN-1:XLEN-4] {
        bins mcontrol6 = {4'd6};
    }
    priv_bits: coverpoint ins.current.rs1_val[26:0] {
        bins priv = {27'b001_1000_0000_0000_0000_0101_1000};
    }
    csr_tselect:  coverpoint ins.current.insn[31:20] {
        bins tselect = {CSR_TSELECT};
    }
    csr_tdata: coverpoint ins.current.insn[31:20] {
        bins tdata1 = {CSR_TDATA1};
        bins tdata2 = {CSR_TDATA2};
        bins tdata3 = {CSR_TDATA3};
    }
    csr_tdata1: coverpoint ins.current.insn[31:20] {
        bins tdata1 = {CSR_TDATA1};
    }
    csr_tinfo: coverpoint ins.current.insn[31:20] {
        bins tinfo = {CSR_TINFO};
    }
    csr_global_reg: coverpoint ins.current.insn[31:20] {
        bins tselect  = {CSR_TSELECT};
        bins tcontrol = {CSR_TCONTROL};
        bins mcontext = {CSR_MCONTEXT};
        bins scontext = {CSR_SCONTEXT};
        `ifdef H_SUPPORTED
            bins hcontext = {CSR_HCONTEXT};
        `endif
    }
    csr_local_reg: coverpoint ins.current.insn[31:20] {
        bins tdata1 = {CSR_TDATA1};
        bins tdata2 = {CSR_TDATA2};
        bins tdata3 = {CSR_TDATA3};
        bins tinfo  = {CSR_TINFO};
    }
    csr_access: coverpoint ins.current.insn {
        wildcard bins csrrw0 = {CSRRW} iff (ins.current.rs1_val == '0);
        wildcard bins csrrw1 = {CSRRW} iff (ins.current.rs1_val == '1);
    }
    csrr: coverpoint ins.current.insn {
        wildcard bins csrr = {CSRR};
    }
    csrw: coverpoint ins.current.insn {
        wildcard bins csrw = {CSRW};
    }

    // main coverpoints
    cp_tdata_write:           cross priv_mode_m, triggernum, type_disabled, csr_tdata, csr_access;          // NTRIG * 3 CSRs * 2 values
    cp_csr_access_global:     cross priv_mode_m, csr_global_reg, csr_access;                                // 5 CSRs * 2 values
    cp_csr_access_local:      cross priv_mode_m, triggernum, csr_local_reg, csr_access;                     // NTRIG * 4 CSRs * 2 values
    cp_tselect_trigs:         cross priv_mode_m, triggernum, csrr, csr_tselect;                             // NTRIG
    cp_tdata1_mode_hardwired: cross priv_mode_m, triggernum, csrw, csr_tdata1, tdata1_type_six, priv_bits;  // NTRIG
    cp_tinfo_read_only:       cross priv_mode_m, triggernum, csr_tinfo, csr_access;                         // NTRIG
endgroup

///////////////////////////////////////////////////////////////////////////////
// Etrigger
///////////////////////////////////////////////////////////////////////////////
`ifdef UDB_SDTRIG_ETRIGGER_SUPPORTED
covergroup SdtrigSm_etrigger_cg with function sample(ins_t ins);
    option.per_instance = 0;
    `include "general/RISCV_coverage_standard_coverpoints.svh"
    `include "general/RISCV_coverage_sdtrig_coverpoints.svh"

    // tdata1: type = 5 (etrigger), dmode = 0, action = 0 (breakpoint)
    etrigger_cfg: coverpoint {get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[XLEN-1:XLEN-4],
                              get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[XLEN-5],
                              get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[5:0]} {
        bins etrigger_dmode0_bp = {11'b0101_0_000000};
    }

    // exception performed: code x (the one enabled in tdata2) or illegal instruction (0xFFFFFFFF)
    excp_performed: coverpoint (ins.current.insn == 32'hFFFFFFFF) iff (ins.current.trap) {
        bins excp_x       = {1'b0};
        bins excp_illegal = {1'b1};
    }

    // tdata2 is one-hot: bit N enables mcause code N
    tdata2_excode: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata2", "tdata2") {
        `ifndef ZCA_SUPPORTED // no instruction-address-misaligned with 16-bit alignment
            bins inst_addr_misaligned = {1 << 0};
        `endif
        bins inst_access_fault     = {1 << 1};
        bins illegal_inst          = {1 << 2};
        bins breakpoint            = {1 << 3};
        bins load_addr_misaligned  = {1 << 4};
        bins load_access_fault     = {1 << 5};
        bins store_addr_misaligned = {1 << 6};
        bins store_access_fault    = {1 << 7};
        `ifdef U_SUPPORTED
            bins ecall_u = {1 << 8};
        `endif
        bins ecall_m = {1 << 11};
        `ifdef S_SUPPORTED // page faults need S-mode translation
            bins ecall_s          = {1 << 9};
            bins inst_page_fault  = {1 << 12};
            bins load_page_fault  = {1 << 13};
            bins store_page_fault = {1 << 15};
        `endif
    }

    // tdata1 mode bits {vs, vu, m, s, u}: all clear, or only the mode under test set
    etrigger_en_m: coverpoint {get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[12],  // vs
                               get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[11],  // vu
                               get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[9],   // m
                               get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[7],   // s
                               get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[6]} { // u
        bins disabled = {5'b00000};
        `ifdef UDB_SDTRIG_M_AVAILABLE
            bins enabled = {5'b00100};
        `endif
    }

    // norm:Sdtrig_etrigger_access, _config, _timing, _action0 (all three crosses), _m
    // M-mode: NTRIG * codes * 2 modes * 2 exceptions
    cp_etrigger_m: cross priv_mode_m, triggernum, etrigger_cfg, tdata2_excode, etrigger_en_m, excp_performed {
        ignore_bins ig_illegal_x = binsof(tdata2_excode.illegal_inst) && binsof(excp_performed.excp_x); // x is the illegal bin itself
        `ifdef U_SUPPORTED
            ignore_bins ig_ecall_u_x = binsof(tdata2_excode.ecall_u) && binsof(excp_performed.excp_x); // no ecall from U in M
        `endif
        `ifdef S_SUPPORTED
            ignore_bins ig_ecall_s_x         = binsof(tdata2_excode.ecall_s)         && binsof(excp_performed.excp_x); // no ecall from S in M
            ignore_bins ig_inst_page_fault_x = binsof(tdata2_excode.inst_page_fault) && binsof(excp_performed.excp_x); // M fetch is never translated
        `endif
    }

    `ifdef S_SUPPORTED
        etrigger_en_s: coverpoint {get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[12],  // vs
                                   get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[11],  // vu
                                   get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[9],   // m
                                   get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[7],   // s
                                   get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[6]} { // u
            bins disabled = {5'b00000};
            `ifdef UDB_SDTRIG_S_AVAILABLE
                bins enabled = {5'b00010};
            `endif
        }

        // medeleg[x] for the code enabled in tdata2; medeleg[3] (breakpoint) stays 0
        medeleg_excode: coverpoint ((get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "medeleg", "medeleg") &
                                     get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata2", "tdata2")) != '0) {
            bins not_delegated = {1'b0};
            bins delegated     = {1'b1};
        }
        medeleg_breakpoint: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "medeleg", "medeleg")[3] {
            bins not_delegated = {1'b0};
        }

        // norm:Sdtrig_etrigger_s
        // S-mode: NTRIG * codes * 2 modes * 2 medeleg * 2 exceptions
        cp_etrigger_s: cross priv_mode_s, triggernum, etrigger_cfg, tdata2_excode, etrigger_en_s, medeleg_excode, medeleg_breakpoint, excp_performed {
            ignore_bins ig_bp_delegated       = binsof(tdata2_excode.breakpoint) && binsof(medeleg_excode.delegated); // medeleg[3] fixed at 0
            ignore_bins ig_ecall_m_delegated  = binsof(tdata2_excode.ecall_m)    && binsof(medeleg_excode.delegated); // medeleg[11] read-only 0
            ignore_bins ig_illegal_x          = binsof(tdata2_excode.illegal_inst) && binsof(excp_performed.excp_x);
            ignore_bins ig_ecall_m_x          = binsof(tdata2_excode.ecall_m)      && binsof(excp_performed.excp_x); // no ecall from M in S
            `ifdef U_SUPPORTED
                ignore_bins ig_ecall_u_x      = binsof(tdata2_excode.ecall_u)      && binsof(excp_performed.excp_x); // no ecall from U in S
            `endif
        }
    `endif

    `ifdef U_SUPPORTED
        etrigger_en_u: coverpoint {get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[12],  // vs
                                   get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[11],  // vu
                                   get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[9],   // m
                                   get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[7],   // s
                                   get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[6]} { // u
            bins disabled = {5'b00000};
            `ifdef UDB_SDTRIG_U_AVAILABLE
                bins enabled = {5'b00001};
            `endif
        }

        // norm:Sdtrig_etrigger_u
        // U-mode: medeleg only exists with S-mode
        `ifdef S_SUPPORTED
            cp_etrigger_u: cross priv_mode_u, triggernum, etrigger_cfg, tdata2_excode, etrigger_en_u, medeleg_excode, medeleg_breakpoint, excp_performed {
                ignore_bins ig_bp_delegated      = binsof(tdata2_excode.breakpoint)   && binsof(medeleg_excode.delegated);
                ignore_bins ig_ecall_m_delegated = binsof(tdata2_excode.ecall_m)      && binsof(medeleg_excode.delegated);
                ignore_bins ig_illegal_x         = binsof(tdata2_excode.illegal_inst) && binsof(excp_performed.excp_x);
                ignore_bins ig_ecall_s_x         = binsof(tdata2_excode.ecall_s)      && binsof(excp_performed.excp_x); // no ecall from S in U
                ignore_bins ig_ecall_m_x         = binsof(tdata2_excode.ecall_m)      && binsof(excp_performed.excp_x); // no ecall from M in U
            }
        `else
            cp_etrigger_u: cross priv_mode_u, triggernum, etrigger_cfg, tdata2_excode, etrigger_en_u, excp_performed {
                ignore_bins ig_illegal_x = binsof(tdata2_excode.illegal_inst) && binsof(excp_performed.excp_x);
                ignore_bins ig_ecall_m_x = binsof(tdata2_excode.ecall_m)      && binsof(excp_performed.excp_x); // no ecall from M in U
            }
        `endif
    `endif
endgroup
`endif

///////////////////////////////////////////////////////////////////////////////
// Textra
///////////////////////////////////////////////////////////////////////////////
`ifdef UDB_TDATA3_AVAILABLE
covergroup SdtrigSm_textra_cg with function sample(ins_t ins);
    option.per_instance = 0;
    `include "general/RISCV_coverage_standard_coverpoints.svh"
    `include "general/RISCV_coverage_sdtrig_coverpoints.svh"

    tdata1_type: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[XLEN-1:XLEN-4] {
        `ifdef UDB_SDTRIG_ICOUNT_SUPPORTED
            bins icount    = {4'd3};
        `endif
        `ifdef UDB_SDTRIG_ITRIGGER_SUPPORTED
            bins itrigger  = {4'd4};
        `endif
        `ifdef UDB_SDTRIG_ETRIGGER_SUPPORTED
            bins etrigger  = {4'd5};
        `endif
        `ifdef UDB_SDTRIG_MCONTROL6_SUPPORTED
            bins mcontrol6 = {4'd6};
        `endif
    }
    tdata1_dmode: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[XLEN-5] {
        bins zero = {1'b0};
    }
    // action = 0 (breakpoint): tdata1[15:12] in mcontrol6, tdata1[5:0] in icount/itrigger/etrigger
    tdata1_action: coverpoint ((get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[XLEN-1:XLEN-4] == 4'd6) ?
                               (get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[15:12] == 4'd0) :
                               (get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata1", "tdata1")[5:0]   == 6'd0)) {
        bins breakpoint = {1'b1};
    }

    // mhselect = 4 (mcontext), sselect = 0; mhvalue vs mcontext
    `ifdef UDB_MCONTEXT_AVAILABLE
        sselect_ignore: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[1:0] {
            bins ignore = {2'b00};
        }
        `ifdef UDB_MXLEN_32
            mhselect_mcontext: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[25:23] {
                bins mcontext = {3'b100};
            }
            mcontext_pattern: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "mcontext", "mcontext")[5:0] {
                bins pattern = {6'b010101};
            }
            mhvalue: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[31:26] {
                bins match    = {6'b010101}; // equals mcontext
                bins zero     = {6'b000000};
                bins mismatch = {6'b111111};
            }
        `endif
        `ifdef UDB_MXLEN_64
            mhselect_mcontext: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[50:48] {
                bins mcontext = {3'b100};
            }
            mcontext_pattern: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "mcontext", "mcontext")[12:0] {
                bins pattern = {13'h1AAA};
            }
            mhvalue: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[63:51] {
                bins match    = {13'h1AAA}; // equals mcontext
                bins zero     = {13'h0000};
                bins mismatch = {13'h0AAA};
            }
        `endif

        // norm:Sdtrig_etrigger_textra (plus mcontrol6/icount/itrigger textra, textra32/64 mhselect)
        // NTRIG * trigger types * 3 mhvalues
        cp_textra_mcontext: cross priv_mode_m, triggernum, tdata1_type, tdata1_dmode, tdata1_action,
                                  mhselect_mcontext, sselect_ignore, mcontext_pattern, mhvalue;
    `endif

    // mcontext and scontext filters together (AND semantics)
    `ifdef UDB_MCONTEXT_AVAILABLE
    `ifdef UDB_SCONTEXT_AVAILABLE
        `ifdef UDB_MXLEN_32
            mhselect_double: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[25:23] {
                bins ignore   = {3'b000};
                bins mcontext = {3'b100};
            }
            sselect_double: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[1:0] {
                bins ignore   = {2'b00};
                bins scontext = {2'b01};
            }
            sbytemask_zero: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[19:18] {
                bins zero = {2'b00};
            }
            mcontext_ones: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "mcontext", "mcontext")[5:0] {
                bins ones = {6'b111111};
            }
            scontext_ones: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "scontext", "scontext") {
                bins ones = {32'h0000FFFF};
            }
            mhvalue_double: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[31:26] {
                bins zero     = {6'b000000};
                bins all_ones = {6'b111111};
            }
            svalue_double: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[17:2] {
                bins zero     = {16'h0000};
                bins all_ones = {16'hFFFF};
            }
        `endif
        `ifdef UDB_MXLEN_64
            mhselect_double: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[50:48] {
                bins ignore   = {3'b000};
                bins mcontext = {3'b100};
            }
            sselect_double: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[1:0] {
                bins ignore   = {2'b00};
                bins scontext = {2'b01};
            }
            sbytemask_zero: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[39:36] {
                bins zero = {4'b0000};
            }
            mcontext_ones: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "mcontext", "mcontext")[12:0] {
                bins ones = {13'h1FFF};
            }
            scontext_ones: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "scontext", "scontext") {
                bins ones = {64'h00000000_FFFFFFFF};
            }
            mhvalue_double: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[63:51] {
                bins zero     = {13'h0000};
                bins all_ones = {13'h1FFF};
            }
            svalue_double: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE, "tdata3", "tdata3")[33:2] {
                bins zero     = {32'h00000000};
                bins all_ones = {32'hFFFFFFFF};
            }
        `endif

        // norm:Sdtrig_textra32_mhselect_mcontext, norm:Sdtrig_textra32_sselect_scontext
        // NTRIG * trigger types * 2 mhselect * 2 sselect * 2 mhvalue * 2 svalue
        cp_textra_double_context: cross priv_mode_m, triggernum, tdata1_type, tdata1_dmode, tdata1_action,
                                        mhselect_double, sselect_double, sbytemask_zero,
                                        mcontext_ones, scontext_ones, mhvalue_double, svalue_double;
    `endif
    `endif

    // svalue / sselect are tied to 0 without S-mode: write svalue = 1 and sselect = 1
    `ifndef S_SUPPORTED
        csrw_tdata3: coverpoint ins.current.insn {
            wildcard bins csrrw = {CSRRW} iff (ins.current.insn[31:20] == CSR_TDATA3);
        }
        `ifdef UDB_MXLEN_32 // {svalue[17:2], sselect[1:0]}
            sfield_write: coverpoint ins.current.rs1_val[17:0] {
                wildcard bins svalue_one  = {18'b0000_0000_0000_0001_??};
                wildcard bins sselect_one = {18'b????_????_????_????_01};
            }
        `endif
        `ifdef UDB_MXLEN_64 // {svalue[33:2], sselect[1:0]}
            sfield_write: coverpoint ins.current.rs1_val[33:0] {
                wildcard bins svalue_one  = {34'b0000_0000_0000_0000_0000_0000_0000_0001_??};
                wildcard bins sselect_one = {34'b????_????_????_????_????_????_????_????_01};
            }
        `endif

        // norm:Sdtrig_textra32_svalue_no_s, norm:Sdtrig_textra32_sselect_no_s
        cp_smode_fields_hardwired: cross priv_mode_m, triggernum, csrw_tdata3, sfield_write; // NTRIG * 2
    `endif
endgroup
`endif

function void sdtrigsm_sample(int hart, int issue, ins_t ins);
    SdtrigSm_trig_module_reg_cg.sample(ins);
    `ifdef UDB_SDTRIG_ETRIGGER_SUPPORTED
        SdtrigSm_etrigger_cg.sample(ins);
    `endif
    `ifdef UDB_TDATA3_AVAILABLE
        SdtrigSm_textra_cg.sample(ins);
    `endif
endfunction
