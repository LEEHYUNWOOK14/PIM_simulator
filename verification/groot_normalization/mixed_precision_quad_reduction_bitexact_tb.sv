module mixed_precision_quad_reduction_bitexact_tb;
    localparam int CASES = 64;
    logic clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    logic input_valid;
    logic a_input_ready;
    logic [15:0] input_tag;
    logic [15:0][31:0] partial_sum, partial_sumsq;
    logic a_valid, a_ready;
    logic [15:0] a_tag;
    logic [31:0] a_sum, a_sumsq;

    logic [3:0] q_input_ready, q_valid, q_ready;
    logic [3:0][15:0] q_tag;
    logic [3:0][31:0] q_sum, q_sumsq;
    logic b_valid, b_ready;
    logic [15:0] b_tag;
    logic [31:0] b_sum, b_sumsq;
    logic expected_valid;
    logic [15:0] expected_tag;
    logic [31:0] expected_sum, expected_sumsq;
    integer completed;

    mixed_precision_global_reducer16_pipe u_a (
        .clk_i(clk), .rst_ni(rst_n), .input_valid_i(input_valid),
        .input_ready_o(a_input_ready), .input_tag_i(input_tag),
        .partial_sum_i(partial_sum), .partial_sumsq_i(partial_sumsq),
        .output_valid_o(a_valid), .output_ready_i(a_ready),
        .output_tag_o(a_tag), .sum_o(a_sum), .sumsq_o(a_sumsq)
    );

    for (genvar quad = 0; quad < 4; quad++) begin : g_quad
        mixed_precision_quad_reducer4_pipe u_quad (
            .clk_i(clk), .rst_ni(rst_n), .input_valid_i(input_valid),
            .input_ready_o(q_input_ready[quad]), .input_tag_i(input_tag),
            .partial_sum_i(partial_sum[quad*4 +: 4]),
            .partial_sumsq_i(partial_sumsq[quad*4 +: 4]),
            .output_valid_o(q_valid[quad]), .output_ready_i(q_ready[quad]),
            .output_tag_o(q_tag[quad]), .sum_o(q_sum[quad]),
            .sumsq_o(q_sumsq[quad])
        );
    end

    mixed_precision_quad_packet_reducer_pipe u_b (
        .clk_i(clk), .rst_ni(rst_n), .input_valid_i(q_valid),
        .input_ready_o(q_ready), .input_tag_i(q_tag),
        .partial_sum_i(q_sum), .partial_sumsq_i(q_sumsq),
        .output_valid_o(b_valid), .output_ready_i(b_ready),
        .output_tag_o(b_tag), .sum_o(b_sum), .sumsq_o(b_sumsq)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            expected_valid <= 1'b0;
            expected_tag <= '0;
            expected_sum <= '0;
            expected_sumsq <= '0;
            completed <= 0;
        end else begin
            if (a_valid && a_ready) begin
                if (expected_valid) $fatal(1, "A result queue overflow");
                expected_valid <= 1'b1;
                expected_tag <= a_tag;
                expected_sum <= a_sum;
                expected_sumsq <= a_sumsq;
            end
            if (b_valid && b_ready) begin
                if (!expected_valid) $fatal(1, "B result arrived before A reference");
                if (b_tag !== expected_tag || b_sum !== expected_sum ||
                    b_sumsq !== expected_sumsq)
                    $fatal(1, "bit-exact mismatch case=%0d tag=%h/%h sum=%h/%h sumsq=%h/%h",
                        completed, b_tag, expected_tag, b_sum, expected_sum,
                        b_sumsq, expected_sumsq);
                expected_valid <= 1'b0;
                completed <= completed + 1;
            end
        end
    end

    function automatic logic [31:0] sample_fp(input integer index);
        case (index % 12)
            0: sample_fp = 32'h00000000;
            1: sample_fp = 32'h3f800000;
            2: sample_fp = 32'hbf800000;
            3: sample_fp = 32'h3f000000;
            4: sample_fp = 32'h40000000;
            5: sample_fp = 32'hc0400000;
            6: sample_fp = 32'h3dcccccd;
            7: sample_fp = 32'h41200000;
            8: sample_fp = 32'h3eaaaaab;
            9: sample_fp = 32'hc1000000;
            10: sample_fp = 32'h40490fdb;
            default: sample_fp = 32'h3a83126f;
        endcase
    endfunction

    initial begin
        input_valid = 1'b0;
        input_tag = '0;
        partial_sum = '0;
        partial_sumsq = '0;
        a_ready = 1'b1;
        b_ready = 1'b1;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        for (integer test_case = 0; test_case < CASES; test_case++) begin
            while (!a_input_ready || !(&q_input_ready)) @(negedge clk);
            input_tag = 16'h7000 + test_case;
            for (integer bank = 0; bank < 16; bank++) begin
                partial_sum[bank] = sample_fp(test_case*17 + bank*5);
                partial_sumsq[bank] = sample_fp(test_case*11 + bank*7 + 3) & 32'h7fffffff;
            end
            input_valid = 1'b1;
            @(negedge clk);
            input_valid = 1'b0;
            while (completed != test_case+1) @(negedge clk);
        end

        $display("MIXED_PRECISION_QUAD_REDUCTION_BITEXACT_TB PASS cases=%0d exact_sum=1 exact_sumsq=1 order=(b0+b1)+(b2+b3),(q0+q1)+(q2+q3)", CASES);
        $finish;
    end

    initial begin
        repeat (10000) @(negedge clk);
        $fatal(1, "timeout completed=%0d", completed);
    end
endmodule
