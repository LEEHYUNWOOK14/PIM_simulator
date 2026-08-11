module cross_channel_reduction_network #(
    parameter int unsigned CHANNELS = 64,
    parameter int unsigned PORTS = 16,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned KEY_WIDTH = 64,
    parameter int unsigned CHANNEL_WIDTH = CHANNELS > 1 ? $clog2(CHANNELS) : 1
) (
    input logic clk_i, input logic rst_ni,
    input logic begin_valid_i, output logic begin_ready_o,
    input logic [KEY_WIDTH-1:0] begin_key_i,
    input logic [CHANNELS-1:0] begin_expected_mask_i,
    input logic [PORTS-1:0] partial_valid_i,
    output logic [PORTS-1:0] partial_ready_o,
    input logic [PORTS-1:0][CHANNEL_WIDTH-1:0] partial_channel_i,
    input logic [PORTS-1:0][KEY_WIDTH-1:0] partial_key_i,
    input logic [PORTS-1:0][DATA_WIDTH-1:0] partial_data_i,
    output logic result_valid_o, input logic result_ready_i,
    output logic [KEY_WIDTH-1:0] result_key_o,
    output logic [DATA_WIDTH-1:0] result_data_o,
    output logic duplicate_error_o, output logic context_error_o
);
    logic active_q;
    logic [KEY_WIDTH-1:0] key_q;
    logic [CHANNELS-1:0] expected_q, received_q;
    logic [DATA_WIDTH-1:0] accumulator_q;
    logic [PORTS:0][DATA_WIDTH-1:0] sum_chain;
    logic [PORTS:0][CHANNELS-1:0] mask_chain;
    logic [PORTS-1:0] accept;
    logic [PORTS-1:0] duplicate_by_port, context_by_port;

    assign sum_chain[0] = accumulator_q;
    assign mask_chain[0] = received_q;
    for (genvar port = 0; port < PORTS; port = port + 1) begin : g_fold
        logic [DATA_WIDTH-1:0] add_rhs;
        logic prior_accept_same_channel;
        if (port == 0) begin : g_first
            assign prior_accept_same_channel = 1'b0;
        end else begin : g_later
            always @* begin
                prior_accept_same_channel = 1'b0;
                for (integer prior = 0; prior < port; prior = prior + 1)
                    if (accept[prior] &&
                        partial_channel_i[prior] == partial_channel_i[port])
                        prior_accept_same_channel = 1'b1;
            end
        end
        assign partial_ready_o[port] = active_q && partial_key_i[port] == key_q &&
            expected_q[partial_channel_i[port]] && !received_q[partial_channel_i[port]] &&
            !prior_accept_same_channel;
        assign accept[port] = partial_valid_i[port] && partial_ready_o[port];
        assign add_rhs = accept[port] ? partial_data_i[port] : '0;
        fp16_vector_add #(.LANES(DATA_WIDTH/16)) u_add(
            .lhs_i(sum_chain[port]),.rhs_i(add_rhs),.result_o(sum_chain[port+1]));
        assign mask_chain[port+1] = accept[port] ?
            (mask_chain[port] | ({{(CHANNELS-1){1'b0}},1'b1} << partial_channel_i[port])) :
            mask_chain[port];
        assign duplicate_by_port[port] = partial_valid_i[port] && !partial_ready_o[port] &&
            active_q && partial_key_i[port] == key_q &&
            expected_q[partial_channel_i[port]] &&
            mask_chain[port][partial_channel_i[port]];
        assign context_by_port[port] = partial_valid_i[port] && !partial_ready_o[port] &&
                                           !duplicate_by_port[port];
    end

    assign begin_ready_o = !active_q && (!result_valid_o || result_ready_i);
    assign duplicate_error_o = |duplicate_by_port;
    assign context_error_o = |context_by_port;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            active_q <= 1'b0; key_q <= '0; expected_q <= '0; received_q <= '0;
            accumulator_q <= '0; result_valid_o <= 1'b0;
            result_key_o <= '0; result_data_o <= '0;
        end else begin
            if (result_valid_o && result_ready_i) result_valid_o <= 1'b0;
            if (begin_valid_i && begin_ready_o) begin
                active_q <= 1'b1; key_q <= begin_key_i;
                expected_q <= begin_expected_mask_i; received_q <= '0; accumulator_q <= '0;
            end else if (|accept) begin
                received_q <= mask_chain[PORTS];
                accumulator_q <= sum_chain[PORTS];
                if (mask_chain[PORTS] == expected_q) begin
                    active_q <= 1'b0; result_valid_o <= 1'b1;
                    result_key_o <= key_q; result_data_o <= sum_chain[PORTS];
                end
            end
        end
    end
endmodule
