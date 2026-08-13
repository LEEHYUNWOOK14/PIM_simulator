module mixed_precision_bank_apply4 #(
    parameter int unsigned TAG_WIDTH=16
)(
    input logic clk_i,input logic rst_ni,
    input logic config_valid_i,output logic config_ready_o,
    input logic config_rms_norm_i,input logic[TAG_WIDTH-1:0]config_tag_i,
    input logic[31:0]config_mean_i,config_inv_std_i,
    input logic vector_valid_i,output logic vector_ready_o,
    input logic[TAG_WIDTH-1:0]vector_tag_i,input logic[3:0][15:0]x_i,gamma_i,beta_i,
    input logic vector_last_i,
    output logic result_valid_o,input logic result_ready_i,
    output logic[TAG_WIDTH-1:0]result_tag_o,output logic[3:0][15:0]result_data_o,
    output logic result_last_o,output logic context_error_o
);
    logic active_q,mode_q,advance;
    logic[TAG_WIDTH-1:0]tag_q;
    logic[31:0]mean_q,inv_q;
    logic[3:0]valid_q,last_q;
    logic[3:0]mode_pipe_q;
    logic[3:0][TAG_WIDTH-1:0]pipe_tag_q;
    logic[3:0][31:0]x32,gamma32,beta32,centered_d,centered_q,normalized_d,normalized_q,scaled_d,scaled_q,shifted_d,shifted_q;
    logic[3:0][31:0]gamma_stage0_q,beta_stage0_q,gamma_stage1_q,beta_stage1_q,beta_stage2_q;
    logic[31:0]inv_stage0_q;
    logic[3:0][15:0]narrowed;
    assign advance=!valid_q[3]||result_ready_i;
    assign config_ready_o=!active_q&&advance;
    assign vector_ready_o=active_q&&vector_tag_i==tag_q&&advance;
    assign result_valid_o=valid_q[3];assign result_tag_o=pipe_tag_q[3];assign result_last_o=last_q[3];assign result_data_o=narrowed;
    for(genvar lane=0;lane<4;lane++)begin:g_lane
      bf16_to_fp32 u_x(.bf16_i(x_i[lane]),.fp32_o(x32[lane]));
      bf16_to_fp32 u_g(.bf16_i(gamma_i[lane]),.fp32_o(gamma32[lane]));
      bf16_to_fp32 u_b(.bf16_i(beta_i[lane]),.fp32_o(beta32[lane]));
      fp32_add u_center(.lhs_i(x32[lane]),.rhs_i({~mean_q[31],mean_q[30:0]}),.result_o(centered_d[lane]));
      fp32_mul u_norm(.lhs_i(centered_q[lane]),.rhs_i(inv_stage0_q),.result_o(normalized_d[lane]));
      fp32_mul u_scale(.lhs_i(normalized_q[lane]),.rhs_i(gamma_stage1_q[lane]),.result_o(scaled_d[lane]));
      fp32_add u_shift(.lhs_i(scaled_q[lane]),.rhs_i(mode_pipe_q[2]?32'h00000000:beta_stage2_q[lane]),.result_o(shifted_d[lane]));
      fp32_to_bf16_rne u_narrow(.fp32_i(shifted_q[lane]),.bf16_o(narrowed[lane]));
    end
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin active_q<=0;mode_q<=0;tag_q<=0;mean_q<=0;inv_q<=0;valid_q<=0;last_q<=0;mode_pipe_q<=0;pipe_tag_q<=0;centered_q<=0;normalized_q<=0;scaled_q<=0;shifted_q<=0;gamma_stage0_q<=0;beta_stage0_q<=0;gamma_stage1_q<=0;beta_stage1_q<=0;beta_stage2_q<=0;inv_stage0_q<=0;context_error_o<=0;end
      else begin
        context_error_o<=0;
        if(config_valid_i&&config_ready_o)begin active_q<=1;mode_q<=config_rms_norm_i;tag_q<=config_tag_i;mean_q<=config_rms_norm_i?0:config_mean_i;inv_q<=config_inv_std_i;end
        if(vector_valid_i&&(!active_q||vector_tag_i!=tag_q))context_error_o<=1;
        if(advance)begin
          valid_q[0]<=vector_valid_i&&vector_ready_o;valid_q[1]<=valid_q[0];valid_q[2]<=valid_q[1];valid_q[3]<=valid_q[2];
          last_q[0]<=vector_valid_i&&vector_ready_o&&vector_last_i;last_q[1]<=last_q[0];last_q[2]<=last_q[1];last_q[3]<=last_q[2];
          mode_pipe_q[0]<=mode_q;mode_pipe_q[1]<=mode_pipe_q[0];mode_pipe_q[2]<=mode_pipe_q[1];mode_pipe_q[3]<=mode_pipe_q[2];
          pipe_tag_q[0]<=vector_tag_i;pipe_tag_q[1]<=pipe_tag_q[0];pipe_tag_q[2]<=pipe_tag_q[1];pipe_tag_q[3]<=pipe_tag_q[2];
          if(vector_valid_i&&vector_ready_o)begin centered_q<=centered_d;gamma_stage0_q<=gamma32;beta_stage0_q<=beta32;inv_stage0_q<=inv_q;end
          if(valid_q[0])begin normalized_q<=normalized_d;gamma_stage1_q<=gamma_stage0_q;beta_stage1_q<=beta_stage0_q;end
          if(valid_q[1])begin scaled_q<=scaled_d;beta_stage2_q<=beta_stage1_q;end
          if(valid_q[2])shifted_q<=shifted_d;
          if(vector_valid_i&&vector_ready_o&&vector_last_i)active_q<=0;
        end
      end
    end
endmodule
