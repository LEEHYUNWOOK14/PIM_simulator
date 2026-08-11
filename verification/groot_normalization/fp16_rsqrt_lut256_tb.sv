module fp16_rsqrt_lut256_tb;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic input_valid;
    logic input_ready;
    logic [15:0] input_data;
    logic output_valid;
    logic output_ready;
    logic [15:0] output_data;
    logic [31:0] vectors [0:65535];
    integer mismatches, sent, received, cycles;
    logic stalled_last;
    logic [15:0] stalled_data;

    always #5 clk = ~clk;

    fp16_rsqrt_lut256 dut(
        .clk_i(clk),.rst_ni(rst_n),.input_valid_i(input_valid),
        .input_ready_o(input_ready),.input_data_i(input_data),
        .output_valid_o(output_valid),.output_ready_i(output_ready),
        .output_data_o(output_data));

    initial begin
        $readmemh("verification/groot_normalization/fp16_rsqrt_exhaustive.hex",vectors);
        input_valid = 1'b0;
        input_data = '0;
        output_ready = 1'b0;
        mismatches = 0; sent = 0; received = 0; cycles = 0;
        stalled_last = 1'b0; stalled_data = '0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        while (received < 65536) begin
            @(negedge clk);
            if (stalled_last && (!output_valid || output_data !== stalled_data)) begin
                $display("RSQRT FAIL stall stability received=%0d",received);
                mismatches = mismatches + 1;
            end
            if (output_valid && output_ready) begin
                if (output_data !== vectors[received][15:0]) begin
                    if (mismatches < 20)
                        $display("RSQRT FAIL input=%h expected=%h actual=%h",
                            vectors[received][31:16],vectors[received][15:0],output_data);
                    mismatches = mismatches + 1;
                end
                received = received + 1;
            end
            if (input_valid && input_ready) sent = sent + 1;
            cycles = cycles + 1;
            output_ready = cycles % 7 != 0;
            input_valid = sent < 65536;
            input_data = sent < 65536 ? vectors[sent][31:16] : '0;
            stalled_last = output_valid && !output_ready;
            stalled_data = output_data;
        end
        if (mismatches != 0) $fatal(1,"FP16_RSQRT_LUT256_TB FAIL mismatches=%0d",mismatches);
        $display("FP16_RSQRT_LUT256_TB PASS vectors=65536 cycles=%0d latency=1 II=1",cycles);
        $finish;
    end
endmodule
