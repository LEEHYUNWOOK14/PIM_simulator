module bank_local_fp16_reduction #(
    parameter int unsigned BANKS = 8, ENTRIES_PER_BANK = 16,
    parameter int unsigned KEY_WIDTH = 64, LANES = 16,
    parameter int unsigned SLOT_WIDTH = $clog2(ENTRIES_PER_BANK),
    parameter int unsigned DATA_WIDTH = LANES * 16
) (
    input logic clk_i, input logic rst_ni,
    input logic [BANKS-1:0] update_valid_i,
    output logic [BANKS-1:0] update_ready_o,
    input logic [BANKS-1:0][KEY_WIDTH-1:0] update_key_i,
    input logic [BANKS-1:0][SLOT_WIDTH-1:0] update_slot_i,
    input logic [BANKS-1:0][DATA_WIDTH-1:0] update_partial_i,
    input logic [BANKS-1:0] update_first_i, input logic [BANKS-1:0] update_last_i,
    output logic [BANKS-1:0] final_valid_o,
    input logic [BANKS-1:0] final_ready_i,
    output logic [BANKS-1:0][KEY_WIDTH-1:0] final_key_o,
    output logic [BANKS-1:0][DATA_WIDTH-1:0] final_data_o,
    output logic [BANKS-1:0] protocol_error_o
);
    logic [BANKS-1:0][DATA_WIDTH-1:0] add_lhs, add_rhs, add_result;
    for (genvar bank = 0; bank < BANKS; bank++) begin : g_bank
        for (genvar lane = 0; lane < LANES; lane++) begin : g_lane
            fp16_add adder(
                .lhs_i(add_lhs[bank][lane*16 +: 16]),
                .rhs_i(add_rhs[bank][lane*16 +: 16]),
                .result_o(add_result[bank][lane*16 +: 16]));
        end
    end
    bank_local_reduction_buffer #(
        .BANKS(BANKS), .ENTRIES_PER_BANK(ENTRIES_PER_BANK),
        .KEY_WIDTH(KEY_WIDTH), .DATA_WIDTH(DATA_WIDTH), .SLOT_WIDTH(SLOT_WIDTH)
    ) buffer(
        .clk_i, .rst_ni, .update_valid_i, .update_ready_o, .update_key_i,
        .update_slot_i, .update_partial_i, .update_first_i, .update_last_i,
        .add_lhs_o(add_lhs), .add_rhs_o(add_rhs), .add_result_i(add_result),
        .final_valid_o, .final_ready_i, .final_key_o, .final_data_o,
        .protocol_error_o);
endmodule
