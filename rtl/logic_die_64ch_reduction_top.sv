module logic_die_64ch_reduction_top #(
    parameter int unsigned CHANNELS = 64,
    parameter int unsigned PIM_BLOCKS = 8,
    parameter int unsigned ENTRIES_PER_BANK = 16,
    parameter int unsigned KEY_WIDTH = 64,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned SLOT_WIDTH = ENTRIES_PER_BANK > 1 ? $clog2(ENTRIES_PER_BANK) : 1,
    parameter int unsigned CHANNEL_WIDTH = CHANNELS > 1 ? $clog2(CHANNELS) : 1,
    parameter bit USE_INTERNAL_FP16 = 1'b0,
    parameter int unsigned FP16_LANES = DATA_WIDTH / 16
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

    output logic [CHANNELS-1:0][PIM_BLOCKS-1:0][DATA_WIDTH-1:0] add_lhs_o,
    output logic [CHANNELS-1:0][PIM_BLOCKS-1:0][DATA_WIDTH-1:0] add_rhs_o,
    input  logic [CHANNELS-1:0][PIM_BLOCKS-1:0][DATA_WIDTH-1:0] add_result_i,

    output logic [1:0] link_valid_o,
    input  logic [1:0] link_ready_i,
    output logic [2*KEY_WIDTH-1:0] link_key_o,
    output logic [2*DATA_WIDTH-1:0] link_data_o,
    output logic [2*CHANNEL_WIDTH-1:0] link_channel_o,
    output logic [CHANNELS-1:0][PIM_BLOCKS-1:0] protocol_error_o
);
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0] block_final_valid;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0] block_final_ready;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][KEY_WIDTH-1:0] block_final_key;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][DATA_WIDTH-1:0] block_final_data;
    logic [CHANNELS-1:0] channel_valid;
    logic [CHANNELS-1:0] channel_ready;
    logic [CHANNELS-1:0][KEY_WIDTH-1:0] channel_key;
    logic [CHANNELS-1:0][DATA_WIDTH-1:0] channel_data;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][DATA_WIDTH-1:0] selected_add_result;

    if (USE_INTERNAL_FP16) begin : g_internal_fp16
        for (genvar fp_channel = 0; fp_channel < CHANNELS; fp_channel++) begin : g_channel
            for (genvar fp_block = 0; fp_block < PIM_BLOCKS; fp_block++) begin : g_block
                for (genvar lane = 0; lane < FP16_LANES; lane++) begin : g_lane
                    fp16_add adder (
                        .lhs_i(add_lhs_o[fp_channel][fp_block][lane * 16 +: 16]),
                        .rhs_i(add_rhs_o[fp_channel][fp_block][lane * 16 +: 16]),
                        .result_o(selected_add_result[fp_channel][fp_block]
                                                     [lane * 16 +: 16])
                    );
                end
            end
        end
    end else begin : g_external_datapath
        always @* selected_add_result = add_result_i;
    end

    for (genvar channel = 0; channel < CHANNELS; channel++) begin : g_channel
        bank_local_reduction_buffer #(
            .BANKS(PIM_BLOCKS), .ENTRIES_PER_BANK(ENTRIES_PER_BANK),
            .KEY_WIDTH(KEY_WIDTH), .DATA_WIDTH(DATA_WIDTH), .SLOT_WIDTH(SLOT_WIDTH)
        ) reduction_buffer (
            .clk_i(clk_i), .rst_ni(rst_ni),
            .update_valid_i(update_valid_i[channel]),
            .update_ready_o(update_ready_o[channel]),
            .update_key_i(update_key_i[channel]), .update_slot_i(update_slot_i[channel]),
            .update_partial_i(update_partial_i[channel]),
            .update_first_i(update_first_i[channel]), .update_last_i(update_last_i[channel]),
            .add_lhs_o(add_lhs_o[channel]), .add_rhs_o(add_rhs_o[channel]),
            .add_result_i(selected_add_result[channel]),
            .final_valid_o(block_final_valid[channel]),
            .final_ready_i(block_final_ready[channel]),
            .final_key_o(block_final_key[channel]),
            .final_data_o(block_final_data[channel]),
            .protocol_error_o(protocol_error_o[channel])
        );

        logic_die_link_arbiter #(
            .INPUTS(PIM_BLOCKS), .KEY_WIDTH(KEY_WIDTH), .DATA_WIDTH(DATA_WIDTH)
        ) channel_arbiter (
            .clk_i(clk_i), .rst_ni(rst_ni),
            .input_valid_i(block_final_valid[channel]),
            .input_ready_o(block_final_ready[channel]),
            .input_key_i(block_final_key[channel]),
            .input_data_i(block_final_data[channel]),
            .input_route_i('0),
            .output_valid_o(channel_valid[channel]),
            .output_ready_i(channel_ready[channel]),
            .output_key_o(channel_key[channel]),
            .output_data_o(channel_data[channel]),
            .output_source_o(),.output_route_o()
        );
    end

    logic_die_dual_link_arbiter #(
        .INPUTS(CHANNELS), .OUTPUTS(2), .KEY_WIDTH(KEY_WIDTH),
        .DATA_WIDTH(DATA_WIDTH), .INDEX_WIDTH(CHANNEL_WIDTH)
    ) global_arbiter (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .input_valid_i(channel_valid), .input_ready_o(channel_ready),
        .input_key_i(channel_key), .input_data_i(channel_data),
        .output_valid_o(link_valid_o), .output_ready_i(link_ready_i),
        .output_key_o(link_key_o), .output_data_o(link_data_o),
        .output_source_o(link_channel_o)
    );

`ifndef SYNTHESIS
    initial begin
        if (USE_INTERNAL_FP16 && DATA_WIDTH != FP16_LANES * 16)
            $fatal(1, "Internal FP16 datapath requires a whole number of 16-bit lanes");
    end
`endif
endmodule
