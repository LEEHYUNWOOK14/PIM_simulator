// Timing-closure accumulator candidate using the two-stage FP16/BF16 adders.
// The feedback dependency is explicit: one partial pair is accepted every
// two cycles (II=2), preserving exact accumulation order and backpressure.
module normalization_accumulator_pipe2 #(
    parameter int unsigned DATA_FORMAT=0
) (
    input logic clk_i,input logic rst_ni,
    input logic clear_i,
    input logic partial_valid_i,output logic partial_ready_o,
    input logic [15:0] partial_sum_i,input logic [15:0] partial_sumsq_i,
    input logic partial_last_i,
    output logic result_valid_o,input logic result_ready_i,
    output logic [15:0] result_sum_o,output logic [15:0] result_sumsq_o
);
    logic pending_q,last_q;
    logic [15:0] sum_q,sumsq_q;
    logic add_valid_sum,add_valid_sumsq;
    logic add_result_valid_sum,add_result_valid_sumsq;
    logic [15:0] add_sum,add_sumsq;
    assign partial_ready_o=!pending_q&&!result_valid_o;
    assign add_valid_sum=partial_valid_i&&partial_ready_o;
    generate
      if(DATA_FORMAT==0) begin: g_fp
        fp16_add_pipe2 u_sum(.clk_i(clk_i),.rst_ni(rst_ni),.valid_i(add_valid_sum),.valid_o(add_result_valid_sum),.lhs_i(sum_q),.rhs_i(partial_sum_i),.result_o(add_sum));
        fp16_add_pipe2 u_sumsq(.clk_i(clk_i),.rst_ni(rst_ni),.valid_i(add_valid_sum),.valid_o(add_result_valid_sumsq),.lhs_i(sumsq_q),.rhs_i(partial_sumsq_i),.result_o(add_sumsq));
      end else begin: g_bf
        bf16_add_pipe2 u_sum(.clk_i(clk_i),.rst_ni(rst_ni),.valid_i(add_valid_sum),.valid_o(add_result_valid_sum),.lhs_i(sum_q),.rhs_i(partial_sum_i),.result_o(add_sum));
        bf16_add_pipe2 u_sumsq(.clk_i(clk_i),.rst_ni(rst_ni),.valid_i(add_valid_sum),.valid_o(add_result_valid_sumsq),.lhs_i(sumsq_q),.rhs_i(partial_sumsq_i),.result_o(add_sumsq));
      end
    endgenerate
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if(!rst_ni) begin pending_q<=0;last_q<=0;sum_q<=0;sumsq_q<=0;result_valid_o<=0;result_sum_o<=0;result_sumsq_o<=0;end
      else begin
        if(clear_i&&!pending_q&&!result_valid_o) begin sum_q<=0;sumsq_q<=0;end
        if(result_valid_o&&result_ready_i) result_valid_o<=0;
        if(add_valid_sum) begin pending_q<=1;last_q<=partial_last_i;end
        if(add_result_valid_sum&&add_result_valid_sumsq) begin
          pending_q<=0;sum_q<=add_sum;sumsq_q<=add_sumsq;
          if(last_q) begin result_valid_o<=1;result_sum_o<=add_sum;result_sumsq_o<=add_sumsq;end
        end
      end
    end
endmodule
