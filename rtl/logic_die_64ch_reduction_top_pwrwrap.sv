// Physical-design top for the sky130 OpenROAD implementation.
// It keeps the production reduction hierarchy while selecting a pin-count and
// instance-count that can be routed as a standalone demonstrator die.
module logic_die_64ch_reduction_top_pwrwrap #(
    parameter int unsigned CHANNELS = 1,
    parameter int unsigned PIM_BLOCKS = 2,
    parameter int unsigned ENTRIES_PER_BANK = 2,
    parameter int unsigned KEY_WIDTH = 12,
    parameter int unsigned DATA_WIDTH = 16,
    parameter int unsigned SLOT_WIDTH = ENTRIES_PER_BANK > 1 ? $clog2(ENTRIES_PER_BANK) : 1,
    parameter int unsigned CHANNEL_WIDTH = CHANNELS > 1 ? $clog2(CHANNELS) : 1
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [CHANNELS-1:0][PIM_BLOCKS-1:0] update_valid_i,
    output logic [CHANNELS-1:0][PIM_BLOCKS-1:0] update_ready_o,
    input  logic [CHANNELS-1:0][PIM_BLOCKS-1:0][KEY_WIDTH-1:0] update_key_i,
    input  logic [CHANNELS-1:0][PIM_BLOCKS-1:0][SLOT_WIDTH-1:0] update_slot_i,
    input  logic [CHANNELS-1:0][PIM_BLOCKS-1:0][DATA_WIDTH-1:0] update_partial_i,
    input  logic [CHANNELS-1:0][PIM_BLOCKS-1:0] update_first_i,
    input  logic [CHANNELS-1:0][PIM_BLOCKS-1:0] update_last_i,

    output logic [1:0] link_valid_o,
    input  logic [1:0] link_ready_i,
    output logic [2*KEY_WIDTH-1:0] link_key_o,
    output logic [2*DATA_WIDTH-1:0] link_data_o,
    output logic [2*CHANNEL_WIDTH-1:0] link_channel_o,
    output logic [CHANNELS-1:0][PIM_BLOCKS-1:0] protocol_error_o
);
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][DATA_WIDTH-1:0] add_lhs;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][DATA_WIDTH-1:0] add_rhs;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][DATA_WIDTH-1:0] unused_add_result;

    assign unused_add_result = '0;

    logic_die_64ch_reduction_top #(
        .CHANNELS(CHANNELS),
        .PIM_BLOCKS(PIM_BLOCKS),
        .ENTRIES_PER_BANK(ENTRIES_PER_BANK),
        .KEY_WIDTH(KEY_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SLOT_WIDTH(SLOT_WIDTH),
        .CHANNEL_WIDTH(CHANNEL_WIDTH),
        .USE_INTERNAL_FP16(1'b1)
    ) u_core (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .update_valid_i(update_valid_i),
        .update_ready_o(update_ready_o),
        .update_key_i(update_key_i),
        .update_slot_i(update_slot_i),
        .update_partial_i(update_partial_i),
        .update_first_i(update_first_i),
        .update_last_i(update_last_i),
        .add_lhs_o(add_lhs),
        .add_rhs_o(add_rhs),
        .add_result_i(unused_add_result),
        .link_valid_o(link_valid_o),
        .link_ready_i(link_ready_i),
        .link_key_o(link_key_o),
        .link_data_o(link_data_o),
        .link_channel_o(link_channel_o),
        .protocol_error_o(protocol_error_o)
    );
endmodule
