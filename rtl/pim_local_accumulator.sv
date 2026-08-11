module pim_local_accumulator #(
    parameter int unsigned ENTRIES = 16,
    parameter int unsigned KEY_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned SLOT_WIDTH = ENTRIES > 1 ? $clog2(ENTRIES) : 1
) (
    input logic clk_i, input logic rst_ni,
    input logic update_valid_i, output logic update_ready_o,
    input logic [SLOT_WIDTH-1:0] update_slot_i,
    input logic [KEY_WIDTH-1:0] update_key_i,
    input logic [DATA_WIDTH-1:0] update_data_i,
    input logic update_first_i, input logic update_last_i,
    output logic result_valid_o, input logic result_ready_i,
    output logic [KEY_WIDTH-1:0] result_key_o,
    output logic [DATA_WIDTH-1:0] result_data_o,
    output logic protocol_error_o
);
    logic [ENTRIES-1:0] valid_q;
    logic [KEY_WIDTH-1:0] key_q [0:ENTRIES-1];
    logic [DATA_WIDTH-1:0] data_q [0:ENTRIES-1];
    logic [DATA_WIDTH-1:0] sum;
    fp16_vector_add #(.LANES(DATA_WIDTH/16)) u_add(
        .lhs_i(update_first_i ? '0 : data_q[update_slot_i]),
        .rhs_i(update_data_i), .result_o(sum));

    always @* begin
        protocol_error_o = update_valid_i &&
            (update_slot_i >= ENTRIES ||
             (update_first_i ? valid_q[update_slot_i] :
              (!valid_q[update_slot_i] || key_q[update_slot_i] != update_key_i)));
        update_ready_o = !protocol_error_o &&
                         (!update_last_i || !result_valid_o || result_ready_i);
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_q <= '0;
            result_valid_o <= 1'b0;
            result_key_o <= '0;
            result_data_o <= '0;
        end else begin
            if (result_valid_o && result_ready_i) result_valid_o <= 1'b0;
            if (update_valid_i && update_ready_o) begin
                if (update_last_i) begin
                    result_valid_o <= 1'b1;
                    result_key_o <= update_key_i;
                    result_data_o <= sum;
                    valid_q[update_slot_i] <= 1'b0;
                end else begin
                    valid_q[update_slot_i] <= 1'b1;
                    key_q[update_slot_i] <= update_key_i;
                    data_q[update_slot_i] <= sum;
                end
            end
        end
    end
endmodule
