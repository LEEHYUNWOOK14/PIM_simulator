module logic_normalization_scalar_engine_array #(
    parameter int unsigned ENGINES=8,
    parameter int unsigned TAG_WIDTH=16
)(
    input logic clk_i,input logic rst_ni,
    input logic[ENGINES-1:0]request_valid_i,output logic[ENGINES-1:0]request_ready_o,
    input logic[ENGINES-1:0]request_rms_norm_i,
    input logic[ENGINES-1:0][TAG_WIDTH-1:0]request_tag_i,
    input logic[ENGINES-1:0][15:0]request_sum_i,request_sumsq_i,
    input logic[ENGINES-1:0][15:0]request_inv_hidden_i,request_epsilon_i,
    output logic[ENGINES-1:0]response_valid_o,input logic[ENGINES-1:0]response_ready_i,
    output logic[ENGINES-1:0]response_rms_norm_o,
    output logic[ENGINES-1:0][TAG_WIDTH-1:0]response_tag_o,
    output logic[ENGINES-1:0][15:0]response_mean_o,response_inv_std_o,
    output logic[ENGINES-1:0]response_variance_clamped_o
);
    for(genvar e=0;e<ENGINES;e++)begin:g_engine
        logic_normalization_scalar_engine #(.TAG_WIDTH(TAG_WIDTH))u_engine(
          .clk_i(clk_i),.rst_ni(rst_ni),.request_valid_i(request_valid_i[e]),
          .request_ready_o(request_ready_o[e]),.rms_norm_i(request_rms_norm_i[e]),
          .request_tag_i(request_tag_i[e]),.sum_i(request_sum_i[e]),
          .sumsq_i(request_sumsq_i[e]),.inv_hidden_i(request_inv_hidden_i[e]),
          .epsilon_i(request_epsilon_i[e]),.response_valid_o(response_valid_o[e]),
          .response_ready_i(response_ready_i[e]),.response_rms_norm_o(response_rms_norm_o[e]),
          .response_tag_o(response_tag_o[e]),.mean_o(response_mean_o[e]),
          .inv_std_o(response_inv_std_o[e]),.variance_clamped_o(response_variance_clamped_o[e]));
    end
endmodule
