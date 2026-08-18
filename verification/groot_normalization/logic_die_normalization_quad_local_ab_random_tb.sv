module logic_die_normalization_quad_local_ab_random_tb #(
    parameter bit B2_REGISTERED_QUAD_COMPLETION = 1'b0
);
    localparam int BANKS = 16;
    localparam int LANES = 8;
    localparam int VECTORS = 6;
    localparam logic [15:0] VECTOR_COUNT = VECTORS;
    localparam int ELEMENTS = BANKS*LANES*VECTORS;
    localparam logic [15:0] TAG = 16'h7200;

    logic clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;
    logic [3:0] quad_rst_n;
    logic control_rst_n;
    assign control_rst_n = &quad_rst_n;
    for (genvar quad = 0; quad < 4; quad++) begin : g_quad_reset
        normalization_quad_reset_leaf u_reset_leaf (
            .clk_i(clk), .rst_ni(rst_n), .quad_rst_ni_o(quad_rst_n[quad])
        );
    end

    logic job_valid_a, job_ready_a, job_valid_b, job_ready_b;
    logic [BANKS-1:0] red_valid_a, red_ready_a, red_valid_b, red_ready_b;
    logic [BANKS*LANES-1:0][15:0] red_data_a, red_data_b;
    logic request_valid_a, request_ready_a, request_valid_b, request_ready_b;
    logic [15:0] request_tag_a, request_tag_b, request_vectors_a, request_vectors_b;
    logic [BANKS-1:0] request_mask_a, request_mask_b;
    logic [BANKS-1:0] replay_valid_a, replay_ready_a, replay_last_a;
    logic [BANKS-1:0] replay_valid_b, replay_ready_b, replay_last_b;
    logic [BANKS-1:0][15:0] replay_tag_a, replay_tag_b;
    logic [BANKS*LANES-1:0][15:0] replay_x_a, replay_gamma_a, replay_beta_a;
    logic [BANKS*LANES-1:0][15:0] replay_x_b, replay_gamma_b, replay_beta_b;
    logic [BANKS-1:0] wb_valid_a, wb_ready_a, wb_last_a;
    logic [BANKS-1:0] wb_valid_b, wb_ready_b, wb_last_b;
    logic [BANKS-1:0][15:0] wb_tag_a, wb_tag_b;
    logic [BANKS*LANES-1:0][15:0] wb_data_a, wb_data_b;
    logic [63:0] act_a, aff_a, write_a, partial_a, scalar_a;
    logic [63:0] act_b, aff_b, write_b, partial_b, scalar_b;
    logic [3:0] occupancy_a, occupancy_b;
    logic error_a, error_b;
    logic [15:0] output_a [0:ELEMENTS-1];
    logic [15:0] output_b [0:ELEMENTS-1];
    integer output_vectors_a, output_vectors_b, wall_cycles;
    integer red_sent_a, red_sent_b, replay_sent_a, replay_sent_b;
    integer request_seen_a, request_seen_b;

    logic_die_normalization_pcu_top #(
        .LANES(LANES), .SCALAR_ENGINES(4), .CONTEXTS(8)
    ) u_a (
        .clk_i(clk), .rst_ni(rst_n), .counter_clear_i(1'b0),
        .invocation_valid_i(1'b0), .invocation_ready_o(),
        .job_valid_i(job_valid_a), .job_ready_o(job_ready_a),
        .job_rms_norm_i(1'b0), .job_tag_i(TAG),
        .job_vectors_per_bank_i(VECTOR_COUNT), .job_inv_hidden_i(32'h3a800000),
        .job_epsilon_i(32'h3727c5ac), .job_bank_mask_i('1),
        .reduction_valid_i(red_valid_a), .reduction_ready_o(red_ready_a),
        .reduction_data_i(red_data_a), .replay_request_valid_o(request_valid_a),
        .replay_request_ready_i(request_ready_a), .replay_request_tag_o(request_tag_a),
        .replay_request_vectors_per_bank_o(request_vectors_a),
        .replay_request_bank_mask_o(request_mask_a),
        .replay_valid_i(replay_valid_a), .replay_ready_o(replay_ready_a),
        .replay_tag_i(replay_tag_a), .replay_x_i(replay_x_a),
        .replay_gamma_i(replay_gamma_a), .replay_beta_i(replay_beta_a),
        .replay_last_i(replay_last_a), .writeback_valid_o(wb_valid_a),
        .writeback_ready_i(wb_ready_a), .writeback_tag_o(wb_tag_a),
        .writeback_data_o(wb_data_a), .writeback_last_o(wb_last_a),
        .bank_activation_read_bytes_o(act_a), .bank_affine_read_bytes_o(aff_a),
        .bank_writeback_bytes_o(write_a), .bank_to_logic_partial_bytes_o(partial_a),
        .logic_to_bank_scalar_bytes_o(scalar_a), .external_control_bytes_o(),
        .scheduler_reduction_grants_o(), .scheduler_replay_grants_o(),
        .scheduler_writeback_grants_o(), .scheduler_read_conflict_cycles_o(),
        .scheduler_bank_skew_cycles_o(), .context_occupancy_o(occupancy_a),
        .protocol_error_o(error_a)
    );

    logic_die_normalization_quad_local_pcu_top #(
        .LANES(LANES), .SCALAR_ENGINES(4), .CONTEXTS(8),
        .REGISTERED_QUAD_COMPLETION(B2_REGISTERED_QUAD_COMPLETION)
    ) u_b (
        .clk_i(clk), .rst_ni(control_rst_n), .quad_rst_ni_i(quad_rst_n),
        .counter_clear_i(1'b0), .invocation_valid_i(1'b0), .invocation_ready_o(),
        .job_valid_i(job_valid_b), .job_ready_o(job_ready_b),
        .job_rms_norm_i(1'b0), .job_tag_i(TAG),
        .job_vectors_per_bank_i(VECTOR_COUNT), .job_inv_hidden_i(32'h3a800000),
        .job_epsilon_i(32'h3727c5ac), .job_bank_mask_i('1),
        .reduction_valid_i(red_valid_b), .reduction_ready_o(red_ready_b),
        .reduction_data_i(red_data_b), .replay_request_valid_o(request_valid_b),
        .replay_request_ready_i(request_ready_b), .replay_request_tag_o(request_tag_b),
        .replay_request_vectors_per_bank_o(request_vectors_b),
        .replay_request_bank_mask_o(request_mask_b),
        .replay_valid_i(replay_valid_b), .replay_ready_o(replay_ready_b),
        .replay_tag_i(replay_tag_b), .replay_x_i(replay_x_b),
        .replay_gamma_i(replay_gamma_b), .replay_beta_i(replay_beta_b),
        .replay_last_i(replay_last_b), .writeback_valid_o(wb_valid_b),
        .writeback_ready_i(wb_ready_b), .writeback_tag_o(wb_tag_b),
        .writeback_data_o(wb_data_b), .writeback_last_o(wb_last_b),
        .bank_activation_read_bytes_o(act_b), .bank_affine_read_bytes_o(aff_b),
        .bank_writeback_bytes_o(write_b), .bank_to_logic_partial_bytes_o(partial_b),
        .logic_to_bank_scalar_bytes_o(scalar_b), .external_control_bytes_o(),
        .scheduler_reduction_grants_o(), .scheduler_replay_grants_o(),
        .scheduler_writeback_grants_o(), .scheduler_read_conflict_cycles_o(),
        .scheduler_bank_skew_cycles_o(), .context_occupancy_o(occupancy_b),
        .protocol_error_o(error_b)
    );

    function automatic logic [15:0] sample_x(
        input integer vector_index, input integer bank, input integer lane
    );
        case ((vector_index*13 + bank*5 + lane*3) % 8)
            0: sample_x = 16'h3f80;
            1: sample_x = 16'hbf00;
            2: sample_x = 16'h4000;
            3: sample_x = 16'h3e80;
            4: sample_x = 16'hc020;
            5: sample_x = 16'h3d80;
            6: sample_x = 16'h4040;
            default: sample_x = 16'hbec0;
        endcase
    endfunction

    task automatic fill_reduction_a(input integer vector_index);
        for (integer bank = 0; bank < BANKS; bank++)
            for (integer lane = 0; lane < LANES; lane++)
                red_data_a[bank*LANES+lane] = sample_x(vector_index, bank, lane);
    endtask
    task automatic fill_reduction_b(input integer vector_index);
        for (integer bank = 0; bank < BANKS; bank++)
            for (integer lane = 0; lane < LANES; lane++)
                red_data_b[bank*LANES+lane] = sample_x(vector_index, bank, lane);
    endtask
    task automatic fill_replay_a(input integer vector_index);
        for (integer bank = 0; bank < BANKS; bank++) begin
            replay_tag_a[bank] = TAG;
            replay_last_a[bank] = vector_index == VECTORS-1;
            for (integer lane = 0; lane < LANES; lane++) begin
                replay_x_a[bank*LANES+lane] = sample_x(vector_index, bank, lane);
                replay_gamma_a[bank*LANES+lane] =
                    ((bank+lane) % 3 == 0) ? 16'h3f40 : 16'h3f80;
                replay_beta_a[bank*LANES+lane] =
                    ((bank+lane) % 4 == 0) ? 16'h3d00 : 16'hbd00;
            end
        end
    endtask
    task automatic fill_replay_b(input integer vector_index);
        for (integer bank = 0; bank < BANKS; bank++) begin
            replay_tag_b[bank] = TAG;
            replay_last_b[bank] = vector_index == VECTORS-1;
            for (integer lane = 0; lane < LANES; lane++) begin
                replay_x_b[bank*LANES+lane] = sample_x(vector_index, bank, lane);
                replay_gamma_b[bank*LANES+lane] =
                    ((bank+lane) % 3 == 0) ? 16'h3f40 : 16'h3f80;
                replay_beta_b[bank*LANES+lane] =
                    ((bank+lane) % 4 == 0) ? 16'h3d00 : 16'hbd00;
            end
        end
    endtask

    task automatic launch_a;
        @(negedge clk); job_valid_a = 1'b1;
        while (job_ready_a !== 1'b1) @(negedge clk);
        @(posedge clk); @(negedge clk); job_valid_a = 1'b0;
    endtask
    task automatic launch_b;
        @(negedge clk); job_valid_b = 1'b1;
        while (job_ready_b !== 1'b1) @(negedge clk);
        @(posedge clk); @(negedge clk); job_valid_b = 1'b0;
    endtask

    task automatic send_abort_a;
        fill_reduction_a(0); red_valid_a = '1;
        #1;
        while (red_ready_a != '1) @(negedge clk);
        @(posedge clk); @(negedge clk); red_valid_a = '0;
    endtask
    task automatic send_abort_b;
        fill_reduction_b(0); red_valid_b = '1;
        #1;
        while (red_ready_b != '1) @(negedge clk);
        @(posedge clk); @(negedge clk); red_valid_b = '0;
    endtask

    task automatic stream_reduction_a;
        logic [15:0] lfsr;
        logic accepted;
        integer attempts;
        lfsr = 16'h1d2b;
        for (integer vector_index = 0; vector_index < VECTORS; vector_index++) begin
            red_valid_a = '0; attempts = 0; accepted = 1'b0;
            fill_reduction_a(vector_index);
            while (!accepted) begin
                @(negedge clk);
                lfsr = {lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
                red_valid_a = red_valid_a | {4{lfsr[3:0]}};
                attempts++;
                if (attempts % 5 == 0) red_valid_a = '1;
                #1;
                if (red_valid_a == '1 && red_ready_a == '1) begin
                    @(posedge clk); accepted = 1'b1; red_sent_a = vector_index+1;
                end
            end
            @(negedge clk); red_valid_a = '0;
        end
    endtask
    task automatic stream_reduction_b;
        logic [15:0] lfsr;
        logic accepted;
        integer attempts;
        lfsr = 16'h1d2b;
        for (integer vector_index = 0; vector_index < VECTORS; vector_index++) begin
            red_valid_b = '0; attempts = 0; accepted = 1'b0;
            fill_reduction_b(vector_index);
            while (!accepted) begin
                @(negedge clk);
                lfsr = {lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
                red_valid_b = red_valid_b | {4{lfsr[3:0]}};
                attempts++;
                if (attempts % 5 == 0) red_valid_b = '1;
                #1;
                if (red_valid_b == '1 && red_ready_b == '1) begin
                    @(posedge clk); accepted = 1'b1; red_sent_b = vector_index+1;
                end
            end
            @(negedge clk); red_valid_b = '0;
        end
    endtask

    task automatic wait_request_a;
        while (!(request_valid_a && request_ready_a)) @(posedge clk);
        request_seen_a = 1;
        if (request_tag_a != TAG || request_vectors_a != VECTORS || request_mask_a != '1)
            $fatal(1, "A replay descriptor mismatch");
    endtask
    task automatic wait_request_b;
        while (!(request_valid_b && request_ready_b)) @(posedge clk);
        request_seen_b = 1;
        if (request_tag_b != TAG || request_vectors_b != VECTORS || request_mask_b != '1)
            $fatal(1, "B replay descriptor mismatch");
    endtask

    task automatic stream_replay_a;
        logic [15:0] lfsr;
        logic accepted;
        integer attempts;
        lfsr = 16'h7341;
        for (integer vector_index = 0; vector_index < VECTORS; vector_index++) begin
            replay_valid_a = '0; attempts = 0; accepted = 1'b0;
            fill_replay_a(vector_index);
            while (!accepted) begin
                @(negedge clk);
                lfsr = {lfsr[14:0],lfsr[15]^lfsr[14]^lfsr[12]^lfsr[3]};
                replay_valid_a = replay_valid_a | {4{lfsr[7:4]}};
                attempts++;
                if (attempts % 6 == 0) replay_valid_a = '1;
                #1;
                if (replay_valid_a == '1 && replay_ready_a == '1) begin
                    @(posedge clk); accepted = 1'b1; replay_sent_a = vector_index+1;
                end
            end
            @(negedge clk); replay_valid_a = '0;
        end
        replay_last_a = '0;
    endtask
    task automatic stream_replay_b;
        logic [15:0] lfsr;
        logic accepted;
        integer attempts;
        lfsr = 16'h7341;
        for (integer vector_index = 0; vector_index < VECTORS; vector_index++) begin
            replay_valid_b = '0; attempts = 0; accepted = 1'b0;
            fill_replay_b(vector_index);
            while (!accepted) begin
                @(negedge clk);
                lfsr = {lfsr[14:0],lfsr[15]^lfsr[14]^lfsr[12]^lfsr[3]};
                replay_valid_b = replay_valid_b | {4{lfsr[7:4]}};
                attempts++;
                if (attempts % 6 == 0) replay_valid_b = '1;
                #1;
                if (replay_valid_b == '1 && replay_ready_b == '1) begin
                    @(posedge clk); accepted = 1'b1; replay_sent_b = vector_index+1;
                end
            end
            @(negedge clk); replay_valid_b = '0;
        end
        replay_last_b = '0;
    endtask

    always @(posedge clk) begin
        if (rst_n) begin
            wall_cycles <= wall_cycles + 1;
            if (wall_cycles != 0 && wall_cycles % 200 == 0)
                $display("AB_RANDOM progress cycle=%0d red=%0d/%0d req=%0d/%0d replay=%0d/%0d out=%0d/%0d occ=%0d/%0d",
                    wall_cycles, red_sent_a, red_sent_b, request_seen_a, request_seen_b,
                    replay_sent_a, replay_sent_b, output_vectors_a, output_vectors_b,
                    occupancy_a, occupancy_b);
            if ((wb_valid_a & wb_ready_a) == '1) begin
                for (integer bank = 0; bank < BANKS; bank++)
                    for (integer lane = 0; lane < LANES; lane++)
                        output_a[output_vectors_a*BANKS*LANES+bank*LANES+lane]
                            <= wb_data_a[bank*LANES+lane];
                output_vectors_a <= output_vectors_a + 1;
            end
            if ((wb_valid_b & wb_ready_b) == '1) begin
                for (integer bank = 0; bank < BANKS; bank++)
                    for (integer lane = 0; lane < LANES; lane++)
                        output_b[output_vectors_b*BANKS*LANES+bank*LANES+lane]
                            <= wb_data_b[bank*LANES+lane];
                output_vectors_b <= output_vectors_b + 1;
            end
        end
    end

    task automatic drive_random_sinks;
        logic [15:0] lfsr;
        integer phase;
        lfsr = 16'hb4d3; phase = 0;
        while (output_vectors_a < VECTORS || output_vectors_b < VECTORS) begin
            @(negedge clk);
            lfsr = {lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
            phase++;
            request_ready_a = (phase % 3 == 0) || lfsr[0];
            request_ready_b = request_ready_a;
            if (phase % 4 == 0) begin
                wb_ready_a = '1;
                wb_ready_b = '1;
            end else begin
                wb_ready_a = {4{lfsr[3:0]}};
                wb_ready_b = wb_ready_a;
            end
        end
    endtask

    initial begin
        job_valid_a=0; job_valid_b=0; red_valid_a=0; red_valid_b=0;
        red_data_a='0; red_data_b='0; request_ready_a=0; request_ready_b=0;
        replay_valid_a=0; replay_valid_b=0; replay_tag_a='0; replay_tag_b='0;
        replay_x_a='0; replay_x_b='0; replay_gamma_a='0; replay_gamma_b='0;
        replay_beta_a='0; replay_beta_b='0; replay_last_a=0; replay_last_b=0;
        wb_ready_a='0; wb_ready_b='0; output_vectors_a=0; output_vectors_b=0;
        wall_cycles=0; red_sent_a=0; red_sent_b=0; replay_sent_a=0; replay_sent_b=0;
        request_seen_a=0; request_seen_b=0;
        repeat (4) @(negedge clk); rst_n=1;
        $display("AB_RANDOM phase=abort_launch cycle=%0d", wall_cycles);

        // Common in-flight abort.  Neither implementation may leak a replay,
        // writeback, context, or traffic count into the following job.
        fork launch_a(); launch_b(); join
        fork send_abort_a(); send_abort_b(); join
        $display("AB_RANDOM phase=abort_reset cycle=%0d", wall_cycles);
        @(negedge clk); rst_n=0;
        repeat (3) @(negedge clk); rst_n=1;
        repeat (4) @(negedge clk);
        if (request_valid_a || request_valid_b || |wb_valid_a || |wb_valid_b ||
            occupancy_a != 0 || occupancy_b != 0 || act_a != 0 || act_b != 0)
            $fatal(1, "in-flight reset leaked state Aocc=%0d Bocc=%0d", occupancy_a, occupancy_b);

        output_vectors_a=0; output_vectors_b=0;
        red_sent_a=0; red_sent_b=0; replay_sent_a=0; replay_sent_b=0;
        request_seen_a=0; request_seen_b=0;
        fork launch_a(); launch_b(); join
        $display("AB_RANDOM phase=real_stream cycle=%0d", wall_cycles);
        fork
            stream_reduction_a();
            stream_reduction_b();
            begin wait_request_a(); stream_replay_a(); end
            begin wait_request_b(); stream_replay_b(); end
            drive_random_sinks();
        join
        $display("AB_RANDOM phase=streams_complete cycle=%0d outA=%0d outB=%0d",
            wall_cycles, output_vectors_a, output_vectors_b);
        repeat (5) @(negedge clk);

        if (error_a || error_b) $fatal(1, "protocol error A=%b B=%b", error_a, error_b);
        for (integer element = 0; element < ELEMENTS; element++)
            if (output_a[element] !== output_b[element])
                $fatal(1, "A/B output mismatch element=%0d A=%h B=%h",
                    element, output_a[element], output_b[element]);
        if ({act_a,aff_a,write_a,partial_a,scalar_a} !==
            {act_b,aff_b,write_b,partial_b,scalar_b})
            $fatal(1, "A/B counter mismatch");
        if (occupancy_a != 0 || occupancy_b != 0)
            $fatal(1, "context leak A=%0d B=%0d", occupancy_a, occupancy_b);

        $display("LOGIC_DIE_NORMALIZATION_QUAD_LOCAL_AB_RANDOM_TB PASS vectors=%0d elements=%0d partial_valid_stalls=1 replay_valid_stalls=1 per_bank_writeback_ready_skew=1 replay_request_backpressure=1 inflight_reset=1 bit_exact=1 cycles=%0d",
            VECTORS, ELEMENTS, wall_cycles);
        $finish;
    end

    initial begin
        repeat (5000) @(negedge clk);
        $fatal(1, "timeout outA=%0d outB=%0d reqA=%b reqB=%b",
            output_vectors_a, output_vectors_b, request_valid_a, request_valid_b);
    end
endmodule
