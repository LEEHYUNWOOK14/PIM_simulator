module logic_normalization_engine_array #(
    parameter int unsigned ENGINES=4,
    parameter int unsigned BANKS=16,
    parameter int unsigned TAG_WIDTH=16,
    parameter int unsigned BANK_ID_WIDTH=BANKS>1?$clog2(BANKS):1
)(
    input logic clk_i,input logic rst_ni,
    input logic[ENGINES-1:0]begin_valid_i,output logic[ENGINES-1:0]begin_ready_o,
    input logic[ENGINES-1:0]begin_rms_norm_i,
    input logic[ENGINES-1:0][TAG_WIDTH-1:0]begin_tag_i,
    input logic[ENGINES-1:0][BANKS-1:0]begin_expected_bank_mask_i,
    input logic[ENGINES-1:0][15:0]begin_inv_hidden_i,begin_epsilon_i,
    input logic[ENGINES-1:0]partial_valid_i,output logic[ENGINES-1:0]partial_ready_o,
    input logic[ENGINES-1:0][TAG_WIDTH-1:0]partial_tag_i,
    input logic[ENGINES-1:0][BANK_ID_WIDTH-1:0]partial_bank_i,
    input logic[ENGINES-1:0][15:0]partial_sum_i,partial_sumsq_i,
    output logic[ENGINES-1:0]response_valid_o,input logic[ENGINES-1:0]response_ready_i,
    output logic[ENGINES-1:0]response_rms_norm_o,
    output logic[ENGINES-1:0][TAG_WIDTH-1:0]response_tag_o,
    output logic[ENGINES-1:0][15:0]response_mean_o,response_inv_std_o,
    output logic[ENGINES-1:0]response_variance_clamped_o,
    output logic[ENGINES-1:0]duplicate_error_o,context_error_o
);
    for(genvar engine=0;engine<ENGINES;engine++)begin:g_engine
        logic_normalization_reduction_engine #(.BANKS(BANKS),.TAG_WIDTH(TAG_WIDTH))u_engine(
          .clk_i(clk_i),.rst_ni(rst_ni),.begin_valid_i(begin_valid_i[engine]),
          .begin_ready_o(begin_ready_o[engine]),.begin_rms_norm_i(begin_rms_norm_i[engine]),
          .begin_tag_i(begin_tag_i[engine]),.begin_expected_mask_i(begin_expected_bank_mask_i[engine]),
          .begin_inv_hidden_i(begin_inv_hidden_i[engine]),.begin_epsilon_i(begin_epsilon_i[engine]),
          .partial_valid_i(partial_valid_i[engine]),.partial_ready_o(partial_ready_o[engine]),
          .partial_tag_i(partial_tag_i[engine]),.partial_bank_i(partial_bank_i[engine]),
          .partial_sum_i(partial_sum_i[engine]),.partial_sumsq_i(partial_sumsq_i[engine]),
          .response_valid_o(response_valid_o[engine]),.response_ready_i(response_ready_i[engine]),
          .response_rms_norm_o(response_rms_norm_o[engine]),.response_tag_o(response_tag_o[engine]),
          .response_mean_o(response_mean_o[engine]),.response_inv_std_o(response_inv_std_o[engine]),
          .response_variance_clamped_o(response_variance_clamped_o[engine]),
          .duplicate_error_o(duplicate_error_o[engine]),.context_error_o(context_error_o[engine]));
    end
endmodule
