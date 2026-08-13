module hierarchical_normalization_scalar_return_top #(
    parameter int unsigned BANKS=16,LANES=4,SCALAR_ENGINES=8,TAG_WIDTH=16,
    parameter int unsigned COUNT_WIDTH=16,BANK_FIFO_DEPTH=4,CONTEXT_ENTRIES=16
)(
    input logic clk_i,input logic rst_ni,
    input logic config_valid_i,output logic config_ready_o,
    input logic config_rms_norm_i,input logic[TAG_WIDTH-1:0]config_tag_i,
    input logic[BANKS-1:0]config_expected_mask_i,
    input logic[COUNT_WIDTH-1:0]config_vectors_per_bank_i,
    input logic[15:0]config_inv_hidden_i,config_epsilon_i,
    input logic[BANKS-1:0]bank_vector_valid_i,output logic[BANKS-1:0]bank_vector_ready_o,
    input logic[BANKS-1:0][LANES-1:0][15:0]bank_vector_data_i,
    output logic[BANKS-1:0]bank_scalar_valid_o,input logic[BANKS-1:0]bank_scalar_ready_i,
    output logic[BANKS-1:0]bank_scalar_rms_norm_o,
    output logic[BANKS-1:0][TAG_WIDTH-1:0]bank_scalar_tag_o,
    output logic[BANKS-1:0][15:0]bank_scalar_mean_o,bank_scalar_inv_std_o,
    output logic[BANKS-1:0]bank_protocol_error_o,
    output logic tag_mismatch_error_o,unexpected_bank_error_o,invalid_config_error_o,
    output logic allocation_error_o,duplicate_tag_error_o,context_lookup_miss_error_o,
    output logic zero_target_error_o
);
    logic inner_config_valid,inner_config_ready,context_allocate_valid,context_allocate_ready;
    logic scalar_valid,scalar_ready,scalar_mode,scalar_clamp,lookup_hit,lookup_consume;
    logic[TAG_WIDTH-1:0]scalar_tag;logic[15:0]scalar_mean,scalar_inv;
    logic[BANKS-1:0]lookup_mask;
    assign config_ready_o=inner_config_ready&&context_allocate_ready;
    assign inner_config_valid=config_valid_i&&context_allocate_ready;
    assign context_allocate_valid=config_valid_i&&inner_config_ready;

    hierarchical_normalization_streaming_top #(.BANKS(BANKS),.LANES(LANES),
      .SCALAR_ENGINES(SCALAR_ENGINES),.TAG_WIDTH(TAG_WIDTH),.COUNT_WIDTH(COUNT_WIDTH),
      .BANK_FIFO_DEPTH(BANK_FIFO_DEPTH))u_stream(
      .clk_i(clk_i),.rst_ni(rst_ni),.config_valid_i(inner_config_valid),.config_ready_o(inner_config_ready),
      .config_rms_norm_i(config_rms_norm_i),.config_tag_i(config_tag_i),
      .config_expected_mask_i(config_expected_mask_i),.config_vectors_per_bank_i(config_vectors_per_bank_i),
      .config_inv_hidden_i(config_inv_hidden_i),.config_epsilon_i(config_epsilon_i),
      .bank_vector_valid_i(bank_vector_valid_i),.bank_vector_ready_o(bank_vector_ready_o),
      .bank_vector_data_i(bank_vector_data_i),.response_valid_o(scalar_valid),.response_ready_i(scalar_ready),
      .response_rms_norm_o(scalar_mode),.response_tag_o(scalar_tag),.response_mean_o(scalar_mean),
      .response_inv_std_o(scalar_inv),.response_variance_clamped_o(scalar_clamp),
      .bank_protocol_error_o(bank_protocol_error_o),.tag_mismatch_error_o(tag_mismatch_error_o),
      .unexpected_bank_error_o(unexpected_bank_error_o),.invalid_config_error_o(invalid_config_error_o),
      .allocation_error_o(allocation_error_o));

    normalization_row_context_table #(.BANKS(BANKS),.TAG_WIDTH(TAG_WIDTH),.ENTRIES(CONTEXT_ENTRIES))u_context(
      .clk_i(clk_i),.rst_ni(rst_ni),.allocate_valid_i(context_allocate_valid),
      .allocate_ready_o(context_allocate_ready),.allocate_tag_i(config_tag_i),
      .allocate_target_mask_i(config_expected_mask_i),.lookup_valid_i(scalar_valid),
      .lookup_hit_o(lookup_hit),.lookup_tag_i(scalar_tag),.lookup_target_mask_o(lookup_mask),
      .lookup_consume_i(lookup_consume),.duplicate_tag_error_o(duplicate_tag_error_o),
      .lookup_miss_error_o(context_lookup_miss_error_o));

    assign scalar_ready=lookup_hit&&lookup_consume;
    normalization_scalar_broadcast #(.BANKS(BANKS),.TAG_WIDTH(TAG_WIDTH))u_broadcast(
      .clk_i(clk_i),.rst_ni(rst_ni),.input_valid_i(scalar_valid&&lookup_hit),
      .input_ready_o(lookup_consume),.target_mask_i(lookup_mask),.rms_norm_i(scalar_mode),
      .tag_i(scalar_tag),.mean_i(scalar_mean),.inv_std_i(scalar_inv),
      .bank_valid_o(bank_scalar_valid_o),.bank_ready_i(bank_scalar_ready_i),
      .bank_rms_norm_o(bank_scalar_rms_norm_o),.bank_tag_o(bank_scalar_tag_o),
      .bank_mean_o(bank_scalar_mean_o),.bank_inv_std_o(bank_scalar_inv_std_o),
      .zero_target_error_o(zero_target_error_o));
endmodule
