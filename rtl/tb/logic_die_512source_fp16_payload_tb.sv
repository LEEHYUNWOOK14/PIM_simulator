module logic_die_512source_fp16_payload_tb;
    localparam int CHANNELS = 64;
    localparam int PIM_BLOCKS = 8;
    localparam int SOURCES = CHANNELS * PIM_BLOCKS;
    localparam int ENTRIES = 16;
    localparam int KEY_WIDTH = 64;
    localparam int LANES = 16;
    localparam int DATA_WIDTH = LANES * 16;
    localparam int SLOT_WIDTH = $clog2(ENTRIES);
    localparam int EVENTS = 24576;
    localparam int WAVES = EVENTS / SOURCES;

    logic clk = 0, rst_n = 0;
    logic [SOURCES-1:0] update_valid, update_ready, update_first, update_last;
    logic [SOURCES-1:0][KEY_WIDTH-1:0] update_key;
    logic [SOURCES-1:0][SLOT_WIDTH-1:0] update_slot;
    logic [SOURCES-1:0][DATA_WIDTH-1:0] update_partial;
    logic [SOURCES-1:0] final_valid, final_ready, protocol_error;
    logic [SOURCES-1:0][KEY_WIDTH-1:0] final_key;
    logic [SOURCES-1:0][DATA_WIDTH-1:0] final_data;
    logic [SOURCES-1:0][KEY_WIDTH-1:0] expected_key;
    logic [SOURCES-1:0][DATA_WIDTH-1:0] expected_data;

    always #5 clk = ~clk;
    bank_local_fp16_reduction #(
        .BANKS(SOURCES), .ENTRIES_PER_BANK(ENTRIES), .KEY_WIDTH(KEY_WIDTH),
        .LANES(LANES), .SLOT_WIDTH(SLOT_WIDTH)
    ) dut (
        .clk_i(clk), .rst_ni(rst_n), .update_valid_i(update_valid),
        .update_ready_o(update_ready), .update_key_i(update_key),
        .update_slot_i(update_slot), .update_partial_i(update_partial),
        .update_first_i(update_first), .update_last_i(update_last),
        .final_valid_o(final_valid), .final_ready_i(final_ready),
        .final_key_o(final_key), .final_data_o(final_data),
        .protocol_error_o(protocol_error)
    );

    initial begin
        integer fd, parsed, event_sequence, cycle_value, channel, rank, pim_block;
        integer tap_index, tap_count, source, wave, accepted, finalized;
        reg [KEY_WIDTH-1:0] key;
        reg [DATA_WIDTH-1:0] partial, expected;
        reg [2047:0] header;

        update_valid = '0; update_key = '0; update_slot = '0;
        update_partial = '0; update_first = '0; update_last = '0;
        final_ready = '1; expected_key = '0; expected_data = '0;
        accepted = 0; finalized = 0;
        fd = $fopen("experiment/results/depthwise_actual_payload_trace.csv.payload.csv", "r");
        if (!fd) $fatal(1, "unable to open C++ FP16 payload trace");
        parsed = $fgets(header, fd);
        repeat (2) @(posedge clk);
        rst_n = 1;

        for (wave = 0; wave < WAVES; wave = wave + 1) begin
            @(negedge clk);
            update_valid = '0;
            for (integer item = 0; item < SOURCES; item = item + 1) begin
                parsed = $fscanf(fd, "%d,%d,%d,%d,%d,%d,%d,%d,%h,%h\n",
                    event_sequence, cycle_value, channel, rank, pim_block, key,
                    tap_index, tap_count, partial, expected);
                if (parsed != 10) $fatal(1, "trace parse failed at event %0d", accepted);
                source = channel * PIM_BLOCKS + pim_block;
                if (tap_count != 3 || event_sequence != accepted)
                    $fatal(1, "unexpected trace order sequence=%0d tap_count=%0d",
                           event_sequence, tap_count);
                update_valid[source] = 1;
                update_key[source] = key;
                update_slot[source] = (event_sequence / SOURCES) % ENTRIES;
                update_partial[source] = partial;
                update_first[source] = tap_index == 1;
                update_last[source] = tap_index == tap_count;
                expected_key[source] = key;
                expected_data[source] = expected;
                accepted = accepted + 1;
            end
            #1;
            if (update_ready !== {SOURCES{1'b1}} || |protocol_error)
                $fatal(1, "reduction input rejected at wave %0d", wave);
            @(posedge clk);
            @(negedge clk);
            update_valid = '0;
            if (wave >= 2 * ENTRIES) begin
                if (final_valid !== {SOURCES{1'b1}})
                    $fatal(1, "missing finals at wave %0d", wave);
                for (source = 0; source < SOURCES; source = source + 1) begin
                    if (final_key[source] !== expected_key[source] ||
                        final_data[source] !== expected_data[source])
                        $fatal(1, "source %0d key=%h/%h data=%h/%h", source,
                               final_key[source], expected_key[source],
                               final_data[source], expected_data[source]);
                    finalized = finalized + 1;
                end
            end
        end
        $fclose(fd);
        if (accepted != EVENTS || finalized != EVENTS / 3)
            $fatal(1, "count mismatch accepted=%0d finalized=%0d", accepted, finalized);
        $display("LOGIC_DIE_512SOURCE_FP16_PAYLOAD_TB PASS partials[%0d] finals[%0d] lanes[%0d] reference[C++ MobileNetV4]",
                 accepted, finalized, LANES);
        $finish;
    end
endmodule
