module logic_die_link_arbiter #(
    parameter int unsigned INPUTS = 8,
    parameter int unsigned KEY_WIDTH = 64,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned INDEX_WIDTH = INPUTS > 1 ? $clog2(INPUTS) : 1
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [INPUTS-1:0] input_valid_i,
    output logic [INPUTS-1:0] input_ready_o,
    input  logic [INPUTS*KEY_WIDTH-1:0] input_key_i,
    input  logic [INPUTS*DATA_WIDTH-1:0] input_data_i,
    input  logic [INPUTS-1:0] input_route_i,

    output logic output_valid_o,
    input  logic output_ready_i,
    output logic [KEY_WIDTH-1:0] output_key_o,
    output logic [DATA_WIDTH-1:0] output_data_o,
    output logic [INDEX_WIDTH-1:0] output_source_o,
    output logic output_route_o
);
    logic [INDEX_WIDTH-1:0] round_robin_q;
    logic hold_q;
    logic [INPUTS-1:0] candidate_grant;
    logic candidate_valid;
    logic [KEY_WIDTH-1:0] candidate_key;
    logic [DATA_WIDTH-1:0] candidate_data;
    logic [INDEX_WIDTH-1:0] candidate_source;
    logic candidate_route;
    logic [INPUTS-1:0] hold_grant_q;
    logic [KEY_WIDTH-1:0] hold_key_q;
    logic [DATA_WIDTH-1:0] hold_data_q;
    logic [INDEX_WIDTH-1:0] hold_source_q;
    logic hold_route_q;
    integer offset;
    integer candidate;
    logic found;

    always @* begin
        candidate_grant = '0;
        candidate_valid = 1'b0;
        candidate_key = '0;
        candidate_data = '0;
        candidate_source = '0;
        candidate_route = 1'b0;
        found = 1'b0;
        candidate = 0;
        for (offset = 0; offset < INPUTS; offset = offset + 1) begin
            candidate = round_robin_q + offset;
            if (candidate >= INPUTS) candidate = candidate - INPUTS;
            if (!found && input_valid_i[candidate]) begin
                candidate_grant[candidate] = 1'b1;
                candidate_valid = 1'b1;
                candidate_key = input_key_i[candidate*KEY_WIDTH +: KEY_WIDTH];
                candidate_data = input_data_i[candidate*DATA_WIDTH +: DATA_WIDTH];
                candidate_source = candidate[INDEX_WIDTH-1:0];
                candidate_route = input_route_i[candidate];
                found = 1'b1;
            end
        end

        if (hold_q) begin
            output_valid_o = 1'b1;
            output_key_o = hold_key_q;
            output_data_o = hold_data_q;
            output_source_o = hold_source_q;
            output_route_o = hold_route_q;
        end else begin
            output_valid_o = candidate_valid;
            output_key_o = candidate_key;
            output_data_o = candidate_data;
            output_source_o = candidate_source;
            output_route_o = candidate_route;
        end
        input_ready_o = (hold_q ? hold_grant_q : candidate_grant) &
                        {INPUTS{output_ready_i}};
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            round_robin_q <= '0;
            hold_q <= 1'b0;
            hold_grant_q <= '0;
            hold_key_q <= '0;
            hold_data_q <= '0;
            hold_source_q <= '0;
            hold_route_q <= 1'b0;
        end else begin
            if (!hold_q && candidate_valid && !output_ready_i) begin
                hold_q <= 1'b1;
                hold_grant_q <= candidate_grant;
                hold_key_q <= candidate_key;
                hold_data_q <= candidate_data;
                hold_source_q <= candidate_source;
                hold_route_q <= candidate_route;
            end else if (hold_q && output_ready_i) begin
                hold_q <= 1'b0;
            end
            if (output_valid_o && output_ready_i) begin
                if (output_source_o == INPUTS - 1)
                    round_robin_q <= '0;
                else
                    round_robin_q <= output_source_o + 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (INPUTS < 1) $fatal(1, "INPUTS must be at least one");
        if (2**INDEX_WIDTH < INPUTS) $fatal(1, "INDEX_WIDTH is too small");
    end
`endif
endmodule
