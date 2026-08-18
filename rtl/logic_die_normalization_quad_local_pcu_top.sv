// B-variant PCU wrapper.  External behavior and counters match the frozen PCU,
// but scheduling payloads, bank reducers/apply pipes, partial-stat formation,
// and scalar-return destinations are physically owned by four bank quads.
module logic_die_normalization_quad_local_pcu_top #(
    parameter int unsigned BANKS = 16,
    parameter int unsigned QUADS = 4,
    parameter int unsigned LANES = 8,
    parameter int unsigned SCALAR_ENGINES = 4,
    parameter int unsigned CONTEXTS = 8,
    parameter int unsigned LOCAL_REDUCE_CONTEXTS = 2,
    parameter int unsigned APPLY_FIFO_DEPTH = 16,
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned COUNT_WIDTH = 16,
    parameter int unsigned COMMAND_BYTES = 32,
    parameter int unsigned TRAFFIC_COUNTER_WIDTH = 32,
    parameter int unsigned STARVE_LIMIT = 16,
    parameter bit SHARED_RW_PORT = 1'b0,
    // B2 collapses accepted bank tags into one registered descriptor per quad.
    // Keep the default off so the already-routed B baseline remains reproducible.
    parameter bit REGISTERED_QUAD_COMPLETION = 1'b0
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [QUADS-1:0] quad_rst_ni_i,
    input  logic counter_clear_i,
    input  logic invocation_valid_i,
    output logic invocation_ready_o,
    input  logic job_valid_i,
    output logic job_ready_o,
    input  logic job_rms_norm_i,
    input  logic [TAG_WIDTH-1:0] job_tag_i,
    input  logic [COUNT_WIDTH-1:0] job_vectors_per_bank_i,
    input  logic [31:0] job_inv_hidden_i,
    input  logic [31:0] job_epsilon_i,
    input  logic [BANKS-1:0] job_bank_mask_i,
    input  logic [BANKS-1:0] reduction_valid_i,
    output logic [BANKS-1:0] reduction_ready_o,
    input  logic [BANKS-1:0][LANES-1:0][15:0] reduction_data_i,
    output logic replay_request_valid_o,
    input  logic replay_request_ready_i,
    output logic [TAG_WIDTH-1:0] replay_request_tag_o,
    output logic [COUNT_WIDTH-1:0] replay_request_vectors_per_bank_o,
    output logic [BANKS-1:0] replay_request_bank_mask_o,
    input  logic [BANKS-1:0] replay_valid_i,
    output logic [BANKS-1:0] replay_ready_o,
    input  logic [BANKS-1:0][TAG_WIDTH-1:0] replay_tag_i,
    input  logic [BANKS-1:0][LANES-1:0][15:0] replay_x_i,
    input  logic [BANKS-1:0][LANES-1:0][15:0] replay_gamma_i,
    input  logic [BANKS-1:0][LANES-1:0][15:0] replay_beta_i,
    input  logic [BANKS-1:0] replay_last_i,
    output logic [BANKS-1:0] writeback_valid_o,
    input  logic [BANKS-1:0] writeback_ready_i,
    output logic [BANKS-1:0][TAG_WIDTH-1:0] writeback_tag_o,
    output logic [BANKS-1:0][LANES-1:0][15:0] writeback_data_o,
    output logic [BANKS-1:0] writeback_last_o,
    output logic [63:0] bank_activation_read_bytes_o,
    output logic [63:0] bank_affine_read_bytes_o,
    output logic [63:0] bank_writeback_bytes_o,
    output logic [63:0] bank_to_logic_partial_bytes_o,
    output logic [63:0] logic_to_bank_scalar_bytes_o,
    output logic [63:0] external_control_bytes_o,
    output logic [31:0] scheduler_reduction_grants_o,
    output logic [31:0] scheduler_replay_grants_o,
    output logic [31:0] scheduler_writeback_grants_o,
    output logic [31:0] scheduler_read_conflict_cycles_o,
    output logic [31:0] scheduler_bank_skew_cycles_o,
    output logic [$clog2(CONTEXTS+1)-1:0] context_occupancy_o,
    output logic protocol_error_o
);
    localparam int unsigned CTX_INDEX_WIDTH = (CONTEXTS <= 1) ? 1 : $clog2(CONTEXTS);
    localparam int unsigned VECTOR_BYTES = LANES*2;
    localparam int unsigned AFFINE_VECTOR_BYTES = LANES*4;
    localparam int unsigned PARTIAL_BYTES = 8;
    localparam int unsigned SCALAR_BYTES = 8;

    logic [CONTEXTS-1:0] ctx_valid_q;
    logic [TAG_WIDTH-1:0] ctx_tag_q [0:CONTEXTS-1];
    logic [COUNT_WIDTH-1:0] ctx_vectors_q [0:CONTEXTS-1];
    logic [BANKS-1:0] ctx_mask_q [0:CONTEXTS-1];
    logic [BANKS-1:0] ctx_done_q [0:CONTEXTS-1];
    logic [BANKS-1:0] completion_bits [0:CONTEXTS-1];
    logic free_found, lookup_found;
    logic [CTX_INDEX_WIDTH-1:0] free_index, lookup_index;
    logic core_begin_ready, job_fire;
    logic scalar_configured;
    logic [TAG_WIDTH-1:0] scalar_configured_tag;
    logic core_protocol_error, scheduler_error, wrapper_error_q;
    logic replay_pending_q;
    logic [TAG_WIDTH-1:0] replay_tag_q;
    logic [COUNT_WIDTH-1:0] replay_vectors_q;
    logic [BANKS-1:0] replay_mask_q;
    logic [BANKS-1:0] reduction_fire, replay_fire, writeback_fire;
    logic [TRAFFIC_COUNTER_WIDTH-1:0] activation_bytes_q, affine_bytes_q;
    logic [TRAFFIC_COUNTER_WIDTH-1:0] writeback_bytes_q, partial_bytes_q;
    logic [TRAFFIC_COUNTER_WIDTH-1:0] scalar_bytes_q, external_bytes_q;
    logic [BANKS-1:0] core_reduction_valid, core_reduction_ready;
    logic [BANKS-1:0][LANES-1:0][15:0] core_reduction_data;
    logic [BANKS-1:0] core_replay_valid, core_replay_ready, core_replay_last;
    logic [BANKS-1:0][TAG_WIDTH-1:0] core_replay_tag;
    logic [BANKS-1:0][LANES-1:0][15:0] core_replay_x;
    logic [BANKS-1:0][LANES-1:0][15:0] core_replay_gamma, core_replay_beta;
    logic [BANKS-1:0] core_writeback_valid, core_writeback_ready, core_writeback_last;
    logic [BANKS-1:0][TAG_WIDTH-1:0] core_writeback_tag;
    logic [BANKS-1:0][LANES-1:0][15:0] core_writeback_data;
    logic [QUADS-1:0] quad_completion_valid;
    logic [QUADS-1:0][TAG_WIDTH-1:0] quad_completion_tag;
    logic scheduler_rst_n, datapath_rst_n, wrapper_rst_n;

    initial begin
        if (BANKS != 16 || QUADS != 4)
            $fatal(1, "quad-local PCU requires 16 banks in four quads");
        if (CONTEXTS < 2) $fatal(1, "CONTEXTS must be at least two");
        if (TRAFFIC_COUNTER_WIDTH < 24 || TRAFFIC_COUNTER_WIDTH > 64)
            $fatal(1, "TRAFFIC_COUNTER_WIDTH must be in [24,64]");
    end

    always_comb begin
        free_found = 1'b0;
        free_index = '0;
        for (integer c = 0; c < CONTEXTS; c++) begin
            if (!ctx_valid_q[c] && !free_found) begin
                free_found = 1'b1;
                free_index = c[CTX_INDEX_WIDTH-1:0];
            end
        end
        lookup_found = 1'b0;
        lookup_index = '0;
        for (integer c = 0; c < CONTEXTS; c++) begin
            if (ctx_valid_q[c] &&
                ctx_tag_q[c] == scalar_configured_tag && !lookup_found) begin
                lookup_found = 1'b1;
                lookup_index = c[CTX_INDEX_WIDTH-1:0];
            end
        end
        for (integer c = 0; c < CONTEXTS; c++)
            completion_bits[c] = '0;
        if (REGISTERED_QUAD_COMPLETION) begin
            for (integer quad = 0; quad < QUADS; quad++) begin
                for (integer c = 0; c < CONTEXTS; c++)
                    if (quad_completion_valid[quad] &&
                        ctx_valid_q[c] &&
                        ctx_tag_q[c] == quad_completion_tag[quad])
                        completion_bits[c][quad*(BANKS/QUADS) +: (BANKS/QUADS)] = '1;
            end
        end else begin
            for (integer bank = 0; bank < BANKS; bank++) begin
                if (writeback_valid_o[bank] && writeback_ready_i[bank] &&
                    writeback_last_o[bank]) begin
                    for (integer c = 0; c < CONTEXTS; c++)
                        if (ctx_valid_q[c] && ctx_tag_q[c] == writeback_tag_o[bank])
                            completion_bits[c][bank] = 1'b1;
                end
            end
        end
    end

    assign job_ready_o = scheduler_rst_n && datapath_rst_n && wrapper_rst_n &&
        (&quad_rst_ni_i) && core_begin_ready && free_found && (&job_bank_mask_i);
    assign job_fire = job_valid_i && job_ready_o;
    assign replay_request_valid_o = replay_pending_q;
    assign replay_request_tag_o = replay_tag_q;
    assign replay_request_vectors_per_bank_o = replay_vectors_q;
    assign replay_request_bank_mask_o = replay_mask_q;
    assign context_occupancy_o = $countones(ctx_valid_q);
    assign protocol_error_o = core_protocol_error || wrapper_error_q || scheduler_error;
    assign invocation_ready_o = scheduler_rst_n && datapath_rst_n && wrapper_rst_n &&
        (&quad_rst_ni_i);
    assign reduction_fire = reduction_valid_i & reduction_ready_o;
    assign replay_fire = replay_valid_i & replay_ready_o;
    assign writeback_fire = writeback_valid_o & writeback_ready_i;
    assign bank_activation_read_bytes_o = {{(64-TRAFFIC_COUNTER_WIDTH){1'b0}}, activation_bytes_q};
    assign bank_affine_read_bytes_o = {{(64-TRAFFIC_COUNTER_WIDTH){1'b0}}, affine_bytes_q};
    assign bank_writeback_bytes_o = {{(64-TRAFFIC_COUNTER_WIDTH){1'b0}}, writeback_bytes_q};
    assign bank_to_logic_partial_bytes_o = {{(64-TRAFFIC_COUNTER_WIDTH){1'b0}}, partial_bytes_q};
    assign logic_to_bank_scalar_bytes_o = {{(64-TRAFFIC_COUNTER_WIDTH){1'b0}}, scalar_bytes_q};
    assign external_control_bytes_o = {{(64-TRAFFIC_COUNTER_WIDTH){1'b0}}, external_bytes_q};

    normalization_quad_reset_leaf u_scheduler_reset_leaf (
        .clk_i(clk_i), .rst_ni(rst_ni), .quad_rst_ni_o(scheduler_rst_n)
    );
    normalization_quad_reset_leaf u_datapath_reset_leaf (
        .clk_i(clk_i), .rst_ni(rst_ni), .quad_rst_ni_o(datapath_rst_n)
    );
    normalization_quad_reset_leaf u_wrapper_reset_leaf (
        .clk_i(clk_i), .rst_ni(rst_ni), .quad_rst_ni_o(wrapper_rst_n)
    );

    normalization_quad_local_bank_scheduler #(
        .BANKS(BANKS), .QUADS(QUADS), .LANES(LANES), .TAG_WIDTH(TAG_WIDTH),
        .STARVE_LIMIT(STARVE_LIMIT), .SHARED_RW_PORT(SHARED_RW_PORT)
    ) u_quad_scheduler (
        .clk_i(clk_i), .rst_ni(scheduler_rst_n), .quad_rst_ni_i(quad_rst_ni_i),
        .counter_clear_i(counter_clear_i),
        .reduction_valid_i(reduction_valid_i), .reduction_ready_o(reduction_ready_o),
        .reduction_data_i(reduction_data_i),
        .core_reduction_valid_o(core_reduction_valid),
        .core_reduction_ready_i(core_reduction_ready),
        .core_reduction_data_o(core_reduction_data),
        .replay_valid_i(replay_valid_i), .replay_ready_o(replay_ready_o),
        .replay_tag_i(replay_tag_i), .replay_x_i(replay_x_i),
        .replay_gamma_i(replay_gamma_i), .replay_beta_i(replay_beta_i),
        .replay_last_i(replay_last_i), .core_replay_valid_o(core_replay_valid),
        .core_replay_ready_i(core_replay_ready), .core_replay_tag_o(core_replay_tag),
        .core_replay_x_o(core_replay_x), .core_replay_gamma_o(core_replay_gamma),
        .core_replay_beta_o(core_replay_beta), .core_replay_last_o(core_replay_last),
        .core_writeback_valid_i(core_writeback_valid),
        .core_writeback_ready_o(core_writeback_ready),
        .core_writeback_tag_i(core_writeback_tag),
        .core_writeback_data_i(core_writeback_data),
        .core_writeback_last_i(core_writeback_last),
        .bank_writeback_valid_o(writeback_valid_o),
        .bank_writeback_ready_i(writeback_ready_i),
        .bank_writeback_tag_o(writeback_tag_o),
        .bank_writeback_data_o(writeback_data_o),
        .bank_writeback_last_o(writeback_last_o),
        .reduction_grants_o(scheduler_reduction_grants_o),
        .replay_grants_o(scheduler_replay_grants_o),
        .writeback_grants_o(scheduler_writeback_grants_o),
        .read_conflict_cycles_o(scheduler_read_conflict_cycles_o),
        .bank_skew_cycles_o(scheduler_bank_skew_cycles_o),
        .quad_completion_valid_o(quad_completion_valid),
        .quad_completion_tag_o(quad_completion_tag),
        .protocol_error_o(scheduler_error)
    );

    mixed_precision_quad_local_multirow_datapath #(
        .BANKS(BANKS), .QUADS(QUADS), .LANES(LANES),
        .SCALAR_ENGINES(SCALAR_ENGINES), .CONTEXTS(CONTEXTS),
        .TAG_WIDTH(TAG_WIDTH), .COUNT_WIDTH(COUNT_WIDTH),
        .LOCAL_REDUCE_CONTEXTS(LOCAL_REDUCE_CONTEXTS),
        .APPLY_FIFO_DEPTH(APPLY_FIFO_DEPTH)
    ) u_quad_datapath (
        .clk_i(clk_i), .rst_ni(datapath_rst_n), .quad_rst_ni_i(quad_rst_ni_i),
        .begin_valid_i(job_valid_i && free_found && (&job_bank_mask_i)),
        .begin_ready_o(core_begin_ready), .rms_norm_i(job_rms_norm_i),
        .tag_i(job_tag_i), .vectors_per_bank_i(job_vectors_per_bank_i),
        .inv_hidden_i(job_inv_hidden_i), .epsilon_i(job_epsilon_i),
        .reduce_valid_i(core_reduction_valid), .reduce_ready_o(core_reduction_ready),
        .reduce_data_i(core_reduction_data), .apply_valid_i(core_replay_valid),
        .apply_ready_o(core_replay_ready), .apply_tag_i(core_replay_tag),
        .apply_x_i(core_replay_x), .apply_gamma_i(core_replay_gamma),
        .apply_beta_i(core_replay_beta), .apply_last_i(core_replay_last),
        .result_valid_o(core_writeback_valid), .result_ready_i(core_writeback_ready),
        .result_tag_o(core_writeback_tag), .result_data_o(core_writeback_data),
        .result_last_o(core_writeback_last), .scalar_configured_o(scalar_configured),
        .scalar_configured_tag_o(scalar_configured_tag), .context_occupancy_o(),
        .protocol_error_o(core_protocol_error)
    );

    always_ff @(posedge clk_i or negedge wrapper_rst_n) begin
        if (!wrapper_rst_n) begin
            ctx_valid_q <= '0;
            for (integer c = 0; c < CONTEXTS; c++) begin
                ctx_tag_q[c] <= '0;
                ctx_vectors_q[c] <= '0;
                ctx_mask_q[c] <= '0;
                ctx_done_q[c] <= '0;
            end
            replay_pending_q <= 1'b0;
            replay_tag_q <= '0;
            replay_vectors_q <= '0;
            replay_mask_q <= '0;
            wrapper_error_q <= 1'b0;
            activation_bytes_q <= '0;
            affine_bytes_q <= '0;
            writeback_bytes_q <= '0;
            partial_bytes_q <= '0;
            scalar_bytes_q <= '0;
            external_bytes_q <= '0;
        end else begin
            wrapper_error_q <= 1'b0;
            if (counter_clear_i) begin
                activation_bytes_q <= '0;
                affine_bytes_q <= '0;
                writeback_bytes_q <= '0;
                partial_bytes_q <= '0;
                scalar_bytes_q <= '0;
                external_bytes_q <= '0;
            end else begin
                activation_bytes_q <= activation_bytes_q +
                    (($countones(reduction_fire)+$countones(replay_fire))*VECTOR_BYTES);
                affine_bytes_q <= affine_bytes_q +
                    ($countones(replay_fire)*AFFINE_VECTOR_BYTES);
                writeback_bytes_q <= writeback_bytes_q +
                    ($countones(writeback_fire)*VECTOR_BYTES);
                if (invocation_valid_i && invocation_ready_o)
                    external_bytes_q <= external_bytes_q + COMMAND_BYTES;
                if (scalar_configured && lookup_found) begin
                    partial_bytes_q <= partial_bytes_q +
                        ($countones(ctx_mask_q[lookup_index])*PARTIAL_BYTES);
                    scalar_bytes_q <= scalar_bytes_q +
                        ($countones(ctx_mask_q[lookup_index])*SCALAR_BYTES);
                end
            end

            if (job_valid_i && !(&job_bank_mask_i)) wrapper_error_q <= 1'b1;
            if (REGISTERED_QUAD_COMPLETION &&
                ((|quad_completion_valid) && !(&quad_completion_valid)))
                wrapper_error_q <= 1'b1;
            if (REGISTERED_QUAD_COMPLETION && (&quad_completion_valid)) begin
                for (integer quad = 1; quad < QUADS; quad++)
                    if (quad_completion_tag[quad] != quad_completion_tag[0])
                        wrapper_error_q <= 1'b1;
            end
            if (job_fire) begin
                ctx_valid_q[free_index] <= 1'b1;
                ctx_tag_q[free_index] <= job_tag_i;
                ctx_vectors_q[free_index] <= job_vectors_per_bank_i;
                ctx_mask_q[free_index] <= job_bank_mask_i;
                ctx_done_q[free_index] <= '0;
            end
            if (scalar_configured) begin
                if (!lookup_found || replay_pending_q) begin
                    wrapper_error_q <= 1'b1;
                end else begin
                    replay_pending_q <= 1'b1;
                    replay_tag_q <= scalar_configured_tag;
                    replay_vectors_q <= ctx_vectors_q[lookup_index];
                    replay_mask_q <= ctx_mask_q[lookup_index];
                end
            end
            if (replay_request_valid_o && replay_request_ready_i)
                replay_pending_q <= 1'b0;

            for (integer c = 0; c < CONTEXTS; c++) begin
                if (ctx_valid_q[c] && |completion_bits[c]) begin
                    if ((ctx_done_q[c] | completion_bits[c]) == ctx_mask_q[c]) begin
                        ctx_valid_q[c] <= 1'b0;
                        ctx_done_q[c] <= '0;
                    end else begin
                        ctx_done_q[c] <= ctx_done_q[c] | completion_bits[c];
                    end
                end
            end
        end
    end
endmodule
