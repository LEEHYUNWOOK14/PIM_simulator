// Command-level boundary between the frozen 8-lane normalization PCU and the
// repository DRAM timing model. One logical normalization row is kept in one
// open DRAM row per bank. Two 8xBF16 PCU vectors share one 256-bit DRAM word.
// Affine words pack gamma in [127:0] and beta in [255:128].
module normalization_hbm_boundary_adapter #(
    parameter int unsigned BANKS = 16,
    parameter int unsigned LANES = 8,
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned COUNT_WIDTH = 16,
    parameter int unsigned ROW_WIDTH = 5,
    parameter int unsigned COL_WIDTH = 5,
    parameter int unsigned DATA_WIDTH = 256
)(
    input  logic clk_i,
    input  logic rst_ni,

    input  logic start_valid_i,
    output logic start_ready_o,
    input  logic [TAG_WIDTH-1:0] start_tag_i,
    input  logic [COUNT_WIDTH-1:0] start_vectors_per_bank_i,
    input  logic [ROW_WIDTH-1:0] start_row_i,
    input  logic [COL_WIDTH-1:0] start_x_base_col_i,
    input  logic [COL_WIDTH-1:0] start_affine_base_col_i,
    input  logic [COL_WIDTH-1:0] start_output_base_col_i,

    output logic [BANKS-1:0] reduction_valid_o,
    input  logic [BANKS-1:0] reduction_ready_i,
    output logic [BANKS*LANES-1:0][15:0] reduction_data_o,

    input  logic replay_request_valid_i,
    output logic replay_request_ready_o,
    input  logic [TAG_WIDTH-1:0] replay_request_tag_i,
    input  logic [COUNT_WIDTH-1:0] replay_request_vectors_per_bank_i,
    input  logic [BANKS-1:0] replay_request_bank_mask_i,

    output logic [BANKS-1:0] replay_valid_o,
    input  logic [BANKS-1:0] replay_ready_i,
    output logic [BANKS-1:0][TAG_WIDTH-1:0] replay_tag_o,
    output logic [BANKS*LANES-1:0][15:0] replay_x_o,
    output logic [BANKS*LANES-1:0][15:0] replay_gamma_o,
    output logic [BANKS*LANES-1:0][15:0] replay_beta_o,
    output logic [BANKS-1:0] replay_last_o,

    input  logic [BANKS-1:0] writeback_valid_i,
    output logic [BANKS-1:0] writeback_ready_o,
    input  logic [BANKS-1:0][TAG_WIDTH-1:0] writeback_tag_i,
    input  logic [BANKS*LANES-1:0][15:0] writeback_data_i,
    input  logic [BANKS-1:0] writeback_last_i,

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
    output logic [31:0] cycle_count_o,
    output logic [31:0] act_command_count_o,
    output logic [31:0] read_command_count_o,
    output logic [31:0] write_command_count_o,
    output logic [31:0] pre_command_count_o,
    output logic [31:0] command_wait_cycles_o
);
`include "rtl/pim_rtl_constants.svh"
    localparam int unsigned BANK_WIDTH = $clog2(BANKS);
    localparam int unsigned HALF_WIDTH = DATA_WIDTH/2;

    typedef enum logic [4:0] {
        S_IDLE, S_ACT, S_RED_RD, S_RED_WAIT, S_RED_SEND, S_WAIT_REPLAY,
        S_REP_X_RD, S_REP_X_WAIT, S_AFF_RD, S_AFF_WAIT, S_REP_SEND,
        S_WAIT_WB, S_WR, S_PRE, S_DONE
    } state_t;
    state_t state_q;

    logic [TAG_WIDTH-1:0] tag_q;
    logic [COUNT_WIDTH-1:0] vectors_q, red_vector_q, replay_vector_q;
    logic [ROW_WIDTH-1:0] row_q;
    logic [COL_WIDTH-1:0] x_base_q, affine_base_q, output_base_q;
    logic [BANK_WIDTH-1:0] bank_q;
    logic [DATA_WIDTH-1:0] x_word_q [0:BANKS-1];
    logic [DATA_WIDTH-1:0] affine_word_q [0:BANKS-1];
    logic [DATA_WIDTH-1:0] wb_word_q [0:BANKS-1];
    // Physical fanout isolation.  The original combinational output selected
    // one 128-bit half from every 256-bit bank word using one shared vector
    // parity bit.  That parity net drove more than 2K mux selects.  Capture
    // the selected half while each bank response arrives, and prepare the odd
    // half at the even-vector handshake instead.  Output behavior and cycle
    // count stay unchanged while the wide select cone disappears.
    logic [HALF_WIDTH-1:0] reduction_payload_q [0:BANKS-1];
    logic [HALF_WIDTH-1:0] replay_x_payload_q [0:BANKS-1];
    logic [COUNT_WIDTH-1:0] wb_vector_q;
    logic wb_word_complete_q, wb_partial_q;
    logic error_q;
    logic command_candidate;
    logic command_fire;
    logic reduction_fire, replay_fire, writeback_fire;
    logic vector_last;

    initial begin
        if (BANKS != 16) $fatal(1, "normalization adapter requires 16 banks");
        if (LANES != 8) $fatal(1, "packed boundary prototype is defined for frozen 8-lane PCU");
        if (DATA_WIDTH != 256) $fatal(1, "adapter requires a 256-bit DRAM word");
    end

    assign start_ready_o = state_q == S_IDLE;
    assign replay_request_ready_o = state_q == S_WAIT_REPLAY;
    assign read_ready_o = state_q == S_RED_WAIT || state_q == S_REP_X_WAIT || state_q == S_AFF_WAIT;
    assign done_o = state_q == S_DONE;
    assign protocol_error_o = error_q;
    assign command_fire = cmd_valid_o && cmd_ready_i;
    assign reduction_fire = (&reduction_valid_o) && (&reduction_ready_i);
    assign replay_fire = (&replay_valid_o) && (&replay_ready_i);
    assign writeback_fire = (&writeback_valid_i) && (&writeback_ready_o);
    assign vector_last = replay_vector_q == vectors_q - 1'b1;

    // The timing model exposes command legality on ready even when valid is
    // low and flags an illegal asserted valid as an error. Therefore fields
    // are presented continuously and valid is pulsed only on a legal cycle.
    assign cmd_valid_o = command_candidate && cmd_ready_i;

    always @* begin
        command_candidate = 1'b0;
        cmd_o = DRAM_CMD_NOP;
        cmd_bank_o = bank_q;
        cmd_row_o = row_q;
        cmd_col_o = '0;
        cmd_write_data_o = '0;
        cmd_write_mask_o = '0;
        case (state_q)
            S_ACT: begin
                command_candidate = 1'b1;
                cmd_o = DRAM_CMD_ACT;
            end
            S_RED_RD, S_REP_X_RD: begin
                command_candidate = 1'b1;
                cmd_o = DRAM_CMD_RD;
                cmd_col_o = x_base_q + ((state_q == S_RED_RD ? red_vector_q : replay_vector_q) >> 1);
            end
            S_AFF_RD: begin
                command_candidate = 1'b1;
                cmd_o = DRAM_CMD_RD;
                cmd_col_o = affine_base_q + replay_vector_q;
            end
            S_WR: begin
                command_candidate = 1'b1;
                cmd_o = DRAM_CMD_WR;
                // wb_vector_q points at the next vector after capture. Address
                // the word completed by the immediately preceding vector.
                cmd_col_o = output_base_q + ((wb_vector_q - 1'b1) >> 1);
                cmd_write_data_o = wb_word_q[bank_q];
                cmd_write_mask_o = wb_partial_q ? {{(DATA_WIDTH/16){1'b0}}, {(DATA_WIDTH/16){1'b1}}} : '1;
            end
            S_PRE: begin
                command_candidate = 1'b1;
                cmd_o = DRAM_CMD_PRE;
            end
            default: begin end
        endcase
    end

    always @* begin
        reduction_valid_o = '0;
        reduction_data_o = '0;
        replay_valid_o = '0;
        replay_tag_o = '0;
        replay_x_o = '0;
        replay_gamma_o = '0;
        replay_beta_o = '0;
        replay_last_o = '0;
        writeback_ready_o = '0;

        if (state_q == S_RED_SEND) begin
            reduction_valid_o = '1;
            for (integer b = 0; b < BANKS; b++)
                for (integer l = 0; l < LANES; l++)
                    reduction_data_o[b*LANES+l] = reduction_payload_q[b][l*16 +: 16];
        end
        if (state_q == S_REP_SEND) begin
            replay_valid_o = '1;
            replay_last_o = {BANKS{vector_last}};
            for (integer b = 0; b < BANKS; b++) begin
                replay_tag_o[b] = tag_q;
                for (integer l = 0; l < LANES; l++) begin
                    replay_x_o[b*LANES+l] = replay_x_payload_q[b][l*16 +: 16];
                    replay_gamma_o[b*LANES+l] = affine_word_q[b][l*16 +: 16];
                    replay_beta_o[b*LANES+l] = affine_word_q[b][HALF_WIDTH+(l*16) +: 16];
                end
            end
        end
        // A common ready preserves all-bank atomicity. It must not depend on
        // valid: the PCU scheduler derives its outward valid from sink ready.
        if (!wb_word_complete_q)
            writeback_ready_o = '1;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= S_IDLE;
            tag_q <= '0;
            vectors_q <= '0;
            red_vector_q <= '0;
            replay_vector_q <= '0;
            wb_vector_q <= '0;
            row_q <= '0;
            x_base_q <= '0;
            affine_base_q <= '0;
            output_base_q <= '0;
            bank_q <= '0;
            wb_word_complete_q <= 1'b0;
            wb_partial_q <= 1'b0;
            error_q <= 1'b0;
            cycle_count_o <= '0;
            act_command_count_o <= '0;
            read_command_count_o <= '0;
            write_command_count_o <= '0;
            pre_command_count_o <= '0;
            command_wait_cycles_o <= '0;
            for (integer b = 0; b < BANKS; b++) begin
                x_word_q[b] <= '0;
                affine_word_q[b] <= '0;
                wb_word_q[b] <= '0;
                reduction_payload_q[b] <= '0;
                replay_x_payload_q[b] <= '0;
            end
        end else begin
            if (state_q != S_IDLE && state_q != S_DONE) cycle_count_o <= cycle_count_o + 1'b1;
            if (command_candidate && !cmd_ready_i) command_wait_cycles_o <= command_wait_cycles_o + 1'b1;
            if (command_fire) begin
                case (cmd_o)
                    DRAM_CMD_ACT: act_command_count_o <= act_command_count_o + 1'b1;
                    DRAM_CMD_RD: read_command_count_o <= read_command_count_o + 1'b1;
                    DRAM_CMD_WR: write_command_count_o <= write_command_count_o + 1'b1;
                    DRAM_CMD_PRE: pre_command_count_o <= pre_command_count_o + 1'b1;
                    default: begin end
                endcase
            end

            if (writeback_fire) begin
                for (integer b = 0; b < BANKS; b++) begin
                    for (integer l = 0; l < LANES; l++)
                        wb_word_q[b][(wb_vector_q[0]*HALF_WIDTH)+(l*16) +: 16] <= writeback_data_i[b*LANES+l];
                    if (writeback_tag_i[b] != tag_q || writeback_last_i[b] != (wb_vector_q == vectors_q-1'b1))
                        error_q <= 1'b1;
                end
                if (wb_vector_q[0] || wb_vector_q == vectors_q-1'b1) begin
                    wb_word_complete_q <= 1'b1;
                    wb_partial_q <= !wb_vector_q[0];
                end
                wb_vector_q <= wb_vector_q + 1'b1;
            end

            case (state_q)
                S_IDLE: if (start_valid_i) begin
                    if (start_vectors_per_bank_i == 0) error_q <= 1'b1;
                    tag_q <= start_tag_i;
                    vectors_q <= start_vectors_per_bank_i;
                    row_q <= start_row_i;
                    x_base_q <= start_x_base_col_i;
                    affine_base_q <= start_affine_base_col_i;
                    output_base_q <= start_output_base_col_i;
                    red_vector_q <= '0;
                    replay_vector_q <= '0;
                    wb_vector_q <= '0;
                    bank_q <= '0;
                    wb_word_complete_q <= 1'b0;
                    wb_partial_q <= 1'b0;
                    error_q <= 1'b0;
                    cycle_count_o <= '0;
                    act_command_count_o <= '0;
                    read_command_count_o <= '0;
                    write_command_count_o <= '0;
                    pre_command_count_o <= '0;
                    command_wait_cycles_o <= '0;
                    state_q <= S_ACT;
                end
                S_ACT: if (command_fire) begin
                    if (bank_q == BANKS-1) begin bank_q <= '0; state_q <= S_RED_RD; end
                    else bank_q <= bank_q + 1'b1;
                end
                S_RED_RD: if (command_fire) state_q <= S_RED_WAIT;
                S_RED_WAIT: if (read_valid_i) begin
                    x_word_q[bank_q] <= read_data_i;
                    reduction_payload_q[bank_q] <= red_vector_q[0] ?
                        read_data_i[DATA_WIDTH-1:HALF_WIDTH] : read_data_i[HALF_WIDTH-1:0];
                    if (bank_q == BANKS-1) begin bank_q <= '0; state_q <= S_RED_SEND; end
                    else begin bank_q <= bank_q + 1'b1; state_q <= S_RED_RD; end
                end
                S_RED_SEND: if (reduction_fire) begin
                    if (red_vector_q == vectors_q-1'b1) state_q <= S_WAIT_REPLAY;
                    else if (red_vector_q[0]) begin red_vector_q <= red_vector_q + 1'b1; bank_q <= '0; state_q <= S_RED_RD; end
                    else begin
                        for (integer b = 0; b < BANKS; b++)
                            reduction_payload_q[b] <= x_word_q[b][DATA_WIDTH-1:HALF_WIDTH];
                        red_vector_q <= red_vector_q + 1'b1;
                    end
                end
                S_WAIT_REPLAY: if (replay_request_valid_i) begin
                    if (replay_request_tag_i != tag_q || replay_request_vectors_per_bank_i != vectors_q ||
                        replay_request_bank_mask_i != {BANKS{1'b1}}) error_q <= 1'b1;
                    replay_vector_q <= '0;
                    bank_q <= '0;
                    state_q <= S_REP_X_RD;
                end
                S_REP_X_RD: if (command_fire) state_q <= S_REP_X_WAIT;
                S_REP_X_WAIT: if (read_valid_i) begin
                    x_word_q[bank_q] <= read_data_i;
                    replay_x_payload_q[bank_q] <= replay_vector_q[0] ?
                        read_data_i[DATA_WIDTH-1:HALF_WIDTH] : read_data_i[HALF_WIDTH-1:0];
                    if (bank_q == BANKS-1) begin bank_q <= '0; state_q <= S_AFF_RD; end
                    else begin bank_q <= bank_q + 1'b1; state_q <= S_REP_X_RD; end
                end
                S_AFF_RD: if (command_fire) state_q <= S_AFF_WAIT;
                S_AFF_WAIT: if (read_valid_i) begin
                    affine_word_q[bank_q] <= read_data_i;
                    if (bank_q == BANKS-1) begin bank_q <= '0; state_q <= S_REP_SEND; end
                    else begin bank_q <= bank_q + 1'b1; state_q <= S_AFF_RD; end
                end
                S_REP_SEND: if (replay_fire) begin
                    if (replay_vector_q[0] || vector_last) state_q <= S_WAIT_WB;
                    else begin
                        for (integer b = 0; b < BANKS; b++)
                            replay_x_payload_q[b] <= x_word_q[b][DATA_WIDTH-1:HALF_WIDTH];
                        replay_vector_q <= replay_vector_q + 1'b1; bank_q <= '0; state_q <= S_AFF_RD;
                    end
                end
                S_WAIT_WB: if (wb_word_complete_q) begin bank_q <= '0; state_q <= S_WR; end
                S_WR: if (command_fire) begin
                    if (bank_q == BANKS-1) begin
                        bank_q <= '0;
                        wb_word_complete_q <= 1'b0;
                        if (replay_vector_q == vectors_q-1'b1) state_q <= S_PRE;
                        else begin replay_vector_q <= replay_vector_q + 1'b1; state_q <= S_REP_X_RD; end
                    end else bank_q <= bank_q + 1'b1;
                end
                S_PRE: if (command_fire) begin
                    if (bank_q == BANKS-1) begin bank_q <= '0; state_q <= S_DONE; end
                    else bank_q <= bank_q + 1'b1;
                end
                S_DONE: state_q <= S_IDLE;
                default: state_q <= S_IDLE;
            endcase
        end
    end
endmodule
