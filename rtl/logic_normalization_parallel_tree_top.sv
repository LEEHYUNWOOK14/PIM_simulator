module logic_normalization_parallel_tree_top #(
    parameter int unsigned BANKS=16,
    parameter int unsigned SCALAR_ENGINES=8,
    parameter int unsigned TAG_WIDTH=16,
    parameter int unsigned LEVELS=$clog2(BANKS),
    parameter int unsigned ENGINE_ID_WIDTH=SCALAR_ENGINES>1?$clog2(SCALAR_ENGINES):1,
    parameter int unsigned OUTSTANDING_WIDTH=$clog2(SCALAR_ENGINES+1)
)(
    input logic clk_i,input logic rst_ni,
    input logic row_valid_i,output logic row_ready_o,
    input logic row_rms_norm_i,input logic[TAG_WIDTH-1:0]row_tag_i,
    input logic[BANKS-1:0]row_bank_mask_i,
    input logic[BANKS-1:0][15:0]row_partial_sum_i,row_partial_sumsq_i,
    input logic[15:0]row_inv_hidden_i,row_epsilon_i,
    output logic response_valid_o,input logic response_ready_i,
    output logic response_rms_norm_o,output logic[TAG_WIDTH-1:0]response_tag_o,
    output logic[15:0]response_mean_o,response_inv_std_o,
    output logic response_variance_clamped_o,
    output logic allocation_error_o
);
    logic[15:0]sum_stage_q[0:LEVELS-1][0:BANKS-1],sumsq_stage_q[0:LEVELS-1][0:BANKS-1];
    logic[15:0]sum_stage_d[0:LEVELS-1][0:BANKS-1],sumsq_stage_d[0:LEVELS-1][0:BANKS-1];
    logic[LEVELS-1:0]valid_pipe_q,mode_pipe_q;
    logic[LEVELS-1:0][TAG_WIDTH-1:0]tag_pipe_q;
    logic[LEVELS-1:0][15:0]invh_pipe_q,eps_pipe_q;
    logic[SCALAR_ENGINES-1:0]e_req_v,e_req_r,e_req_mode,e_rsp_v,e_rsp_r,e_rsp_mode,e_clamp;
    logic[SCALAR_ENGINES-1:0][TAG_WIDTH-1:0]e_req_tag,e_rsp_tag;
    logic[SCALAR_ENGINES-1:0][15:0]e_req_sum,e_req_sumsq,e_req_invh,e_req_eps,e_mean,e_inv;
    logic[ENGINE_ID_WIDTH-1:0]alloc_rr_q,rsp_rr_q,alloc_sel,rsp_sel;
    logic alloc_found,rsp_found,row_fire,response_fire,tree_output_valid;
    logic[OUTSTANDING_WIDTH-1:0]outstanding_q;

    assign response_fire=response_valid_o&&response_ready_i;
    assign row_ready_o=outstanding_q<SCALAR_ENGINES||response_fire;
    assign row_fire=row_valid_i&&row_ready_o;
    assign tree_output_valid=valid_pipe_q[LEVELS-1];

    for(genvar n=0;n<BANKS/2;n++)begin:g_first
      fp16_add u_sum(.lhs_i(row_bank_mask_i[n*2]?row_partial_sum_i[n*2]:16'h0000),
        .rhs_i(row_bank_mask_i[n*2+1]?row_partial_sum_i[n*2+1]:16'h0000),.result_o(sum_stage_d[0][n]));
      fp16_add u_sumsq(.lhs_i(row_bank_mask_i[n*2]?row_partial_sumsq_i[n*2]:16'h0000),
        .rhs_i(row_bank_mask_i[n*2+1]?row_partial_sumsq_i[n*2+1]:16'h0000),.result_o(sumsq_stage_d[0][n]));
    end
    for(genvar l=1;l<LEVELS;l++)begin:g_level
      for(genvar n=0;n<(BANKS>>(l+1));n++)begin:g_node
        fp16_add u_sum(.lhs_i(sum_stage_q[l-1][n*2]),.rhs_i(sum_stage_q[l-1][n*2+1]),.result_o(sum_stage_d[l][n]));
        fp16_add u_sumsq(.lhs_i(sumsq_stage_q[l-1][n*2]),.rhs_i(sumsq_stage_q[l-1][n*2+1]),.result_o(sumsq_stage_d[l][n]));
      end
    end

    always @* begin
      alloc_found=0;alloc_sel='0;
      for(integer off=0;off<SCALAR_ENGINES;off++)begin integer idx;idx=(alloc_rr_q+off)%SCALAR_ENGINES;
        if(!alloc_found&&e_req_r[idx])begin alloc_found=1;alloc_sel=idx[ENGINE_ID_WIDTH-1:0];end
      end
      e_req_v='0;e_req_mode={SCALAR_ENGINES{mode_pipe_q[LEVELS-1]}};
      e_req_tag={SCALAR_ENGINES{tag_pipe_q[LEVELS-1]}};
      e_req_sum={SCALAR_ENGINES{sum_stage_q[LEVELS-1][0]}};
      e_req_sumsq={SCALAR_ENGINES{sumsq_stage_q[LEVELS-1][0]}};
      e_req_invh={SCALAR_ENGINES{invh_pipe_q[LEVELS-1]}};
      e_req_eps={SCALAR_ENGINES{eps_pipe_q[LEVELS-1]}};
      if(tree_output_valid&&alloc_found)e_req_v[alloc_sel]=1;

      rsp_found=0;rsp_sel='0;
      for(integer off=0;off<SCALAR_ENGINES;off++)begin integer idx;idx=(rsp_rr_q+off)%SCALAR_ENGINES;
        if(!rsp_found&&e_rsp_v[idx])begin rsp_found=1;rsp_sel=idx[ENGINE_ID_WIDTH-1:0];end
      end
      response_valid_o=rsp_found;e_rsp_r='0;
      response_rms_norm_o=rsp_found?e_rsp_mode[rsp_sel]:0;
      response_tag_o=rsp_found?e_rsp_tag[rsp_sel]:'0;
      response_mean_o=rsp_found?e_mean[rsp_sel]:'0;
      response_inv_std_o=rsp_found?e_inv[rsp_sel]:'0;
      response_variance_clamped_o=rsp_found?e_clamp[rsp_sel]:0;
      if(rsp_found)e_rsp_r[rsp_sel]=response_ready_i;
    end

    always_ff @(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        valid_pipe_q<='0;mode_pipe_q<='0;tag_pipe_q<='0;invh_pipe_q<='0;eps_pipe_q<='0;
        alloc_rr_q<='0;rsp_rr_q<='0;outstanding_q<='0;allocation_error_o<=0;
      end else begin
        valid_pipe_q[0]<=row_fire;mode_pipe_q[0]<=row_rms_norm_i;tag_pipe_q[0]<=row_tag_i;
        invh_pipe_q[0]<=row_inv_hidden_i;eps_pipe_q[0]<=row_epsilon_i;
        for(integer l=1;l<LEVELS;l++)begin
          valid_pipe_q[l]<=valid_pipe_q[l-1];mode_pipe_q[l]<=mode_pipe_q[l-1];
          tag_pipe_q[l]<=tag_pipe_q[l-1];invh_pipe_q[l]<=invh_pipe_q[l-1];eps_pipe_q[l]<=eps_pipe_q[l-1];
        end
        for(integer l=0;l<LEVELS;l++)for(integer n=0;n<(BANKS>>(l+1));n++)begin
          sum_stage_q[l][n]<=sum_stage_d[l][n];sumsq_stage_q[l][n]<=sumsq_stage_d[l][n];
        end
        allocation_error_o<=tree_output_valid&&!alloc_found;
        if(tree_output_valid&&alloc_found)alloc_rr_q<=alloc_sel+1'b1;
        if(response_fire)rsp_rr_q<=rsp_sel+1'b1;
        case({row_fire,response_fire})
          2'b10:outstanding_q<=outstanding_q+1'b1;
          2'b01:outstanding_q<=outstanding_q-1'b1;
          default:begin end
        endcase
      end
    end

    logic_normalization_scalar_engine_array #(.ENGINES(SCALAR_ENGINES),.TAG_WIDTH(TAG_WIDTH))u_scalars(
      .clk_i(clk_i),.rst_ni(rst_ni),.request_valid_i(e_req_v),.request_ready_o(e_req_r),
      .request_rms_norm_i(e_req_mode),.request_tag_i(e_req_tag),.request_sum_i(e_req_sum),
      .request_sumsq_i(e_req_sumsq),.request_inv_hidden_i(e_req_invh),.request_epsilon_i(e_req_eps),
      .response_valid_o(e_rsp_v),.response_ready_i(e_rsp_r),.response_rms_norm_o(e_rsp_mode),
      .response_tag_o(e_rsp_tag),.response_mean_o(e_mean),.response_inv_std_o(e_inv),
      .response_variance_clamped_o(e_clamp));
`ifndef SYNTHESIS
    initial if(BANKS<2||(BANKS&(BANKS-1))!=0||SCALAR_ENGINES<LEVELS+1)
      $fatal(1,"invalid BANKS or insufficient SCALAR_ENGINES");
`endif
endmodule
