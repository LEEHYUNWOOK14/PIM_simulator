// Timing-oriented C11 reducer: 4-lane FP32 tree and four modulo accumulators.
// Consecutive vectors use different accumulator slots, allowing the 3-cycle
// pipelined FP32 adder to sustain one vector per cycle.
module mixed_precision_bank_reducer4_interleaved #(
    parameter int unsigned TAG_WIDTH=16,parameter int unsigned COUNT_WIDTH=16
)(
    input logic clk_i,input logic rst_ni,input logic begin_valid_i,output logic begin_ready_o,
    input logic[TAG_WIDTH-1:0]begin_tag_i,input logic[COUNT_WIDTH-1:0]begin_vector_count_i,
    input logic vector_valid_i,output logic vector_ready_o,input logic[3:0][15:0]vector_data_i,
    output logic result_valid_o,input logic result_ready_i,output logic[TAG_WIDTH-1:0]result_tag_o,
    output logic[31:0]result_sum_o,result_sumsq_o,output logic protocol_error_o
);
    typedef enum logic[1:0]{IDLE,REDUCE,COMBINE,FINAL_WAIT}state_t;state_t state_q;
    logic[TAG_WIDTH-1:0]tag_q;logic[COUNT_WIDTH-1:0]input_remaining_q,completed_q,expected_q;
    logic[1:0]input_slot_q,slot_delay_q[0:6],acc_slot_q[0:2];logic input_fire,input_last;
    logic x_valid_q;logic[3:0][31:0]expanded,square,x_q,square_q;
    logic[1:0]pair_sum_valid,pair_sumsq_valid;logic[1:0][31:0]pair_sum,pair_sumsq;
    logic vector_sum_valid,vector_sumsq_valid;logic[31:0]vector_sum,vector_sumsq;
    logic accum_sum_valid,accum_sumsq_valid;logic[31:0]accum_sum_result,accum_sumsq_result;
    logic[3:0][31:0]sum_slot_q,sumsq_slot_q;
    logic[1:0]combine_sum_valid,combine_sumsq_valid;logic[1:0][31:0]combine_sum,combine_sumsq;
    logic final_sum_valid,final_sumsq_valid;logic[31:0]final_sum,final_sumsq;
    assign input_fire=vector_valid_i&&vector_ready_o;assign input_last=input_remaining_q==1;
    assign begin_ready_o=state_q==IDLE&&(!result_valid_o||result_ready_i);
    assign vector_ready_o=state_q==REDUCE&&input_remaining_q!=0;
    for(genvar lane=0;lane<4;lane++)begin:g_lane
      bf16_to_fp32 u_expand(.bf16_i(vector_data_i[lane]),.fp32_o(expanded[lane]));
      fp32_mul u_square(.lhs_i(expanded[lane]),.rhs_i(expanded[lane]),.result_o(square[lane]));
    end
    for(genvar pair=0;pair<2;pair++)begin:g_pair
      fp32_add_pipe4 u_sum(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(x_valid_q),.valid_o(pair_sum_valid[pair]),.lhs_i(x_q[pair*2]),.rhs_i(x_q[pair*2+1]),.result_o(pair_sum[pair]));
      fp32_add_pipe4 u_sumsq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(x_valid_q),.valid_o(pair_sumsq_valid[pair]),.lhs_i(square_q[pair*2]),.rhs_i(square_q[pair*2+1]),.result_o(pair_sumsq[pair]));
    end
    fp32_add_pipe4 u_vector_sum(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&pair_sum_valid),.valid_o(vector_sum_valid),.lhs_i(pair_sum[0]),.rhs_i(pair_sum[1]),.result_o(vector_sum));
    fp32_add_pipe4 u_vector_sumsq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&pair_sumsq_valid),.valid_o(vector_sumsq_valid),.lhs_i(pair_sumsq[0]),.rhs_i(pair_sumsq[1]),.result_o(vector_sumsq));
    fp32_add_pipe4 u_acc_sum(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(vector_sum_valid),.valid_o(accum_sum_valid),.lhs_i(sum_slot_q[slot_delay_q[6]]),.rhs_i(vector_sum),.result_o(accum_sum_result));
    fp32_add_pipe4 u_acc_sumsq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(vector_sumsq_valid),.valid_o(accum_sumsq_valid),.lhs_i(sumsq_slot_q[slot_delay_q[6]]),.rhs_i(vector_sumsq),.result_o(accum_sumsq_result));
    for(genvar pair=0;pair<2;pair++)begin:g_combine
      fp32_add_pipe4 u_sum(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(state_q==COMBINE),.valid_o(combine_sum_valid[pair]),.lhs_i(sum_slot_q[pair*2]),.rhs_i(sum_slot_q[pair*2+1]),.result_o(combine_sum[pair]));
      fp32_add_pipe4 u_sumsq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(state_q==COMBINE),.valid_o(combine_sumsq_valid[pair]),.lhs_i(sumsq_slot_q[pair*2]),.rhs_i(sumsq_slot_q[pair*2+1]),.result_o(combine_sumsq[pair]));
    end
    fp32_add_pipe4 u_final_sum(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&combine_sum_valid),.valid_o(final_sum_valid),.lhs_i(combine_sum[0]),.rhs_i(combine_sum[1]),.result_o(final_sum));
    fp32_add_pipe4 u_final_sumsq(.clk_i,.rst_ni,.enable_i(1'b1),.valid_i(&combine_sumsq_valid),.valid_o(final_sumsq_valid),.lhs_i(combine_sumsq[0]),.rhs_i(combine_sumsq[1]),.result_o(final_sumsq));
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        state_q<=IDLE;tag_q<=0;input_remaining_q<=0;completed_q<=0;expected_q<=0;input_slot_q<=0;x_valid_q<=0;x_q<=0;square_q<=0;
        for(integer i=0;i<7;i++)slot_delay_q[i]<=0;for(integer i=0;i<3;i++)acc_slot_q[i]<=0;
        sum_slot_q<=0;sumsq_slot_q<=0;result_valid_o<=0;result_tag_o<=0;result_sum_o<=0;result_sumsq_o<=0;protocol_error_o<=0;
      end else begin
        protocol_error_o<=0;x_valid_q<=input_fire;
        if(result_valid_o&&result_ready_i)result_valid_o<=0;
        if(input_fire)begin x_q<=expanded;square_q<=square;slot_delay_q[0]<=input_slot_q;input_slot_q<=input_slot_q+1'b1;input_remaining_q<=input_remaining_q-1'b1;end
        for(integer i=1;i<7;i++)slot_delay_q[i]<=slot_delay_q[i-1];
        if(vector_sum_valid)acc_slot_q[0]<=slot_delay_q[6];acc_slot_q[1]<=acc_slot_q[0];acc_slot_q[2]<=acc_slot_q[1];
        if(accum_sum_valid&&accum_sumsq_valid)begin
          sum_slot_q[acc_slot_q[2]]<=accum_sum_result;sumsq_slot_q[acc_slot_q[2]]<=accum_sumsq_result;completed_q<=completed_q+1'b1;
          if(completed_q+1'b1==expected_q)state_q<=COMBINE;
        end
        if(state_q==COMBINE)state_q<=FINAL_WAIT;
        if(final_sum_valid&&final_sumsq_valid)begin result_valid_o<=1;result_tag_o<=tag_q;result_sum_o<=final_sum;result_sumsq_o<=final_sumsq;state_q<=IDLE;end
        if(begin_valid_i&&begin_ready_o)begin
          if(begin_vector_count_i==0)protocol_error_o<=1;
          else begin state_q<=REDUCE;tag_q<=begin_tag_i;input_remaining_q<=begin_vector_count_i;expected_q<=begin_vector_count_i;completed_q<=0;input_slot_q<=0;sum_slot_q<=0;sumsq_slot_q<=0;end
        end
        if(vector_valid_i&&!vector_ready_o)protocol_error_o<=1;
      end
    end
endmodule
