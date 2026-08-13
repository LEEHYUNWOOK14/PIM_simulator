module logic_normalization_barrier_tree_top #(
    parameter int unsigned BANKS=16,
    parameter int unsigned SCALAR_ENGINES=8,
    parameter int unsigned TAG_WIDTH=16
)(
    input logic clk_i,input logic rst_ni,
    input logic config_valid_i,output logic config_ready_o,
    input logic config_rms_norm_i,input logic[TAG_WIDTH-1:0]config_tag_i,
    input logic[BANKS-1:0]config_expected_mask_i,
    input logic[15:0]config_inv_hidden_i,config_epsilon_i,
    input logic[BANKS-1:0]bank_valid_i,output logic[BANKS-1:0]bank_ready_o,
    input logic[BANKS-1:0][TAG_WIDTH-1:0]bank_tag_i,
    input logic[BANKS-1:0][15:0]bank_sum_i,bank_sumsq_i,
    output logic response_valid_o,input logic response_ready_i,
    output logic response_rms_norm_o,output logic[TAG_WIDTH-1:0]response_tag_o,
    output logic[15:0]response_mean_o,response_inv_std_o,
    output logic response_variance_clamped_o,
    output logic tag_mismatch_error_o,unexpected_bank_error_o,
    output logic invalid_config_error_o,allocation_error_o
);
    logic row_v,row_r,row_mode;
    logic[TAG_WIDTH-1:0]row_tag;
    logic[BANKS-1:0]row_mask;
    logic[BANKS-1:0][15:0]row_sum,row_sumsq;
    logic[15:0]row_invh,row_eps;
    logic_normalization_bank_barrier #(.BANKS(BANKS),.TAG_WIDTH(TAG_WIDTH))u_barrier(
      .clk_i(clk_i),.rst_ni(rst_ni),.config_valid_i(config_valid_i),.config_ready_o(config_ready_o),
      .config_rms_norm_i(config_rms_norm_i),.config_tag_i(config_tag_i),
      .config_expected_mask_i(config_expected_mask_i),.config_inv_hidden_i(config_inv_hidden_i),
      .config_epsilon_i(config_epsilon_i),.bank_valid_i(bank_valid_i),.bank_ready_o(bank_ready_o),
      .bank_tag_i(bank_tag_i),.bank_sum_i(bank_sum_i),.bank_sumsq_i(bank_sumsq_i),
      .row_valid_o(row_v),.row_ready_i(row_r),.row_rms_norm_o(row_mode),.row_tag_o(row_tag),
      .row_bank_mask_o(row_mask),.row_partial_sum_o(row_sum),.row_partial_sumsq_o(row_sumsq),
      .row_inv_hidden_o(row_invh),.row_epsilon_o(row_eps),
      .tag_mismatch_error_o(tag_mismatch_error_o),.unexpected_bank_error_o(unexpected_bank_error_o),
      .invalid_config_error_o(invalid_config_error_o));
    logic_normalization_parallel_tree_top #(.BANKS(BANKS),.SCALAR_ENGINES(SCALAR_ENGINES),.TAG_WIDTH(TAG_WIDTH))u_tree(
      .clk_i(clk_i),.rst_ni(rst_ni),.row_valid_i(row_v),.row_ready_o(row_r),
      .row_rms_norm_i(row_mode),.row_tag_i(row_tag),.row_bank_mask_i(row_mask),
      .row_partial_sum_i(row_sum),.row_partial_sumsq_i(row_sumsq),
      .row_inv_hidden_i(row_invh),.row_epsilon_i(row_eps),
      .response_valid_o(response_valid_o),.response_ready_i(response_ready_i),
      .response_rms_norm_o(response_rms_norm_o),.response_tag_o(response_tag_o),
      .response_mean_o(response_mean_o),.response_inv_std_o(response_inv_std_o),
      .response_variance_clamped_o(response_variance_clamped_o),.allocation_error_o(allocation_error_o));
endmodule
