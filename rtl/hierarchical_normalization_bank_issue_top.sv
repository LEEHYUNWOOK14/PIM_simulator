module hierarchical_normalization_bank_issue_top #(
    parameter int unsigned BANKS=16,LANES=4,SCALAR_ENGINES=8,TAG_WIDTH=16,
    parameter int unsigned COUNT_WIDTH=16,BANK_FIFO_DEPTH=4,CONTEXT_ENTRIES=16,
    parameter int unsigned DATA_WIDTH=256,KEY_WIDTH=32
)(
    input logic clk_i,input logic rst_ni,
    input logic config_valid_i,output logic config_ready_o,input logic config_rms_norm_i,
    input logic[TAG_WIDTH-1:0]config_tag_i,input logic[BANKS-1:0]config_expected_mask_i,
    input logic[COUNT_WIDTH-1:0]config_vectors_per_bank_i,
    input logic[15:0]config_inv_hidden_i,config_epsilon_i,
    input logic[BANKS-1:0]bank_vector_valid_i,output logic[BANKS-1:0]bank_vector_ready_o,
    input logic[BANKS-1:0][LANES-1:0][15:0]bank_vector_data_i,
    input logic[2:0]gamma_grf_b_index_i,beta_grf_b_index_i,
    output logic[BANKS-1:0]srf_write_valid_o,input logic[BANKS-1:0]srf_write_ready_i,
    output logic[BANKS-1:0][DATA_WIDTH-1:0]srf_write_data_o,
    output logic[BANKS-1:0]command_valid_o,input logic[BANKS-1:0]command_ready_i,
    output logic[BANKS-1:0][31:0]command_o,output logic[BANKS-1:0][1:0]precision_o,
    output logic[BANKS-1:0][KEY_WIDTH-1:0]context_key_o,
    output logic[BANKS-1:0]transaction_done_o,
    output logic[BANKS-1:0]bank_protocol_error_o,
    output logic tag_mismatch_error_o,unexpected_bank_error_o,invalid_config_error_o,
    output logic allocation_error_o,duplicate_tag_error_o,context_lookup_miss_error_o,
    output logic zero_target_error_o
);
    logic[BANKS-1:0]scalar_v,scalar_r,scalar_mode;
    logic[BANKS-1:0][TAG_WIDTH-1:0]scalar_tag;
    logic[BANKS-1:0][15:0]scalar_mean,scalar_inv;
    hierarchical_normalization_scalar_return_top #(.BANKS(BANKS),.LANES(LANES),
      .SCALAR_ENGINES(SCALAR_ENGINES),.TAG_WIDTH(TAG_WIDTH),.COUNT_WIDTH(COUNT_WIDTH),
      .BANK_FIFO_DEPTH(BANK_FIFO_DEPTH),.CONTEXT_ENTRIES(CONTEXT_ENTRIES))u_return(
      .clk_i,.rst_ni,.config_valid_i,.config_ready_o,.config_rms_norm_i,.config_tag_i,
      .config_expected_mask_i,.config_vectors_per_bank_i,.config_inv_hidden_i,.config_epsilon_i,
      .bank_vector_valid_i,.bank_vector_ready_o,.bank_vector_data_i,
      .bank_scalar_valid_o(scalar_v),.bank_scalar_ready_i(scalar_r),
      .bank_scalar_rms_norm_o(scalar_mode),.bank_scalar_tag_o(scalar_tag),
      .bank_scalar_mean_o(scalar_mean),.bank_scalar_inv_std_o(scalar_inv),
      .bank_protocol_error_o,.tag_mismatch_error_o,.unexpected_bank_error_o,.invalid_config_error_o,
      .allocation_error_o,.duplicate_tag_error_o,.context_lookup_miss_error_o,.zero_target_error_o);
    for(genvar b=0;b<BANKS;b++)begin:g_adapter
      bank_normalization_microprogram_adapter #(.DATA_WIDTH(DATA_WIDTH),.TAG_WIDTH(TAG_WIDTH),
        .KEY_WIDTH(KEY_WIDTH))u_adapter(.clk_i,.rst_ni,.scalar_valid_i(scalar_v[b]),
        .scalar_ready_o(scalar_r[b]),.scalar_rms_norm_i(scalar_mode[b]),.scalar_tag_i(scalar_tag[b]),
        .scalar_mean_i(scalar_mean[b]),.scalar_inv_std_i(scalar_inv[b]),
        .gamma_grf_b_index_i,.beta_grf_b_index_i,.srf_write_valid_o(srf_write_valid_o[b]),
        .srf_write_ready_i(srf_write_ready_i[b]),.srf_write_data_o(srf_write_data_o[b]),
        .command_valid_o(command_valid_o[b]),.command_ready_i(command_ready_i[b]),
        .command_o(command_o[b]),.precision_o(precision_o[b]),.context_key_o(context_key_o[b]),
        .transaction_done_o(transaction_done_o[b]));
    end
endmodule
