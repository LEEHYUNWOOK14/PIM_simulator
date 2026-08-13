module mixed_precision_normalization_datapath_c11 #(
    parameter int unsigned BANKS=16,LANES=4,TAG_WIDTH=16,COUNT_WIDTH=16
)(
    input logic clk_i,input logic rst_ni,
    input logic begin_valid_i,output logic begin_ready_o,input logic rms_norm_i,input logic[TAG_WIDTH-1:0]tag_i,
    input logic[COUNT_WIDTH-1:0]vectors_per_bank_i,input logic[31:0]inv_hidden_i,epsilon_i,
    input logic[BANKS-1:0]reduce_valid_i,output logic[BANKS-1:0]reduce_ready_o,input logic[BANKS-1:0][LANES-1:0][15:0]reduce_data_i,
    input logic[BANKS-1:0]apply_valid_i,output logic[BANKS-1:0]apply_ready_o,input logic[BANKS-1:0][TAG_WIDTH-1:0]apply_tag_i,
    input logic[BANKS-1:0][LANES-1:0][15:0]apply_x_i,apply_gamma_i,apply_beta_i,input logic[BANKS-1:0]apply_last_i,
    output logic[BANKS-1:0]result_valid_o,input logic[BANKS-1:0]result_ready_i,output logic[BANKS-1:0][TAG_WIDTH-1:0]result_tag_o,
    output logic[BANKS-1:0][LANES-1:0][15:0]result_data_o,output logic[BANKS-1:0]result_last_o,
    output logic scalar_configured_o,output logic[31:0]scalar_mean_o,scalar_inv_std_o,output logic protocol_error_o
);
  initial begin if(BANKS!=16)$fatal(1,"C11 global reducer requires BANKS=16");if(LANES!=4)$fatal(1,"C11 bank datapath requires LANES=4");end
  logic mode_q;logic[TAG_WIDTH-1:0]tag_q;
  logic[BANKS-1:0]local_begin_ready,local_valid,local_ready,local_error,apply_config_ready,apply_error;
  logic[BANKS-1:0][TAG_WIDTH-1:0]local_tag;logic[BANKS-1:0][31:0]local_sum,local_sumsq;
  logic global_valid,global_ready,global_out_valid,global_out_ready;logic[TAG_WIDTH-1:0]global_tag,global_out_tag;logic[31:0]global_sum,global_sumsq;
  logic scalar_valid,scalar_ready,scalar_mode,scalar_clamped;logic[TAG_WIDTH-1:0]scalar_tag;logic[31:0]scalar_mean,scalar_inv;
  logic all_local_begin_ready,all_apply_config_ready;
  always@*begin all_local_begin_ready=&local_begin_ready;all_apply_config_ready=&apply_config_ready;end
  assign begin_ready_o=all_local_begin_ready;
  for(genvar bank=0;bank<BANKS;bank++)begin:g_bank
    mixed_precision_bank_reducer4_interleaved #(.TAG_WIDTH(TAG_WIDTH),.COUNT_WIDTH(COUNT_WIDTH))u_reduce(
      .clk_i,.rst_ni,.begin_valid_i(begin_valid_i&&begin_ready_o),.begin_ready_o(local_begin_ready[bank]),.begin_tag_i(tag_i),.begin_vector_count_i(vectors_per_bank_i),
      .vector_valid_i(reduce_valid_i[bank]),.vector_ready_o(reduce_ready_o[bank]),.vector_data_i(reduce_data_i[bank]),.result_valid_o(local_valid[bank]),
      .result_ready_i(local_ready[bank]),.result_tag_o(local_tag[bank]),.result_sum_o(local_sum[bank]),.result_sumsq_o(local_sumsq[bank]),.protocol_error_o(local_error[bank]));
    mixed_precision_bank_apply4_pipe #(.TAG_WIDTH(TAG_WIDTH))u_apply(
      .clk_i,.rst_ni,.config_valid_i(scalar_valid&&scalar_ready),.config_ready_o(apply_config_ready[bank]),.config_rms_norm_i(scalar_mode),.config_tag_i(scalar_tag),
      .config_mean_i(scalar_mean),.config_inv_std_i(scalar_inv),.vector_valid_i(apply_valid_i[bank]),.vector_ready_o(apply_ready_o[bank]),.vector_tag_i(apply_tag_i[bank]),
      .x_i(apply_x_i[bank]),.gamma_i(apply_gamma_i[bank]),.beta_i(apply_beta_i[bank]),.vector_last_i(apply_last_i[bank]),.result_valid_o(result_valid_o[bank]),
      .result_ready_i(result_ready_i[bank]),.result_tag_o(result_tag_o[bank]),.result_data_o(result_data_o[bank]),.result_last_o(result_last_o[bank]),.context_error_o(apply_error[bank]));
  end
  assign global_valid=&local_valid;assign global_tag=local_tag[0];assign local_ready={BANKS{global_ready&&global_valid}};
  mixed_precision_global_reducer16_pipe #(.TAG_WIDTH(TAG_WIDTH))u_global(.clk_i,.rst_ni,.input_valid_i(global_valid),.input_ready_o(global_ready),.input_tag_i(global_tag),
    .partial_sum_i(local_sum),.partial_sumsq_i(local_sumsq),.output_valid_o(global_out_valid),.output_ready_i(global_out_ready),.output_tag_o(global_out_tag),.sum_o(global_sum),.sumsq_o(global_sumsq));
  mixed_precision_scalar_nr2_pipe #(.TAG_WIDTH(TAG_WIDTH))u_scalar(.clk_i,.rst_ni,.request_valid_i(global_out_valid),.request_ready_o(global_out_ready),.request_rms_norm_i(mode_q),
    .request_tag_i(global_out_tag),.sum_i(global_sum),.sumsq_i(global_sumsq),.inv_hidden_i(inv_hidden_i),.epsilon_i(epsilon_i),.response_valid_o(scalar_valid),
    .response_ready_i(scalar_ready),.response_rms_norm_o(scalar_mode),.response_tag_o(scalar_tag),.mean_o(scalar_mean),.inv_std_o(scalar_inv),.variance_clamped_o(scalar_clamped));
  assign scalar_ready=all_apply_config_ready;
  assign protocol_error_o=|local_error|| |apply_error||(global_valid&&(|(local_tag^{BANKS{local_tag[0]}})));
  always_ff@(posedge clk_i or negedge rst_ni)begin
    if(!rst_ni)begin mode_q<=0;tag_q<=0;scalar_configured_o<=0;scalar_mean_o<=0;scalar_inv_std_o<=0;end
    else begin scalar_configured_o<=0;if(begin_valid_i&&begin_ready_o)begin mode_q<=rms_norm_i;tag_q<=tag_i;end
      if(scalar_valid&&scalar_ready)begin scalar_configured_o<=1;scalar_mean_o<=scalar_mean;scalar_inv_std_o<=scalar_inv;end end
  end
endmodule
