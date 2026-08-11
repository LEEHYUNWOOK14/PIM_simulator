module bank_normalization_pipelined_vector_reducer #(
    parameter int unsigned LANES = 4,
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned COUNT_WIDTH = 16,
    parameter int unsigned DATA_FORMAT = 0, // 0=FP16, 1=BF16
    parameter int unsigned LEVELS = $clog2(LANES)
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic begin_valid_i,
    output logic begin_ready_o,
    input  logic [TAG_WIDTH-1:0] begin_tag_i,
    input  logic [COUNT_WIDTH-1:0] begin_vector_count_i,
    input  logic vector_valid_i,
    output logic vector_ready_o,
    input  logic [LANES-1:0][15:0] vector_data_i,
    output logic result_valid_o,
    input  logic result_ready_i,
    output logic [TAG_WIDTH-1:0] result_tag_o,
    output logic [15:0] result_sum_o,
    output logic [15:0] result_sumsq_o,
    output logic protocol_error_o
);
    logic busy_q, accepting_q;
    logic [TAG_WIDTH-1:0] tag_q;
    logic [COUNT_WIDTH-1:0] input_remaining_q;
    logic [15:0] row_sum_q, row_sumsq_q;
    logic [LANES-1:0][15:0] squares;
    logic [15:0] sum_stage_q [0:LEVELS-1][0:LANES-1];
    logic [15:0] sumsq_stage_q [0:LEVELS-1][0:LANES-1];
    logic [15:0] sum_stage_d [0:LEVELS-1][0:LANES-1];
    logic [15:0] sumsq_stage_d [0:LEVELS-1][0:LANES-1];
    logic [LEVELS-1:0] valid_pipe_q, last_pipe_q;
    logic input_fire, input_last;
    logic [15:0] accumulated_sum, accumulated_sumsq;

    assign input_fire = vector_valid_i && vector_ready_o;
    assign input_last = input_remaining_q == 1;
    assign begin_ready_o = !busy_q && (!result_valid_o || result_ready_i);
    assign vector_ready_o = accepting_q;

    for (genvar lane = 0; lane < LANES; lane++) begin : g_square
        if (DATA_FORMAT == 0) begin : g_fp16_square
            fp16_mul u_square(.lhs_i(vector_data_i[lane]),.rhs_i(vector_data_i[lane]),
                              .result_o(squares[lane]));
        end else begin : g_bf16_square
            bf16_mul u_square(.lhs_i(vector_data_i[lane]),.rhs_i(vector_data_i[lane]),
                              .result_o(squares[lane]));
        end
    end
    for (genvar node = 0; node < LANES/2; node++) begin : g_first_level
        if (DATA_FORMAT == 0) begin : g_fp16_first
            fp16_add u_sum(.lhs_i(vector_data_i[node*2]),.rhs_i(vector_data_i[node*2+1]),.result_o(sum_stage_d[0][node]));
            fp16_add u_sumsq(.lhs_i(squares[node*2]),.rhs_i(squares[node*2+1]),.result_o(sumsq_stage_d[0][node]));
        end else begin : g_bf16_first
            bf16_add u_sum(.lhs_i(vector_data_i[node*2]),.rhs_i(vector_data_i[node*2+1]),.result_o(sum_stage_d[0][node]));
            bf16_add u_sumsq(.lhs_i(squares[node*2]),.rhs_i(squares[node*2+1]),.result_o(sumsq_stage_d[0][node]));
        end
    end
    for (genvar level = 1; level < LEVELS; level++) begin : g_later_level
        for (genvar node = 0; node < (LANES >> (level + 1)); node++) begin : g_node
            if (DATA_FORMAT == 0) begin : g_fp16_later
                fp16_add u_sum(.lhs_i(sum_stage_q[level-1][node*2]),.rhs_i(sum_stage_q[level-1][node*2+1]),.result_o(sum_stage_d[level][node]));
                fp16_add u_sumsq(.lhs_i(sumsq_stage_q[level-1][node*2]),.rhs_i(sumsq_stage_q[level-1][node*2+1]),.result_o(sumsq_stage_d[level][node]));
            end else begin : g_bf16_later
                bf16_add u_sum(.lhs_i(sum_stage_q[level-1][node*2]),.rhs_i(sum_stage_q[level-1][node*2+1]),.result_o(sum_stage_d[level][node]));
                bf16_add u_sumsq(.lhs_i(sumsq_stage_q[level-1][node*2]),.rhs_i(sumsq_stage_q[level-1][node*2+1]),.result_o(sumsq_stage_d[level][node]));
            end
        end
    end
    generate
        if (DATA_FORMAT == 0) begin : g_fp16_accumulate
            fp16_add u_row_sum(.lhs_i(row_sum_q),.rhs_i(sum_stage_q[LEVELS-1][0]),.result_o(accumulated_sum));
            fp16_add u_row_sumsq(.lhs_i(row_sumsq_q),.rhs_i(sumsq_stage_q[LEVELS-1][0]),.result_o(accumulated_sumsq));
        end else begin : g_bf16_accumulate
            bf16_add u_row_sum(.lhs_i(row_sum_q),.rhs_i(sum_stage_q[LEVELS-1][0]),.result_o(accumulated_sum));
            bf16_add u_row_sumsq(.lhs_i(row_sumsq_q),.rhs_i(sumsq_stage_q[LEVELS-1][0]),.result_o(accumulated_sumsq));
        end
    endgenerate

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_q <= 1'b0;
            accepting_q <= 1'b0;
            tag_q <= '0;
            input_remaining_q <= '0;
            row_sum_q <= 16'h0000;
            row_sumsq_q <= 16'h0000;
            valid_pipe_q <= '0;
            last_pipe_q <= '0;
            result_valid_o <= 1'b0;
            result_tag_o <= '0;
            result_sum_o <= 16'h0000;
            result_sumsq_o <= 16'h0000;
            protocol_error_o <= 1'b0;
        end else begin
            protocol_error_o <= 1'b0;
            if (result_valid_o && result_ready_i) result_valid_o <= 1'b0;

            valid_pipe_q[0] <= input_fire;
            last_pipe_q[0] <= input_fire && input_last;
            for (integer level = 1; level < LEVELS; level++) begin
                valid_pipe_q[level] <= valid_pipe_q[level-1];
                last_pipe_q[level] <= last_pipe_q[level-1];
            end
            for (integer level = 0; level < LEVELS; level++)
                for (integer node = 0; node < (LANES >> (level + 1)); node++) begin
                    sum_stage_q[level][node] <= sum_stage_d[level][node];
                    sumsq_stage_q[level][node] <= sumsq_stage_d[level][node];
                end

            if (begin_valid_i && begin_ready_o) begin
                if (begin_vector_count_i == 0) protocol_error_o <= 1'b1;
                else begin
                    busy_q <= 1'b1;
                    accepting_q <= 1'b1;
                    tag_q <= begin_tag_i;
                    input_remaining_q <= begin_vector_count_i;
                    row_sum_q <= 16'h0000;
                    row_sumsq_q <= 16'h0000;
                end
            end
            if (vector_valid_i && !vector_ready_o) protocol_error_o <= 1'b1;
            if (input_fire) begin
                input_remaining_q <= input_remaining_q - 1'b1;
                if (input_last) accepting_q <= 1'b0;
            end
            if (valid_pipe_q[LEVELS-1]) begin
                row_sum_q <= accumulated_sum;
                row_sumsq_q <= accumulated_sumsq;
                if (last_pipe_q[LEVELS-1]) begin
                    busy_q <= 1'b0;
                    result_valid_o <= 1'b1;
                    result_tag_o <= tag_q;
                    result_sum_o <= accumulated_sum;
                    result_sumsq_o <= accumulated_sumsq;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (LANES < 2 || (LANES & (LANES - 1)) != 0 || LEVELS != $clog2(LANES))
            $fatal(1, "LANES must be a power of two >= 2 and LEVELS must match");
        if (DATA_FORMAT > 1) $fatal(1, "DATA_FORMAT must be 0 (FP16) or 1 (BF16)");
    end
`endif
endmodule
