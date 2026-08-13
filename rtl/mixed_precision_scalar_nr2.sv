module mixed_precision_scalar_nr2 #(
    parameter int unsigned TAG_WIDTH=16
)(
    input logic clk_i,input logic rst_ni,
    input logic request_valid_i,output logic request_ready_o,
    input logic request_rms_norm_i,input logic[TAG_WIDTH-1:0]request_tag_i,
    input logic[31:0]sum_i,sumsq_i,inv_hidden_i,epsilon_i,
    output logic response_valid_o,input logic response_ready_i,
    output logic response_rms_norm_o,output logic[TAG_WIDTH-1:0]response_tag_o,
    output logic[31:0]mean_o,inv_std_o,output logic variance_clamped_o
);
    typedef enum logic[3:0]{IDLE,VARIANCE,EPSILON,LUT_SEND,LUT_WAIT,NR_SQUARE,NR_XYY,NR_HALF,NR_CORRECTION,NR_UPDATE}state_t;
    state_t state_q;
    logic mode_q,clamped_q,iteration_q;
    logic[TAG_WIDTH-1:0]tag_q;
    logic[31:0]epsilon_q,mean_q,mean_square_q,variance_q,argument_q,y_q,yy_q,xyy_q,half_q,correction_q;
    logic[31:0]input_mean,input_mean_square,mean_squared,variance_raw,epsilon_result;
    logic[31:0]yy_d,xyy_d,half_d,correction_d,y_next;
    logic[15:0]argument_bf16,lut_output_bf16;logic[31:0]lut_output_fp32;
    logic lut_input_valid,lut_input_ready,lut_output_valid,lut_output_ready;
    fp32_mul u_mean(.lhs_i(sum_i),.rhs_i(inv_hidden_i),.result_o(input_mean));
    fp32_mul u_mean_square(.lhs_i(sumsq_i),.rhs_i(inv_hidden_i),.result_o(input_mean_square));
    fp32_mul u_square_mean(.lhs_i(mean_q),.rhs_i(mean_q),.result_o(mean_squared));
    fp32_add u_variance(.lhs_i(mean_square_q),.rhs_i({~mean_squared[31],mean_squared[30:0]}),.result_o(variance_raw));
    fp32_add u_epsilon(.lhs_i(variance_q),.rhs_i(epsilon_q),.result_o(epsilon_result));
    fp32_mul u_yy(.lhs_i(y_q),.rhs_i(y_q),.result_o(yy_d));
    fp32_mul u_xyy(.lhs_i(argument_q),.rhs_i(yy_q),.result_o(xyy_d));
    fp32_mul u_half(.lhs_i(32'h3f000000),.rhs_i(xyy_q),.result_o(half_d));
    fp32_add u_correction(.lhs_i(32'h3fc00000),.rhs_i({~half_q[31],half_q[30:0]}),.result_o(correction_d));
    fp32_mul u_update(.lhs_i(y_q),.rhs_i(correction_q),.result_o(y_next));
    fp32_to_bf16_rne u_arg_narrow(.fp32_i(argument_q),.bf16_o(argument_bf16));
    bf16_to_fp32 u_seed_expand(.bf16_i(lut_output_bf16),.fp32_o(lut_output_fp32));
    assign lut_input_valid=state_q==LUT_SEND;
    assign lut_output_ready=state_q==LUT_WAIT;
    bf16_rsqrt_lut256 u_lut(.clk_i,.rst_ni,.input_valid_i(lut_input_valid),.input_ready_o(lut_input_ready),.input_data_i(argument_bf16),.output_valid_o(lut_output_valid),.output_ready_i(lut_output_ready),.output_data_o(lut_output_bf16));
    assign request_ready_o=state_q==IDLE&&(!response_valid_o||response_ready_i);
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        state_q<=IDLE;mode_q<=0;clamped_q<=0;iteration_q<=0;tag_q<=0;epsilon_q<=0;mean_q<=0;mean_square_q<=0;variance_q<=0;argument_q<=0;y_q<=0;yy_q<=0;xyy_q<=0;half_q<=0;correction_q<=0;
        response_valid_o<=0;response_rms_norm_o<=0;response_tag_o<=0;mean_o<=0;inv_std_o<=0;variance_clamped_o<=0;
      end else begin
        if(response_valid_o&&response_ready_i)response_valid_o<=0;
        case(state_q)
          IDLE:if(request_valid_i&&request_ready_o)begin
            mode_q<=request_rms_norm_i;tag_q<=request_tag_i;epsilon_q<=epsilon_i;
            mean_q<=request_rms_norm_i?32'h00000000:input_mean;mean_square_q<=input_mean_square;
            clamped_q<=0;iteration_q<=0;state_q<=VARIANCE;
          end
          VARIANCE:begin
            if(!mode_q&&variance_raw[31]&&|variance_raw[30:0])begin variance_q<=0;clamped_q<=1;end
            else variance_q<=mode_q?mean_square_q:variance_raw;
            state_q<=EPSILON;
          end
          EPSILON:begin argument_q<=epsilon_result;state_q<=LUT_SEND;end
          LUT_SEND:if(lut_input_ready)state_q<=LUT_WAIT;
          LUT_WAIT:if(lut_output_valid)begin y_q<=lut_output_fp32;state_q<=NR_SQUARE;end
          NR_SQUARE:begin yy_q<=yy_d;state_q<=NR_XYY;end
          NR_XYY:begin xyy_q<=xyy_d;state_q<=NR_HALF;end
          NR_HALF:begin half_q<=half_d;state_q<=NR_CORRECTION;end
          NR_CORRECTION:begin correction_q<=correction_d;state_q<=NR_UPDATE;end
          NR_UPDATE:begin
            if(!iteration_q)begin y_q<=y_next;iteration_q<=1;state_q<=NR_SQUARE;end
            else if(!response_valid_o||response_ready_i)begin
              response_valid_o<=1;response_rms_norm_o<=mode_q;response_tag_o<=tag_q;
              mean_o<=mean_q;inv_std_o<=y_next;variance_clamped_o<=clamped_q;state_q<=IDLE;
            end
          end
          default:state_q<=IDLE;
        endcase
      end
    end
endmodule

