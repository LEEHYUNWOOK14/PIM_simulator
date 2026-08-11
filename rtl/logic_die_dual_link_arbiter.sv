module logic_die_dual_link_arbiter #(
    parameter int unsigned INPUTS = 8,
    parameter int unsigned OUTPUTS = 2,
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

    output logic [OUTPUTS-1:0] output_valid_o,
    input  logic [OUTPUTS-1:0] output_ready_i,
    output logic [OUTPUTS*KEY_WIDTH-1:0] output_key_o,
    output logic [OUTPUTS*DATA_WIDTH-1:0] output_data_o,
    output logic [OUTPUTS*INDEX_WIDTH-1:0] output_source_o
);
    logic [INDEX_WIDTH-1:0] round_robin_q;
    logic hold_q;
    logic [INPUTS-1:0] candidate_grant;
    logic [OUTPUTS-1:0] candidate_valid;
    logic [OUTPUTS*KEY_WIDTH-1:0] candidate_key;
    logic [OUTPUTS*DATA_WIDTH-1:0] candidate_data;
    logic [OUTPUTS*INDEX_WIDTH-1:0] candidate_source;
    logic [INPUTS-1:0] hold_grant_q;
    logic [OUTPUTS-1:0] hold_valid_q;
    logic [OUTPUTS*KEY_WIDTH-1:0] hold_key_q;
    logic [OUTPUTS*DATA_WIDTH-1:0] hold_data_q;
    logic [OUTPUTS*INDEX_WIDTH-1:0] hold_source_q;
    logic selected_ready;
    integer offset;
    integer candidate;
    integer selected;

    always @* begin
        candidate_grant = '0;
        candidate_valid = '0;
        candidate_key = '0;
        candidate_data = '0;
        candidate_source = '0;
        selected = 0;
        candidate = 0;

        for (offset = 0; offset < INPUTS; offset = offset + 1) begin
            candidate = round_robin_q + offset;
            if (candidate >= INPUTS) candidate = candidate - INPUTS;
            if (input_valid_i[candidate] && selected < OUTPUTS) begin
                candidate_grant[candidate] = 1'b1;
                candidate_valid[selected] = 1'b1;
                candidate_key[selected*KEY_WIDTH +: KEY_WIDTH] =
                    input_key_i[candidate*KEY_WIDTH +: KEY_WIDTH];
                candidate_data[selected*DATA_WIDTH +: DATA_WIDTH] =
                    input_data_i[candidate*DATA_WIDTH +: DATA_WIDTH];
                candidate_source[selected*INDEX_WIDTH +: INDEX_WIDTH] = candidate;
                selected = selected + 1;
            end
        end

        if (hold_q) begin
            output_valid_o = hold_valid_q;
            output_key_o = hold_key_q;
            output_data_o = hold_data_q;
            output_source_o = hold_source_q;
        end else begin
            output_valid_o = candidate_valid;
            output_key_o = candidate_key;
            output_data_o = candidate_data;
            output_source_o = candidate_source;
        end

        selected_ready = 1'b1;
        for (offset = 0; offset < OUTPUTS; offset = offset + 1)
            if (output_valid_o[offset] && !output_ready_i[offset]) selected_ready = 1'b0;
        input_ready_o = (hold_q ? hold_grant_q : candidate_grant) &
                        {INPUTS{selected_ready}};
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            round_robin_q <= '0;
            hold_q <= 1'b0;
            hold_grant_q <= '0;
            hold_valid_q <= '0;
            hold_key_q <= '0;
            hold_data_q <= '0;
            hold_source_q <= '0;
        end else begin
            if (!hold_q && |candidate_valid && !selected_ready) begin
                hold_q <= 1'b1;
                hold_grant_q <= candidate_grant;
                hold_valid_q <= candidate_valid;
                hold_key_q <= candidate_key;
                hold_data_q <= candidate_data;
                hold_source_q <= candidate_source;
            end else if (hold_q && selected_ready) begin
                hold_q <= 1'b0;
            end

            if (selected_ready && |output_valid_o) begin
                if (output_valid_o[OUTPUTS-1]) begin
                    if (output_source_o[(OUTPUTS-1)*INDEX_WIDTH +: INDEX_WIDTH] == INPUTS - 1)
                        round_robin_q <= '0;
                    else
                        round_robin_q <=
                            output_source_o[(OUTPUTS-1)*INDEX_WIDTH +: INDEX_WIDTH] + 1'b1;
                end else begin
                    if (output_source_o[0 +: INDEX_WIDTH] == INPUTS - 1)
                        round_robin_q <= '0;
                    else
                        round_robin_q <= output_source_o[0 +: INDEX_WIDTH] + 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (INPUTS < 2) $fatal(1, "INPUTS must be at least two");
        if (OUTPUTS != 2) $fatal(1, "This implementation requires OUTPUTS=2");
        if (2**INDEX_WIDTH < INPUTS) $fatal(1, "INDEX_WIDTH is too small");
    end
`endif
endmodule
