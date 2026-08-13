module mixed_precision_bank_reducer4 #(
    parameter int unsigned TAG_WIDTH=16,
    parameter int unsigned COUNT_WIDTH=16
)(
    input logic clk_i,input logic rst_ni,
    input logic begin_valid_i,output logic begin_ready_o,
    input logic[TAG_WIDTH-1:0]begin_tag_i,
    input logic[COUNT_WIDTH-1:0]begin_vector_count_i,
    input logic vector_valid_i,output logic vector_ready_o,
    input logic[3:0][15:0]vector_data_i,
    output logic result_valid_o,input logic result_ready_i,
    output logic[TAG_WIDTH-1:0]result_tag_o,
    output logic[31:0]result_sum_o,result_sumsq_o,
    output logic protocol_error_o
);
    logic busy_q,accepting_q;
    logic[TAG_WIDTH-1:0]tag_q;
    logic[COUNT_WIDTH-1:0]remaining_q;
    logic[2:0]valid_q,last_q;
    logic[3:0][31:0]expanded,square;
    logic[3:0][31:0]x_stage0_q,square_stage0_q;
    logic[1:0][31:0]sum_pair_d,sumsq_pair_d,sum_pair_q,sumsq_pair_q;
    logic[31:0]vector_sum_d,vector_sumsq_d,vector_sum_q,vector_sumsq_q;
    logic[31:0]row_sum_q,row_sumsq_q,accumulated_sum,accumulated_sumsq;
    logic input_fire,input_last;

    assign input_fire=vector_valid_i&&vector_ready_o;
    assign input_last=remaining_q==1;
    assign begin_ready_o=!busy_q&&(!result_valid_o||result_ready_i);
    assign vector_ready_o=accepting_q;
    for(genvar lane=0;lane<4;lane++)begin:g_lane
      bf16_to_fp32 u_expand(.bf16_i(vector_data_i[lane]),.fp32_o(expanded[lane]));
      fp32_mul u_square(.lhs_i(expanded[lane]),.rhs_i(expanded[lane]),.result_o(square[lane]));
    end
    for(genvar pair=0;pair<2;pair++)begin:g_pair
      fp32_add u_sum(.lhs_i(x_stage0_q[pair*2]),.rhs_i(x_stage0_q[pair*2+1]),.result_o(sum_pair_d[pair]));
      fp32_add u_sumsq(.lhs_i(square_stage0_q[pair*2]),.rhs_i(square_stage0_q[pair*2+1]),.result_o(sumsq_pair_d[pair]));
    end
    fp32_add u_vector_sum(.lhs_i(sum_pair_q[0]),.rhs_i(sum_pair_q[1]),.result_o(vector_sum_d));
    fp32_add u_vector_sumsq(.lhs_i(sumsq_pair_q[0]),.rhs_i(sumsq_pair_q[1]),.result_o(vector_sumsq_d));
    fp32_add u_acc_sum(.lhs_i(row_sum_q),.rhs_i(vector_sum_q),.result_o(accumulated_sum));
    fp32_add u_acc_sumsq(.lhs_i(row_sumsq_q),.rhs_i(vector_sumsq_q),.result_o(accumulated_sumsq));

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        busy_q<=0;accepting_q<=0;tag_q<='0;remaining_q<='0;valid_q<='0;last_q<='0;
        x_stage0_q<='0;square_stage0_q<='0;sum_pair_q<='0;sumsq_pair_q<='0;
        vector_sum_q<=0;vector_sumsq_q<=0;row_sum_q<=0;row_sumsq_q<=0;
        result_valid_o<=0;result_tag_o<='0;result_sum_o<=0;result_sumsq_o<=0;protocol_error_o<=0;
      end else begin
        protocol_error_o<=0;
        if(result_valid_o&&result_ready_i)result_valid_o<=0;
        valid_q[0]<=input_fire;last_q[0]<=input_fire&&input_last;
        valid_q[1]<=valid_q[0];last_q[1]<=last_q[0];
        valid_q[2]<=valid_q[1];last_q[2]<=last_q[1];
        if(input_fire)begin x_stage0_q<=expanded;square_stage0_q<=square;end
        if(valid_q[0])begin sum_pair_q<=sum_pair_d;sumsq_pair_q<=sumsq_pair_d;end
        if(valid_q[1])begin vector_sum_q<=vector_sum_d;vector_sumsq_q<=vector_sumsq_d;end
        if(begin_valid_i&&begin_ready_o)begin
          if(begin_vector_count_i==0)protocol_error_o<=1;
          else begin busy_q<=1;accepting_q<=1;tag_q<=begin_tag_i;remaining_q<=begin_vector_count_i;row_sum_q<=0;row_sumsq_q<=0;end
        end
        if(vector_valid_i&&!vector_ready_o)protocol_error_o<=1;
        if(input_fire)begin remaining_q<=remaining_q-1'b1;if(input_last)accepting_q<=0;end
        if(valid_q[2])begin
          row_sum_q<=accumulated_sum;row_sumsq_q<=accumulated_sumsq;
          if(last_q[2])begin
            busy_q<=0;result_valid_o<=1;result_tag_o<=tag_q;
            result_sum_o<=accumulated_sum;result_sumsq_o<=accumulated_sumsq;
          end
        end
      end
    end
endmodule

