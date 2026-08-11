module bank_side_pim_subsystem #(
    parameter int unsigned BANKS = 16,
    parameter int unsigned PIM_BLOCKS = 8,
    parameter int unsigned ROWS = 32,
    parameter int unsigned COLS = 8,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned KEY_WIDTH = 32,
    parameter int unsigned CRF_DEPTH = 32,
    parameter int unsigned BANK_WIDTH = BANKS > 1 ? $clog2(BANKS) : 1,
    parameter int unsigned ROW_WIDTH = ROWS > 1 ? $clog2(ROWS) : 1,
    parameter int unsigned COL_WIDTH = COLS > 1 ? $clog2(COLS) : 1,
    parameter int unsigned CRF_ADDR_WIDTH = CRF_DEPTH > 1 ? $clog2(CRF_DEPTH) : 1,
    parameter int unsigned PIM_BLOCK_WIDTH = PIM_BLOCKS > 1 ? $clog2(PIM_BLOCKS) : 1
) (
    input logic clk_i, input logic rst_ni,
    input logic dram_cmd_valid_i, output logic dram_cmd_ready_o,
    input logic [2:0] dram_cmd_i,
    input logic [BANK_WIDTH-1:0] dram_bank_i,
    input logic [ROW_WIDTH-1:0] dram_row_i,
    input logic [COL_WIDTH-1:0] dram_col_i,
    input logic [DATA_WIDTH-1:0] dram_write_data_i,
    input logic [DATA_WIDTH/8-1:0] dram_write_mask_i,
    output logic dram_read_valid_o, input logic dram_read_ready_i,
    output logic [DATA_WIDTH-1:0] dram_read_data_o,
    output logic dram_timing_error_o,
    input logic crf_program_valid_i, output logic crf_program_ready_o,
    input logic [CRF_ADDR_WIDTH-1:0] crf_program_addr_i,
    input logic [31:0] crf_program_data_i,
    input logic crf_start_i,
    input logic [KEY_WIDTH-1:0] context_key_i,
    input logic [1:0] precision_i,
    input logic [ROW_WIDTH-1:0] pim_row_i,
    input logic [COL_WIDTH-1:0] pim_col_i,
    input logic register_write_valid_i,
    input logic [PIM_BLOCK_WIDTH-1:0] register_write_block_i,
    input logic register_write_bank_i,
    input logic [2:0] register_write_index_i,
    input logic [DATA_WIDTH-1:0] register_write_data_i,
    input logic srf_write_valid_i,
    input logic [PIM_BLOCK_WIDTH-1:0] srf_write_block_i,
    input logic [DATA_WIDTH-1:0] srf_write_data_i,
    output logic [PIM_BLOCKS-1:0] result_valid_o,
    input logic [PIM_BLOCKS-1:0] result_ready_i,
    output logic [PIM_BLOCKS-1:0][KEY_WIDTH-1:0] result_key_o,
    output logic [PIM_BLOCKS-1:0][2:0] result_destination_o,
    output logic [PIM_BLOCKS-1:0][3:0] result_index_o,
    output logic [PIM_BLOCKS-1:0][DATA_WIDTH-1:0] result_data_o,
    output logic [PIM_BLOCKS-1:0] command_error_o,
    output logic crf_active_o, output logic crf_done_o
);
    logic crf_command_valid, crf_command_ready;
    logic [31:0] crf_command;
    logic [PIM_BLOCKS-1:0] block_command_ready;
    logic [PIM_BLOCKS-1:0] core_command_error;
    logic [PIM_BLOCKS*2-1:0] pim_read_enable;
    logic [PIM_BLOCKS*2-1:0][BANK_WIDTH-1:0] pim_read_bank;
    logic [PIM_BLOCKS*2-1:0][ROW_WIDTH-1:0] pim_read_row;
    logic [PIM_BLOCKS*2-1:0][COL_WIDTH-1:0] pim_read_col;
    logic [PIM_BLOCKS*2-1:0] pim_read_valid;
    logic [PIM_BLOCKS*2-1:0][DATA_WIDTH-1:0] pim_read_data;
    logic decoded_legal;
    logic [3:0] unused_opcode, unused_dst_idx, unused_src0_idx, unused_src1_idx;
    logic [2:0] unused_dst, unused_src0, unused_src1, unused_src2;
    logic unused_auto, unused_relu, unused_arithmetic;
    logic [10:0] unused_loop_count, unused_loop_offset;

    dram_bank_array_model #(.BANKS(BANKS),.ROWS(ROWS),.COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH),.PIM_READ_PORTS(PIM_BLOCKS*2)) u_dram(
        .clk_i,.rst_ni,.cmd_valid_i(dram_cmd_valid_i),.cmd_ready_o(dram_cmd_ready_o),
        .cmd_i(dram_cmd_i),.bank_i(dram_bank_i),.row_i(dram_row_i),.col_i(dram_col_i),
        .write_data_i(dram_write_data_i),.write_mask_i(dram_write_mask_i),
        .read_valid_o(dram_read_valid_o),.read_ready_i(dram_read_ready_i),
        .read_data_o(dram_read_data_o),.timing_error_o(dram_timing_error_o),
        .pim_read_enable_i(pim_read_enable),.pim_read_bank_i(pim_read_bank),
        .pim_read_row_i(pim_read_row),.pim_read_col_i(pim_read_col),
        .pim_read_valid_o(pim_read_valid),.pim_read_data_o(pim_read_data));

    pim_crf #(.DEPTH(CRF_DEPTH)) u_crf(
        .clk_i,.rst_ni,.program_valid_i(crf_program_valid_i),
        .program_ready_o(crf_program_ready_o),.program_addr_i(crf_program_addr_i),
        .program_data_i(crf_program_data_i),.start_i(crf_start_i),
        .command_ready_i(crf_command_ready),.command_valid_o(crf_command_valid),
        .command_o(crf_command),.active_o(crf_active_o),.done_o(crf_done_o),.pc_o());
    pim_command_decoder u_command_check(
        .command_i(crf_command),.opcode_o(unused_opcode),.dst_o(unused_dst),
        .src0_o(unused_src0),.src1_o(unused_src1),.src2_o(unused_src2),
        .auto_o(unused_auto),.relu_o(unused_relu),.dst_idx_o(unused_dst_idx),
        .src0_idx_o(unused_src0_idx),.src1_idx_o(unused_src1_idx),
        .loop_count_o(unused_loop_count),.loop_offset_o(unused_loop_offset),
        .arithmetic_o(unused_arithmetic),.legal_o(decoded_legal));
    // Illegal words retire with an error pulse instead of wedging the shared CRF.
    assign crf_command_ready = !decoded_legal || &block_command_ready;
    assign command_error_o = core_command_error |
        {PIM_BLOCKS{crf_command_valid && !decoded_legal}};

    genvar b;
    generate for (b = 0; b < PIM_BLOCKS; b = b + 1) begin : g_block
        assign pim_read_enable[b*2] = crf_active_o;
        assign pim_read_enable[b*2+1] = crf_active_o;
        assign pim_read_bank[b*2] = b*2;
        assign pim_read_bank[b*2+1] = b*2+1;
        assign pim_read_row[b*2] = pim_row_i;
        assign pim_read_row[b*2+1] = pim_row_i;
        assign pim_read_col[b*2] = pim_col_i;
        assign pim_read_col[b*2+1] = pim_col_i;
        bank_pim_core #(.DATA_WIDTH(DATA_WIDTH),.KEY_WIDTH(KEY_WIDTH)) u_core(
            .clk_i,.rst_ni,.command_valid_i(crf_command_valid && crf_command_ready),
            .command_ready_o(block_command_ready[b]),.command_i(crf_command),
            .precision_i,.context_key_i,.even_bank_data_i(pim_read_data[b*2]),
            .odd_bank_data_i(pim_read_data[b*2+1]),
            .even_bank_valid_i(pim_read_valid[b*2]),.odd_bank_valid_i(pim_read_valid[b*2+1]),
            .register_write_valid_i(register_write_valid_i && register_write_block_i==b),
            .register_write_bank_i,.register_write_index_i,.register_write_data_i,
            .srf_write_valid_i(srf_write_valid_i && srf_write_block_i==b),.srf_write_data_i,
            .result_valid_o(result_valid_o[b]),.result_ready_i(result_ready_i[b]),
            .result_key_o(result_key_o[b]),.result_destination_o(result_destination_o[b]),
            .result_index_o(result_index_o[b]),.result_data_o(result_data_o[b]),
            .command_error_o(core_command_error[b]));
    end endgenerate

`ifndef SYNTHESIS
    initial if (BANKS != PIM_BLOCKS*2) $fatal(1,"each PIM block requires an even/odd bank pair");
`endif
endmodule
