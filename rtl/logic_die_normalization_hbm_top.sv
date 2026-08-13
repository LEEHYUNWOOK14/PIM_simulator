// Physical-integration top for the frozen normalization PCU and its command-
// level DRAM boundary. The wide per-bank datapaths remain internal, so coarse
// placement/global routing measures their real logic-die wiring rather than
// treating thousands of PCU signals as package IO pins.
module logic_die_normalization_hbm_top #(
    parameter int unsigned BANKS = 16,
    parameter int unsigned LANES = 8,
    parameter int unsigned SCALAR_ENGINES = 4,
    parameter int unsigned CONTEXTS = 8,
    parameter int unsigned LOCAL_REDUCE_CONTEXTS = 2,
    parameter int unsigned APPLY_FIFO_DEPTH = 16,
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned COUNT_WIDTH = 16,
    parameter int unsigned ROW_WIDTH = 5,
    parameter int unsigned COL_WIDTH = 5,
    parameter int unsigned DATA_WIDTH = 256
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic counter_clear_i,

    input  logic job_valid_i,
    output logic job_ready_o,
    input  logic job_rms_norm_i,
    input  logic [TAG_WIDTH-1:0] job_tag_i,
    input  logic [COUNT_WIDTH-1:0] job_vectors_per_bank_i,
    input  logic [31:0] job_inv_hidden_i,
    input  logic [31:0] job_epsilon_i,
    input  logic [ROW_WIDTH-1:0] job_row_i,
    input  logic [COL_WIDTH-1:0] job_x_base_col_i,
    input  logic [COL_WIDTH-1:0] job_affine_base_col_i,
    input  logic [COL_WIDTH-1:0] job_output_base_col_i,

    output logic cmd_valid_o,
    input  logic cmd_ready_i,
    output logic [2:0] cmd_o,
    output logic [$clog2(BANKS)-1:0] cmd_bank_o,
    output logic [ROW_WIDTH-1:0] cmd_row_o,
    output logic [COL_WIDTH-1:0] cmd_col_o,
    output logic [DATA_WIDTH-1:0] cmd_write_data_o,
    output logic [DATA_WIDTH/8-1:0] cmd_write_mask_o,
    input  logic read_valid_i,
    output logic read_ready_o,
    input  logic [DATA_WIDTH-1:0] read_data_i,

    output logic done_o,
    output logic protocol_error_o,
    output logic [31:0] adapter_cycle_count_o,
    output logic [31:0] adapter_command_wait_cycles_o
);
    logic pcu_job_ready, adapter_start_ready;
    logic [BANKS-1:0] reduction_valid, reduction_ready;
    logic [BANKS*LANES-1:0][15:0] reduction_data;
    logic replay_request_valid, replay_request_ready;
    logic [TAG_WIDTH-1:0] replay_request_tag;
    logic [COUNT_WIDTH-1:0] replay_request_vectors;
    logic [BANKS-1:0] replay_request_mask;
    logic [BANKS-1:0] replay_valid, replay_ready, replay_last;
    logic [BANKS-1:0][TAG_WIDTH-1:0] replay_tag;
    logic [BANKS*LANES-1:0][15:0] replay_x, replay_gamma, replay_beta;
    logic [BANKS-1:0] writeback_valid, writeback_ready, writeback_last;
    logic [BANKS-1:0][TAG_WIDTH-1:0] writeback_tag;
    logic [BANKS*LANES-1:0][15:0] writeback_data;
    logic pcu_error, adapter_error;

    assign job_ready_o = pcu_job_ready && adapter_start_ready;
    assign protocol_error_o = pcu_error || adapter_error;

    logic_die_normalization_pcu_top #(
        .BANKS(BANKS), .LANES(LANES), .SCALAR_ENGINES(SCALAR_ENGINES),
        .CONTEXTS(CONTEXTS), .LOCAL_REDUCE_CONTEXTS(LOCAL_REDUCE_CONTEXTS),
        .APPLY_FIFO_DEPTH(APPLY_FIFO_DEPTH), .TAG_WIDTH(TAG_WIDTH),
        .COUNT_WIDTH(COUNT_WIDTH), .SHARED_RW_PORT(1'b0)
    ) u_pcu (
        .clk_i(clk_i), .rst_ni(rst_ni), .counter_clear_i(counter_clear_i),
        .invocation_valid_i(1'b0), .invocation_ready_o(),
        .job_valid_i(job_valid_i && adapter_start_ready), .job_ready_o(pcu_job_ready),
        .job_rms_norm_i(job_rms_norm_i), .job_tag_i(job_tag_i),
        .job_vectors_per_bank_i(job_vectors_per_bank_i),
        .job_inv_hidden_i(job_inv_hidden_i), .job_epsilon_i(job_epsilon_i),
        .job_bank_mask_i({BANKS{1'b1}}),
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
        .bank_activation_read_bytes_o(), .bank_affine_read_bytes_o(),
        .bank_writeback_bytes_o(), .bank_to_logic_partial_bytes_o(),
        .logic_to_bank_scalar_bytes_o(), .external_control_bytes_o(),
        .scheduler_reduction_grants_o(), .scheduler_replay_grants_o(),
        .scheduler_writeback_grants_o(), .scheduler_read_conflict_cycles_o(),
        .scheduler_bank_skew_cycles_o(), .context_occupancy_o(),
        .protocol_error_o(pcu_error)
    );

    normalization_hbm_boundary_adapter #(
        .BANKS(BANKS), .LANES(LANES), .TAG_WIDTH(TAG_WIDTH),
        .COUNT_WIDTH(COUNT_WIDTH), .ROW_WIDTH(ROW_WIDTH),
        .COL_WIDTH(COL_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) u_adapter (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .start_valid_i(job_valid_i && pcu_job_ready),
        .start_ready_o(adapter_start_ready), .start_tag_i(job_tag_i),
        .start_vectors_per_bank_i(job_vectors_per_bank_i),
        .start_row_i(job_row_i), .start_x_base_col_i(job_x_base_col_i),
        .start_affine_base_col_i(job_affine_base_col_i),
        .start_output_base_col_i(job_output_base_col_i),
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
        .cmd_valid_o(cmd_valid_o), .cmd_ready_i(cmd_ready_i), .cmd_o(cmd_o),
        .cmd_bank_o(cmd_bank_o), .cmd_row_o(cmd_row_o), .cmd_col_o(cmd_col_o),
        .cmd_write_data_o(cmd_write_data_o), .cmd_write_mask_o(cmd_write_mask_o),
        .read_valid_i(read_valid_i), .read_ready_o(read_ready_o),
        .read_data_i(read_data_i), .done_o(done_o),
        .protocol_error_o(adapter_error), .cycle_count_o(adapter_cycle_count_o),
        .act_command_count_o(), .read_command_count_o(),
        .write_command_count_o(), .pre_command_count_o(),
        .command_wait_cycles_o(adapter_command_wait_cycles_o)
    );
endmodule
