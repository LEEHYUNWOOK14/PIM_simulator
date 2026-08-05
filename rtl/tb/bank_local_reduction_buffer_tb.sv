module bank_local_reduction_buffer_tb;
    localparam int BANKS = 8;
    localparam int ENTRIES = 16;
    localparam int KEY_WIDTH = 16;
    localparam int DATA_WIDTH = 32;
    localparam int SLOT_WIDTH = $clog2(ENTRIES);

    logic clk = 0;
    logic rst_n = 0;
    logic [BANKS-1:0] update_valid, update_ready, update_first, update_last;
    logic [BANKS-1:0][KEY_WIDTH-1:0] update_key;
    logic [BANKS-1:0][SLOT_WIDTH-1:0] update_slot;
    logic [BANKS-1:0][DATA_WIDTH-1:0] update_partial;
    logic [BANKS-1:0][DATA_WIDTH-1:0] add_lhs, add_rhs, add_result;
    logic [BANKS-1:0] final_valid, final_ready, protocol_error;
    logic [BANKS-1:0][KEY_WIDTH-1:0] final_key;
    logic [BANKS-1:0][DATA_WIDTH-1:0] final_data;

    always #5 clk = ~clk;
    always_comb
        for (int unsigned bank = 0; bank < BANKS; bank++)
            add_result[bank] = add_lhs[bank] + add_rhs[bank];

    bank_local_reduction_buffer #(
        .BANKS(BANKS), .ENTRIES_PER_BANK(ENTRIES), .KEY_WIDTH(KEY_WIDTH),
        .DATA_WIDTH(DATA_WIDTH), .SLOT_WIDTH(SLOT_WIDTH)
    ) dut (.*,
        .clk_i(clk), .rst_ni(rst_n),
        .update_valid_i(update_valid), .update_ready_o(update_ready),
        .update_key_i(update_key), .update_slot_i(update_slot),
        .update_partial_i(update_partial), .update_first_i(update_first),
        .update_last_i(update_last), .add_lhs_o(add_lhs), .add_rhs_o(add_rhs),
        .add_result_i(add_result), .final_valid_o(final_valid),
        .final_ready_i(final_ready), .final_key_o(final_key), .final_data_o(final_data),
        .protocol_error_o(protocol_error)
    );

    task automatic send_update(input int bank, input int slot, input int key,
                               input int value, input bit first, input bit last);
        @(negedge clk);
        update_valid[bank] = 1'b1;
        update_slot[bank] = slot;
        update_key[bank] = key;
        update_partial[bank] = value;
        update_first[bank] = first;
        update_last[bank] = last;
        do @(posedge clk); while (!update_ready[bank]);
        @(negedge clk);
        update_valid[bank] = 1'b0;
        update_first[bank] = 1'b0;
        update_last[bank] = 1'b0;
    endtask

    initial begin
        update_valid = '0;
        update_key = '0;
        update_slot = '0;
        update_partial = '0;
        update_first = '0;
        update_last = '0;
        final_ready = '1;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        send_update(0, 3, 16'h1234, 10, 1, 0);
        send_update(0, 3, 16'h1234, 20, 0, 0);
        send_update(0, 3, 16'h1234, 12, 0, 1);
        @(posedge clk);
        if (!final_valid[0] || final_key[0] != 16'h1234 || final_data[0] != 42)
            $fatal(1, "three-update reduction failed");

        send_update(1, 2, 16'h2222, 7, 1, 1);
        @(posedge clk);
        if (!final_valid[1] || final_data[1] != 7)
            $fatal(1, "first-and-last update failed");

        update_valid[2] = 1'b1;
        update_slot[2] = 4;
        update_key[2] = 16'h3333;
        update_partial[2] = 1;
        update_first[2] = 1'b0;
        #1;
        if (!protocol_error[2] || update_ready[2])
            $fatal(1, "empty-slot continuation was not rejected");
        update_valid[2] = 1'b0;

        $display("BANK_LOCAL_REDUCTION_BUFFER_TB PASS");
        $finish;
    end
endmodule
