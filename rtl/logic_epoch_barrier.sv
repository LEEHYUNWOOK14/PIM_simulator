module logic_epoch_barrier #(
    parameter int unsigned CHANNELS = 64,
    parameter int unsigned EPOCH_WIDTH = 16,
    parameter int unsigned CHANNEL_WIDTH = CHANNELS > 1 ? $clog2(CHANNELS) : 1
) (
    input logic clk_i, input logic rst_ni,
    input logic begin_valid_i, output logic begin_ready_o,
    input logic [EPOCH_WIDTH-1:0] begin_epoch_i,
    input logic [CHANNELS-1:0] begin_expected_mask_i,
    input logic fill_done_valid_i,
    input logic [CHANNEL_WIDTH-1:0] fill_done_channel_i,
    input logic execution_done_i,
    output logic release_valid_o,
    output logic [EPOCH_WIDTH-1:0] release_epoch_o,
    output logic [CHANNELS-1:0] ready_mask_o,
    output logic active_o,
    output logic unexpected_channel_error_o
);
    logic [CHANNELS-1:0] expected_q, ready_q;
    logic [EPOCH_WIDTH-1:0] epoch_q;
    logic active_q, released_q;
    assign begin_ready_o = !active_q;
    assign active_o = active_q;
    assign ready_mask_o = ready_q;
    assign release_epoch_o = epoch_q;
    assign release_valid_o = active_q && !released_q && ready_q == expected_q;
    assign unexpected_channel_error_o = fill_done_valid_i && active_q &&
                                         !expected_q[fill_done_channel_i];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            active_q <= 1'b0; released_q <= 1'b0;
            expected_q <= '0; ready_q <= '0; epoch_q <= '0;
        end else begin
            if (begin_valid_i && begin_ready_o) begin
                active_q <= 1'b1; released_q <= 1'b0;
                epoch_q <= begin_epoch_i; expected_q <= begin_expected_mask_i; ready_q <= '0;
            end
            if (fill_done_valid_i && active_q && expected_q[fill_done_channel_i])
                ready_q[fill_done_channel_i] <= 1'b1;
            if (release_valid_o) released_q <= 1'b1;
            if (execution_done_i && released_q) active_q <= 1'b0;
        end
    end
endmodule
