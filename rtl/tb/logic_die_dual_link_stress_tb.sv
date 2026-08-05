module logic_die_dual_link_stress_tb;
    localparam int INPUTS = 8;
    localparam int OUTPUTS = 2;
    localparam int KEY_WIDTH = 16;
    localparam int DATA_WIDTH = 32;
    localparam int INDEX_WIDTH = $clog2(INPUTS);
    localparam int SATURATION_CYCLES = 512;
    localparam int RANDOM_CYCLES = 2000;

    logic clk = 0;
    logic rst_n = 0;
    logic [INPUTS-1:0] input_valid, input_ready;
    logic [INPUTS*KEY_WIDTH-1:0] input_key;
    logic [INPUTS*DATA_WIDTH-1:0] input_data;
    logic [OUTPUTS-1:0] output_valid, output_ready;
    logic [OUTPUTS*KEY_WIDTH-1:0] output_key;
    logic [OUTPUTS*DATA_WIDTH-1:0] output_data;
    logic [OUTPUTS*INDEX_WIDTH-1:0] output_source;
    logic [INPUTS-1:0] handshake_q;
    logic [31:0] lfsr = 32'h1ace_b00c;
    logic stalled_q = 0;
    logic [OUTPUTS-1:0] stalled_valid_q;
    logic [OUTPUTS*DATA_WIDTH-1:0] stalled_data_q;
    logic [OUTPUTS*INDEX_WIDTH-1:0] stalled_source_q;
    integer source_count [0:INPUTS-1];
    integer source_sequence [0:INPUTS-1];
    integer saturation_bursts = 0;
    integer random_bursts = 0;
    integer phase = 0;

    always #5 clk = ~clk;

    logic_die_dual_link_arbiter #(
        .INPUTS(INPUTS), .OUTPUTS(OUTPUTS), .KEY_WIDTH(KEY_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk_i(clk), .rst_ni(rst_n), .input_valid_i(input_valid),
        .input_ready_o(input_ready), .input_key_i(input_key), .input_data_i(input_data),
        .output_valid_o(output_valid), .output_ready_i(output_ready),
        .output_key_o(output_key), .output_data_o(output_data),
        .output_source_o(output_source)
    );

    always @(posedge clk) begin
        integer lane;
        integer source;
        integer handshakes;
        if (!rst_n) begin
            handshake_q = '0;
            stalled_q = 1'b0;
        end else begin
            handshake_q = input_valid & input_ready;
            handshakes = 0;
            for (source = 0; source < INPUTS; source = source + 1) begin
                if (handshake_q[source]) begin
                    source_count[source] = source_count[source] + 1;
                    handshakes = handshakes + 1;
                end
            end
            if (phase == 1) saturation_bursts = saturation_bursts + handshakes;
            if (phase == 2) random_bursts = random_bursts + handshakes;

            for (lane = 0; lane < OUTPUTS; lane = lane + 1) begin
                if (output_valid[lane]) begin
                    source = output_source[lane*INDEX_WIDTH +: INDEX_WIDTH];
                    if (!input_valid[source])
                        $fatal(1, "arbiter selected invalid source %0d", source);
                    if (output_data[lane*DATA_WIDTH +: DATA_WIDTH] !=
                        input_data[source*DATA_WIDTH +: DATA_WIDTH])
                        $fatal(1, "payload mismatch on lane %0d", lane);
                end
            end

            if (stalled_q &&
                (output_valid != stalled_valid_q || output_data != stalled_data_q ||
                 output_source != stalled_source_q))
                $fatal(1, "output changed while coupled-ready transaction was stalled");
            stalled_q = |output_valid && !(output_ready[0] &&
                                           (!output_valid[1] || output_ready[1]));
            stalled_valid_q = output_valid;
            stalled_data_q = output_data;
            stalled_source_q = output_source;
        end
    end

    initial begin
        integer cycle;
        integer source;
        input_valid = '0;
        input_key = '0;
        input_data = '0;
        output_ready = '1;
        handshake_q = '0;
        for (source = 0; source < INPUTS; source = source + 1) begin
            source_count[source] = 0;
            source_sequence[source] = 0;
            input_key[source*KEY_WIDTH +: KEY_WIDTH] = source;
            input_data[source*DATA_WIDTH +: DATA_WIDTH] = source * 100000;
        end
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        phase = 1;
        @(negedge clk);
        input_valid = '1;
        for (cycle = 0; cycle < SATURATION_CYCLES; cycle = cycle + 1) begin
            @(negedge clk);
            for (source = 0; source < INPUTS; source = source + 1) begin
                if (handshake_q[source]) begin
                    source_sequence[source] = source_sequence[source] + 1;
                    input_data[source*DATA_WIDTH +: DATA_WIDTH] =
                        source * 100000 + source_sequence[source];
                end
            end
        end
        if (saturation_bursts != SATURATION_CYCLES * OUTPUTS)
            $fatal(1, "saturation throughput was %0d bursts, expected %0d",
                   saturation_bursts, SATURATION_CYCLES * OUTPUTS);
        for (source = 0; source < INPUTS; source = source + 1)
            if (source_count[source] != SATURATION_CYCLES * OUTPUTS / INPUTS)
                $fatal(1, "source %0d was not served fairly: %0d", source,
                       source_count[source]);

        phase = 2;
        for (cycle = 0; cycle < RANDOM_CYCLES; cycle = cycle + 1) begin
            @(negedge clk);
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            output_ready = lfsr[1:0];
            for (source = 0; source < INPUTS; source = source + 1) begin
                if (handshake_q[source]) input_valid[source] = 1'b0;
                if (!input_valid[source] && lfsr[(source + 3) % 32]) begin
                    source_sequence[source] = source_sequence[source] + 1;
                    input_valid[source] = 1'b1;
                    input_data[source*DATA_WIDTH +: DATA_WIDTH] =
                        source * 100000 + source_sequence[source];
                end
            end
        end

        if (random_bursts == 0) $fatal(1, "random phase made no progress");
        for (source = 0; source < INPUTS; source = source + 1)
            if (source_count[source] <= SATURATION_CYCLES * OUTPUTS / INPUTS)
                $fatal(1, "source %0d starved during random phase", source);

        $display("LOGIC_DIE_DUAL_LINK_STRESS_TB PASS saturation_bursts[%0d] saturation_bytes_per_cycle[64] random_bursts[%0d]",
                 saturation_bursts, random_bursts);
        $finish;
    end
endmodule
