module normalization_writeback_quad_local_reset_tb;
    localparam int BANKS = 16;
    localparam int QUADS = 4;
    localparam int LANES = 8;
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic [QUADS-1:0] quad_rst_n;
    logic control_rst_n;
    logic [BANKS-1:0] source_valid, source_ready, source_last;
    logic [BANKS-1:0][15:0] source_tag;
    logic [BANKS*LANES-1:0][15:0] source_data;
    logic [BANKS-1:0] sink_valid, sink_ready, sink_last;
    logic [BANKS-1:0][15:0] sink_tag;
    logic [BANKS*LANES-1:0][15:0] sink_data;
    logic protocol_error;

    assign control_rst_n = &quad_rst_n;
    for (genvar quad = 0; quad < QUADS; quad++) begin : g_quad_reset
        normalization_quad_reset_leaf u_reset_leaf (
            .clk_i(clk), .rst_ni(rst_n), .quad_rst_ni_o(quad_rst_n[quad])
        );
    end
    normalization_writeback_quad_local_reset_slice #(
        .BANKS(BANKS), .QUADS(QUADS), .LANES(LANES)
    ) dut (
        .clk_i(clk), .rst_ni(control_rst_n), .quad_rst_ni_i(quad_rst_n),
        .source_valid_i(source_valid), .source_ready_o(source_ready),
        .source_tag_i(source_tag), .source_data_i(source_data),
        .source_last_i(source_last), .sink_valid_o(sink_valid),
        .sink_ready_i(sink_ready), .sink_tag_o(sink_tag),
        .sink_data_o(sink_data), .sink_last_o(sink_last),
        .protocol_error_o(protocol_error)
    );

    task automatic load_payload(input logic [15:0] base);
        for (integer bank = 0; bank < BANKS; bank++) begin
            source_tag[bank] = base + bank;
            source_last[bank] = bank[0];
            for (integer lane = 0; lane < LANES; lane++)
                source_data[bank*LANES+lane] = base ^ (bank << 8) ^ lane;
        end
    endtask

    initial begin
        source_valid = '0;
        source_tag = '0;
        source_data = '0;
        source_last = '0;
        sink_ready = '0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        wait (control_rst_n === 1'b1);
        wait (source_ready === '1);

        // Fill all four local payload stores and hold the downstream side.
        @(negedge clk); load_payload(16'h4100); source_valid = '1;
        @(posedge clk); if (source_ready !== '1) $fatal(1, "initial payload not accepted");
        @(negedge clk); source_valid = '0;
        @(posedge clk); #1;
        if (sink_valid !== '1) $fatal(1, "payload was not held in flight");

        // Asynchronous root assertion must clear occupancy and every local
        // quad payload before the transaction can leak downstream.
        @(negedge clk); rst_n = 1'b0; #1;
        if (sink_valid !== '0 || sink_tag !== '0 || sink_data !== '0 || sink_last !== '0)
            $fatal(1, "in-flight writeback survived quad reset");
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        wait (control_rst_n === 1'b1);
        wait (source_ready === '1);
        if (protocol_error) $fatal(1, "reset raised protocol error");

        // A fresh post-reset packet must be delivered exactly once and retain
        // all per-quad tag/data/last bits.
        @(negedge clk); load_payload(16'h5200); source_valid = '1;
        @(posedge clk); if (source_ready !== '1) $fatal(1, "post-reset payload not accepted");
        @(negedge clk); source_valid = '0;
        @(posedge clk); #1;
        for (integer bank = 0; bank < BANKS; bank++) begin
            if (!sink_valid[bank] || sink_tag[bank] !== 16'h5200 + bank ||
                sink_last[bank] !== bank[0])
                $fatal(1, "post-reset control mismatch bank=%0d", bank);
            for (integer lane = 0; lane < LANES; lane++)
                if (sink_data[bank*LANES+lane] !== (16'h5200 ^ (bank << 8) ^ lane))
                    $fatal(1, "post-reset data mismatch bank=%0d lane=%0d", bank, lane);
        end
        @(negedge clk); sink_ready = '1;
        @(posedge clk); @(negedge clk); sink_ready = '0;
        @(posedge clk); #1;
        if (sink_valid !== '0 || protocol_error)
            $fatal(1, "post-reset transaction did not retire cleanly");
        $display("NORMALIZATION_WRITEBACK_QUAD_LOCAL_RESET_TB PASS inflight_reset=1 quads=4 bit_exact=1 stale_writeback=0");
        $finish;
    end
    initial begin
        repeat (100) @(negedge clk);
        $fatal(1, "timeout");
    end
endmodule
