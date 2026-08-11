module normalization_interface_contract_tb;
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic config_valid, config_ready, rms_norm;
    logic [15:0] config_tag, mean, inv_std;
    logic element_valid, element_ready, element_last;
    logic [15:0] element_tag, x, gamma, beta;
    logic result_valid, result_ready, result_last, context_error;
    logic [15:0] result_tag, result_data;
    integer errors;

    bank_normalization_apply dut (
        .clk_i(clk), .rst_ni(rst_n),
        .config_valid_i(config_valid), .config_ready_o(config_ready),
        .config_rms_norm_i(rms_norm), .config_tag_i(config_tag),
        .config_mean_i(mean), .config_inv_std_i(inv_std),
        .element_valid_i(element_valid), .element_ready_o(element_ready),
        .element_tag_i(element_tag), .element_x_i(x),
        .element_gamma_i(gamma), .element_beta_i(beta),
        .element_last_i(element_last), .result_valid_o(result_valid),
        .result_ready_i(result_ready), .result_tag_o(result_tag),
        .result_data_o(result_data), .result_last_o(result_last),
        .context_error_o(context_error));

    task configure(input logic [15:0] tag);
        begin
            config_tag = tag;
            config_valid = 1;
            do @(posedge clk); while (!config_ready);
            @(negedge clk);
            config_valid = 0;
        end
    endtask

    initial begin
        config_valid = 0; rms_norm = 1; config_tag = 0;
        mean = 0; inv_std = 16'h3c00;
        element_valid = 0; element_tag = 0; x = 16'h3c00;
        gamma = 16'h3c00; beta = 0; element_last = 0;
        result_ready = 0; errors = 0;

        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1;
        configure(16'h0042);

        // First element occupies the single-entry output register.
        element_tag = 16'h0042;
        element_valid = 1;
        @(posedge clk);
        @(negedge clk);
        if (!result_valid || result_data !== 16'h3c00)
            errors = errors + 1;

        // The producer may hold valid and payload while ready is low.
        x = 16'h4000;
        repeat (3) begin
            @(posedge clk);
            @(negedge clk);
            if (element_ready || context_error) errors = errors + 1;
            if (!result_valid || result_tag !== 16'h0042 ||
                result_data !== 16'h3c00 || result_last !== 1'b0)
                errors = errors + 1;
        end

        // Consume the first result; the held second element transfers in the
        // same cycle and must replace it without dropping valid.
        result_ready = 1;
        @(posedge clk);
        @(negedge clk);
        element_valid = 0;
        result_ready = 0;
        if (!result_valid || result_data !== 16'h4000 || context_error)
            errors = errors + 1;

        // Asynchronous reset must clear a stalled response and context.
        rst_n = 0;
        #1;
        if (result_valid || result_tag !== 0 || result_data !== 0 ||
            result_last || context_error || element_ready)
            errors = errors + 1;
        repeat (2) @(posedge clk);
        @(negedge clk); rst_n = 1;

        // Data without a configured context remains a real protocol error.
        element_valid = 1;
        element_tag = 16'h0042;
        @(posedge clk);
        @(negedge clk);
        element_valid = 0;
        if (!context_error) errors = errors + 1;

        if (errors)
            $fatal(1, "NORMALIZATION_INTERFACE_CONTRACT_TB FAIL errors=%0d", errors);
        $display("NORMALIZATION_INTERFACE_CONTRACT_TB PASS backpressure reset context_error");
        $finish;
    end
endmodule
