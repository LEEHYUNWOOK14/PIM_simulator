module hierarchical_normalization_bank_core_top #(
    parameter int unsigned BANKS=16,LANES=4,SCALAR_ENGINES=8,TAG_WIDTH=16,
    parameter int unsigned COUNT_WIDTH=16,BANK_FIFO_DEPTH=4,CONTEXT_ENTRIES=16,
    parameter int unsigned RESULT_TRACKER_ENTRIES=CONTEXT_ENTRIES,
    parameter int unsigned DATA_WIDTH=256,KEY_WIDTH=32
)(
    input logic clk_i,input logic rst_ni,
    input logic config_valid_i,output logic config_ready_o,input logic config_rms_norm_i,
    input logic[TAG_WIDTH-1:0]config_tag_i,input logic[BANKS-1:0]config_expected_mask_i,
    input logic[COUNT_WIDTH-1:0]config_vectors_per_bank_i,
    input logic[15:0]config_inv_hidden_i,config_epsilon_i,
    input logic[BANKS-1:0]bank_vector_valid_i,output logic[BANKS-1:0]bank_vector_ready_o,
    input logic[BANKS-1:0][LANES-1:0][15:0]bank_vector_data_i,
    input logic[BANKS-1:0][DATA_WIDTH-1:0]activation_data_i,
    input logic[BANKS-1:0]activation_valid_i,
    input logic[BANKS-1:0]grf_write_valid_i,input logic[BANKS-1:0][2:0]grf_write_index_i,
    input logic[BANKS-1:0][DATA_WIDTH-1:0]grf_write_data_i,
    input logic[2:0]gamma_grf_b_index_i,beta_grf_b_index_i,
    output logic[BANKS-1:0]result_valid_o,input logic[BANKS-1:0]result_ready_i,
    output logic[BANKS-1:0][KEY_WIDTH-1:0]result_key_o,
    output logic[BANKS-1:0][2:0]result_destination_o,
    output logic[BANKS-1:0][3:0]result_index_o,
    output logic[BANKS-1:0][DATA_WIDTH-1:0]result_data_o,
    output logic[BANKS-1:0]transaction_done_o,command_error_o,bank_protocol_error_o,
    output logic row_completion_valid_o,input logic row_completion_ready_i,
    output logic[TAG_WIDTH-1:0]row_completion_tag_o,
    output logic tag_mismatch_error_o,unexpected_bank_error_o,invalid_config_error_o,
    output logic allocation_error_o,duplicate_tag_error_o,context_lookup_miss_error_o,
    output logic zero_target_error_o,final_result_unknown_tag_error_o,
    output logic duplicate_final_result_error_o
);
`include "rtl/pim_rtl_constants.svh"
    logic[BANKS-1:0]srf_v,cmd_v,cmd_r;
    logic[BANKS-1:0][DATA_WIDTH-1:0]srf_data;
    logic[BANKS-1:0][31:0]cmd;logic[BANKS-1:0][1:0]precision;
    logic[BANKS-1:0][KEY_WIDTH-1:0]context_key;
    logic issue_config_valid,issue_config_ready,tracker_allocate_valid,tracker_allocate_ready;
    logic issue_duplicate_tag_error,issue_zero_target_error,tracker_duplicate_tag_error;
    logic tracker_zero_mask_error;
    logic[BANKS-1:0]core_result_valid,core_result_ready,final_result_valid,tracker_result_ready;
    logic[BANKS-1:0][KEY_WIDTH-1:0]core_result_key;
    logic[BANKS-1:0][2:0]core_result_destination;
    logic[BANKS-1:0][3:0]core_result_index;
    logic[BANKS-1:0][DATA_WIDTH-1:0]core_result_data;
    logic[BANKS-1:0][TAG_WIDTH-1:0]final_result_tag;
    assign config_ready_o=issue_config_ready&&tracker_allocate_ready;
    assign issue_config_valid=config_valid_i&&tracker_allocate_ready;
    assign tracker_allocate_valid=config_valid_i&&issue_config_ready;
    assign duplicate_tag_error_o=issue_duplicate_tag_error||tracker_duplicate_tag_error;
    assign zero_target_error_o=issue_zero_target_error||tracker_zero_mask_error;
    hierarchical_normalization_bank_issue_top #(.BANKS(BANKS),.LANES(LANES),
      .SCALAR_ENGINES(SCALAR_ENGINES),.TAG_WIDTH(TAG_WIDTH),.COUNT_WIDTH(COUNT_WIDTH),
      .BANK_FIFO_DEPTH(BANK_FIFO_DEPTH),.CONTEXT_ENTRIES(CONTEXT_ENTRIES),
      .DATA_WIDTH(DATA_WIDTH),.KEY_WIDTH(KEY_WIDTH))u_issue(
      .clk_i,.rst_ni,.config_valid_i(issue_config_valid),.config_ready_o(issue_config_ready),.config_rms_norm_i,.config_tag_i,
      .config_expected_mask_i,.config_vectors_per_bank_i,.config_inv_hidden_i,.config_epsilon_i,
      .bank_vector_valid_i,.bank_vector_ready_o,.bank_vector_data_i,.gamma_grf_b_index_i,
      .beta_grf_b_index_i,.srf_write_valid_o(srf_v),.srf_write_ready_i({BANKS{1'b1}}),
      .srf_write_data_o(srf_data),.command_valid_o(cmd_v),.command_ready_i(cmd_r),
      .command_o(cmd),.precision_o(precision),.context_key_o(context_key),.transaction_done_o,
      .bank_protocol_error_o,.tag_mismatch_error_o,.unexpected_bank_error_o,.invalid_config_error_o,
      .allocation_error_o,.duplicate_tag_error_o(issue_duplicate_tag_error),.context_lookup_miss_error_o,
      .zero_target_error_o(issue_zero_target_error));
    normalization_bank_result_tracker #(.BANKS(BANKS),.TAG_WIDTH(TAG_WIDTH),
      .ENTRIES(RESULT_TRACKER_ENTRIES))u_result_tracker(
      .clk_i,.rst_ni,.allocate_valid_i(tracker_allocate_valid),.allocate_ready_o(tracker_allocate_ready),
      .allocate_tag_i(config_tag_i),.allocate_expected_mask_i(config_expected_mask_i),
      .bank_result_valid_i(final_result_valid),.bank_result_ready_o(tracker_result_ready),
      .bank_result_tag_i(final_result_tag),.completion_valid_o(row_completion_valid_o),
      .completion_ready_i(row_completion_ready_i),.completion_tag_o(row_completion_tag_o),
      .duplicate_tag_error_o(tracker_duplicate_tag_error),
      .unknown_tag_error_o(final_result_unknown_tag_error_o),
      .duplicate_bank_error_o(duplicate_final_result_error_o),
      .zero_mask_error_o(tracker_zero_mask_error));
    for(genvar b=0;b<BANKS;b++)begin:g_core
      assign result_valid_o[b]=core_result_valid[b];
      assign result_key_o[b]=core_result_key[b];
      assign result_destination_o[b]=core_result_destination[b];
      assign result_index_o[b]=core_result_index[b];
      assign result_data_o[b]=core_result_data[b];
      assign final_result_valid[b]=core_result_valid[b]&&(core_result_destination[b]==PIM_OPD_M_OUT)&&result_ready_i[b];
      assign final_result_tag[b]=core_result_key[b][TAG_WIDTH-1:0];
      assign core_result_ready[b]=result_ready_i[b]&&
        ((core_result_destination[b]!=PIM_OPD_M_OUT)||tracker_result_ready[b]);
      bank_pim_core #(.DATA_WIDTH(DATA_WIDTH),.KEY_WIDTH(KEY_WIDTH))u_core(
        .clk_i,.rst_ni,.command_valid_i(cmd_v[b]),.command_ready_o(cmd_r[b]),.command_i(cmd[b]),
        .precision_i(precision[b]),.context_key_i(context_key[b]),.even_bank_data_i(activation_data_i[b]),
        .odd_bank_data_i('0),.even_bank_valid_i(activation_valid_i[b]),.odd_bank_valid_i(1'b0),
        .register_write_valid_i(grf_write_valid_i[b]),.register_write_bank_i(1'b1),
        .register_write_index_i(grf_write_index_i[b]),.register_write_data_i(grf_write_data_i[b]),
        .srf_write_valid_i(srf_v[b]),.srf_write_data_i(srf_data[b]),.result_valid_o(core_result_valid[b]),
        .result_ready_i(core_result_ready[b]),.result_key_o(core_result_key[b]),
        .result_destination_o(core_result_destination[b]),.result_index_o(core_result_index[b]),
        .result_data_o(core_result_data[b]),.command_error_o(command_error_o[b]));
    end
endmodule
