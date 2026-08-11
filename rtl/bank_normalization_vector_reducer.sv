module bank_normalization_vector_reducer #(
    parameter int unsigned LANES = 4,
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned COUNT_WIDTH = 16,
    parameter int unsigned DATA_FORMAT = 0 // 0=FP16, 1=BF16
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
    logic active_q;
    logic [TAG_WIDTH-1:0] tag_q;
    logic [COUNT_WIDTH-1:0] remaining_q;
    logic [15:0] sum_q, sumsq_q;
    localparam int unsigned LEVELS = LANES > 1 ? $clog2(LANES) : 0;
    logic [LANES-1:0][15:0] squares;
    logic [15:0] sum_tree [0:LEVELS][0:LANES-1];
    logic [15:0] sumsq_tree [0:LEVELS][0:LANES-1];
    logic [15:0] sum_next, sumsq_next;

    for (genvar lane = 0; lane < LANES; lane++) begin : g_lane_input
        if (DATA_FORMAT == 0) begin : g_fp16_square
            fp16_mul u_square(.lhs_i(vector_data_i[lane]),
                              .rhs_i(vector_data_i[lane]),.result_o(squares[lane]));
        end else begin : g_bf16_square
            bf16_mul u_square(.lhs_i(vector_data_i[lane]),
                              .rhs_i(vector_data_i[lane]),.result_o(squares[lane]));
        end
        assign sum_tree[0][lane] = vector_data_i[lane];
        assign sumsq_tree[0][lane] = squares[lane];
    end
    for (genvar level = 0; level < LEVELS; level++) begin : g_tree_level
        for (genvar node = 0; node < (LANES >> (level + 1)); node++) begin : g_node
            if (DATA_FORMAT == 0) begin : g_fp16_tree
                fp16_add u_sum_node(.lhs_i(sum_tree[level][node*2]),
                    .rhs_i(sum_tree[level][node*2+1]),.result_o(sum_tree[level+1][node]));
                fp16_add u_sumsq_node(.lhs_i(sumsq_tree[level][node*2]),
                    .rhs_i(sumsq_tree[level][node*2+1]),.result_o(sumsq_tree[level+1][node]));
            end else begin : g_bf16_tree
                bf16_add u_sum_node(.lhs_i(sum_tree[level][node*2]),
                    .rhs_i(sum_tree[level][node*2+1]),.result_o(sum_tree[level+1][node]));
                bf16_add u_sumsq_node(.lhs_i(sumsq_tree[level][node*2]),
                    .rhs_i(sumsq_tree[level][node*2+1]),.result_o(sumsq_tree[level+1][node]));
            end
        end
    end
    generate
        if (DATA_FORMAT == 0) begin : g_fp16_accumulate
            fp16_add u_sum_accumulate(.lhs_i(sum_q),.rhs_i(sum_tree[LEVELS][0]),.result_o(sum_next));
            fp16_add u_sumsq_accumulate(.lhs_i(sumsq_q),.rhs_i(sumsq_tree[LEVELS][0]),.result_o(sumsq_next));
        end else begin : g_bf16_accumulate
            bf16_add u_sum_accumulate(.lhs_i(sum_q),.rhs_i(sum_tree[LEVELS][0]),.result_o(sum_next));
            bf16_add u_sumsq_accumulate(.lhs_i(sumsq_q),.rhs_i(sumsq_tree[LEVELS][0]),.result_o(sumsq_next));
        end
    endgenerate

    assign begin_ready_o = !active_q && (!result_valid_o || result_ready_i);
    assign vector_ready_o = active_q && (!result_valid_o || result_ready_i);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            active_q <= 1'b0;
            tag_q <= '0;
            remaining_q <= '0;
            sum_q <= 16'h0000;
            sumsq_q <= 16'h0000;
            result_valid_o <= 1'b0;
            result_tag_o <= '0;
            result_sum_o <= 16'h0000;
            result_sumsq_o <= 16'h0000;
            protocol_error_o <= 1'b0;
        end else begin
            protocol_error_o <= 1'b0;
            if (result_valid_o && result_ready_i) result_valid_o <= 1'b0;
            if (begin_valid_i && begin_ready_o) begin
                if (begin_vector_count_i == 0) protocol_error_o <= 1'b1;
                else begin
                    active_q <= 1'b1;
                    tag_q <= begin_tag_i;
                    remaining_q <= begin_vector_count_i;
                    sum_q <= 16'h0000;
                    sumsq_q <= 16'h0000;
                end
            end
            if (vector_valid_i && !vector_ready_o) protocol_error_o <= 1'b1;
            if (vector_valid_i && vector_ready_o) begin
                sum_q <= sum_next;
                sumsq_q <= sumsq_next;
                remaining_q <= remaining_q - 1'b1;
                if (remaining_q == 1) begin
                    active_q <= 1'b0;
                    result_valid_o <= 1'b1;
                    result_tag_o <= tag_q;
                    result_sum_o <= sum_next;
                    result_sumsq_o <= sumsq_next;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (LANES == 0 || (LANES & (LANES - 1)) != 0)
            $fatal(1, "LANES must be a non-zero power of two");
        if (DATA_FORMAT > 1) $fatal(1, "DATA_FORMAT must be 0 (FP16) or 1 (BF16)");
    end
`endif
endmodule
