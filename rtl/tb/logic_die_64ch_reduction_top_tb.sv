module logic_die_64ch_reduction_top_tb;
    localparam int CHANNELS = 4;
    localparam int PIM_BLOCKS = 8;
    localparam int ENTRIES = 4;
    localparam int KEY_WIDTH = 16;
    localparam int DATA_WIDTH = 32;
    localparam int SLOT_WIDTH = $clog2(ENTRIES);
    localparam int CHANNEL_WIDTH = $clog2(CHANNELS);

    logic clk = 0;
    logic rst_n = 0;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0] update_valid, update_ready;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][KEY_WIDTH-1:0] update_key;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][SLOT_WIDTH-1:0] update_slot;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][DATA_WIDTH-1:0] update_partial;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0] update_first, update_last;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][DATA_WIDTH-1:0] add_lhs, add_rhs, add_result;
    logic [1:0] link_valid, link_ready;
    logic [2*KEY_WIDTH-1:0] link_key;
    logic [2*DATA_WIDTH-1:0] link_data;
    logic [2*CHANNEL_WIDTH-1:0] link_channel;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0] protocol_error;

    always #5 clk = ~clk;
    for (genvar channel = 0; channel < CHANNELS; channel++) begin : g_channel_adder
        for (genvar block = 0; block < PIM_BLOCKS; block++) begin : g_block_adder
            always @*
                add_result[channel][block] =
                    add_lhs[channel][block] + add_rhs[channel][block];
        end
    end

    logic_die_64ch_reduction_top #(
        .CHANNELS(CHANNELS), .PIM_BLOCKS(PIM_BLOCKS),
        .ENTRIES_PER_BANK(ENTRIES), .KEY_WIDTH(KEY_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk_i(clk), .rst_ni(rst_n), .update_valid_i(update_valid),
        .update_ready_o(update_ready), .update_key_i(update_key),
        .update_slot_i(update_slot), .update_partial_i(update_partial),
        .update_first_i(update_first), .update_last_i(update_last),
        .add_lhs_o(add_lhs), .add_rhs_o(add_rhs), .add_result_i(add_result),
        .link_valid_o(link_valid), .link_ready_i(link_ready), .link_key_o(link_key),
        .link_data_o(link_data), .link_channel_o(link_channel),
        .protocol_error_o(protocol_error)
    );

    initial begin
        update_valid = '0;
        update_key = '0;
        update_slot = '0;
        update_partial = '0;
        update_first = '0;
        update_last = '0;
        link_ready = '1;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        update_valid[0][0] = 1'b1;
        update_first[0][0] = 1'b1;
        update_last[0][0] = 1'b1;
        update_key[0][0] = 16'h2000;
        update_partial[0][0] = 200;
        update_valid[1][1] = 1'b1;
        update_first[1][1] = 1'b1;
        update_last[1][1] = 1'b1;
        update_key[1][1] = 16'h2001;
        update_partial[1][1] = 201;
        update_valid[2][2] = 1'b1;
        update_first[2][2] = 1'b1;
        update_last[2][2] = 1'b1;
        update_key[2][2] = 16'h2002;
        update_partial[2][2] = 202;
        @(posedge clk);
        @(negedge clk);
        update_valid = '0;
        update_first = '0;
        update_last = '0;
        #1;
        if (link_valid != 2'b11 || link_channel[0 +: CHANNEL_WIDTH] != 0 ||
            link_channel[CHANNEL_WIDTH +: CHANNEL_WIDTH] != 1 ||
            link_data[0 +: DATA_WIDTH] != 200 ||
            link_data[DATA_WIDTH +: DATA_WIDTH] != 201)
            $fatal(1, "first two channels did not reach global dual link");
        @(posedge clk);
        @(negedge clk);
        #1;
        if (!link_valid[0] || link_channel[0 +: CHANNEL_WIDTH] != 2 ||
            link_data[0 +: DATA_WIDTH] != 202)
            $fatal(1, "third channel did not drain after round-robin advance");

        $display("LOGIC_DIE_64CH_REDUCTION_TOP_TB PASS");
        $finish;
    end
endmodule
