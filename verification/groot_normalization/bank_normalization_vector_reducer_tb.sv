module bank_normalization_vector_reducer_tb;
    localparam int LANES = 16;
    logic clk = 0, rst_n = 0;
    logic begin_valid, begin_ready;
    logic [15:0] begin_tag, begin_vector_count;
    logic vector_valid, vector_ready;
    logic [LANES-1:0][15:0] vector_data;
    logic result_valid, result_ready;
    logic [15:0] result_tag, result_sum, result_sumsq;
    logic protocol_error;
    integer accepted_vectors, cycles;
    always #5 clk = ~clk;
    always @(posedge clk) if (rst_n) cycles <= cycles + 1;

    bank_normalization_vector_reducer #(.LANES(LANES)) dut (
        .clk_i(clk), .rst_ni(rst_n),
        .begin_valid_i(begin_valid), .begin_ready_o(begin_ready),
        .begin_tag_i(begin_tag), .begin_vector_count_i(begin_vector_count),
        .vector_valid_i(vector_valid), .vector_ready_o(vector_ready),
        .vector_data_i(vector_data), .result_valid_o(result_valid),
        .result_ready_i(result_ready), .result_tag_o(result_tag),
        .result_sum_o(result_sum), .result_sumsq_o(result_sumsq),
        .protocol_error_o(protocol_error));

    task automatic send_vector(input logic [15:0] value);
        begin
            @(negedge clk);
            for (integer lane = 0; lane < LANES; lane++) vector_data[lane] = value;
            vector_valid = 1;
            while (!vector_ready) @(negedge clk);
            @(negedge clk);
            vector_valid = 0;
            accepted_vectors = accepted_vectors + 1;
        end
    endtask

    initial begin
        begin_valid=0; begin_tag=0; begin_vector_count=0;
        vector_valid=0; vector_data='0; result_ready=1;
        accepted_vectors=0; cycles=0;
        repeat(3) @(negedge clk); rst_n=1;
        @(negedge clk); begin_tag=16'h1234; begin_vector_count=2; begin_valid=1;
        @(negedge clk); begin_valid=0;
        send_vector(16'h3c00); // sixteen 1.0 values
        send_vector(16'h4000); // sixteen 2.0 values
        if (!result_valid) @(negedge clk);
        if (!result_valid) $fatal(1,"missing result");
        if (result_tag !== 16'h1234) $fatal(1,"bad tag");
        if (result_sum !== 16'h5200) $fatal(1,"sum got=%h expected=5200",result_sum);
        if (result_sumsq !== 16'h5500) $fatal(1,"sumsq got=%h expected=5500",result_sumsq);
        if (protocol_error) $fatal(1,"unexpected protocol error");
        $display("BANK_NORMALIZATION_VECTOR_REDUCER_TB PASS lanes=%0d vectors=%0d cycles=%0d",
                 LANES,accepted_vectors,cycles);
        $finish;
    end
endmodule
