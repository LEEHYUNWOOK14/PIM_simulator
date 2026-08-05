module hierarchical_reduction_path #(
    parameter int unsigned BANKS = 8,
    parameter int unsigned ENTRIES_PER_BANK = 16,
    parameter int unsigned KEY_WIDTH = 64,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned SLOT_WIDTH = $clog2(ENTRIES_PER_BANK),
    parameter int unsigned INDEX_WIDTH = $clog2(BANKS)
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [BANKS-1:0] update_valid_i,
    output logic [BANKS-1:0] update_ready_o,
    input  logic [BANKS-1:0][KEY_WIDTH-1:0] update_key_i,
    input  logic [BANKS-1:0][SLOT_WIDTH-1:0] update_slot_i,
    input  logic [BANKS-1:0][DATA_WIDTH-1:0] update_partial_i,
    input  logic [BANKS-1:0] update_first_i,
    input  logic [BANKS-1:0] update_last_i,

    output logic [BANKS-1:0][DATA_WIDTH-1:0] add_lhs_o,
    output logic [BANKS-1:0][DATA_WIDTH-1:0] add_rhs_o,
    input  logic [BANKS-1:0][DATA_WIDTH-1:0] add_result_i,

    output logic [1:0] link_valid_o,
    input  logic [1:0] link_ready_i,
    output logic [2*KEY_WIDTH-1:0] link_key_o,
    output logic [2*DATA_WIDTH-1:0] link_data_o,
    output logic [2*INDEX_WIDTH-1:0] link_source_o,
    output logic [BANKS-1:0] protocol_error_o
);
    logic [BANKS-1:0] final_valid;
    logic [BANKS-1:0] final_ready;
    logic [BANKS-1:0][KEY_WIDTH-1:0] final_key;
    logic [BANKS-1:0][DATA_WIDTH-1:0] final_data;

    bank_local_reduction_buffer #(
        .BANKS(BANKS), .ENTRIES_PER_BANK(ENTRIES_PER_BANK),
        .KEY_WIDTH(KEY_WIDTH), .DATA_WIDTH(DATA_WIDTH), .SLOT_WIDTH(SLOT_WIDTH)
    ) reduction_buffer (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .update_valid_i(update_valid_i), .update_ready_o(update_ready_o),
        .update_key_i(update_key_i), .update_slot_i(update_slot_i),
        .update_partial_i(update_partial_i), .update_first_i(update_first_i),
        .update_last_i(update_last_i), .add_lhs_o(add_lhs_o), .add_rhs_o(add_rhs_o),
        .add_result_i(add_result_i), .final_valid_o(final_valid),
        .final_ready_i(final_ready), .final_key_o(final_key), .final_data_o(final_data),
        .protocol_error_o(protocol_error_o)
    );

    logic_die_dual_link_arbiter #(
        .INPUTS(BANKS), .OUTPUTS(2), .KEY_WIDTH(KEY_WIDTH),
        .DATA_WIDTH(DATA_WIDTH), .INDEX_WIDTH(INDEX_WIDTH)
    ) link_arbiter (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .input_valid_i(final_valid), .input_ready_o(final_ready),
        .input_key_i(final_key), .input_data_i(final_data),
        .output_valid_o(link_valid_o), .output_ready_i(link_ready_i),
        .output_key_o(link_key_o), .output_data_o(link_data_o),
        .output_source_o(link_source_o)
    );
endmodule
