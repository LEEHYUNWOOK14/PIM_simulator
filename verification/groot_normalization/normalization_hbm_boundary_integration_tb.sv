module normalization_hbm_boundary_integration_tb #(
    parameter int WIDTH = 2048,
    parameter bit RMS_MODE = 1'b0
);
    localparam int BANKS = 16;
    localparam int LANES = 8;
    localparam int VECTORS = WIDTH/(BANKS*LANES);
    localparam int X_WORDS = (VECTORS+1)/2;
    localparam int X_BASE = 0;
    localparam int AFF_BASE = X_WORDS;
    localparam int OUT_BASE = X_WORDS+VECTORS;
    localparam int ROWS = 8;
    localparam int COLS = 32;
    localparam int ROW_WIDTH = $clog2(ROWS);
    localparam int COL_WIDTH = $clog2(COLS);
    localparam logic [15:0] TAG = 16'h6200;
    localparam logic [15:0] VECTOR_COUNT = VECTORS;
    localparam logic [ROW_WIDTH-1:0] TEST_ROW = 3;
    localparam logic [COL_WIDTH-1:0] X_BASE_COL = X_BASE;
    localparam logic [COL_WIDTH-1:0] AFF_BASE_COL = AFF_BASE;
    localparam logic [COL_WIDTH-1:0] OUT_BASE_COL = OUT_BASE;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic launch_valid, launch_ready;
    logic pcu_job_ready, adapter_start_ready;
    logic [BANKS-1:0] reduction_valid, reduction_ready;
    logic [BANKS*LANES-1:0][15:0] reduction_data;
    logic replay_request_valid, replay_request_ready;
    logic [15:0] replay_request_tag, replay_request_vectors;
    logic [BANKS-1:0] replay_request_mask;
    logic [BANKS-1:0] replay_valid, replay_ready, replay_last;
    logic [BANKS-1:0][15:0] replay_tag;
    logic [BANKS*LANES-1:0][15:0] replay_x, replay_gamma, replay_beta;
    logic [BANKS-1:0] pcu_writeback_valid, pcu_writeback_ready, pcu_writeback_last;
    logic [BANKS-1:0][15:0] pcu_writeback_tag;
    logic [BANKS*LANES-1:0][15:0] pcu_writeback_data;
    logic [BANKS-1:0] writeback_valid, writeback_ready, writeback_last;
    logic [BANKS-1:0][15:0] writeback_tag;
    logic [BANKS*LANES-1:0][15:0] writeback_data;
    logic protocol_error_pcu, protocol_error_adapter, protocol_error_slice;
    logic adapter_done;

    logic cmd_valid, cmd_ready;
    logic [2:0] cmd;
    logic [3:0] cmd_bank;
    logic [ROW_WIDTH-1:0] cmd_row;
    logic [COL_WIDTH-1:0] cmd_col;
    logic [255:0] cmd_write_data;
    logic [31:0] cmd_write_mask;
    logic read_valid, read_ready;
    logic [255:0] read_data;
    logic timing_error;
    logic [31:0] adapter_cycles, act_count, read_count, write_count, pre_count, wait_cycles;
    integer wall_cycles = 0;
    integer outstanding_reads = 0;
    integer peak_outstanding_reads = 0;

    assign launch_ready = pcu_job_ready && adapter_start_ready;

    logic_die_normalization_pcu_top #(
        .BANKS(BANKS), .LANES(LANES), .SCALAR_ENGINES(4), .CONTEXTS(8),
        .LOCAL_REDUCE_CONTEXTS(2), .APPLY_FIFO_DEPTH(16), .SHARED_RW_PORT(1'b0)
    ) u_pcu (
        .clk_i(clk), .rst_ni(rst_n), .counter_clear_i(1'b0),
        .invocation_valid_i(1'b0), .invocation_ready_o(),
        .job_valid_i(launch_valid && adapter_start_ready), .job_ready_o(pcu_job_ready),
        .job_rms_norm_i(RMS_MODE), .job_tag_i(TAG), .job_vectors_per_bank_i(VECTOR_COUNT),
        .job_inv_hidden_i(WIDTH == 128 ? 32'h3c000000 : 32'h3a000000),
        .job_epsilon_i(32'h3727c5ac), .job_bank_mask_i('1),
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
        .replay_last_i(replay_last), .writeback_valid_o(pcu_writeback_valid),
        .writeback_ready_i(pcu_writeback_ready), .writeback_tag_o(pcu_writeback_tag),
        .writeback_data_o(pcu_writeback_data), .writeback_last_o(pcu_writeback_last),
        .bank_activation_read_bytes_o(), .bank_affine_read_bytes_o(),
        .bank_writeback_bytes_o(), .bank_to_logic_partial_bytes_o(),
        .logic_to_bank_scalar_bytes_o(), .external_control_bytes_o(),
        .scheduler_reduction_grants_o(), .scheduler_replay_grants_o(),
        .scheduler_writeback_grants_o(), .scheduler_read_conflict_cycles_o(),
        .scheduler_bank_skew_cycles_o(), .context_occupancy_o(),
        .protocol_error_o(protocol_error_pcu)
    );

    normalization_writeback_quad_slice #(
        .BANKS(BANKS), .QUADS(4), .LANES(LANES)
    ) u_writeback_slice (
        .clk_i(clk), .rst_ni(rst_n),
        .source_valid_i(pcu_writeback_valid),
        .source_ready_o(pcu_writeback_ready),
        .source_tag_i(pcu_writeback_tag),
        .source_data_i(pcu_writeback_data),
        .source_last_i(pcu_writeback_last),
        .sink_valid_o(writeback_valid), .sink_ready_i(writeback_ready),
        .sink_tag_o(writeback_tag), .sink_data_o(writeback_data),
        .sink_last_o(writeback_last), .protocol_error_o(protocol_error_slice)
    );

    normalization_hbm_boundary_adapter #(
        .BANKS(BANKS), .LANES(LANES), .ROW_WIDTH(ROW_WIDTH), .COL_WIDTH(COL_WIDTH)
    ) u_adapter (
        .clk_i(clk), .rst_ni(rst_n),
        .start_valid_i(launch_valid && pcu_job_ready), .start_ready_o(adapter_start_ready),
        .start_tag_i(TAG), .start_vectors_per_bank_i(VECTOR_COUNT), .start_row_i(TEST_ROW),
        .start_x_base_col_i(X_BASE_COL), .start_affine_base_col_i(AFF_BASE_COL),
        .start_output_base_col_i(OUT_BASE_COL),
        .reduction_valid_o(reduction_valid), .reduction_ready_i(reduction_ready),
        .reduction_data_o(reduction_data),
        .replay_request_valid_i(replay_request_valid),
        .replay_request_ready_o(replay_request_ready),
        .replay_request_tag_i(replay_request_tag),
        .replay_request_vectors_per_bank_i(replay_request_vectors),
        .replay_request_bank_mask_i(replay_request_mask),
        .replay_valid_o(replay_valid), .replay_ready_i(replay_ready),
        .replay_tag_o(replay_tag), .replay_x_o(replay_x),
        .replay_gamma_o(replay_gamma), .replay_beta_o(replay_beta),
        .replay_last_o(replay_last), .writeback_valid_i(writeback_valid),
        .writeback_ready_o(writeback_ready), .writeback_tag_i(writeback_tag),
        .writeback_data_i(writeback_data), .writeback_last_i(writeback_last),
        .cmd_valid_o(cmd_valid), .cmd_ready_i(cmd_ready), .cmd_o(cmd),
        .cmd_bank_o(cmd_bank), .cmd_row_o(cmd_row), .cmd_col_o(cmd_col),
        .cmd_write_data_o(cmd_write_data), .cmd_write_mask_o(cmd_write_mask),
        .read_valid_i(read_valid), .read_ready_o(read_ready), .read_data_i(read_data),
        .done_o(adapter_done), .protocol_error_o(protocol_error_adapter),
        .cycle_count_o(adapter_cycles), .act_command_count_o(act_count),
        .read_command_count_o(read_count), .write_command_count_o(write_count),
        .pre_command_count_o(pre_count), .command_wait_cycles_o(wait_cycles)
    );

    dram_bank_array_model #(
        .BANKS(BANKS), .ROWS(ROWS), .COLS(COLS), .PIM_READ_PORTS(1)
    ) u_dram (
        .clk_i(clk), .rst_ni(rst_n), .cmd_valid_i(cmd_valid), .cmd_ready_o(cmd_ready),
        .cmd_i(cmd), .bank_i(cmd_bank), .row_i(cmd_row), .col_i(cmd_col),
        .write_data_i(cmd_write_data), .write_mask_i(cmd_write_mask),
        .read_valid_o(read_valid), .read_ready_i(read_ready), .read_data_o(read_data),
        .timing_error_o(timing_error), .pim_read_enable_i('0),
        .pim_read_bank_i('0), .pim_read_row_i('0), .pim_read_col_i('0),
        .pim_read_valid_o(), .pim_read_data_o()
    );

    always @(posedge clk) if (rst_n) begin
        wall_cycles <= wall_cycles + 1;
        if (timing_error) $fatal(1, "DRAM timing violation cmd=%0d bank=%0d", cmd, cmd_bank);
        if (cmd_valid && cmd_ready && cmd == 3'd2) begin
            outstanding_reads <= outstanding_reads + 1;
            if (outstanding_reads + 1 > peak_outstanding_reads)
                peak_outstanding_reads <= outstanding_reads + 1;
            if (outstanding_reads != 0)
                $fatal(1, "read credit exceeded one outstanding=%0d", outstanding_reads + 1);
        end
        if (read_valid && read_ready) begin
            if (outstanding_reads != 1)
                $fatal(1, "read response without exactly one credit outstanding=%0d", outstanding_reads);
            outstanding_reads <= outstanding_reads - 1;
        end
    end

    initial begin
        launch_valid = 0;
        for (integer b = 0; b < BANKS; b++) begin
            for (integer c = 0; c < X_WORDS; c++)
                for (integer e = 0; e < 16; e++)
                    u_dram.memory[b][3][X_BASE+c][e*16 +: 16] = 16'h3f80;
            for (integer v = 0; v < VECTORS; v++) begin
                for (integer e = 0; e < 8; e++) begin
                    u_dram.memory[b][3][AFF_BASE+v][e*16 +: 16] = RMS_MODE ? 16'h4000 : 16'h3f80;
                    u_dram.memory[b][3][AFF_BASE+v][128+e*16 +: 16] = RMS_MODE ? 16'h4080 : 16'h0000;
                end
            end
            for (integer c = 0; c < X_WORDS; c++) u_dram.memory[b][3][OUT_BASE+c] = {256{1'b1}};
        end

        repeat (4) @(negedge clk);
        rst_n = 1;
        @(negedge clk); launch_valid = 1;
        @(posedge clk); while (!launch_ready) @(posedge clk);
        @(negedge clk); launch_valid = 0;
        wait (adapter_done);
        @(negedge clk);

        if (protocol_error_pcu || protocol_error_adapter || protocol_error_slice)
            $fatal(1, "protocol error pcu=%b adapter=%b slice=%b",
                protocol_error_pcu, protocol_error_adapter, protocol_error_slice);
        if (act_count != BANKS || pre_count != BANKS)
            $fatal(1, "ACT/PRE count mismatch act=%0d pre=%0d", act_count, pre_count);
        if (read_count != BANKS*(2*X_WORDS+VECTORS))
            $fatal(1, "read count mismatch got=%0d expected=%0d", read_count, BANKS*(2*X_WORDS+VECTORS));
        if (write_count != BANKS*X_WORDS)
            $fatal(1, "write count mismatch got=%0d expected=%0d", write_count, BANKS*X_WORDS);
        if (peak_outstanding_reads != 1 || outstanding_reads != 0)
            $fatal(1, "read credit accounting mismatch peak=%0d final=%0d",
                peak_outstanding_reads, outstanding_reads);
        for (integer b = 0; b < BANKS; b++)
            for (integer v = 0; v < VECTORS; v++)
                for (integer l = 0; l < LANES; l++) begin
                    logic [15:0] got;
                    got = u_dram.memory[b][3][OUT_BASE+(v/2)][(v%2)*128+l*16 +: 16];
                    if (got !== (RMS_MODE ? 16'h4000 : 16'h0000))
                        $fatal(1, "output mismatch bank=%0d vector=%0d lane=%0d got=%h", b, v, l, got);
                end
        if ((VECTORS % 2) == 1)
            for (integer b = 0; b < BANKS; b++)
                if (u_dram.memory[b][3][OUT_BASE+X_WORDS-1][255:128] !== {128{1'b1}})
                    $fatal(1, "partial write mask corrupted upper half bank=%0d", b);

        $display("NORMALIZATION_HBM_BOUNDARY_INTEGRATION_TB PASS width=%0d rms=%0d vectors=%0d wall_cycles=%0d adapter_cycles=%0d act=%0d read=%0d write=%0d pre=%0d wait=%0d read_credit_peak=%0d read_credit_final=%0d timing_errors=0",
            WIDTH, RMS_MODE, VECTORS, wall_cycles, adapter_cycles, act_count,
            read_count, write_count, pre_count, wait_cycles,
            peak_outstanding_reads, outstanding_reads);
        $finish;
    end

    initial begin
        repeat (30000) @(negedge clk);
        $fatal(1, "timeout state=%0d adapter_cycles=%0d", u_adapter.state_q, adapter_cycles);
    end
endmodule
