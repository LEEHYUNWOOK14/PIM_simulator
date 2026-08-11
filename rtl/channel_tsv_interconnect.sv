module channel_tsv_interconnect #(
    parameter int unsigned CHANNELS = 64,
    parameter int unsigned LANES = 2,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned KEY_WIDTH = 32,
    parameter int unsigned CHANNEL_WIDTH = CHANNELS > 1 ? $clog2(CHANNELS) : 1
) (
    input logic clk_i, input logic rst_ni,
    input logic [CHANNELS-1:0] input_valid_i,
    output logic [CHANNELS-1:0] input_ready_o,
    input logic [CHANNELS-1:0][KEY_WIDTH-1:0] input_key_i,
    input logic [CHANNELS-1:0][DATA_WIDTH-1:0] input_data_i,
    output logic [LANES-1:0] output_valid_o,
    input logic [LANES-1:0] output_ready_i,
    output logic [LANES-1:0][KEY_WIDTH-1:0] output_key_o,
    output logic [LANES-1:0][DATA_WIDTH-1:0] output_data_o,
    output logic [LANES-1:0][CHANNEL_WIDTH-1:0] output_channel_o
);
    logic [CHANNEL_WIDTH-1:0] rr_q;
    logic [LANES-1:0] hold_valid_q;
    logic [LANES-1:0][KEY_WIDTH-1:0] hold_key_q;
    logic [LANES-1:0][DATA_WIDTH-1:0] hold_data_q;
    logic [LANES-1:0][CHANNEL_WIDTH-1:0] hold_channel_q;
    logic [LANES-1:0] candidate_valid;
    logic [LANES-1:0][CHANNEL_WIDTH-1:0] candidate_channel;

    always @* begin
        logic [CHANNELS-1:0] selected;
        selected = '0; candidate_valid = '0; candidate_channel = '0; input_ready_o = '0;
        output_valid_o = hold_valid_q; output_key_o = hold_key_q;
        output_data_o = hold_data_q; output_channel_o = hold_channel_q;
        for (integer held_lane = 0; held_lane < LANES; held_lane = held_lane + 1)
            if (hold_valid_q[held_lane]) selected[hold_channel_q[held_lane]] = 1'b1;
        for (integer lane = 0; lane < LANES; lane = lane + 1) begin
            logic found;
            found = 1'b0;
            if (!hold_valid_q[lane]) begin
                for (integer offset = 0; offset < CHANNELS; offset = offset + 1) begin
                    integer candidate;
                    candidate = (rr_q + offset) % CHANNELS;
                    if (!found && !selected[candidate] && input_valid_i[candidate]) begin
                        found = 1'b1; selected[candidate] = 1'b1;
                        candidate_valid[lane] = 1'b1;
                        candidate_channel[lane] = candidate[CHANNEL_WIDTH-1:0];
                        output_valid_o[lane] = 1'b1;
                        output_key_o[lane] = input_key_i[candidate];
                        output_data_o[lane] = input_data_i[candidate];
                        output_channel_o[lane] = candidate[CHANNEL_WIDTH-1:0];
                        input_ready_o[candidate] = output_ready_i[lane];
                    end
                end
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin rr_q <= '0; hold_valid_q <= '0; end
        else for (integer lane = 0; lane < LANES; lane = lane + 1) begin
            if (hold_valid_q[lane] && output_ready_i[lane]) hold_valid_q[lane] <= 1'b0;
            if (!hold_valid_q[lane] && candidate_valid[lane]) begin
                if (!output_ready_i[lane]) begin
                    hold_valid_q[lane] <= 1'b1;
                    hold_key_q[lane] <= output_key_o[lane];
                    hold_data_q[lane] <= output_data_o[lane];
                    hold_channel_q[lane] <= output_channel_o[lane];
                end
                if (output_ready_i[lane])
                    rr_q <= output_channel_o[lane] == CHANNELS-1 ? '0 : output_channel_o[lane] + 1'b1;
            end
        end
    end
endmodule
