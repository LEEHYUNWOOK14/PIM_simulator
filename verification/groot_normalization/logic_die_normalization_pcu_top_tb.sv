module logic_die_normalization_pcu_top_tb #(
    parameter int LANES = 4,
    parameter bit RMS_MODE = 1'b0,
    parameter int WIDTH = 0,
    parameter int CONTEXTS = 8,
    parameter bit QUAD_LOCAL_AB = 1'b0,
    parameter bit B2_REGISTERED_QUAD_COMPLETION = 1'b0
);
    localparam int BANKS = 16;
    localparam int VECTORS = (WIDTH == 0) ? 4 : WIDTH / (BANKS * LANES);
    localparam logic [15:0] VECTOR_COUNT = VECTORS;
    logic clk = 0, rst_n = 0, counter_clear = 0;
    always #5 clk = ~clk;

    logic invocation_valid, invocation_ready, job_valid, job_ready;
    logic [15:0] job_tag;
    logic [BANKS-1:0] reduction_valid, reduction_ready;
    logic [BANKS*LANES-1:0][15:0] reduction_data;
    logic replay_request_valid, replay_request_ready;
    logic [15:0] replay_request_tag, replay_request_vectors;
    logic [BANKS-1:0] replay_request_mask;
    logic [BANKS-1:0] replay_valid, replay_ready, replay_last;
    logic [BANKS-1:0][15:0] replay_tag;
    logic [BANKS*LANES-1:0][15:0] replay_x, replay_gamma, replay_beta;
    logic [BANKS-1:0] writeback_valid, writeback_ready;
    logic [BANKS-1:0][15:0] writeback_tag;
    logic [BANKS*LANES-1:0][15:0] writeback_data;
    logic [BANKS-1:0] writeback_last;
    logic [63:0] activation_bytes, affine_bytes, writeback_bytes;
    logic [63:0] partial_bytes, scalar_bytes, external_bytes;
    logic [$clog2(CONTEXTS+1)-1:0] occupancy;
    logic protocol_error;
    logic [3:0] quad_rst_n;
    logic control_rst_n;
    integer output_vectors = 0;
    integer output_errors = 0;
    integer cycles = 0;
    logic [15:0] bp_lfsr;

    assign control_rst_n = &quad_rst_n;
    for (genvar quad = 0; quad < 4; quad++) begin : g_quad_reset
        normalization_quad_reset_leaf u_reset_leaf (
            .clk_i(clk), .rst_ni(rst_n), .quad_rst_ni_o(quad_rst_n[quad])
        );
    end

    generate
      if (QUAD_LOCAL_AB) begin : g_b
        logic_die_normalization_quad_local_pcu_top #(
            .LANES(LANES), .SCALAR_ENGINES(4), .CONTEXTS(CONTEXTS),
            .REGISTERED_QUAD_COMPLETION(B2_REGISTERED_QUAD_COMPLETION)
        ) dut (
        .clk_i(clk), .rst_ni(control_rst_n), .quad_rst_ni_i(quad_rst_n),
        .counter_clear_i(counter_clear),
        .invocation_valid_i(invocation_valid), .invocation_ready_o(invocation_ready),
        .job_valid_i(job_valid), .job_ready_o(job_ready), .job_rms_norm_i(RMS_MODE),
        .job_tag_i(job_tag), .job_vectors_per_bank_i(VECTOR_COUNT),
        .job_inv_hidden_i((WIDTH == 128) ? 32'h3c000000 :
                          (WIDTH == 2048) ? 32'h3a000000 :
                          (LANES == 4) ? 32'h3b800000 :
                          (LANES == 8) ? 32'h3b000000 : 32'h3a800000),
        .job_epsilon_i(32'h3727c5ac), .job_bank_mask_i({BANKS{1'b1}}),
        .reduction_valid_i(reduction_valid), .reduction_ready_o(reduction_ready),
        .reduction_data_i(reduction_data),
        .replay_request_valid_o(replay_request_valid),
        .replay_request_ready_i(replay_request_ready),
        .replay_request_tag_o(replay_request_tag),
        .replay_request_vectors_per_bank_o(replay_request_vectors),
        .replay_request_bank_mask_o(replay_request_mask),
        .replay_valid_i(replay_valid), .replay_ready_o(replay_ready),
        .replay_tag_i(replay_tag), .replay_x_i(replay_x),
        .replay_gamma_i(replay_gamma), .replay_beta_i(replay_beta),
        .replay_last_i(replay_last), .writeback_valid_o(writeback_valid),
        .writeback_ready_i(writeback_ready), .writeback_tag_o(writeback_tag),
        .writeback_data_o(writeback_data), .writeback_last_o(writeback_last),
        .bank_activation_read_bytes_o(activation_bytes),
        .bank_affine_read_bytes_o(affine_bytes),
        .bank_writeback_bytes_o(writeback_bytes),
        .bank_to_logic_partial_bytes_o(partial_bytes),
        .logic_to_bank_scalar_bytes_o(scalar_bytes),
        .external_control_bytes_o(external_bytes),
        .context_occupancy_o(occupancy), .protocol_error_o(protocol_error)
        );
      end else begin : g_a
        logic_die_normalization_pcu_top #(
            .LANES(LANES), .SCALAR_ENGINES(4), .CONTEXTS(CONTEXTS)
        ) dut (
        .clk_i(clk), .rst_ni(rst_n), .counter_clear_i(counter_clear),
        .invocation_valid_i(invocation_valid), .invocation_ready_o(invocation_ready),
        .job_valid_i(job_valid), .job_ready_o(job_ready), .job_rms_norm_i(RMS_MODE),
        .job_tag_i(job_tag), .job_vectors_per_bank_i(VECTOR_COUNT),
        .job_inv_hidden_i((WIDTH == 128) ? 32'h3c000000 :
                          (WIDTH == 2048) ? 32'h3a000000 :
                          (LANES == 4) ? 32'h3b800000 :
                          (LANES == 8) ? 32'h3b000000 : 32'h3a800000),
        .job_epsilon_i(32'h3727c5ac), .job_bank_mask_i({BANKS{1'b1}}),
        .reduction_valid_i(reduction_valid), .reduction_ready_o(reduction_ready),
        .reduction_data_i(reduction_data),
        .replay_request_valid_o(replay_request_valid),
        .replay_request_ready_i(replay_request_ready),
        .replay_request_tag_o(replay_request_tag),
        .replay_request_vectors_per_bank_o(replay_request_vectors),
        .replay_request_bank_mask_o(replay_request_mask),
        .replay_valid_i(replay_valid), .replay_ready_o(replay_ready),
        .replay_tag_i(replay_tag), .replay_x_i(replay_x),
        .replay_gamma_i(replay_gamma), .replay_beta_i(replay_beta),
        .replay_last_i(replay_last), .writeback_valid_o(writeback_valid),
        .writeback_ready_i(writeback_ready), .writeback_tag_o(writeback_tag),
        .writeback_data_o(writeback_data), .writeback_last_o(writeback_last),
        .bank_activation_read_bytes_o(activation_bytes),
        .bank_affine_read_bytes_o(affine_bytes),
        .bank_writeback_bytes_o(writeback_bytes),
        .bank_to_logic_partial_bytes_o(partial_bytes),
        .logic_to_bank_scalar_bytes_o(scalar_bytes),
        .external_control_bytes_o(external_bytes),
        .context_occupancy_o(occupancy), .protocol_error_o(protocol_error)
        );
      end
    endgenerate

    always @(posedge clk) begin
        if (rst_n) begin
            cycles++;
            for (integer b = 0; b < BANKS; b++) begin
                if (writeback_valid[b] && writeback_ready[b]) begin
                    output_vectors++;
                    if (writeback_tag[b] !== 16'h5100) output_errors++;
                    for (integer lane = 0; lane < LANES; lane++)
                        if (writeback_data[b*LANES+lane] !== (RMS_MODE ? 16'h4000 : 16'h0000)) output_errors++;
                end
            end
        end
    end

    task automatic send_reduction;
        begin
            reduction_valid = '1;
            for (integer vec = 0; vec < VECTORS; vec++) begin
                for (integer b = 0; b < BANKS; b++)
                    for (integer lane = 0; lane < LANES; lane++)
                        reduction_data[b*LANES+lane] = 16'h3f80;
                @(posedge clk);
                while (reduction_ready !== {BANKS{1'b1}}) @(posedge clk);
                @(negedge clk);
            end
            reduction_valid = '0;
        end
    endtask

    task automatic drive_random_writeback_backpressure;
        begin
            bp_lfsr = 16'h5a3c;
            while (output_vectors < BANKS * VECTORS) begin
                @(negedge clk);
                bp_lfsr = {bp_lfsr[14:0], bp_lfsr[15]^bp_lfsr[13]^bp_lfsr[12]^bp_lfsr[10]};
                // About 75% ready, lockstep across banks. Per-bank skew is
                // independently stressed in normalization_bank_scheduler_tb.
                writeback_ready = {BANKS{bp_lfsr[0] | bp_lfsr[1]}};
            end
            writeback_ready = '1;
        end
    endtask

    task automatic send_replay;
        begin
            replay_valid = '1;
            for (integer vec = 0; vec < VECTORS; vec++) begin
                for (integer b = 0; b < BANKS; b++) begin
                    replay_tag[b] = 16'h5100;
                    replay_last[b] = (vec == VECTORS-1);
                    for (integer lane = 0; lane < LANES; lane++) begin
                        replay_x[b*LANES+lane] = 16'h3f80;
                        replay_gamma[b*LANES+lane] = RMS_MODE ? 16'h4000 : 16'h3f80;
                        // RMSNorm has weight-only affine.  A large non-zero beta
                        // proves that the mode correctly omits the add path.
                        replay_beta[b*LANES+lane] = RMS_MODE ? 16'h4080 : 16'h0000;
                    end
                end
                @(posedge clk);
                while (replay_ready !== {BANKS{1'b1}}) @(posedge clk);
                @(negedge clk);
            end
            replay_valid = '0;
            replay_last = '0;
        end
    endtask

    initial begin
        invocation_valid = 0; job_valid = 0; job_tag = 16'h5100; reduction_valid = 0; reduction_data = '0;
        replay_request_ready = 0; replay_valid = 0; replay_tag = '0;
        replay_x = '0; replay_gamma = '0; replay_beta = '0; replay_last = 0;
        writeback_ready = '1;
        repeat (3) @(negedge clk);
        rst_n = 1;

        // Abort an in-flight row and prove reset clears contexts, pipelines,
        // scheduler state, and traffic counters before the real transaction.
        @(negedge clk); job_tag = 16'h5000; job_valid = 1;
        @(posedge clk); while (!job_ready) @(posedge clk);
        @(negedge clk); job_valid = 0; reduction_valid = '1;
        for (integer b = 0; b < BANKS; b++)
            for (integer lane = 0; lane < LANES; lane++)
                reduction_data[b*LANES+lane] = 16'h3f80;
        @(posedge clk); while (reduction_ready !== {BANKS{1'b1}}) @(posedge clk);
        @(negedge clk); reduction_valid = 0; rst_n = 0;
        repeat (2) @(negedge clk); rst_n = 1; job_tag = 16'h5100;
        @(negedge clk);
        if (occupancy != 0 || protocol_error || activation_bytes != 0 ||
            affine_bytes != 0 || writeback_bytes != 0)
            $fatal(1, "mid-transaction reset did not clear PCU state");

        @(negedge clk); invocation_valid = 1;
        @(posedge clk);
        while (invocation_ready !== 1'b1) @(posedge clk);
        @(negedge clk); invocation_valid = 0;
        @(negedge clk); job_valid = 1;
        @(posedge clk); while (!job_ready) @(posedge clk);
        @(negedge clk); job_valid = 0;
        send_reduction();

        wait (replay_request_valid);
        repeat (5) begin
            @(negedge clk);
            if (!replay_request_valid || replay_request_tag != 16'h5100 ||
                replay_request_vectors != VECTORS || replay_request_mask != {BANKS{1'b1}})
                $fatal(1, "replay request was not held under backpressure");
        end
        replay_request_ready = 1;
        @(posedge clk); @(negedge clk); replay_request_ready = 0;
        fork
            send_replay();
            drive_random_writeback_backpressure();
        join

        while (output_vectors < BANKS * VECTORS) @(negedge clk);
        repeat (4) @(negedge clk);
        if (protocol_error || output_errors) $fatal(1, "data/protocol failure errors=%0d protocol=%b", output_errors, protocol_error);
        if (activation_bytes != 2 * BANKS * VECTORS * LANES * 2)
            $fatal(1, "activation byte count mismatch got=%0d", activation_bytes);
        if (affine_bytes != BANKS * VECTORS * LANES * 4)
            $fatal(1, "affine byte count mismatch got=%0d", affine_bytes);
        if (writeback_bytes != BANKS * VECTORS * LANES * 2)
            $fatal(1, "writeback byte count mismatch got=%0d", writeback_bytes);
        if (partial_bytes != BANKS * 8 || scalar_bytes != BANKS * 8)
            $fatal(1, "logic boundary mismatch partial=%0d scalar=%0d", partial_bytes, scalar_bytes);
        if (external_bytes != 32) $fatal(1, "external control mismatch got=%0d", external_bytes);
        if (occupancy != 0) $fatal(1, "wrapper context leaked occupancy=%0d", occupancy);
        $display("LOGIC_DIE_NORMALIZATION_PCU_TOP_TB PASS variant=%0d lanes=%0d rms=%0d width=%0d vectors=%0d cycles=%0d lane_utilization_pct=100 replay_backpressure=5 random_writeback_bp=1 reset_mid_transaction=1 activation_bytes=%0d affine_bytes=%0d writeback_bytes=%0d partial_bytes=%0d scalar_bytes=%0d external_bytes=%0d",
            QUAD_LOCAL_AB, LANES, RMS_MODE,
            (WIDTH == 0 ? BANKS*LANES*VECTORS : WIDTH), VECTORS, cycles,
            activation_bytes, affine_bytes, writeback_bytes, partial_bytes, scalar_bytes, external_bytes);
        $finish;
    end

    initial begin
        repeat (30000) @(negedge clk);
        $fatal(1, "timeout outputs=%0d occupancy=%0d", output_vectors, occupancy);
    end
endmodule
