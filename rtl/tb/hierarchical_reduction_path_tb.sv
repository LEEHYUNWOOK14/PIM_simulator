module hierarchical_reduction_path_tb;
    localparam int BANKS = 8;
    localparam int ENTRIES = 16;
    localparam int KEY_WIDTH = 16;
    localparam int DATA_WIDTH = 32;
    localparam int SLOT_WIDTH = $clog2(ENTRIES);
    localparam int INDEX_WIDTH = $clog2(BANKS);

    logic clk = 0;
    logic rst_n = 0;
    logic [BANKS-1:0] update_valid, update_ready, update_first, update_last;
    logic [BANKS-1:0][KEY_WIDTH-1:0] update_key;
    logic [BANKS-1:0][SLOT_WIDTH-1:0] update_slot;
    logic [BANKS-1:0][DATA_WIDTH-1:0] update_partial;
    logic [BANKS-1:0][DATA_WIDTH-1:0] add_lhs, add_rhs, add_result;
    logic [1:0] link_valid, link_ready;
    logic [2*KEY_WIDTH-1:0] link_key;
    logic [2*DATA_WIDTH-1:0] link_data;
    logic [2*INDEX_WIDTH-1:0] link_source;
    logic [BANKS-1:0] protocol_error;

    always #5 clk = ~clk;
    always_comb
        for (int unsigned bank = 0; bank < BANKS; bank++)
            add_result[bank] = add_lhs[bank] + add_rhs[bank];

    hierarchical_reduction_path #(
        .BANKS(BANKS), .ENTRIES_PER_BANK(ENTRIES), .KEY_WIDTH(KEY_WIDTH),
        .DATA_WIDTH(DATA_WIDTH), .SLOT_WIDTH(SLOT_WIDTH)
    ) dut (
        .clk_i(clk), .rst_ni(rst_n), .update_valid_i(update_valid),
        .update_ready_o(update_ready), .update_key_i(update_key),
        .update_slot_i(update_slot), .update_partial_i(update_partial),
        .update_first_i(update_first), .update_last_i(update_last),
        .add_lhs_o(add_lhs), .add_rhs_o(add_rhs), .add_result_i(add_result),
        .link_valid_o(link_valid), .link_ready_i(link_ready), .link_key_o(link_key),
        .link_data_o(link_data), .link_source_o(link_source),
        .protocol_error_o(protocol_error)
    );

    initial begin
        update_valid = '0;
        update_key = '0;
        update_slot = '0;
        update_partial = '0;
        update_first = '0;
        update_last = '0;
        link_ready = 2'b01;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        update_valid[0] = 1'b1;
        update_valid[1] = 1'b1;
        update_first[0] = 1'b1;
        update_first[1] = 1'b1;
        update_last[0] = 1'b1;
        update_last[1] = 1'b1;
        update_slot[0] = 2;
        update_slot[1] = 3;
        update_key[0] = 16'h1000;
        update_key[1] = 16'h1001;
        update_partial[0] = 40;
        update_partial[1] = 41;
        #1;
        if (!update_ready[0] || !update_ready[1])
            $fatal(1, "reduction buffer did not accept simultaneous updates");
        @(posedge clk);

        @(negedge clk);
        update_valid = '0;
        update_first = '0;
        update_last = '0;
        #1;
        if (link_valid != 2'b11 || link_data[0 +: DATA_WIDTH] != 40 ||
            link_data[DATA_WIDTH +: DATA_WIDTH] != 41)
            $fatal(1, "dual-link data did not match reduction outputs");
        if (link_source[0 +: INDEX_WIDTH] != 0 ||
            link_source[INDEX_WIDTH +: INDEX_WIDTH] != 1)
            $fatal(1, "dual-link source mapping failed");
        repeat (2) @(posedge clk);
        #1;
        if (link_valid != 2'b11)
            $fatal(1, "partial link readiness did not preserve both outputs");

        @(negedge clk);
        link_ready = 2'b11;
        @(posedge clk);
        $display("HIERARCHICAL_REDUCTION_PATH_TB PASS");
        $finish;
    end
endmodule
