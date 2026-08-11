module dram_command_decoder #(
    parameter int unsigned BANK_WIDTH = 4,
    parameter int unsigned ROW_WIDTH = 14,
    parameter int unsigned COL_WIDTH = 7
) (
    input logic request_valid_i,
    input logic [2:0] request_opcode_i,
    input logic [BANK_WIDTH-1:0] request_bank_i,
    input logic [ROW_WIDTH-1:0] request_row_i,
    input logic [COL_WIDTH-1:0] request_col_i,
    input logic [255:0] request_write_data_i,
    output logic command_valid_o,
    output logic [2:0] command_o,
    output logic [BANK_WIDTH-1:0] bank_o,
    output logic [ROW_WIDTH-1:0] row_o,
    output logic [COL_WIDTH-1:0] col_o,
    output logic [255:0] write_data_o,
    output logic legal_o
);
`include "rtl/pim_rtl_constants.svh"
    always @* begin
        command_valid_o = request_valid_i;
        command_o = request_opcode_i;
        bank_o = request_bank_i; row_o = request_row_i; col_o = request_col_i;
        write_data_o = request_write_data_i;
        legal_o = request_opcode_i == DRAM_CMD_NOP || request_opcode_i == DRAM_CMD_ACT ||
                  request_opcode_i == DRAM_CMD_RD || request_opcode_i == DRAM_CMD_WR ||
                  request_opcode_i == DRAM_CMD_PRE || request_opcode_i == DRAM_CMD_REF;
    end
endmodule
