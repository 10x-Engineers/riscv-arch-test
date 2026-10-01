///////////////////////////////////////////
//
// RISC-V Architectural Functional Coverage Covergroups Initialization File
//
// Copyright (C) 2026 Harvey Mudd College, 10x Engineers, UET Lahore, Habib University
//
// SPDX-License-Identifier: Apache-2.0
//
////////////////////////////////////////////////////////////////////////////////////////////////

    SdtrigSm_trig_module_reg_cg = new();       SdtrigSm_trig_module_reg_cg.set_inst_name("obj_SdtrigSm_trig_module_reg");

    `ifdef UDB_SDTRIG_ITRIGGER_SUPPORTED
        SdtrigSm_itrigger_cg = new();          SdtrigSm_itrigger_cg.set_inst_name("obj_SdtrigSm_itrigger");
    `endif

    `ifdef UDB_TDATA3_AVAILABLE
        SdtrigSm_textra_cg = new();            SdtrigSm_textra_cg.set_inst_name("obj_SdtrigSm_textra");
    `endif
