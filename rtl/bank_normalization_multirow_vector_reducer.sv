module bank_normalization_multirow_vector_reducer #(
    parameter int unsigned LANES = 4,
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned COUNT_WIDTH = 16,
    parameter int unsigned RESULT_FIFO_DEPTH = 8,
    parameter int unsigned LEVELS = $clog2(LANES),
    parameter int unsigned FIFO_PTR_WIDTH = RESULT_FIFO_DEPTH > 1 ? $clog2(RESULT_FIFO_DEPTH) : 1,
    parameter int unsigned FIFO_COUNT_WIDTH = $clog2(RESULT_FIFO_DEPTH + 1)
) (
    input logic clk_i, input logic rst_ni,
    input logic begin_valid_i, output logic begin_ready_o,
    input logic [TAG_WIDTH-1:0] begin_tag_i,
    input logic [COUNT_WIDTH-1:0] begin_vector_count_i,
    input logic vector_valid_i, output logic vector_ready_o,
    input logic [LANES-1:0][15:0] vector_data_i,
    output logic result_valid_o, input logic result_ready_i,
    output logic [TAG_WIDTH-1:0] result_tag_o,
    output logic [15:0] result_sum_o, result_sumsq_o,
    output logic protocol_error_o
);
    logic input_active_q, input_first_q;
    logic [TAG_WIDTH-1:0] input_tag_q;
    logic [COUNT_WIDTH-1:0] input_remaining_q;
    logic [FIFO_COUNT_WIDTH-1:0] outstanding_q;
    logic [15:0] row_sum_q, row_sumsq_q;
    logic [LANES-1:0][15:0] squares;
    logic [15:0] sum_stage_q [0:LEVELS-1][0:LANES-1];
    logic [15:0] sumsq_stage_q [0:LEVELS-1][0:LANES-1];
    logic [15:0] sum_stage_d [0:LEVELS-1][0:LANES-1];
    logic [15:0] sumsq_stage_d [0:LEVELS-1][0:LANES-1];
    logic [LEVELS-1:0] valid_pipe_q, first_pipe_q, last_pipe_q;
    logic [LEVELS-1:0][TAG_WIDTH-1:0] tag_pipe_q;
    logic [15:0] accumulated_sum, accumulated_sumsq, accumulation_lhs_sum,
                 accumulation_lhs_sumsq;
    logic input_fire, input_last, begin_fire, result_fire, result_push;

    logic [TAG_WIDTH-1:0] fifo_tag_q [0:RESULT_FIFO_DEPTH-1];
    logic [15:0] fifo_sum_q [0:RESULT_FIFO_DEPTH-1];
    logic [15:0] fifo_sumsq_q [0:RESULT_FIFO_DEPTH-1];
    logic [FIFO_PTR_WIDTH-1:0] fifo_read_ptr_q, fifo_write_ptr_q;
    logic [FIFO_COUNT_WIDTH-1:0] fifo_count_q;

    assign vector_ready_o = input_active_q;
    assign input_fire = vector_valid_i && vector_ready_o;
    assign input_last = input_remaining_q == 1;
    assign result_valid_o = fifo_count_q != 0;
    assign result_tag_o = fifo_tag_q[fifo_read_ptr_q];
    assign result_sum_o = fifo_sum_q[fifo_read_ptr_q];
    assign result_sumsq_o = fifo_sumsq_q[fifo_read_ptr_q];
    assign result_fire = result_valid_o && result_ready_i;
    assign begin_ready_o = (!input_active_q || (input_fire && input_last)) &&
                           (outstanding_q < RESULT_FIFO_DEPTH || result_fire);
    assign begin_fire = begin_valid_i && begin_ready_o;
    assign result_push = valid_pipe_q[LEVELS-1] && last_pipe_q[LEVELS-1];
    assign accumulation_lhs_sum = first_pipe_q[LEVELS-1] ? 16'h0000 : row_sum_q;
    assign accumulation_lhs_sumsq = first_pipe_q[LEVELS-1] ? 16'h0000 : row_sumsq_q;

    for(genvar lane=0;lane<LANES;lane++)begin:g_square
        fp16_mul u_square(.lhs_i(vector_data_i[lane]),.rhs_i(vector_data_i[lane]),
                          .result_o(squares[lane]));
    end
    for(genvar node=0;node<LANES/2;node++)begin:g_first
        fp16_add u_sum(.lhs_i(vector_data_i[node*2]),.rhs_i(vector_data_i[node*2+1]),
                       .result_o(sum_stage_d[0][node]));
        fp16_add u_sumsq(.lhs_i(squares[node*2]),.rhs_i(squares[node*2+1]),
                         .result_o(sumsq_stage_d[0][node]));
    end
    for(genvar level=1;level<LEVELS;level++)begin:g_level
        for(genvar node=0;node<(LANES>>(level+1));node++)begin:g_node
            fp16_add u_sum(.lhs_i(sum_stage_q[level-1][node*2]),
                           .rhs_i(sum_stage_q[level-1][node*2+1]),
                           .result_o(sum_stage_d[level][node]));
            fp16_add u_sumsq(.lhs_i(sumsq_stage_q[level-1][node*2]),
                             .rhs_i(sumsq_stage_q[level-1][node*2+1]),
                             .result_o(sumsq_stage_d[level][node]));
        end
    end
    fp16_add u_acc_sum(.lhs_i(accumulation_lhs_sum),
                       .rhs_i(sum_stage_q[LEVELS-1][0]),.result_o(accumulated_sum));
    fp16_add u_acc_sumsq(.lhs_i(accumulation_lhs_sumsq),
                         .rhs_i(sumsq_stage_q[LEVELS-1][0]),.result_o(accumulated_sumsq));

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)begin
            input_active_q<=0;input_first_q<=0;input_tag_q<='0;input_remaining_q<='0;
            outstanding_q<='0;row_sum_q<=0;row_sumsq_q<=0;valid_pipe_q<='0;
            first_pipe_q<='0;last_pipe_q<='0;tag_pipe_q<='0;
            fifo_read_ptr_q<='0;fifo_write_ptr_q<='0;fifo_count_q<='0;
            protocol_error_o<=0;
        end else begin
            protocol_error_o<=0;
            valid_pipe_q[0]<=input_fire;
            first_pipe_q[0]<=input_fire&&input_first_q;
            last_pipe_q[0]<=input_fire&&input_last;
            tag_pipe_q[0]<=input_tag_q;
            for(integer level=1;level<LEVELS;level++)begin
                valid_pipe_q[level]<=valid_pipe_q[level-1];
                first_pipe_q[level]<=first_pipe_q[level-1];
                last_pipe_q[level]<=last_pipe_q[level-1];
                tag_pipe_q[level]<=tag_pipe_q[level-1];
            end
            for(integer level=0;level<LEVELS;level++)
                for(integer node=0;node<(LANES>>(level+1));node++)begin
                    sum_stage_q[level][node]<=sum_stage_d[level][node];
                    sumsq_stage_q[level][node]<=sumsq_stage_d[level][node];
                end

            if(vector_valid_i&&!vector_ready_o)protocol_error_o<=1;
            if(begin_valid_i&&!begin_ready_o)protocol_error_o<=1;

            // A new begin may be accepted on the same edge as the previous row's
            // last vector. The old vector still carries the old registered tag.
            if(input_fire&&input_last)begin
                if(begin_fire)begin
                    input_active_q<=1;input_first_q<=1;input_tag_q<=begin_tag_i;
                    input_remaining_q<=begin_vector_count_i;
                end else input_active_q<=0;
            end else if(begin_fire)begin
                input_active_q<=1;input_first_q<=1;input_tag_q<=begin_tag_i;
                input_remaining_q<=begin_vector_count_i;
            end else if(input_fire)begin
                input_first_q<=0;input_remaining_q<=input_remaining_q-1'b1;
            end
            if(begin_fire&&begin_vector_count_i==0)begin
                input_active_q<=0;protocol_error_o<=1;
            end

            if(valid_pipe_q[LEVELS-1])begin
                row_sum_q<=accumulated_sum;row_sumsq_q<=accumulated_sumsq;
            end
            if(result_push)begin
                fifo_tag_q[fifo_write_ptr_q]<=tag_pipe_q[LEVELS-1];
                fifo_sum_q[fifo_write_ptr_q]<=accumulated_sum;
                fifo_sumsq_q[fifo_write_ptr_q]<=accumulated_sumsq;
                fifo_write_ptr_q<=fifo_write_ptr_q+1'b1;
            end
            if(result_fire)fifo_read_ptr_q<=fifo_read_ptr_q+1'b1;
            case({result_push,result_fire})
                2'b10:fifo_count_q<=fifo_count_q+1'b1;
                2'b01:fifo_count_q<=fifo_count_q-1'b1;
                default:begin end
            endcase
            case({begin_fire,result_fire})
                2'b10:outstanding_q<=outstanding_q+1'b1;
                2'b01:outstanding_q<=outstanding_q-1'b1;
                default:begin end
            endcase
        end
    end
`ifndef SYNTHESIS
    initial begin
        if(LANES<2||(LANES&(LANES-1))!=0||RESULT_FIFO_DEPTH<LEVELS+2)
            $fatal(1,"invalid LANES or insufficient RESULT_FIFO_DEPTH");
    end
`endif
endmodule
