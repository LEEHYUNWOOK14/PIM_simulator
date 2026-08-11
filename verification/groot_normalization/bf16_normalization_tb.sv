module bf16_normalization_tb;
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic [15:0] add_a, add_b, add_y, mul_a, mul_b, mul_y;
    logic begin_valid, begin_ready, element_valid, element_ready;
    logic [15:0] begin_tag, element_count, element_data;
    logic reduce_valid, reduce_ready, reduce_error;
    logic [15:0] reduce_tag, reduce_sum, reduce_sumsq;
    logic config_valid, config_ready, rms_norm, apply_valid, apply_ready;
    logic [15:0] config_tag, mean, inv_std, apply_tag, x, gamma, beta;
    logic apply_last, result_valid, result_ready, result_last, context_error;
    logic [15:0] result_tag, result_data;
    integer errors;

    bf16_add add_dut(.lhs_i(add_a), .rhs_i(add_b), .result_o(add_y));
    bf16_mul mul_dut(.lhs_i(mul_a), .rhs_i(mul_b), .result_o(mul_y));
    bank_normalization_local_reducer #(.DATA_FORMAT(1)) reducer (
        .clk_i(clk), .rst_ni(rst_n), .begin_valid_i(begin_valid),
        .begin_ready_o(begin_ready), .begin_tag_i(begin_tag),
        .begin_element_count_i(element_count), .element_valid_i(element_valid),
        .element_ready_o(element_ready), .element_data_i(element_data),
        .result_valid_o(reduce_valid), .result_ready_i(reduce_ready),
        .result_tag_o(reduce_tag), .result_sum_o(reduce_sum),
        .result_sumsq_o(reduce_sumsq), .protocol_error_o(reduce_error));
    bank_normalization_apply #(.DATA_FORMAT(1)) apply (
        .clk_i(clk), .rst_ni(rst_n), .config_valid_i(config_valid),
        .config_ready_o(config_ready), .config_rms_norm_i(rms_norm),
        .config_tag_i(config_tag), .config_mean_i(mean),
        .config_inv_std_i(inv_std), .element_valid_i(apply_valid),
        .element_ready_o(apply_ready), .element_tag_i(apply_tag),
        .element_x_i(x), .element_gamma_i(gamma), .element_beta_i(beta),
        .element_last_i(apply_last), .result_valid_o(result_valid),
        .result_ready_i(result_ready), .result_tag_o(result_tag),
        .result_data_o(result_data), .result_last_o(result_last),
        .context_error_o(context_error));

    task check_primitives(input logic [15:0] aa, ab, ae, ma, mb, me);
        begin
            add_a=aa; add_b=ab; mul_a=ma; mul_b=mb; #1;
            if (add_y !== ae) begin $display("BF16 ADD %h %h got=%h exp=%h",aa,ab,add_y,ae); errors=errors+1; end
            if (mul_y !== me) begin $display("BF16 MUL %h %h got=%h exp=%h",ma,mb,mul_y,me); errors=errors+1; end
        end
    endtask

    task send_reduce(input logic [15:0] value);
        begin
            element_data=value; element_valid=1;
            do @(posedge clk); while (!element_ready);
            @(negedge clk); element_valid=0;
        end
    endtask

    initial begin
        errors=0; add_a=0; add_b=0; mul_a=0; mul_b=0;
        begin_valid=0; begin_tag=0; element_count=0; element_valid=0; element_data=0;
        reduce_ready=0; config_valid=0; rms_norm=0; config_tag=0; mean=0; inv_std=0;
        apply_valid=0; apply_tag=0; x=0; gamma=0; beta=0; apply_last=0; result_ready=0;

        check_primitives(16'h3f80,16'h4000,16'h4040,16'h3fc0,16'h4000,16'h4040);
        check_primitives(16'h3f80,16'hbf80,16'h0000,16'h0000,16'h7f80,16'h7fc0);
        check_primitives(16'h0001,16'h0001,16'h0002,16'h7f80,16'h4000,16'h7f80);
        check_primitives(16'h7f80,16'hff80,16'h7fc0,16'h7fc1,16'h3f80,16'h7fc0);

        repeat(3) @(posedge clk); @(negedge clk); rst_n=1;
        begin_tag=16'h12; element_count=2; begin_valid=1;
        do @(posedge clk); while(!begin_ready);
        @(negedge clk); begin_valid=0;
        send_reduce(16'h3f80); // 1
        send_reduce(16'h4000); // 2
        wait(reduce_valid); @(negedge clk);
        if(reduce_tag!==16'h12 || reduce_sum!==16'h4040 || reduce_sumsq!==16'h40a0 || reduce_error)
            errors=errors+1;
        repeat(2) begin @(posedge clk); @(negedge clk); if(!reduce_valid) errors=errors+1; end
        reduce_ready=1; @(posedge clk); @(negedge clk); reduce_ready=0;

        // BF16 LayerNorm apply: ((3 - 1) * 0.5) * 2 + 1 = 3.
        rms_norm=0; config_tag=16'h34; mean=16'h3f80; inv_std=16'h3f00;
        config_valid=1; do @(posedge clk); while(!config_ready);
        @(negedge clk); config_valid=0;
        apply_tag=16'h34; x=16'h4040; gamma=16'h4000; beta=16'h3f80;
        apply_last=1; apply_valid=1; do @(posedge clk); while(!apply_ready);
        @(negedge clk); apply_valid=0;
        wait(result_valid); @(negedge clk);
        if(result_tag!==16'h34 || result_data!==16'h4040 || !result_last || context_error)
            errors=errors+1;
        result_ready=1; @(posedge clk); @(negedge clk); result_ready=0;

        if(errors) $fatal(1,"BF16_NORMALIZATION_TB FAIL errors=%0d",errors);
        $display("BF16_NORMALIZATION_TB PASS primitive reducer apply special_values backpressure");
        $finish;
    end
endmodule
