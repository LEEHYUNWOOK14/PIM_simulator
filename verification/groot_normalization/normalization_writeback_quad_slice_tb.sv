`timescale 1ns/1ps

module normalization_writeback_quad_slice_tb;
    localparam int BANKS = 16;
    localparam int LANES = 8;
    localparam int TAG_WIDTH = 16;

    logic clk_i = 1'b0;
    logic rst_ni = 1'b0;
    logic [BANKS-1:0] source_valid_i;
    logic [BANKS-1:0] source_ready_o;
    logic [BANKS-1:0][TAG_WIDTH-1:0] source_tag_i;
    logic [BANKS-1:0][LANES-1:0][15:0] source_data_i;
    logic [BANKS-1:0] source_last_i;
    logic [BANKS-1:0] sink_valid_o;
    logic [BANKS-1:0] sink_ready_i;
    logic [BANKS-1:0][TAG_WIDTH-1:0] sink_tag_o;
    logic [BANKS-1:0][LANES-1:0][15:0] sink_data_o;
    logic [BANKS-1:0] sink_last_o;
    logic protocol_error_o;

    logic [BANKS-1:0][TAG_WIDTH-1:0] expected_tag;
    logic [BANKS-1:0][LANES-1:0][15:0] expected_data;
    logic [BANKS-1:0] expected_last;

    always #5 clk_i = ~clk_i;

    normalization_writeback_quad_slice #(
        .BANKS(BANKS), .QUADS(4), .LANES(LANES), .TAG_WIDTH(TAG_WIDTH)
    ) dut (.*);

    task automatic set_payload(input int unsigned seq_id);
        source_data_i = (seq_id == 1) ?
            {BANKS*LANES{16'h1a5a}} : {BANKS*LANES{16'h2b6b}};
        for (int bank = 0; bank < BANKS; bank++) begin
            source_tag_i[bank] = seq_id * 16 + bank;
            source_last_i[bank] = ((seq_id + bank) % 3) == 0;
        end
    endtask

    task automatic remember_payload;
        expected_tag = source_tag_i;
        expected_data = source_data_i;
        expected_last = source_last_i;
    endtask

    task automatic check_payload(input string phase);
        if (sink_tag_o !== expected_tag || sink_data_o !== expected_data ||
            sink_last_o !== expected_last)
            $fatal(1, "%s payload mismatch", phase);
    endtask

    initial begin
        source_valid_i = '0;
        source_tag_i = '0;
        source_data_i = '0;
        source_last_i = '0;
        sink_ready_i = '0;

        repeat (3) @(posedge clk_i);
        rst_ni = 1'b1;
        @(negedge clk_i);

        // Capture transaction 1 while the sink is blocked.
        set_payload(1);
        remember_payload();
        source_valid_i = '1;
        @(posedge clk_i); #1;
        if (sink_valid_o !== '1 || source_ready_o !== '0)
            $fatal(1, "slice did not become full");
        check_payload("initial capture");

        // Payload must remain stable for arbitrary backpressure.
        source_valid_i = '0;
        repeat (4) begin
            @(posedge clk_i); #1;
            if (sink_valid_o !== '1 || source_ready_o !== '0)
                $fatal(1, "full/ready state changed under backpressure");
            check_payload("backpressure hold");
        end

        // Consume transaction 1 and replace it with transaction 2 on the same
        // edge. This is the one-transaction-per-cycle elastic case.
        @(negedge clk_i);
        sink_ready_i = '1;
        set_payload(2);
        remember_payload();
        source_valid_i = '1;
        #1;
        if (source_ready_o !== '1)
            $fatal(1, "slice did not permit simultaneous dequeue/enqueue");
        @(posedge clk_i); #1;
        if (sink_valid_o !== '1)
            $fatal(1, "replacement transaction was lost");
        check_payload("simultaneous dequeue/enqueue");

        // Drain transaction 2 and verify the slice becomes empty.
        @(negedge clk_i);
        source_valid_i = '0;
        @(posedge clk_i); #1;
        if (sink_valid_o !== '0 || source_ready_o !== '1)
            $fatal(1, "slice did not drain");

        // A partial 16-bank transaction is illegal and must be reported
        // sticky without being accepted as a complete transaction.
        @(negedge clk_i);
        sink_ready_i = '0;
        source_valid_i = 16'h0001;
        @(posedge clk_i); #1;
        if (!protocol_error_o || sink_valid_o !== '0)
            $fatal(1, "partial-valid protocol violation was not contained");
        source_valid_i = '0;
        repeat (2) @(posedge clk_i);
        if (!protocol_error_o)
            $fatal(1, "protocol error was not sticky");

        $display("NORMALIZATION_WRITEBACK_QUAD_SLICE_TB PASS");
        $finish;
    end
endmodule
