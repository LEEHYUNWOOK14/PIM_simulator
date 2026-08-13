module hierarchical_normalization_datapath #(
    parameter int unsigned BANKS=4,
    parameter int unsigned TAG_WIDTH=16,
    parameter int unsigned COUNT_WIDTH=16,
    parameter int unsigned DATA_FORMAT=0,
    parameter int unsigned BANK_WIDTH=BANKS>1?$clog2(BANKS):1
)(
    input logic clk_i,input logic rst_ni,
    input logic begin_valid_i,output logic begin_ready_o,
    input logic rms_norm_i,input logic[TAG_WIDTH-1:0]tag_i,
    input logic[BANKS-1:0]expected_bank_mask_i,
    input logic[BANKS-1:0][COUNT_WIDTH-1:0]bank_element_count_i,
    input logic[15:0]inv_hidden_i,input logic[15:0]epsilon_i,
    input logic[BANKS-1:0]reduce_element_valid_i,
    output logic[BANKS-1:0]reduce_element_ready_o,
    input logic[BANKS-1:0][15:0]reduce_element_data_i,
    input logic[BANKS-1:0]apply_element_valid_i,
    output logic[BANKS-1:0]apply_element_ready_o,
    input logic[BANKS-1:0][TAG_WIDTH-1:0]apply_element_tag_i,
    input logic[BANKS-1:0][15:0]apply_x_i,apply_gamma_i,apply_beta_i,
    input logic[BANKS-1:0]apply_last_i,
    output logic[BANKS-1:0]result_valid_o,
    input logic[BANKS-1:0]result_ready_i,
    output logic[BANKS-1:0][TAG_WIDTH-1:0]result_tag_o,
    output logic[BANKS-1:0][15:0]result_data_o,
    output logic[BANKS-1:0]result_last_o,
    output logic scalar_configured_o,
    output logic[15:0]scalar_mean_o,scalar_inv_std_o,
    output logic protocol_error_o
);
    logic mode_q;logic[TAG_WIDTH-1:0]tag_q;logic[BANKS-1:0]mask_q;
    logic[BANKS-1:0]local_begin_ready,local_result_valid,local_result_ready;
    logic[BANKS-1:0][TAG_WIDTH-1:0]local_result_tag;
    logic[BANKS-1:0][15:0]local_sum,local_sumsq;
    logic[BANKS-1:0]local_error,apply_config_ready,apply_error;
    logic logic_begin_ready,partial_valid,partial_ready;
    logic[BANK_WIDTH-1:0]partial_bank;logic[TAG_WIDTH-1:0]partial_tag;
    logic[15:0]partial_sum,partial_sumsq;
    logic norm_valid,norm_ready,norm_mode,norm_clamp,norm_dup,norm_context;
    logic[TAG_WIDTH-1:0]norm_tag;logic[15:0]norm_mean,norm_inv;
    logic all_local_ready,all_apply_ready;integer selected;

    always @* begin
        all_local_ready=1;all_apply_ready=1;
        for(integer b=0;b<BANKS;b=b+1)begin
            if(expected_bank_mask_i[b]&&!local_begin_ready[b])all_local_ready=0;
            if(mask_q[b]&&!apply_config_ready[b])all_apply_ready=0;
        end
    end
    assign begin_ready_o=logic_begin_ready&&all_local_ready&&all_apply_ready;
    for(genvar b=0;b<BANKS;b=b+1)begin:g_bank
        bank_normalization_local_reducer #(.TAG_WIDTH(TAG_WIDTH),.COUNT_WIDTH(COUNT_WIDTH),.DATA_FORMAT(DATA_FORMAT)) u_reduce(
          .clk_i,.rst_ni,.begin_valid_i(begin_valid_i&&begin_ready_o&&expected_bank_mask_i[b]),
          .begin_ready_o(local_begin_ready[b]),.begin_tag_i(tag_i),
          .begin_element_count_i(bank_element_count_i[b]),.element_valid_i(reduce_element_valid_i[b]),
          .element_ready_o(reduce_element_ready_o[b]),.element_data_i(reduce_element_data_i[b]),
          .result_valid_o(local_result_valid[b]),.result_ready_i(local_result_ready[b]),
          .result_tag_o(local_result_tag[b]),.result_sum_o(local_sum[b]),
          .result_sumsq_o(local_sumsq[b]),.protocol_error_o(local_error[b]));
        bank_normalization_apply #(.TAG_WIDTH(TAG_WIDTH),.DATA_FORMAT(DATA_FORMAT)) u_apply(
          .clk_i,.rst_ni,.config_valid_i(norm_valid&&norm_ready&&mask_q[b]),
          .config_ready_o(apply_config_ready[b]),.config_rms_norm_i(norm_mode),
          .config_tag_i(norm_tag),.config_mean_i(norm_mean),.config_inv_std_i(norm_inv),
          .element_valid_i(apply_element_valid_i[b]),.element_ready_o(apply_element_ready_o[b]),
          .element_tag_i(apply_element_tag_i[b]),.element_x_i(apply_x_i[b]),
          .element_gamma_i(apply_gamma_i[b]),.element_beta_i(apply_beta_i[b]),
          .element_last_i(apply_last_i[b]),.result_valid_o(result_valid_o[b]),
          .result_ready_i(result_ready_i[b]),.result_tag_o(result_tag_o[b]),
          .result_data_o(result_data_o[b]),.result_last_o(result_last_o[b]),
          .context_error_o(apply_error[b]));
    end
    always @* begin
        partial_valid=0;partial_bank='0;partial_tag='0;partial_sum=0;partial_sumsq=0;
        local_result_ready='0;selected=-1;
        for(integer b=0;b<BANKS;b=b+1)if(selected<0&&local_result_valid[b])begin
            selected=b;partial_valid=1;partial_bank=b[BANK_WIDTH-1:0];
            partial_tag=local_result_tag[b];partial_sum=local_sum[b];partial_sumsq=local_sumsq[b];
            local_result_ready[b]=partial_ready;
        end
    end
    logic_normalization_reduction_engine #(.BANKS(BANKS),.TAG_WIDTH(TAG_WIDTH),.DATA_FORMAT(DATA_FORMAT)) u_logic(
      .clk_i,.rst_ni,.begin_valid_i(begin_valid_i&&begin_ready_o),.begin_ready_o(logic_begin_ready),
      .begin_rms_norm_i(rms_norm_i),.begin_tag_i(tag_i),.begin_expected_mask_i(expected_bank_mask_i),
      .begin_inv_hidden_i(inv_hidden_i),.begin_epsilon_i(epsilon_i),
      .partial_valid_i(partial_valid),.partial_ready_o(partial_ready),.partial_bank_i(partial_bank),
      .partial_tag_i(partial_tag),.partial_sum_i(partial_sum),.partial_sumsq_i(partial_sumsq),
      .response_valid_o(norm_valid),.response_ready_i(norm_ready),.response_rms_norm_o(norm_mode),
      .response_tag_o(norm_tag),.response_mean_o(norm_mean),.response_inv_std_o(norm_inv),
      .response_variance_clamped_o(norm_clamp),.duplicate_error_o(norm_dup),
      .context_error_o(norm_context));
    assign norm_ready=all_apply_ready;
    assign protocol_error_o=|local_error|| |apply_error||norm_dup||norm_context;
    always_ff @(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin mode_q<=0;tag_q<='0;mask_q<='0;scalar_configured_o<=0;
        scalar_mean_o<=0;scalar_inv_std_o<=0;end
      else begin
        scalar_configured_o<=0;
        if(begin_valid_i&&begin_ready_o)begin mode_q<=rms_norm_i;tag_q<=tag_i;mask_q<=expected_bank_mask_i;end
        if(norm_valid&&norm_ready)begin scalar_configured_o<=1;scalar_mean_o<=norm_mean;scalar_inv_std_o<=norm_inv;end
      end
    end
`ifndef SYNTHESIS
    initial if(DATA_FORMAT>1)$fatal(1,"DATA_FORMAT must be 0 (FP16) or 1 (BF16)");
`endif
endmodule
