module dram_bank_array_model #(
    parameter int unsigned BANKS = 16,
    parameter int unsigned ROWS = 32,
    parameter int unsigned COLS = 8,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned BANK_WIDTH = BANKS > 1 ? $clog2(BANKS) : 1,
    parameter int unsigned ROW_WIDTH = ROWS > 1 ? $clog2(ROWS) : 1,
    parameter int unsigned COL_WIDTH = COLS > 1 ? $clog2(COLS) : 1,
    parameter int unsigned TRCD_RD = 14,
    parameter int unsigned TRCD_WR = 10,
    parameter int unsigned TRAS = 33,
    parameter int unsigned TRP = 14,
    parameter int unsigned TWR = 12,
    parameter int unsigned TCCD = 4,
    parameter int unsigned TRRD = 4,
    parameter int unsigned TFAW = 16,
    parameter int unsigned TRFC = 160,
    parameter int unsigned TWTR = 4,
    parameter int unsigned TRTW = 4,
    parameter int unsigned READ_LATENCY = 2
    ,parameter int unsigned PIM_READ_PORTS = 8
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic cmd_valid_i,
    output logic cmd_ready_o,
    input  logic [2:0] cmd_i,
    input  logic [BANK_WIDTH-1:0] bank_i,
    input  logic [ROW_WIDTH-1:0] row_i,
    input  logic [COL_WIDTH-1:0] col_i,
    input  logic [DATA_WIDTH-1:0] write_data_i,
    input  logic [DATA_WIDTH/8-1:0] write_mask_i,
    output logic read_valid_o,
    input  logic read_ready_i,
    output logic [DATA_WIDTH-1:0] read_data_o,
    output logic timing_error_o
    ,input logic [PIM_READ_PORTS-1:0] pim_read_enable_i
    ,input logic [PIM_READ_PORTS-1:0][BANK_WIDTH-1:0] pim_read_bank_i
    ,input logic [PIM_READ_PORTS-1:0][ROW_WIDTH-1:0] pim_read_row_i
    ,input logic [PIM_READ_PORTS-1:0][COL_WIDTH-1:0] pim_read_col_i
    ,output logic [PIM_READ_PORTS-1:0] pim_read_valid_o
    ,output logic [PIM_READ_PORTS-1:0][DATA_WIDTH-1:0] pim_read_data_o
);
`include "rtl/pim_rtl_constants.svh"
    localparam int unsigned TIMER_WIDTH = 16;
    logic [DATA_WIDTH-1:0] memory [0:BANKS-1][0:ROWS-1][0:COLS-1];
    logic [BANKS-1:0] open_valid_q;
    logic [BANKS-1:0][ROW_WIDTH-1:0] open_row_q;
    logic [BANKS-1:0][TIMER_WIDTH-1:0] since_act_q, since_pre_q;
    logic [BANKS-1:0][TIMER_WIDTH-1:0] since_write_q;
    logic [TIMER_WIDTH-1:0] since_last_act_q, since_col_q;
    logic [3:0][TIMER_WIDTH-1:0] act_age_q;
    logic last_col_valid_q, last_col_write_q;
    logic refresh_busy_q;
    logic [TIMER_WIDTH-1:0] refresh_count_q;
    logic [TIMER_WIDTH-1:0] read_count_q;
    logic read_pending_q;
    logic [DATA_WIDTH-1:0] read_pending_data_q;
    logic command_legal;
    logic [TIMER_WIDTH-1:0] required_col_gap;

    always @* begin
        command_legal = 1'b0;
        required_col_gap = TCCD;
        if (last_col_valid_q && last_col_write_q && cmd_i == DRAM_CMD_RD && TWTR > required_col_gap)
            required_col_gap = TWTR;
        if (last_col_valid_q && !last_col_write_q && cmd_i == DRAM_CMD_WR && TRTW > required_col_gap)
            required_col_gap = TRTW;
        case (cmd_i)
            DRAM_CMD_NOP: command_legal = !refresh_busy_q;
            DRAM_CMD_ACT: command_legal = !refresh_busy_q && !open_valid_q[bank_i] &&
                                           since_pre_q[bank_i] >= TRP &&
                                           since_last_act_q >= TRRD && act_age_q[3] >= TFAW;
            DRAM_CMD_RD: command_legal = open_valid_q[bank_i] && open_row_q[bank_i] == row_i &&
                                                since_act_q[bank_i] >= TRCD_RD && !read_pending_q &&
                                                (!read_valid_o || read_ready_i) && !refresh_busy_q &&
                                                (!last_col_valid_q || since_col_q >= required_col_gap);
            DRAM_CMD_WR: command_legal = open_valid_q[bank_i] && open_row_q[bank_i] == row_i &&
                                                since_act_q[bank_i] >= TRCD_WR && !refresh_busy_q &&
                                                (!last_col_valid_q || since_col_q >= required_col_gap);
            DRAM_CMD_PRE: command_legal = !refresh_busy_q && open_valid_q[bank_i] &&
                                             since_act_q[bank_i] >= TRAS && since_write_q[bank_i] >= TWR;
            DRAM_CMD_REF: command_legal = !refresh_busy_q && !(|open_valid_q) &&
                                          !read_pending_q && !read_valid_o;
            default: command_legal = 1'b0;
        endcase
        cmd_ready_o = command_legal;
        timing_error_o = cmd_valid_i && !command_legal;
        pim_read_valid_o = '0;
        pim_read_data_o = '0;
        for (integer port = 0; port < PIM_READ_PORTS; port = port + 1)
            if (!refresh_busy_q && pim_read_enable_i[port] && open_valid_q[pim_read_bank_i[port]] &&
                open_row_q[pim_read_bank_i[port]] == pim_read_row_i[port] &&
                since_act_q[pim_read_bank_i[port]] >= TRCD_RD) begin
                pim_read_valid_o[port] = 1'b1;
                pim_read_data_o[port] = memory[pim_read_bank_i[port]]
                                              [pim_read_row_i[port]][pim_read_col_i[port]];
            end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            open_valid_q <= '0;
            open_row_q <= '0;
            read_valid_o <= 1'b0;
            read_data_o <= '0;
            read_pending_q <= 1'b0;
            read_count_q <= '0;
            since_last_act_q <= {TIMER_WIDTH{1'b1}};
            since_col_q <= {TIMER_WIDTH{1'b1}};
            act_age_q <= '1;
            last_col_valid_q <= 1'b0;
            last_col_write_q <= 1'b0;
            refresh_busy_q <= 1'b0;
            refresh_count_q <= '0;
            for (integer bank = 0; bank < BANKS; bank = bank + 1) begin
                since_act_q[bank] <= '0;
                since_pre_q[bank] <= TRP;
                since_write_q[bank] <= {TIMER_WIDTH{1'b1}};
            end
        end else begin
            for (integer bank = 0; bank < BANKS; bank = bank + 1) begin
                if (since_act_q[bank] != {TIMER_WIDTH{1'b1}})
                    since_act_q[bank] <= since_act_q[bank] + 1'b1;
                if (since_pre_q[bank] != {TIMER_WIDTH{1'b1}})
                    since_pre_q[bank] <= since_pre_q[bank] + 1'b1;
                if (since_write_q[bank] != {TIMER_WIDTH{1'b1}})
                    since_write_q[bank] <= since_write_q[bank] + 1'b1;
            end
            if (since_last_act_q != {TIMER_WIDTH{1'b1}})
                since_last_act_q <= since_last_act_q + 1'b1;
            if (since_col_q != {TIMER_WIDTH{1'b1}})
                since_col_q <= since_col_q + 1'b1;
            for (integer age = 0; age < 4; age = age + 1)
                if (act_age_q[age] != {TIMER_WIDTH{1'b1}})
                    act_age_q[age] <= act_age_q[age] + 1'b1;
            if (refresh_busy_q) begin
                if (refresh_count_q == 0) refresh_busy_q <= 1'b0;
                else refresh_count_q <= refresh_count_q - 1'b1;
            end
            if (read_valid_o && read_ready_i) read_valid_o <= 1'b0;
            if (read_pending_q) begin
                if (read_count_q == 0) begin
                    read_valid_o <= 1'b1;
                    read_data_o <= read_pending_data_q;
                    read_pending_q <= 1'b0;
                end else read_count_q <= read_count_q - 1'b1;
            end
            if (cmd_valid_i && cmd_ready_o) begin
                case (cmd_i)
                    DRAM_CMD_ACT: begin
                        open_valid_q[bank_i] <= 1'b1;
                        open_row_q[bank_i] <= row_i;
                        since_act_q[bank_i] <= '0;
                        since_last_act_q <= '0;
                        act_age_q[3] <= act_age_q[2];
                        act_age_q[2] <= act_age_q[1];
                        act_age_q[1] <= act_age_q[0];
                        act_age_q[0] <= '0;
                    end
                    DRAM_CMD_RD: begin
                        read_pending_data_q <= memory[bank_i][row_i][col_i];
                        read_count_q <= READ_LATENCY > 0 ? READ_LATENCY - 1 : 0;
                        read_pending_q <= 1'b1;
                        since_col_q <= '0;
                        last_col_valid_q <= 1'b1;
                        last_col_write_q <= 1'b0;
                    end
                    DRAM_CMD_WR: begin
                        for (integer byte_idx = 0; byte_idx < DATA_WIDTH/8; byte_idx = byte_idx + 1)
                            if (write_mask_i[byte_idx])
                                memory[bank_i][row_i][col_i][byte_idx*8 +: 8] <=
                                    write_data_i[byte_idx*8 +: 8];
                        since_write_q[bank_i] <= '0;
                        since_col_q <= '0;
                        last_col_valid_q <= 1'b1;
                        last_col_write_q <= 1'b1;
                    end
                    DRAM_CMD_PRE: begin
                        open_valid_q[bank_i] <= 1'b0;
                        since_pre_q[bank_i] <= '0;
                    end
                    DRAM_CMD_REF: begin
                        refresh_busy_q <= TRFC != 0;
                        refresh_count_q <= TRFC > 0 ? TRFC - 1 : 0;
                        last_col_valid_q <= 1'b0;
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
