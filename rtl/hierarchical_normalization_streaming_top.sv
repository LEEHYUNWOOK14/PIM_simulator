module hierarchical_normalization_streaming_top #(
    parameter int unsigned BANKS=16,
    parameter int unsigned LANES=4,
    parameter int unsigned SCALAR_ENGINES=8,
    parameter int unsigned TAG_WIDTH=16,
    parameter int unsigned COUNT_WIDTH=16,
    parameter int unsigned BANK_FIFO_DEPTH=4
)(
    input logic clk_i,input logic rst_ni,
    input logic config_valid_i,output logic config_ready_o,
    input logic config_rms_norm_i,input logic[TAG_WIDTH-1:0]config_tag_i,
    input logic[BANKS-1:0]config_expected_mask_i,
    input logic[COUNT_WIDTH-1:0]config_vectors_per_bank_i,
    input logic[15:0]config_inv_hidden_i,config_epsilon_i,
    input logic[BANKS-1:0]bank_vector_valid_i,output logic[BANKS-1:0]bank_vector_ready_o,
    input logic[BANKS-1:0][LANES-1:0][15:0]bank_vector_data_i,
    output logic response_valid_o,input logic response_ready_i,
    output logic response_rms_norm_o,output logic[TAG_WIDTH-1:0]response_tag_o,
    output logic[15:0]response_mean_o,response_inv_std_o,
    output logic response_variance_clamped_o,
    output logic[BANKS-1:0]bank_protocol_error_o,
    output logic tag_mismatch_error_o,unexpected_bank_error_o,
    output logic invalid_config_error_o,allocation_error_o
);
    logic[BANKS-1:0]bank_begin_v,bank_begin_r,bank_result_v,bank_result_r;
    logic[BANKS-1:0][TAG_WIDTH-1:0]bank_result_tag;
    logic[BANKS-1:0][15:0]bank_result_sum,bank_result_sumsq;
    logic barrier_config_ready,config_all_ready,config_fire;
    always @* begin
      config_all_ready=barrier_config_ready;
      for(integer b=0;b<BANKS;b++)
        if(config_expected_mask_i[b]&&!bank_begin_r[b])config_all_ready=0;
      config_ready_o=config_all_ready;
      config_fire=config_valid_i&&config_ready_o;
      bank_begin_v='0;
      for(integer b=0;b<BANKS;b++)bank_begin_v[b]=config_fire&&config_expected_mask_i[b];
    end
    for(genvar b=0;b<BANKS;b++)begin:g_bank
      bank_normalization_multirow_vector_reducer #(.LANES(LANES),.TAG_WIDTH(TAG_WIDTH),
        .COUNT_WIDTH(COUNT_WIDTH),.RESULT_FIFO_DEPTH(BANK_FIFO_DEPTH))u_reducer(
        .clk_i(clk_i),.rst_ni(rst_ni),.begin_valid_i(bank_begin_v[b]),
        .begin_ready_o(bank_begin_r[b]),.begin_tag_i(config_tag_i),
        .begin_vector_count_i(config_vectors_per_bank_i),.vector_valid_i(bank_vector_valid_i[b]),
        .vector_ready_o(bank_vector_ready_o[b]),.vector_data_i(bank_vector_data_i[b]),
        .result_valid_o(bank_result_v[b]),.result_ready_i(bank_result_r[b]),
        .result_tag_o(bank_result_tag[b]),.result_sum_o(bank_result_sum[b]),
        .result_sumsq_o(bank_result_sumsq[b]),.protocol_error_o(bank_protocol_error_o[b]));
    end
    logic_normalization_barrier_tree_top #(.BANKS(BANKS),.SCALAR_ENGINES(SCALAR_ENGINES),
      .TAG_WIDTH(TAG_WIDTH))u_logic(
      .clk_i(clk_i),.rst_ni(rst_ni),.config_valid_i(config_fire),
      .config_ready_o(barrier_config_ready),.config_rms_norm_i(config_rms_norm_i),
      .config_tag_i(config_tag_i),.config_expected_mask_i(config_expected_mask_i),
      .config_inv_hidden_i(config_inv_hidden_i),.config_epsilon_i(config_epsilon_i),
      .bank_valid_i(bank_result_v),.bank_ready_o(bank_result_r),.bank_tag_i(bank_result_tag),
      .bank_sum_i(bank_result_sum),.bank_sumsq_i(bank_result_sumsq),
      .response_valid_o(response_valid_o),.response_ready_i(response_ready_i),
      .response_rms_norm_o(response_rms_norm_o),.response_tag_o(response_tag_o),
      .response_mean_o(response_mean_o),.response_inv_std_o(response_inv_std_o),
      .response_variance_clamped_o(response_variance_clamped_o),
      .tag_mismatch_error_o(tag_mismatch_error_o),.unexpected_bank_error_o(unexpected_bank_error_o),
      .invalid_config_error_o(invalid_config_error_o),.allocation_error_o(allocation_error_o));
endmodule
