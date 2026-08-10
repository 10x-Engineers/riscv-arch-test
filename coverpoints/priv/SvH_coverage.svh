///////////////////////////////////////////
//
// RISC-V Architectural Functional Coverage Covergroups
//
// Written By: Muhammad Abdullah abdullah.gohar@10xengineers.ai January 07, 2026
//
// Copyright (C) 2025 Harvey Mudd College, 10x Engineers, UET Lahore
//
// SPDX-License-Identifier: Apache-2.0
//
////////////////////////////////////////////////////////////////////////////////////////////////

`define COVER_SVH
covergroup SvH_cg with function sample(ins_t ins);
    option.per_instance = 0;
    `include "general/RISCV_coverage_standard_coverpoints.svh"

    // How to read comments:
    //   What / Test — cite ELF + Sail path/symbol or sail_to_rvvi.py when bins stay empty.
    //   Our side = tests + sail_to_rvvi.py. Sail side = model under sail-riscv-hypervisor/.
    // Open Sail hole: vsbe_hstatus.set (sys_regs.sail::legalize_hstatus leaves VSBE unassigned).
    // Speculative VS A-bit (sheet cp_vsatp_speculative_a_bit): no cross — .rvvi has no
    // squash/speculation sideband; waived in status tracker until converter/Sail emit it.

    read_write_acc: coverpoint {ins.current.write_access, ins.current.read_access} {
        bins read_acc = {2'b01};
        bins write_acc = {2'b10};
    }

    exec_acc: coverpoint ins.current.execute_access {
        bins exec_acc  = {1'b1};
    }

    acc_instr: coverpoint ins.current.insn {
        wildcard bins lw = {LW};
        wildcard bins sw = {SW};
        wildcard bins hlv_w = {HLV_W};
        wildcard bins hsv_w = {HSV_W};
    }

    csrrw: coverpoint ins.current.insn {
        wildcard bins csrrw = {CSRRW};
    }

    // Write hgatp (CSRRW) then read it back (CSRR) — used for VMID check.
    raw_csrrw_csrr: coverpoint {ins.prev.insn[14:12], ins.current.insn[14:12]} {
        bins raw = {6'b001_010};
    }

    vs_pte_rsw: coverpoint ins.current.vs_pte_d[9:8];
    g_pte_rsw: coverpoint ins.current.g_pte_d[9:8];

    // CSR addresses used by the crosses below (same on RV32 and RV64).
    vsatp: coverpoint ins.current.insn[31:20] {
        bins vsatp = {CSR_VSATP};
    }
    hgatp: coverpoint ins.current.insn[31:20] {
        bins hgatp = {CSR_HGATP};
    }
    satp: coverpoint ins.current.insn[31:20] {
        bins satp = {CSR_SATP};
    }

    `ifdef UDB_MXLEN_64
        mode_field_values: coverpoint ins.current.rs1_val[63:60] {
            bins values_to_write[] = {[0:15]};
        }

        mode_vsatp: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "vsatp", "mode") {
            bins bare = {0};
            bins sv39 = {8};
        }

        mode_hgatp: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "hgatp", "mode") {
            bins bare = {0};
            bins sv39x4 = {8};
        }

        mode_satp: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "satp", "mode") {
            bins bare = {0};
            bins sv39 = {8};
        }

        pbmte_menvcfg: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "menvcfg", "pbmte") {
            bins no_support = {1'b0};
        }

        vs_pte_i_svpbmt: coverpoint ins.current.vs_pte_i[62:61];
        vs_pte_d_svpbmt: coverpoint ins.current.vs_pte_d[62:61];

        g_pte_i_svpbmt: coverpoint ins.current.g_pte_i[62:61];
        g_pte_d_svpbmt: coverpoint ins.current.g_pte_d[62:61];

        vs_pte_i_reserved: coverpoint ins.current.vs_pte_i[60:54] {
            bins all_zeros      = {7'b0000000};
            bins walking_one_54 = {7'b0000001};
            bins walking_one_55 = {7'b0000010};
            bins walking_one_56 = {7'b0000100};
            bins walking_one_57 = {7'b0001000};
            bins walking_one_58 = {7'b0010000};
            bins walking_one_59 = {7'b0100000};
            bins walking_one_60 = {7'b1000000};
            bins all_ones       = {7'b1111111};
        }
        vs_pte_d_reserved: coverpoint ins.current.vs_pte_d[60:54] {
            bins all_zeros      = {7'b0000000};
            bins walking_one_54 = {7'b0000001};
            bins walking_one_55 = {7'b0000010};
            bins walking_one_56 = {7'b0000100};
            bins walking_one_57 = {7'b0001000};
            bins walking_one_58 = {7'b0010000};
            bins walking_one_59 = {7'b0100000};
            bins walking_one_60 = {7'b1000000};
            bins all_ones       = {7'b1111111};
        }

        g_pte_i_reserved: coverpoint ins.current.g_pte_i[60:54] {
            bins all_zeros      = {7'b0000000};
            bins walking_one_54 = {7'b0000001};
            bins walking_one_55 = {7'b0000010};
            bins walking_one_56 = {7'b0000100};
            bins walking_one_57 = {7'b0001000};
            bins walking_one_58 = {7'b0010000};
            bins walking_one_59 = {7'b0100000};
            bins walking_one_60 = {7'b1000000};
            bins all_ones       = {7'b1111111};
        }
        g_pte_d_reserved: coverpoint ins.current.g_pte_d[60:54] {
            bins all_zeros      = {7'b0000000};
            bins walking_one_54 = {7'b0000001};
            bins walking_one_55 = {7'b0000010};
            bins walking_one_56 = {7'b0000100};
            bins walking_one_57 = {7'b0001000};
            bins walking_one_58 = {7'b0010000};
            bins walking_one_59 = {7'b0100000};
            bins walking_one_60 = {7'b1000000};
            bins all_ones       = {7'b1111111};
        }
    `endif

    vsatp_mode: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "vsatp", "mode") {
        `ifdef UDB_MXLEN_64
            bins sv39 = {4'b1000};
        `else
            bins sv32 = {1'b1};
        `endif
    }
    hgatp_mode: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "hgatp", "mode") {
        `ifdef UDB_MXLEN_64
            bins sv39x4 = {4'b1000};
        `else
            bins sv32x4 = {1'b1};
        `endif
    }

    // Only the PPN bits of rs1 (not MODE/ASID/VMID).
`ifdef UDB_MXLEN_32
    ppn_field_values: coverpoint ins.current.rs1_val[21:0] {
        bins all_zeros = {0};
        bins all_ones        = {22'b1111111111111111111111};
        bins walking_ones_0  = {22'b0000000000000000000001};
        bins walking_ones_1  = {22'b0000000000000000000010};
        bins walking_ones_2  = {22'b0000000000000000000100};
        bins walking_ones_3  = {22'b0000000000000000001000};
        bins walking_ones_4  = {22'b0000000000000000010000};
        bins walking_ones_5  = {22'b0000000000000000100000};
        bins walking_ones_6  = {22'b0000000000000001000000};
        bins walking_ones_7  = {22'b0000000000000010000000};
        bins walking_ones_8  = {22'b0000000000000100000000};
        bins walking_ones_9  = {22'b0000000000001000000000};
        bins walking_ones_10  = {22'b0000000000010000000000};
        bins walking_ones_11  = {22'b0000000000100000000000};
        bins walking_ones_12  = {22'b0000000001000000000000};
        bins walking_ones_13  = {22'b0000000010000000000000};
        bins walking_ones_14  = {22'b0000000100000000000000};
        bins walking_ones_15  = {22'b0000001000000000000000};
        bins walking_ones_16  = {22'b0000010000000000000000};
        bins walking_ones_17  = {22'b0000100000000000000000};
        bins walking_ones_18  = {22'b0001000000000000000000};
        bins walking_ones_19  = {22'b0010000000000000000000};
        bins walking_ones_20  = {22'b0100000000000000000000};
        bins walking_ones_21  = {22'b1000000000000000000000};
    }
`else
    ppn_field_values: coverpoint ins.current.rs1_val[43:0] {
        bins all_zeros = {0};
        bins all_ones        = {44'b11111111111111111111111111111111111111111111};
        bins walking_ones_0  = {44'b00000000000000000000000000000000000000000001};
        bins walking_ones_1  = {44'b00000000000000000000000000000000000000000010};
        bins walking_ones_2  = {44'b00000000000000000000000000000000000000000100};
        bins walking_ones_3  = {44'b00000000000000000000000000000000000000001000};
        bins walking_ones_4  = {44'b00000000000000000000000000000000000000010000};
        bins walking_ones_5  = {44'b00000000000000000000000000000000000000100000};
        bins walking_ones_6  = {44'b00000000000000000000000000000000000001000000};
        bins walking_ones_7  = {44'b00000000000000000000000000000000000010000000};
        bins walking_ones_8  = {44'b00000000000000000000000000000000000100000000};
        bins walking_ones_9  = {44'b00000000000000000000000000000000001000000000};
        bins walking_ones_10  = {44'b00000000000000000000000000000000010000000000};
        bins walking_ones_11  = {44'b00000000000000000000000000000000100000000000};
        bins walking_ones_12  = {44'b00000000000000000000000000000001000000000000};
        bins walking_ones_13  = {44'b00000000000000000000000000000010000000000000};
        bins walking_ones_14  = {44'b00000000000000000000000000000100000000000000};
        bins walking_ones_15  = {44'b00000000000000000000000000001000000000000000};
        bins walking_ones_16  = {44'b00000000000000000000000000010000000000000000};
        bins walking_ones_17  = {44'b00000000000000000000000000100000000000000000};
        bins walking_ones_18  = {44'b00000000000000000000000001000000000000000000};
        bins walking_ones_19  = {44'b00000000000000000000000010000000000000000000};
        bins walking_ones_20  = {44'b00000000000000000000000100000000000000000000};
        bins walking_ones_21  = {44'b00000000000000000000001000000000000000000000};
        bins walking_ones_22  = {44'b00000000000000000000010000000000000000000000};
        bins walking_ones_23  = {44'b00000000000000000000100000000000000000000000};
        bins walking_ones_24  = {44'b00000000000000000001000000000000000000000000};
        bins walking_ones_25  = {44'b00000000000000000010000000000000000000000000};
        bins walking_ones_26  = {44'b00000000000000000100000000000000000000000000};
        bins walking_ones_27  = {44'b00000000000000001000000000000000000000000000};
        bins walking_ones_28  = {44'b00000000000000010000000000000000000000000000};
        bins walking_ones_29  = {44'b00000000000000100000000000000000000000000000};
        bins walking_ones_30  = {44'b00000000000001000000000000000000000000000000};
        bins walking_ones_31  = {44'b00000000000010000000000000000000000000000000};
        bins walking_ones_32  = {44'b00000000000100000000000000000000000000000000};
        bins walking_ones_33  = {44'b00000000001000000000000000000000000000000000};
        bins walking_ones_34  = {44'b00000000010000000000000000000000000000000000};
        bins walking_ones_35  = {44'b00000000100000000000000000000000000000000000};
        bins walking_ones_36  = {44'b00000001000000000000000000000000000000000000};
        bins walking_ones_37  = {44'b00000010000000000000000000000000000000000000};
        bins walking_ones_38  = {44'b00000100000000000000000000000000000000000000};
        bins walking_ones_39  = {44'b00001000000000000000000000000000000000000000};
        bins walking_ones_40  = {44'b00010000000000000000000000000000000000000000};
        bins walking_ones_41  = {44'b00100000000000000000000000000000000000000000};
        bins walking_ones_42  = {44'b01000000000000000000000000000000000000000000};
        bins walking_ones_43  = {44'b10000000000000000000000000000000000000000000};
    }
`endif

    asid_field_value: coverpoint ins.current.rs1_val {
        `ifdef UDB_MXLEN_32
            wildcard bins all_ones = {32'b?_111111111_??????????????????????};
        `else
            wildcard bins all_ones = {64'b????_1111111111111111_????????????????????????????????????????????};
        `endif
    }
    vmid_field_value: coverpoint ins.current.rs1_val {
        `ifdef UDB_MXLEN_32
            wildcard bins all_ones = {32'b???_1111111_??????????????????????};
        `else
            wildcard bins all_ones = {64'b??????_11111111111111_????????????????????????????????????????????};
        `endif
    }
    // VMID from the previous CSRRW's rs1 (write, then read).
    vmid_field_prev: coverpoint ins.prev.rs1_val {
        `ifdef UDB_MXLEN_32
            wildcard bins all_ones = {32'b???_1111111_??????????????????????};
        `else
            wildcard bins all_ones = {64'b??????_11111111111111_????????????????????????????????????????????};
        `endif
    }

    sum_vsstatus: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "vsstatus", "sum") {
        bins unset = {0};
        bins set = {1};
    }

    mxr_vsstatus: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "vsstatus", "mxr") {
        bins unset = {0};
        bins set = {1};
    }

    vsbe_hstatus: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "hstatus", "vsbe") {
        bins unset = {0};
        bins set = {1};
    }

    tvm_mstatus: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "mstatus", "tvm") {
        bins tvm_set = {1};
        bins tvm_unset = {0};
    }

    mstatus_mprv_set: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "mstatus", "mprv") {
        bins mprv_set = {1};
    }
    mstatus_mprv_unset: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "mstatus", "mprv") {
        bins mprv_unset = {0};
    }
    mprv_mstatus: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "mstatus", "mprv") {
        bins mprv_unset = {0};
        bins mprv_set = {1};
    }

    hgatp_bare: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "hgatp", "mode") {
        bins hgatp_bare = {0};
    }
    vsatp_bare: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "vsatp", "mode") {
        bins satp_bare = {0};
    }
    satp_bare: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "satp", "mode") {
        bins satp_bare = {0};
    }

    `ifdef UDB_MXLEN_32
    // RV32: MPV is mstatush[7]. Use PREV so a trap on this insn does not
    // clear MPV before we sample.
    mstatus_mpv_set: coverpoint ins.prev.csr[CSR_MSTATUSH][7] {
        bins mpv_set = {1};
    }
    mstatus_mpv_unset: coverpoint ins.prev.csr[CSR_MSTATUSH][7] {
        bins mpv_unset = {0};
    }
    `else
    mstatus_mpv_set: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_PREV, "mstatus", "mpv") {
        bins mpv_set = {1};
    }
    mstatus_mpv_unset: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_PREV, "mstatus", "mpv") {
        bins mpv_unset = {0};
    }
    `endif

    mpp_mstatus_m: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_PREV, "mstatus", "mpp") {
        bins m_mode = {2'b11};
    }
    mpp_mstatus_s: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_PREV, "mstatus", "mpp") {
        bins s_mode = {2'b01};
    }
    mpp_mstatus_u: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_PREV, "mstatus", "mpp") {
        bins s_mode = {2'b00};
    }

    vs_pte_xwr111_d: coverpoint ins.current.vs_pte_d[7:0] {
        wildcard bins vs_pte_d = {8'b11??1111};
    }
    vs_pte_xwr100_s_d: coverpoint ins.current.vs_pte_d[7:0] {
        wildcard bins vs_pte_s = {8'b11?01001};
    }
    vs_pte_xwr100_u_d: coverpoint ins.current.vs_pte_d[7:0] {
        wildcard bins vs_pte_u = {8'b11?11001};
    }

    vs_pte_xwr111_u_d: coverpoint ins.current.vs_pte_d[7:0] {
        wildcard bins leaf_pte = {8'b11?11111};
    }
    vs_pte_xwr111_u_i: coverpoint ins.current.vs_pte_i[7:0] {
        wildcard bins leaf_pte = {8'b11?11111};
    }

    vs_pte_i_inv: coverpoint ins.current.vs_pte_i[7:0] {
        wildcard bins invalid_pte = {8'b11??1??0};
    }
    vs_pte_d_inv: coverpoint ins.current.vs_pte_d[7:0] {
        wildcard bins invalid_pte = {8'b11???110};
    }

    vs_pte_legal_xwr_i: coverpoint ins.current.vs_pte_i[7:0] {
        wildcard bins rwx100 = {8'b???00011};
        wildcard bins rwx110 = {8'b???00111};
        wildcard bins rwx001 = {8'b???01001};
        wildcard bins rwx101 = {8'b???01011};
        wildcard bins rwx111 = {8'b???01111};
    }
    vs_pte_legal_xwr_d: coverpoint ins.current.vs_pte_d[7:0] {
        wildcard bins rwx100 = {8'b???00011};
        wildcard bins rwx110 = {8'b???00111};
        wildcard bins rwx001 = {8'b???01001};
        wildcard bins rwx101 = {8'b???01011};
        wildcard bins rwx111 = {8'b???01111};
    }

    vs_pte_nonleaf_lvl0_i: coverpoint ins.current.vs_pte_i[7:0] {
        wildcard bins lvl0_xwr000 = {8'b????0001};
    }
    vs_pte_nonleaf_lvl0_d: coverpoint ins.current.vs_pte_d[7:0] {
        wildcard bins lvl0_xwr000 = {8'b????0001};
    }

    vs_pte_xwr_comb_i: coverpoint ins.current.vs_pte_i[7:0] {
        wildcard bins rwx001_u = {8'b???11001};
        wildcard bins rwx001_s = {8'b???01001};
        wildcard bins rwx111_u = {8'b???11111};
        wildcard bins rwx111_s = {8'b???01111};
    }
    vs_pte_xwr_comb_d: coverpoint ins.current.vs_pte_d[7:0] {
        wildcard bins rwx001_u = {8'b???11001};
        wildcard bins rwx001_s = {8'b???01001};
        wildcard bins rwx111_u = {8'b???11111};
        wildcard bins rwx111_s = {8'b???01111};
    }

    vs_pte_uxwr_perm_i: coverpoint ins.current.vs_pte_i[7:0] {
        wildcard bins urwx0000 = {8'b???00001};
        wildcard bins urwx1000 = {8'b???10001};
        wildcard bins urwx0111 = {8'b???01111};
        wildcard bins urwx1111 = {8'b???11111};
    }
    vs_pte_uxwr_perm_d: coverpoint ins.current.vs_pte_d[7:0] {
        wildcard bins urwx0000 = {8'b???00001};
        wildcard bins urwx1000 = {8'b???10001};
        wildcard bins urwx0111 = {8'b???01111};
        wildcard bins urwx1111 = {8'b???11111};
    }

    // VS data/fetch leaf A/D: 11 = already accessed; 00 = needs update (Svade → page fault).
    vs_pte_ad: coverpoint ins.current.vs_pte_d[7:0] {
        wildcard bins vs_pte_ad_set = {8'b11??1111};
        wildcard bins vs_pte_ad_unset = {8'b00??1111};
    }
    vs_pte_ad_i: coverpoint ins.current.vs_pte_i[7:0] {
        wildcard bins vs_pte_ad_set = {8'b11??1111};
        wildcard bins vs_pte_ad_unset = {8'b00??1111};
    }

    g_pte_xwr100_d: coverpoint ins.current.g_pte_d[7:0] {
        wildcard bins g_pte_xwr100 = {8'b????1001};
    }

    // G PTE that maps VS page-table pages: A=D=0, R/W (no X). Implicit PT walk, not data XWR=111.
    g_pte_ad_unset: coverpoint ins.current.g_pte_d[7:0] {
        wildcard bins g_pte_ad = {8'b00??0111};
    }
    g_pte_ad_unset_i: coverpoint ins.current.g_pte_i[7:0] {
        wildcard bins g_pte_ad = {8'b00??0111};
    }

    g_pte_i_u: coverpoint ins.current.g_pte_i[7:0] {
        wildcard bins g_pte_u_unset = {8'b???01111};
        wildcard bins g_pte_u_set = {8'b???11111};
    }
    g_pte_d_u: coverpoint ins.current.g_pte_d[7:0] {
        wildcard bins g_pte_u_unset = {8'b???01111};
        wildcard bins g_pte_u_set = {8'b???11111};
    }

    g_pte_nonleaf_lvl0_i: coverpoint ins.current.g_pte_i[7:0] {
        wildcard bins lvl0_xwr000 = {8'b????0001};
    }
    g_pte_nonleaf_lvl0_d: coverpoint ins.current.g_pte_d[7:0] {
        wildcard bins lvl0_xwr000 = {8'b????0001};
    }

    g_pte_i_inv: coverpoint ins.current.g_pte_i[7:0] {
        wildcard bins invalid_pte = {8'b11??1??0};
    }
    g_pte_d_inv: coverpoint ins.current.g_pte_d[7:0] {
        wildcard bins invalid_pte = {8'b11???110};
    }

    g_pte_uxwr_perm_i: coverpoint ins.current.g_pte_i[7:0] {
        wildcard bins urwx0000 = {8'b???00001};
        wildcard bins urwx1000 = {8'b???10001};
        wildcard bins urwx0111 = {8'b???01111};
        wildcard bins urwx1111 = {8'b???11111};
    }
    g_pte_uxwr_perm_d: coverpoint ins.current.g_pte_d[7:0] {
        wildcard bins urwx0000 = {8'b???00001};
        wildcard bins urwx1000 = {8'b???10001};
        wildcard bins urwx0111 = {8'b???01111};
        wildcard bins urwx1111 = {8'b???11111};
    }

    g_pte_d_g_set: coverpoint ins.current.g_pte_d[7:0] {
        wildcard bins g_bit_set = {8'b1???1111};
    }
    g_pte_i_g_set: coverpoint ins.current.g_pte_i[7:0] {
        wildcard bins g_bit_set = {8'b1???1111};
    }

    // Execute-only leaf: X=1, R=0, W=0, V=1.
    vs_pte_xonly_d: coverpoint ins.current.vs_pte_d[7:0] {
        wildcard bins xonly = {8'b????1001};
    }
    g_pte_xonly_d: coverpoint ins.current.g_pte_d[7:0] {
        wildcard bins xonly = {8'b????1001};
    }

    // HS sstatus.MXR (used if a cross samples HS MXR).
    mxr_sstatus: coverpoint get_csr_val(ins.hart, ins.issue, `SAMPLE_CURRENT, "sstatus", "mxr") {
        bins unset = {0};
        bins set = {1};
    }

    // lw/sw vs HLV/HSV (HLV/HSV do not follow MPRV).
    acc_lw_sw: coverpoint ins.current.insn {
        wildcard bins lw = {LW};
        wildcard bins sw = {SW};
    }
    acc_hlv_hsv: coverpoint ins.current.insn {
        wildcard bins hlv_w = {HLV_W};
        wildcard bins hsv_w = {HSV_W};
    }

    // Arch gates (Gap Highlighted SvH — do not score RV64-only bins on RV32):
    //   RV64-only: cp_vsatp_mode_field, cp_satp_mode_field, cp_hgatp_gpa_width_checks
    //   RV64 Env:  cp_*_svpbmt, cp_*_reserved_fields (PTE[62:61]/[60:54])
    //   BOTH (diff): cp_hgatp_mode_field — RV64 0..15 walk; RV32 Bare/Sv32x4
    //   BOTH: cp_vsatp_ppn_field, cp_vsatp_asidlen_detect (Sv32 or Sv39)
    `ifdef UDB_MXLEN_64
        // Write vsatp MODE in HS. Test: svh_csr_vsatp_fields_RV64_HSmode.S
        // RV64-only: 16× MODE encodings from Bare/Sv39 starts.
        cp_vsatp_mode_field: cross priv_mode_hs, csrrw, vsatp, mode_field_values;
        // Write satp MODE from VS. Test: svh_csr_satp_mode_VSmode.S
        // RV64-only.
        cp_satp_mode_field:  cross priv_mode_vs, csrrw, satp, mode_field_values;
        // Write hgatp MODE in HS. Test: svh_csr_hgatp_fields_RV64_HSmode.S
        // RV64 16-encoding walk (RV32 Bare/Sv32x4 is the `else` branch).
        cp_hgatp_mode_field: cross priv_mode_hs, csrrw, hgatp, mode_field_values;
    `else
        // RV32 hgatp MODE is 1 bit: Bare / Sv32x4 only (no third MODE encoding).
        // Test: svh_csr_hgatp_fields_HSmode.S
        // Not compiled on RV32: cp_vsatp_mode_field, cp_satp_mode_field.
        mode_field_values_hgatp32: coverpoint ins.current.rs1_val[31] {
            bins bare   = {1'b0};
            bins sv32x4 = {1'b1};
        }
        cp_hgatp_mode_field: cross priv_mode_hs, csrrw, hgatp, mode_field_values_hgatp32;
    `endif

    `ifdef UDB_MXLEN_64
        // PBMT / reserved PTE fields — RV64 Env only (absent from RV32 SvH_cg).

        // VS guest + PBMT bits [62:61]. Test: svh_vs_pte_attr_RV64_VSmode.S
        // Sail: PBMTE=0 and PBMT≠0 → invalid (vmem_pte.sail::pte_is_invalid).
        cp_vsatp_svpbmt_rw: cross priv_mode_vs, vsatp_mode, pbmte_menvcfg, vs_pte_d_svpbmt, read_write_acc;
        cp_vsatp_svpbmt_x:  cross priv_mode_vs, vsatp_mode, pbmte_menvcfg, vs_pte_i_svpbmt, exec_acc;

        // Same on G-stage (HS HLV/HSV). Test: svh_g_pte_attr_RV64_VSmode.S
        cp_hgatp_svpbmt_rw: cross priv_mode_hs, hgatp_mode, pbmte_menvcfg, g_pte_d_svpbmt, read_write_acc;
        cp_hgatp_svpbmt_x:  cross priv_mode_hs, hgatp_mode, pbmte_menvcfg, g_pte_i_svpbmt, exec_acc;

        // VS guest + PTE bits [60:54]. Test: svh_vs_pte_attr_RV64_VSmode.S
        // Sail: reserved ≠ 0 → invalid. Soft-RSW [60:59] when Svrsw60t59b on.
        cp_vsatp_reserved_fields_rw: cross priv_mode_vs, vsatp_mode, vs_pte_d_reserved, read_write_acc;
        cp_vsatp_reserved_fields_x : cross priv_mode_vs, vsatp_mode, vs_pte_i_reserved, exec_acc;

        // Same on G-stage. Test: svh_g_pte_attr_RV64_VSmode.S
        cp_hgatp_reserved_fields_rw : cross priv_mode_hs, hgatp_mode, g_pte_d_reserved, read_write_acc;
        cp_hgatp_reserved_fields_x  : cross priv_mode_hs, hgatp_mode, g_pte_i_reserved, exec_acc;
    `endif

    // BOTH (Sv32 or Sv39). Tests: svh_csr_vsatp_fields_{,RV64_}HSmode.S
    cp_vsatp_ppn_field:      cross priv_mode_hs, vsatp_mode, csrrw, vsatp, ppn_field_values;
    cp_vsatp_asidlen_detect: cross priv_mode_hs, vsatp_mode, csrrw, vsatp, asid_field_value;

    // Write hgatp PPN. Ignore PPN[1:0] and all-ones: Sv*x4 forces those bits 0.
    cp_hgatp_ppn_field:      cross priv_mode_hs, hgatp_mode, csrrw, hgatp, ppn_field_values {
        ignore_bins align0 = binsof(ppn_field_values.walking_ones_0);
        ignore_bins align1 = binsof(ppn_field_values.walking_ones_1);
        ignore_bins all1   = binsof(ppn_field_values.all_ones);
    }
    // Write hgatp VMID in HS. Test: svh_csr_hgatp_fields_*.S
    cp_hgatp_vmidlen_detect: cross priv_mode_hs, hgatp_mode, csrrw, hgatp, vmid_field_value;

    // R/W PTE leaves for MPRV×vsatp (loads only, not execute-only).
    vs_pte_rw_s_d: coverpoint ins.current.vs_pte_d[7:0] {
        wildcard bins rw_s = {8'b11?00111};
    }
    vs_pte_rw_u_d: coverpoint ins.current.vs_pte_d[7:0] {
        wildcard bins rw_u = {8'b11?10111};
    }
    g_pte_rw_d: coverpoint ins.current.g_pte_d[7:0] {
        wildcard bins rw = {8'b????0111};
    }

    // MPRV=1 in M: data translate uses vsatp (as VS or VU). Tests only do lw.
    // Test: svh_mprv_*_Mmode.S
    cp_vsatp_mprv_effects_s: cross priv_mode_m, mstatus_mprv_set, mpp_mstatus_s, vsatp_mode, hgatp_bare, satp_bare, vs_pte_rw_s_d, read_write_acc {
        ignore_bins writes = binsof(read_write_acc.write_acc);
    }
    cp_vsatp_mprv_effects_u: cross priv_mode_m, mstatus_mprv_set, mpp_mstatus_u, vsatp_mode, hgatp_bare, satp_bare, vs_pte_rw_u_d, read_write_acc {
        ignore_bins writes = binsof(read_write_acc.write_acc);
    }
    // MPRV=0: vsatp is not used for this data access.
    cp_vsatp_mprv_effects_off: cross priv_mode_m, mstatus_mprv_unset, vsatp_mode, hgatp_bare, satp_bare, read_write_acc {
        ignore_bins writes = binsof(read_write_acc.write_acc);
    }

    // MPRV=1 × lw as M/HS/VS/U/VU. HLV ignores MPRV (cross below).
    // VS/VU (MPV=1): G-stage is walked. M/HS/U: no G walk.
    cp_hgatp_mprv_effects_m: cross priv_mode_m, mstatus_mprv_set, mpp_mstatus_m, hgatp_mode, acc_lw_sw {
        ignore_bins stores = binsof(acc_lw_sw.sw);
    }
    cp_hgatp_mprv_effects_hs: cross priv_mode_m, mstatus_mprv_set, mpp_mstatus_s, mstatus_mpv_unset, hgatp_mode, acc_lw_sw {
        ignore_bins stores = binsof(acc_lw_sw.sw);
    }
    cp_hgatp_mprv_effects_vs: cross priv_mode_m, mstatus_mprv_set, mpp_mstatus_s, mstatus_mpv_set, hgatp_mode, g_pte_xwr100_d, acc_lw_sw {
        ignore_bins stores = binsof(acc_lw_sw.sw);
    }
    cp_hgatp_mprv_effects_u: cross priv_mode_m, mstatus_mprv_set, mpp_mstatus_u, mstatus_mpv_unset, hgatp_mode, acc_lw_sw {
        ignore_bins stores = binsof(acc_lw_sw.sw);
    }
    cp_hgatp_mprv_effects_vu: cross priv_mode_m, mstatus_mprv_set, mpp_mstatus_u, mstatus_mpv_set, hgatp_mode, g_pte_xwr100_d, acc_lw_sw {
        ignore_bins stores = binsof(acc_lw_sw.sw);
    }
    // HLV/HSV ignore MPRV. R/W G leaf allowed.
    cp_hgatp_mprv_effects_hlv: cross priv_mode_m, mstatus_mprv_set, hgatp_mode, g_pte_rw_d, acc_hlv_hsv {
        ignore_bins hsv = binsof(acc_hlv_hsv.hsv_w);
    }


    // VS data little vs big endian (hstatus.VSBE). Test: svh_vsbe_endian_VSmode.S
    // Hit: 50% RV32 and RV64. LE (VSBE=0) Covered. VSBE=1 ZERO on both reports.
    // Our side: test already writes VSBE=1 — nothing more for us to do.
    // Sail issue: legalize_hstatus in model/core/sys_regs.sail never assigns VSBE
    // ("We don't currently support changing VSBE"); bit stays 0.
    // Sail fix needed: honor VSBE writes in legalize_hstatus and use it for guest
    // data endian in the mem path. Then vsbe_hstatus.set / this cross can hit.
    cp_vsatp_endianess:   cross priv_mode_vs, vsatp_mode, vsbe_hstatus, vs_pte_xwr111_d, read_write_acc;

    // TVM=1 illegal hgatp CSR access. Test: svh_tvm_hgatp_*_HSmode.S
    // Hit: 100% both arch. Our side fixed (test + TRAP in sail_to_rvvi.py).
    cp_hgatp_tvm_effects: cross priv_mode_hs, tvm_mstatus, csrrw, hgatp;

    // RSW bits [9:8] on the leaf. VS guest vs HS HLV/HSV.
    cp_vsatp_pte_rsw: cross priv_mode_vs, vsatp_mode, vs_pte_rsw, read_write_acc;
    cp_hgatp_pte_rsw: cross priv_mode_hs, hgatp_mode, g_pte_rsw, read_write_acc;

    // VS PTE V=0. Test: svh_vsatp_fault_VSmode.S (lw/sw + jalr into V=0).
    // Hit: 100% both. Our side fixed: fetch-fault walks → VS_PTE_I in sail_to_rvvi.py.
    cp_vsatp_invalid_pte_rw: cross priv_mode_vs, vsatp_mode, vs_pte_d_inv, read_write_acc;
    cp_vsatp_invalid_pte_x:  cross priv_mode_vs, vsatp_mode, vs_pte_i_inv, exec_acc;

    // G PTE V=0. _rw = HS HLV/HSV. _x = VS fetch (HS code fetch does not walk hgatp).
    // Test: svh_hgatp_fault_VSmode.S  Hit: 100% both. Same converter fetch-trap fix.
    cp_hgatp_invalid_pte_rw: cross priv_mode_hs, hgatp_mode, g_pte_d_inv, read_write_acc;
    cp_hgatp_invalid_pte_x:  cross priv_mode_vs, hgatp_mode, g_pte_i_inv, exec_acc;

    // SUM + U-page in VS. Test: svh_vs_perm / sum tests.
    cp_vsatp_sum_effects_rw: cross priv_mode_vs, sum_vsstatus, vs_pte_xwr111_u_d, read_write_acc;
    cp_vsatp_sum_effects_x : cross priv_mode_vs, sum_vsstatus, vs_pte_xwr111_u_i, exec_acc;

    // Level-0 PTE is a pointer (V=1, XWR=000), not a leaf. Hit: 100% both.
    // Our side fixed: sail_to_rvvi.py emits nonleaf when the walk has no leaf.
    cp_vsatp_nonleaf_lvl0_rw: cross priv_mode_vs, vsatp_mode, vs_pte_nonleaf_lvl0_d, read_write_acc;
    cp_vsatp_nonleaf_lvl0_x:  cross priv_mode_vs, vsatp_mode, vs_pte_nonleaf_lvl0_i, exec_acc;
    cp_hgatp_nonleaf_lvl0_rw: cross priv_mode_hs, hgatp_mode, g_pte_nonleaf_lvl0_d, read_write_acc;
    cp_hgatp_nonleaf_lvl0_x:  cross priv_mode_hs, hgatp_mode, g_pte_nonleaf_lvl0_i, exec_acc;

    // VS/VU × SUM × MXR × PTE combos. Not cp_two_stage_mxr.
    // Test: svh_vsstatus_mxr_sum_VS/VUmode.S (+ Sv39). Hit: 100% both.
    // Our side fixed: VU tests + fences so .rvvi still has VS_PTE_* (not a Sail gap).
    cp_vsstatus_mxr_sum_rw: cross priv_mode_vs_vu, vsatp_mode, sum_vsstatus, mxr_vsstatus, vs_pte_xwr_comb_d, read_write_acc;
    cp_vsstatus_mxr_sum_x:  cross priv_mode_vs_vu, vsatp_mode, sum_vsstatus, mxr_vsstatus, vs_pte_xwr_comb_i, exec_acc;

    // SUM × legal S-page XWR. Test: svh_vs_perm_*.S  Hit: 100% both. Our side fixed.
    cp_vsatp_spages_sum_rw: cross priv_mode_vs, vsatp_mode, sum_vsstatus, vs_pte_legal_xwr_d, read_write_acc;
    cp_vsatp_spages_sum_x:  cross priv_mode_vs, vsatp_mode, sum_vsstatus, vs_pte_legal_xwr_i, exec_acc;

    // VS/VU permission matrix. Test: svh_vs_perm_VS/VUmode.S (+ Sv39). Hit: 100% both.
    cp_vsatp_perm_checks_rw: cross priv_mode_vs_vu, vsatp_mode, vs_pte_uxwr_perm_d, read_write_acc;
    cp_vsatp_perm_checks_x:  cross priv_mode_vs_vu, vsatp_mode, vs_pte_uxwr_perm_i, exec_acc;

    // G-stage permission matrix. Test: svh_g_perm_VS/VUmode.S  Hit: 100% both.
    cp_hgatp_perm_checks_rw: cross priv_mode_vs_vu, hgatp_mode, g_pte_uxwr_perm_d, read_write_acc;
    cp_hgatp_perm_checks_x:  cross priv_mode_vs_vu, hgatp_mode, g_pte_uxwr_perm_i, exec_acc;

    // G-stage A/D on *implicit* VS page-table walks (not HS HLV on a data leaf).
    // Test: svh_g_adbit_VSmode.S (+ Sv39 twin). VS lw/sw/fetch, ADUE=0 (Svade).
    //   G PTE for VS L0 table: A=D=0 R/W → guest-page (implicit read).
    //   VS leaf A=D=00, G-for-PT A=1 → page fault (VS A/D update).
    // Sail ADUE=1 (menvcfg/henvcfg) would set A/D in memory instead of faulting;
    // this config leaves ADUE=0 so we score the fault half of the coverpoint.
    cp_hgatp_adbit_behavior: cross priv_mode_vs, vsatp_mode, hgatp_mode, g_pte_ad_unset, read_write_acc, trap_set;
    cp_hgatp_adbit_behavior_x: cross priv_mode_vs, vsatp_mode, hgatp_mode, g_pte_ad_unset_i, exec_acc, trap_set;
    cp_hgatp_adbit_vs_ad_rw: cross priv_mode_vs, vsatp_mode, vs_pte_ad, read_write_acc;
    cp_hgatp_adbit_vs_ad_x:  cross priv_mode_vs, vsatp_mode, vs_pte_ad_i, exec_acc;

    // Write then read hgatp VMID. Test: svh_csr_hgatp_fields_*.S
    cp_hgatp_vmid_scoping:   cross priv_mode_hs, hgatp_mode, raw_csrrw_csrr, hgatp, vmid_field_prev;

    // HS + vsatp Bare + G U bit. Test: svh_g_u_bit_HSmode.S
    cp_hgatp_u_mode_access_rw: cross priv_mode_hs, hgatp_mode, vsatp_bare, g_pte_d_u, read_write_acc;
    cp_hgatp_u_mode_access_x:  cross priv_mode_hs, hgatp_mode, vsatp_bare, g_pte_i_u, exec_acc;

    // HS HLV/HSV, G=1 leaf. Test: svh_g_perm / g_u_bit.
    cp_hgatp_pte_g_bit_rw: cross priv_mode_hs, hgatp_mode, g_pte_d_g_set, read_write_acc;
    cp_hgatp_pte_g_bit_x:  cross priv_mode_hs, hgatp_mode, g_pte_i_g_set, exec_acc;


    // Both stages on: VS load / store / fetch. Tests: svh_two_stage_*.S
    two_stage_read:  cross priv_mode_vs, vsatp_mode, hgatp_mode, read_write_acc {
        ignore_bins writes = binsof(read_write_acc.write_acc);
    }
    two_stage_write: cross priv_mode_vs, vsatp_mode, hgatp_mode, read_write_acc {
        ignore_bins reads = binsof(read_write_acc.read_acc);
    }
    two_stage_ifetch: cross priv_mode_vs, vsatp_mode, hgatp_mode, exec_acc;
    // Both Bare. Test: svh_stage_both_bare_VSmode.S
    stage_both_bare: cross priv_mode_vs, vsatp_bare, hgatp_bare, read_write_acc;
    // vsatp on, hgatp Bare.
    cp_hgatp_bare_trans: cross priv_mode_vs, vsatp_mode, hgatp_bare, read_write_acc;
    // Both stages on (G walks VS page tables too).
    cp_h_vm_gstagetrans: cross priv_mode_vs, vsatp_mode, hgatp_mode, read_write_acc;

    // Two-stage load of X-only page. MXR=0 fault, MXR=1 allow. Not cp_vsstatus_mxr_sum.
    // Sheet R43: loads from {VS,VU}. Tests: svh_two_stage_mxr_*_{VS,VU}mode.S (+ Sv39).
    cp_two_stage_mxr: cross priv_mode_vs_vu, vsatp_mode, hgatp_mode, mxr_vsstatus, vs_pte_xonly_d, read_write_acc {
        ignore_bins writes = binsof(read_write_acc.write_acc);
    }

    // More fault / structure / VU two-stage / X-only MXR=0
    trap_set: coverpoint ins.trap {
        bins trapped = {1'b1};
    }

    hfence_vvma_insn: coverpoint ins.current.insn {
        wildcard bins hfence_vvma = {HFENCE_VVMA};
    }
    hfence_gvma_insn: coverpoint ins.current.insn {
        wildcard bins hfence_gvma = {HFENCE_GVMA};
    }

    // Invalid G PTE + trap + load/store/fetch. Test: svh_hgatp_fault_VSmode.S
    // Hit: 100% both. Our side fixed: sail_to_rvvi.py emits TRAP 1 from Sail
    // "trapping from …" (testbench already parsed TRAP).
    hgatp_exception_reporting_rw: cross priv_mode_vs, hgatp_mode, g_pte_d_inv, read_write_acc, trap_set;
    hgatp_exception_reporting_x:  cross priv_mode_vs, hgatp_mode, g_pte_i_inv, exec_acc, trap_set;

    // Two-stage V=0 deny (both stages ON). Test: svh_twostage_invalid_VSmode.S (+ Sv39 twin).
    // lw + sw (separate hops + hfence) so read_acc and write_acc both hit with TRAP.
    // Distinct from cp_*_invalid_pte_* (those allow partner Bare).
    VM_permission_invalid_vs_rw: cross priv_mode_vs, vsatp_mode, hgatp_mode, vs_pte_d_inv, read_write_acc, trap_set;
    VM_permission_invalid_g_rw:  cross priv_mode_vs, vsatp_mode, hgatp_mode, g_pte_d_inv, read_write_acc, trap_set;

    // MPRV+SUM with both stages paged (not Bare-G MPRV). Test: svh_mprv_sum_two_stage_Mmode.S
    mprv_sum_effect_hs_two_stage: cross priv_mode_m, mstatus_mprv_set, sum_vsstatus, vsatp_mode, hgatp_mode, read_write_acc;

    // VU, both stages, U=1 pages. Test: svh_vu_rwx_two_stage_VUmode.S
    rwx_umode_pages_umode_rw: cross priv_mode_vu, vsatp_mode, hgatp_mode, vs_pte_xwr111_u_d, read_write_acc;
    rwx_umode_pages_umode_x:  cross priv_mode_vu, vsatp_mode, hgatp_mode, vs_pte_xwr111_u_i, exec_acc;

    // X-only page, MXR=0, load must fault. HS/VS/VU/G. Not cp_two_stage_mxr.
    // Test: svh_xonly_mxr0_*.S
    xonly_mxr0_vs_hs: cross priv_mode_hs, mxr_vsstatus, vs_pte_xonly_d, read_write_acc {
        ignore_bins mxr1 = binsof(mxr_vsstatus.set);
        ignore_bins writes = binsof(read_write_acc.write_acc);
    }
    xonly_mxr0_vs_vs: cross priv_mode_vs, mxr_vsstatus, vs_pte_xonly_d, read_write_acc {
        ignore_bins mxr1 = binsof(mxr_vsstatus.set);
        ignore_bins writes = binsof(read_write_acc.write_acc);
    }
    xonly_mxr0_vs_vu: cross priv_mode_vu, mxr_vsstatus, vs_pte_xonly_d, read_write_acc {
        ignore_bins mxr1 = binsof(mxr_vsstatus.set);
        ignore_bins writes = binsof(read_write_acc.write_acc);
    }
    xonly_mxr0_g_hs: cross priv_mode_hs, mxr_vsstatus, g_pte_xonly_d, read_write_acc {
        ignore_bins mxr1 = binsof(mxr_vsstatus.set);
        ignore_bins writes = binsof(read_write_acc.write_acc);
    }

    // Bad G superpage / root table. Trap on walk. Test: svh_g_struct_HSmode.S (+ Sv39).
    hgatp_misaligned_superpage: cross priv_mode_hs, hgatp_mode, read_write_acc, trap_set;
    hgatp_root_table_alignment_and_size: cross priv_mode_hs, hgatp_mode, hfence_gvma_insn;

    // RV64: GPA too wide / not canonical. Test: svh_gpa_width_VSmode.S
    `ifdef UDB_MXLEN_64
    cp_hgatp_gpa_width_checks: cross priv_mode_vs, hgatp_mode, read_write_acc, trap_set;
    `endif

    // HFENCE.VVMA / HFENCE.GVMA in HS (illegal in VS/VU). Tests: svh_hfence_*.S
    cp_hfence_functionality: cross priv_mode_hs, hfence_vvma_insn, vsatp_mode;
    cp_hfence_vvma_operand: cross priv_mode_hs, hfence_vvma_insn;
    cp_hgatp_mode_change_hfence: cross priv_mode_hs, hgatp_mode, hfence_gvma_insn;
    cp_hfence_gvma_operand: cross priv_mode_hs, hfence_gvma_insn;



endgroup

function void svh_sample(int hart, int issue, ins_t ins);
    SvH_cg.sample(ins);
endfunction
