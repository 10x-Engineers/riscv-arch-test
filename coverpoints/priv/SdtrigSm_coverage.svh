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
// Itrigger
///////////////////////////////////////////////////////////////////////////////
`ifdef UDB_SDTRIG_ITRIGGER_SUPPORTED
covergroup SdtrigSm_itrigger_cg with function sample(ins_t ins);
    option.per_instance = 0;

    `include "general/RISCV_coverage_standard_coverpoints.svh"
    `include "general/RISCV_coverage_sdtrig_coverpoints.svh"

    // tdata1.type = 4 (itrigger)
    itrigger_type: coverpoint
        get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                    "tdata1", "tdata1")[XLEN-1:XLEN-4] {
        bins itrigger = {4'd4};
    }

    // dmode = 0
    itrigger_dmode: coverpoint
        get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                    "tdata1", "tdata1")[XLEN-5] {
        bins zero = {1'b0};
    }

    // nmi = 0 for the normal interrupt-trigger scenarios
    itrigger_nmi: coverpoint
        get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                    "tdata1", "tdata1")[10] {
        bins off = {1'b0};
    }

    // action = 0 (breakpoint)
    itrigger_action: coverpoint
        get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                    "tdata1", "tdata1")[5:0] {
        bins breakpoint = {6'b000000};
    }

    tdata2_intcode: coverpoint
        get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                    "tdata2", "tdata2") {

        bins ssi  = {1 << 1};   // 1  supervisor software interrupt

        bins msi  = {1 << 3};   // 3  machine software interrupt

        bins sti  = {1 << 5};   // 5  supervisor timer interrupt

        bins mti  = {1 << 7};   // 7  machine timer interrupt

        bins sei  = {1 << 9};   // 9  supervisor external interrupt

        bins mei  = {1 << 11};  // 11 machine external interrupt

        `ifdef SSCOFPMF_SUPPORTED
            bins lcofi = {1 << 13}; // 13 local counter-overflow interrupt
        `endif
    }

    interrupt_performed: coverpoint
        (ins.current.trap &&
         ins.current.csr[CSR_MCAUSE][XLEN-1]) {

        bins no_interrupt = {1'b0};
        bins interrupt    = {1'b1};
    }

    // Trigger hit

    itrigger_hit: coverpoint
        ins.current.csr[CSR_TDATA1][XLEN-6]
        iff (ins.current.trap &&
             ins.current.csr[CSR_MCAUSE][XLEN-1]) {

        bins nofire = {1'b0};
        bins fire   = {1'b1};
    }

    itrigger_priv: coverpoint {
        get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                    "tdata1", "tdata1")[9],   // M
        get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                    "tdata1", "tdata1")[7],   // S
        get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                    "tdata1", "tdata1")[6],   // U
        get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                    "tdata1", "tdata1")[12],  // VS
        get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                    "tdata1", "tdata1")[11]   // VU
    } {

        bins disabled = {5'b00000};

        `ifdef UDB_SDTRIG_M_AVAILABLE
            bins m = {5'b10000};
        `endif

        `ifdef UDB_SDTRIG_S_AVAILABLE
            bins s = {5'b01000};
        `endif

        `ifdef UDB_SDTRIG_U_AVAILABLE
            bins u = {5'b00100};
        `endif

        `ifdef UDB_SDTRIG_VS_AVAILABLE
            bins vs = {5'b00010};
        `endif

        `ifdef UDB_SDTRIG_VU_AVAILABLE
            bins vu = {5'b00001};
        `endif
    }

    `ifdef S_SUPPORTED

        mideleg_intcode: coverpoint
            ((get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                          "mideleg", "mideleg") &
              get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                          "tdata2", "tdata2")) != '0) {

            bins not_delegated = {1'b0};
            bins delegated     = {1'b1};
        }

    `endif

    cp_itrigger_m:
        cross priv_mode_m,
              triggernum,
              itrigger_type,
              itrigger_dmode,
              itrigger_action,
              tdata2_intcode,
              itrigger_priv,
              interrupt_performed,
              itrigger_hit {

        // S/U privilege configurations are not M-origin trigger scenarios.
        ignore_bins ig_non_m_priv =
            binsof(itrigger_priv) with
            ((item[1] == 1'b1) ||
             (item[2] == 1'b1));
    }

    `ifdef S_SUPPORTED

        cp_itrigger_s:
            cross priv_mode_s,
                  triggernum,
                  itrigger_type,
                  itrigger_dmode,
                  itrigger_action,
                  tdata2_intcode,
                  itrigger_priv,
                  mideleg_intcode,
                  interrupt_performed,
                  itrigger_hit {

            // S-origin uses S privilege configuration.
            ignore_bins ig_m_priv =
                binsof(itrigger_priv.m);

            ignore_bins ig_u_priv =
                binsof(itrigger_priv.u);

            // M-origin-only interrupt causes.
            ignore_bins ig_msi =
                binsof(tdata2_intcode.msi);

            ignore_bins ig_mti =
                binsof(tdata2_intcode.mti);

            ignore_bins ig_mei =
                binsof(tdata2_intcode.mei);
        }

    `endif

    `ifdef U_SUPPORTED

        `ifdef S_SUPPORTED

            cp_itrigger_u:
                cross priv_mode_u,
                      triggernum,
                      itrigger_type,
                      itrigger_dmode,
                      itrigger_action,
                      tdata2_intcode,
                      itrigger_priv,
                      mideleg_intcode,
                      interrupt_performed,
                      itrigger_hit {

                ignore_bins ig_m_priv =
                    binsof(itrigger_priv.m);

                ignore_bins ig_s_priv =
                    binsof(itrigger_priv.s);

                ignore_bins ig_msi =
                    binsof(tdata2_intcode.msi);

                ignore_bins ig_mti =
                    binsof(tdata2_intcode.mti);

                ignore_bins ig_mei =
                    binsof(tdata2_intcode.mei);
            }

        `else

            cp_itrigger_u:
                cross priv_mode_u,
                      triggernum,
                      itrigger_type,
                      itrigger_dmode,
                      itrigger_action,
                      tdata2_intcode,
                      itrigger_priv,
                      interrupt_performed,
                      itrigger_hit {

                ignore_bins ig_m_priv =
                    binsof(itrigger_priv.m);

                ignore_bins ig_s_priv =
                    binsof(itrigger_priv.s);

                ignore_bins ig_msi =
                    binsof(tdata2_intcode.msi);

                ignore_bins ig_mti =
                    binsof(tdata2_intcode.mti);

                ignore_bins ig_mei =
                    binsof(tdata2_intcode.mei);
            }

        `endif

    `endif

endgroup
`endif


///////////////////////////////////////////////////////////////////////////////
// Textra scontext / ASID
///////////////////////////////////////////////////////////////////////////////
`ifdef UDB_TDATA3_AVAILABLE
covergroup SdtrigSm_textra_context_cg with function sample(ins_t ins);
    option.per_instance = 0;

    `include "general/RISCV_coverage_standard_coverpoints.svh"
    `include "general/RISCV_coverage_sdtrig_coverpoints.svh"

    tdata1_type: coverpoint
        get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                    "tdata1", "tdata1")[XLEN-1:XLEN-4] {

        `ifdef UDB_SDTRIG_ICOUNT_SUPPORTED
            bins icount = {4'd3};
        `endif

        `ifdef UDB_SDTRIG_ITRIGGER_SUPPORTED
            bins itrigger = {4'd4};
        `endif

        `ifdef UDB_SDTRIG_ETRIGGER_SUPPORTED
            bins etrigger = {4'd5};
        `endif

        `ifdef UDB_SDTRIG_MCONTROL6_SUPPORTED
            bins mcontrol6 = {4'd6};
        `endif
    }

    // dmode = 0
    tdata1_dmode: coverpoint
        get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                    "tdata1", "tdata1")[XLEN-5] {

        bins zero = {1'b0};
    }

    // action = 0.
    // For mcontrol6 action is [15:12].
    // For icount/itrigger/etrigger action is [5:0].
    tdata1_action: coverpoint
        ((get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                      "tdata1", "tdata1")[XLEN-1:XLEN-4] == 4'd6) ?
         (get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                      "tdata1", "tdata1")[15:12] == 4'd0) :
         (get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                      "tdata1", "tdata1")[5:0] == 6'd0)) {

        bins breakpoint = {1'b1};
    }

    `ifdef UDB_SCONTEXT_AVAILABLE

        sselect_scontext: coverpoint
            get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                        "tdata3", "tdata3")[1:0] {

            bins ignore = {2'b00};
            bins scontext = {2'b01};
        }


        `ifdef UDB_MXLEN_32

            // tdata3:
            //
            // [17:2]  svalue
            // [19:18] sbytemask
            // [1:0]   sselect
            svalue_scontext: coverpoint
                get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                            "tdata3", "tdata3")[17:2] {

                bins zero       = {16'h0000};
                bins low_byte   = {16'h0034};
                bins high_byte  = {16'h1200};
                bins full_match = {16'h1234};
            }

            sbytemask_scontext: coverpoint
                get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                            "tdata3", "tdata3")[19:18] {

                bins low_byte  = {2'b01};
                bins high_byte = {2'b10};
                bins both      = {2'b11};
            }

            scontext_value: coverpoint
                get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                            "scontext", "scontext")[15:0] {

                bins pattern = {16'h1234};
            }

            // Observed trigger event.
            scontext_breakpoint: coverpoint
                (ins.current.trap &&
                 (ins.current.csr[CSR_MCAUSE][31:0] == 32'd3)) {

                bins no_breakpoint = {1'b0};
                bins breakpoint    = {1'b1};
            }

            cp_textra_scontext:
                cross priv_mode_m,
                      triggernum,
                      tdata1_type,
                      tdata1_dmode,
                      tdata1_action,
                      sselect_scontext,
                      svalue_scontext,
                      sbytemask_scontext,
                      scontext_value,
                      scontext_breakpoint;

        `endif


        `ifdef UDB_MXLEN_64

            // tdata3:
            //
            // [33:2]  svalue
            // [39:36] sbytemask
            // [1:0]   sselect
            svalue_scontext: coverpoint
                get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                            "tdata3", "tdata3")[33:2] {

                bins zero        = {32'h00000000};
                bins value_1     = {32'h12345600};
                bins value_2     = {32'h12340078};
                bins value_3     = {32'h12005678};
                bins value_4     = {32'h00345678};
                bins full_match  = {32'h12345678};
            }

            sbytemask_scontext: coverpoint
                get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                            "tdata3", "tdata3")[39:36] {

                bins byte_0 = {4'b0001};
                bins byte_1 = {4'b0010};
                bins byte_2 = {4'b0100};
                bins byte_3 = {4'b1000};
                bins all    = {4'b1111};
            }

            scontext_value: coverpoint
                get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                            "scontext", "scontext")[31:0] {

                bins pattern = {32'h12345678};
            }

            scontext_breakpoint: coverpoint
                (ins.current.trap &&
                 (ins.current.csr[CSR_MCAUSE][63:0] == 64'd3)) {

                bins no_breakpoint = {1'b0};
                bins breakpoint    = {1'b1};
            }

            cp_textra_scontext:
                cross priv_mode_m,
                      triggernum,
                      tdata1_type,
                      tdata1_dmode,
                      tdata1_action,
                      sselect_scontext,
                      svalue_scontext,
                      sbytemask_scontext,
                      scontext_value,
                      scontext_breakpoint;

        `endif

    `endif


    ///////////////////////////////////////////////////////////////////////////////
    // cp_textra_asid
    ///////////////////////////////////////////////////////////////////////////////

    `ifdef UDB_SCONTEXT_AVAILABLE

        sselect_asid: coverpoint
            get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                        "tdata3", "tdata3")[1:0] {

            bins ignore = {2'b00};
            bins asid   = {2'b10};
        }

        `ifdef UDB_MXLEN_64

            asid_relation: coverpoint
                ((get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                              "satp", "satp")[59:44] <
                  get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                              "tdata3", "tdata3")
                              [2 +: `UDB_ASID_WIDTH]) ? 2'd0 :

                 (get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                              "satp", "satp")[59:44] ==
                  get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                              "tdata3", "tdata3")
                              [2 +: `UDB_ASID_WIDTH]) ? 2'd1 :

                                                          2'd2) {

                bins below = {2'd0};
                bins equal = {2'd1};
                bins above = {2'd2};
            }

            asid_breakpoint: coverpoint
                (ins.current.trap &&
                 (ins.current.csr[CSR_MCAUSE][63:0] == 64'd3)) {

                bins no_breakpoint = {1'b0};
                bins breakpoint    = {1'b1};
            }

            cp_textra_asid:
                cross priv_mode_m,
                      triggernum,
                      tdata1_type,
                      tdata1_dmode,
                      tdata1_action,
                      sselect_asid,
                      asid_relation,
                      asid_breakpoint;

        `endif

        `ifdef UDB_MXLEN_32

            asid_relation: coverpoint
                ((get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                              "satp", "satp")[30:22] <
                  get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                              "tdata3", "tdata3")
                              [2 +: `UDB_ASID_WIDTH]) ? 2'd0 :

                 (get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                              "satp", "satp")[30:22] ==
                  get_csr_val(ins.hart, ins.issue, `SAMPLE_BEFORE,
                              "tdata3", "tdata3")
                              [2 +: `UDB_ASID_WIDTH]) ? 2'd1 :

                                                          2'd2) {

                bins below = {2'd0};
                bins equal = {2'd1};
                bins above = {2'd2};
            }

            asid_breakpoint: coverpoint
                (ins.current.trap &&
                 (ins.current.csr[CSR_MCAUSE][31:0] == 32'd3)) {

                bins no_breakpoint = {1'b0};
                bins breakpoint    = {1'b1};
            }

            cp_textra_asid:
                cross priv_mode_m,
                      triggernum,
                      tdata1_type,
                      tdata1_dmode,
                      tdata1_action,
                      sselect_asid,
                      asid_relation,
                      asid_breakpoint;

        `endif

    `endif

endgroup
`endif

function void sdtrigsm_sample(int hart, int issue, ins_t ins);
    SdtrigSm_trig_module_reg_cg.sample(ins);
    `ifdef UDB_SDTRIG_ITRIGGER_SUPPORTED
        SdtrigSm_itrigger_cg.sample(ins);
    `endif

    `ifdef UDB_TDATA3_AVAILABLE
        SdtrigSm_textra_cg.sample(ins);
    `endif
endfunction
