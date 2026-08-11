module cross_channel_reduction #(
    parameter int unsigned CHANNELS = 64,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned KEY_WIDTH = 32,
    parameter int unsigned CHANNEL_WIDTH = CHANNELS > 1 ? $clog2(CHANNELS) : 1
) (
    input logic clk_i, input logic rst_ni,
    input logic begin_valid_i, output logic begin_ready_o,
    input logic [KEY_WIDTH-1:0] begin_key_i,
    input logic [CHANNELS-1:0] begin_expected_mask_i,
    input logic partial_valid_i, output logic partial_ready_o,
    input logic [CHANNEL_WIDTH-1:0] partial_channel_i,
    input logic [KEY_WIDTH-1:0] partial_key_i,
    input logic [DATA_WIDTH-1:0] partial_data_i,
    output logic result_valid_o, input logic result_ready_i,
    output logic [KEY_WIDTH-1:0] result_key_o,
    output logic [DATA_WIDTH-1:0] result_data_o,
    output logic duplicate_error_o,
    output logic context_error_o
);
    logic active_q;
    logic [KEY_WIDTH-1:0] key_q;
    logic [CHANNELS-1:0] expected_q, received_q;
    logic [DATA_WIDTH-1:0] accumulator_q, sum;
    fp16_vector_add #(.LANES(DATA_WIDTH/16)) u_add(
        .lhs_i(accumulator_q), .rhs_i(partial_data_i), .result_o(sum));
    assign begin_ready_o = !active_q && (!result_valid_o || result_ready_i);
    assign partial_ready_o = active_q && partial_key_i == key_q &&
                             expected_q[partial_channel_i] && !received_q[partial_channel_i];
    assign duplicate_error_o = partial_valid_i && active_q && received_q[partial_channel_i];
    assign context_error_o = partial_valid_i &&
        (!active_q || partial_key_i != key_q || !expected_q[partial_channel_i]);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            active_q <= 1'b0; result_valid_o <= 1'b0;
            key_q <= '0; expected_q <= '0; received_q <= '0;
            accumulator_q <= '0; result_key_o <= '0; result_data_o <= '0;
        end else begin
            if (result_valid_o && result_ready_i) result_valid_o <= 1'b0;
            if (begin_valid_i && begin_ready_o) begin
                active_q <= 1'b1; key_q <= begin_key_i;
                expected_q <= begin_expected_mask_i; received_q <= '0; accumulator_q <= '0;
            end
            if (partial_valid_i && partial_ready_o) begin
                accumulator_q <= sum;
                received_q[partial_channel_i] <= 1'b1;
                if ((received_q | ({{(CHANNELS-1){1'b0}},1'b1} << partial_channel_i)) == expected_q) begin
                    active_q <= 1'b0;
                    result_valid_o <= 1'b1;
                    result_key_o <= key_q;
                    result_data_o <= sum;
                end
            end
        end
    end
endmodule
