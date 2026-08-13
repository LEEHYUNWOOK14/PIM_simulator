module logic_normalization_scalar_engine_tb #(
    parameter int DATA_FORMAT = 0
);
    logic clk = 1'b0, rst_n = 1'b0;
    logic request_valid, request_ready, rms_norm;
    logic [15:0] request_tag, sum, sumsq, inv_hidden, epsilon;
    logic response_valid, response_ready, response_rms_norm, variance_clamped;
    logic [15:0] response_tag, mean, inv_std;
    logic [127:0] vectors [0:2047];
    integer sent, received, cycles, mismatches;
    logic stalled_last;
    logic [49:0] stalled_payload;

    always #5 clk = ~clk;
    logic_normalization_scalar_engine #(.DATA_FORMAT(DATA_FORMAT)) dut(
        .clk_i(clk),.rst_ni(rst_n),.request_valid_i(request_valid),
        .request_ready_o(request_ready),.rms_norm_i(rms_norm),
        .request_tag_i(request_tag),.sum_i(sum),.sumsq_i(sumsq),
        .inv_hidden_i(inv_hidden),.epsilon_i(epsilon),
        .response_valid_o(response_valid),.response_ready_i(response_ready),
        .response_rms_norm_o(response_rms_norm),.response_tag_o(response_tag),
        .mean_o(mean),.inv_std_o(inv_std),.variance_clamped_o(variance_clamped));

    always @(posedge clk) begin
        if(rst_n) begin
            if(stalled_last && (!response_valid ||
               {response_rms_norm,variance_clamped,response_tag,mean,inv_std} !== stalled_payload)) begin
                $display("NORMALIZATION_SCALAR FAIL stall stability index=%0d",received);
                mismatches=mismatches+1;
            end
            if(response_valid && response_ready) begin
                if(response_rms_norm !== vectors[received][112] ||
                   response_tag[14:0] !== vectors[received][14:0] ||
                   variance_clamped !== vectors[received][15] ||
                   mean !== vectors[received][47:32] ||
                   inv_std !== vectors[received][31:16]) begin
                    if(mismatches < 20)
                        $display("NORMALIZATION_SCALAR FAIL index=%0d mode=%b/%b clamp=%b/%b mean=%h/%h inv=%h/%h",
                            received,response_rms_norm,vectors[received][112],
                            variance_clamped,vectors[received][15],mean,vectors[received][47:32],
                            inv_std,vectors[received][31:16]);
                    mismatches=mismatches+1;
                end
                received=received+1;
            end
            if(request_valid && request_ready) sent=sent+1;
            stalled_last=response_valid && !response_ready;
            stalled_payload={response_rms_norm,variance_clamped,response_tag,mean,inv_std};
        end
    end

    initial begin
        if(DATA_FORMAT)$readmemh("verification/groot_normalization/bf16_normalization_scalar_vectors.hex",vectors);
        else $readmemh("verification/groot_normalization/normalization_scalar_vectors.hex",vectors);
        request_valid=0; response_ready=0; rms_norm=0; request_tag=0;
        sum=0; sumsq=0; inv_hidden=0; epsilon=0;
        sent=0; received=0; cycles=0; mismatches=0;
        stalled_last=0; stalled_payload=0;
        repeat(3) @(posedge clk);
        rst_n=1;
        while(received < 2048) begin
            @(negedge clk);
            cycles=cycles+1;
            response_ready=cycles%5 != 0;
            request_valid=sent<2048;
            rms_norm=vectors[sent][112];
            request_tag={1'b0,vectors[sent][14:0]};
            sum=vectors[sent][111:96];
            sumsq=vectors[sent][95:80];
            inv_hidden=vectors[sent][79:64];
            epsilon=vectors[sent][63:48];
        end
        if(mismatches) $fatal(1,"LOGIC_NORMALIZATION_SCALAR_ENGINE_TB FAIL mismatches=%0d",mismatches);
        $display("LOGIC_NORMALIZATION_SCALAR_ENGINE_TB PASS format=%0d vectors=2048 cycles=%0d",DATA_FORMAT,cycles);
        $finish;
    end
endmodule
