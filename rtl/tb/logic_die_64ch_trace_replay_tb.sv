module logic_die_64ch_trace_replay_tb;
    localparam int CHANNELS = 64;
    localparam int PIM_BLOCKS = 8;
    localparam int SOURCES = CHANNELS * PIM_BLOCKS;
    localparam int ENTRIES = 16;
    localparam int KEY_WIDTH = 64;
    localparam int DATA_WIDTH = 32;
    localparam int SLOT_WIDTH = $clog2(ENTRIES);
    localparam int CHANNEL_WIDTH = $clog2(CHANNELS);
    localparam int EXPECTED_BURSTS = 8192;

    logic clk = 0;
    logic rst_n = 0;
    logic [SOURCES-1:0] update_valid, update_ready, update_first, update_last;
    logic [SOURCES*KEY_WIDTH-1:0] update_key;
    logic [SOURCES*SLOT_WIDTH-1:0] update_slot;
    logic [SOURCES*DATA_WIDTH-1:0] update_partial;
    logic [SOURCES*DATA_WIDTH-1:0] add_lhs, add_rhs, add_result;
    logic [1:0] link_valid, link_ready;
    logic [2*KEY_WIDTH-1:0] link_key;
    logic [2*DATA_WIDTH-1:0] link_data;
    logic [2*CHANNEL_WIDTH-1:0] link_channel;
    logic [SOURCES-1:0] protocol_error;
    integer pending [0:SOURCES-1];
    integer accepted = 0;
    integer emitted = 0;
    integer full_cycles = 0;
    integer partial_cycles = 0;

    always #5 clk = ~clk;
    for (genvar source = 0; source < SOURCES; source++) begin : g_adder
        always @*
            add_result[source*DATA_WIDTH +: DATA_WIDTH] =
                add_lhs[source*DATA_WIDTH +: DATA_WIDTH] +
                add_rhs[source*DATA_WIDTH +: DATA_WIDTH];
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

    always @(posedge clk) begin
        if (rst_n) begin
            if (link_valid == 2'b11) full_cycles = full_cycles + 1;
            else if (|link_valid) partial_cycles = partial_cycles + 1;
            emitted = emitted + link_valid[0] + link_valid[1];
            if (|protocol_error) $fatal(1, "protocol error during trace replay");
        end
    end

    initial begin
        integer fd;
        integer parsed;
        integer event_sequence;
        integer event_cycle;
        integer event_channel;
        integer event_rank;
        integer event_block;
        reg [63:0] event_key;
        integer first_cycle;
        integer replay_cycle;
        integer source;
        integer next_valid;
        reg [1023:0] header;

        update_valid = '0;
        update_first = '1;
        update_last = '1;
        update_key = '0;
        update_slot = '0;
        update_partial = '0;
        link_ready = 2'b11;
        for (source = 0; source < SOURCES; source = source + 1) pending[source] = 0;

        fd = $fopen("experiment/results/depthwise_actual_arrival_trace.csv", "r");
        if (fd == 0) $fatal(1, "unable to open C++ arrival trace");
        parsed = $fgets(header, fd);
        next_valid = $fscanf(fd, "%d,%d,%d,%d,%d,%d\n", event_sequence, event_cycle,
                             event_channel, event_rank, event_block, event_key);
        if (next_valid != 6) $fatal(1, "unable to read first trace event");
        first_cycle = event_cycle;
        replay_cycle = 0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        while (emitted < EXPECTED_BURSTS && replay_cycle < 10000) begin
            @(negedge clk);
            for (source = 0; source < SOURCES; source = source + 1)
                if (update_valid[source] && update_ready[source]) begin
                    pending[source] = pending[source] - 1;
                    accepted = accepted + 1;
                end

            while (next_valid == 6 && event_cycle - first_cycle <= replay_cycle) begin
                source = event_channel * PIM_BLOCKS + event_block;
                pending[source] = pending[source] + 1;
                next_valid = $fscanf(fd, "%d,%d,%d,%d,%d,%d\n", event_sequence, event_cycle,
                                     event_channel, event_rank, event_block, event_key);
            end

            for (source = 0; source < SOURCES; source = source + 1) begin
                update_valid[source] = pending[source] != 0;
                update_key[source*KEY_WIDTH +: KEY_WIDTH] = source;
                update_partial[source*DATA_WIDTH +: DATA_WIDTH] = source;
            end
            replay_cycle = replay_cycle + 1;
        end
        $fclose(fd);

        if (emitted != EXPECTED_BURSTS || accepted != EXPECTED_BURSTS)
            $fatal(1, "trace replay count mismatch accepted=%0d emitted=%0d",
                   accepted, emitted);
        if (full_cycles != EXPECTED_BURSTS / 2 || partial_cycles != 0)
            $fatal(1, "trace replay was not continuously saturated: full=%0d partial=%0d",
                   full_cycles, partial_cycles);

        $display("LOGIC_DIE_64CH_TRACE_REPLAY_TB PASS bursts[%0d] full_cycles[%0d] bytes_per_active_cycle[64]",
                 emitted, full_cycles);
        $finish;
    end
endmodule
