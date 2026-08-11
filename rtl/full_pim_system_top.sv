module full_pim_system_top #(
    parameter int unsigned CHANNELS = 64,
    parameter int unsigned BANKS = 16,
    parameter int unsigned PIM_BLOCKS = 8,
    parameter int unsigned PCUS = 16,
    parameter int unsigned ROWS = 32,
    parameter int unsigned COLS = 8,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned KEY_WIDTH = 32,
    parameter int unsigned TAG_WIDTH = 64,
    parameter int unsigned CRF_DEPTH = 32,
    parameter int unsigned CHANNEL_WIDTH = CHANNELS > 1 ? $clog2(CHANNELS) : 1,
    parameter int unsigned BANK_WIDTH = BANKS > 1 ? $clog2(BANKS) : 1,
    parameter int unsigned ROW_WIDTH = ROWS > 1 ? $clog2(ROWS) : 1,
    parameter int unsigned COL_WIDTH = COLS > 1 ? $clog2(COLS) : 1,
    parameter int unsigned WEIGHT_BUFFER_BYTES = 65536,
    parameter int unsigned WEIGHT_ADDR_WIDTH = WEIGHT_BUFFER_BYTES/(DATA_WIDTH/8) > 1 ?
                                               $clog2(WEIGHT_BUFFER_BYTES/(DATA_WIDTH/8)) : 1,
    parameter int unsigned CRF_ADDR_WIDTH = CRF_DEPTH > 1 ? $clog2(CRF_DEPTH) : 1,
    parameter int unsigned PIM_BLOCK_WIDTH = PIM_BLOCKS > 1 ? $clog2(PIM_BLOCKS) : 1
) (
    input logic clk_i, input logic rst_ni,
    input logic [CHANNELS-1:0] dram_cmd_valid_i,
    output logic [CHANNELS-1:0] dram_cmd_ready_o,
    input logic [CHANNELS-1:0][2:0] dram_cmd_i,
    input logic [CHANNELS-1:0][BANK_WIDTH-1:0] dram_bank_i,
    input logic [CHANNELS-1:0][ROW_WIDTH-1:0] dram_row_i,
    input logic [CHANNELS-1:0][COL_WIDTH-1:0] dram_col_i,
    input logic [CHANNELS-1:0][DATA_WIDTH-1:0] dram_write_data_i,
    input logic [CHANNELS-1:0][DATA_WIDTH/8-1:0] dram_write_mask_i,
    output logic [CHANNELS-1:0] dram_read_valid_o,
    input logic [CHANNELS-1:0] dram_read_ready_i,
    output logic [CHANNELS-1:0][DATA_WIDTH-1:0] dram_read_data_o,
    output logic [CHANNELS-1:0] dram_timing_error_o,
    input logic [CHANNELS-1:0] crf_program_valid_i,
    output logic [CHANNELS-1:0] crf_program_ready_o,
    input logic [CHANNELS-1:0][CRF_ADDR_WIDTH-1:0] crf_program_addr_i,
    input logic [CHANNELS-1:0][31:0] crf_program_data_i,
    input logic [CHANNELS-1:0] crf_start_i,
    input logic [CHANNELS-1:0][KEY_WIDTH-1:0] bank_context_key_i,
    input logic [CHANNELS-1:0][1:0] bank_precision_i,
    input logic [CHANNELS-1:0][ROW_WIDTH-1:0] pim_row_i,
    input logic [CHANNELS-1:0][COL_WIDTH-1:0] pim_col_i,
    input logic [CHANNELS-1:0] register_write_valid_i,
    input logic [CHANNELS-1:0][PIM_BLOCK_WIDTH-1:0] register_write_block_i,
    input logic [CHANNELS-1:0] register_write_bank_i,
    input logic [CHANNELS-1:0][2:0] register_write_index_i,
    input logic [CHANNELS-1:0][DATA_WIDTH-1:0] register_write_data_i,
    input logic [CHANNELS-1:0] srf_write_valid_i,
    input logic [CHANNELS-1:0][PIM_BLOCK_WIDTH-1:0] srf_write_block_i,
    input logic [CHANNELS-1:0][DATA_WIDTH-1:0] srf_write_data_i,
    input logic [CHANNELS-1:0] bank_result_to_logic_i,
    input logic [CHANNELS-1:0][DATA_WIDTH-1:0] logic_src1_i,
    input logic [CHANNELS-1:0][DATA_WIDTH-1:0] logic_src2_i,
    input logic [CHANNELS-1:0][DATA_WIDTH-1:0] logic_accum_i,
    input logic logic_command_valid_i, output logic logic_command_ready_o,
    input logic [CHANNEL_WIDTH-1:0] logic_command_channel_i,
    input logic [15:0] logic_command_epoch_i, logic_command_ordinal_i,
    input logic [31:0] logic_command_signature_i, logic_command_word_i,
    input logic [CHANNELS-1:0] logic_command_expected_mask_i,
    input logic epoch_begin_valid_i, output logic epoch_begin_ready_o,
    input logic [15:0] epoch_begin_id_i,
    input logic [CHANNELS-1:0] epoch_expected_mask_i,
    input logic epoch_fill_done_valid_i,
    input logic [CHANNEL_WIDTH-1:0] epoch_fill_done_channel_i,
    input logic epoch_execution_done_i,
    output logic epoch_release_valid_o,
    output logic [15:0] epoch_release_id_o,
    output logic epoch_active_o,
    input logic weight_write_valid_i, output logic weight_write_ready_o,
    input logic [WEIGHT_ADDR_WIDTH-1:0] weight_write_addr_i,
    input logic [DATA_WIDTH-1:0] weight_write_data_i,
    input logic [DATA_WIDTH/8-1:0] weight_write_mask_i,
    input logic weight_read_valid_i, output logic weight_read_ready_o,
    input logic [WEIGHT_ADDR_WIDTH-1:0] weight_read_addr_i,
    output logic weight_response_valid_o, input logic weight_response_ready_i,
    output logic [DATA_WIDTH-1:0] weight_response_data_o,
    input logic weight_context_commit_i,
    input logic [15:0] weight_context_id_i,
    output logic weight_context_valid_o,
    output logic [PCUS-1:0] logic_result_valid_o,
    input logic [PCUS-1:0] logic_result_ready_i,
    output logic [PCUS-1:0][TAG_WIDTH-1:0] logic_result_tag_o,
    output logic [PCUS-1:0][DATA_WIDTH-1:0] logic_result_data_o,
    output logic logic_bank_result_valid_o, input logic logic_bank_result_ready_i,
    output logic [TAG_WIDTH-1:0] logic_bank_result_tag_o,
    output logic [DATA_WIDTH-1:0] logic_bank_result_data_o,
    output logic logic_host_result_valid_o, input logic logic_host_result_ready_i,
    output logic [TAG_WIDTH-1:0] logic_host_result_tag_o,
    output logic [DATA_WIDTH-1:0] logic_host_result_data_o,
    output logic [1:0] direct_tsv_valid_o,
    input logic [1:0] direct_tsv_ready_i,
    output logic [1:0][KEY_WIDTH-1:0] direct_tsv_key_o,
    output logic [1:0][DATA_WIDTH-1:0] direct_tsv_data_o,
    output logic [1:0][CHANNEL_WIDTH-1:0] direct_tsv_channel_o,
    input logic normalization_begin_valid_i,
    output logic normalization_begin_ready_o,
    input logic normalization_begin_rms_norm_i,
    input logic [TAG_WIDTH-1:0] normalization_begin_tag_i,
    input logic [BANKS-1:0] normalization_expected_bank_mask_i,
    input logic [15:0] normalization_inv_hidden_i,
    input logic [15:0] normalization_epsilon_i,
    input logic normalization_partial_valid_i,
    output logic normalization_partial_ready_o,
    input logic [BANK_WIDTH-1:0] normalization_partial_bank_i,
    input logic [TAG_WIDTH-1:0] normalization_partial_tag_i,
    input logic [15:0] normalization_partial_sum_i,
    input logic [15:0] normalization_partial_sumsq_i,
    output logic normalization_broadcast_valid_o,
    input logic normalization_broadcast_ready_i,
    output logic normalization_broadcast_rms_norm_o,
    output logic [TAG_WIDTH-1:0] normalization_broadcast_tag_o,
    output logic [15:0] normalization_broadcast_mean_o,
    output logic [15:0] normalization_broadcast_inv_std_o,
    output logic normalization_variance_clamped_o,
    output logic protocol_error_o
);
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0] block_result_valid, block_result_ready;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][KEY_WIDTH-1:0] block_result_key;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][DATA_WIDTH-1:0] block_result_data;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][2:0] unused_destination;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0][3:0] unused_index;
    logic [CHANNELS-1:0][PIM_BLOCKS-1:0] block_command_error;
    logic [CHANNELS-1:0] channel_result_valid, channel_result_ready;
    logic [CHANNELS-1:0] channel_result_to_logic;
    logic [CHANNELS-1:0][KEY_WIDTH-1:0] channel_result_key;
    logic [CHANNELS-1:0][DATA_WIDTH-1:0] channel_result_data;
    logic [CHANNELS-1:0] logic_path_valid, logic_path_ready;
    logic [CHANNELS-1:0] direct_path_valid, direct_path_ready;
    logic logic_operand_valid, logic_operand_ready;
    logic [CHANNEL_WIDTH-1:0] logic_operand_channel;
    logic [KEY_WIDTH-1:0] logic_operand_key;
    logic [DATA_WIDTH-1:0] logic_operand_src0;
    logic [PCUS-1:0][CHANNEL_WIDTH-1:0] unused_logic_result_channel;
    logic coal_dup, coal_context, operand_context;
    logic reduction_dup, reduction_context;
    logic reduced_valid, reduced_ready, reduced_destination_bank;
    logic [TAG_WIDTH-1:0] reduced_tag;
    logic [DATA_WIDTH-1:0] reduced_data;
    logic [7:0] unused_occupancy;
    logic normalization_duplicate_error, normalization_context_error;

    genvar channel;
    generate for (channel=0;channel<CHANNELS;channel=channel+1) begin:g_channel
        bank_side_pim_subsystem #(.BANKS(BANKS),.PIM_BLOCKS(PIM_BLOCKS),.ROWS(ROWS),
            .COLS(COLS),.DATA_WIDTH(DATA_WIDTH),.KEY_WIDTH(KEY_WIDTH),.CRF_DEPTH(CRF_DEPTH)) u_bank(
            .clk_i,.rst_ni,.dram_cmd_valid_i(dram_cmd_valid_i[channel]),
            .dram_cmd_ready_o(dram_cmd_ready_o[channel]),.dram_cmd_i(dram_cmd_i[channel]),
            .dram_bank_i(dram_bank_i[channel]),.dram_row_i(dram_row_i[channel]),
            .dram_col_i(dram_col_i[channel]),.dram_write_data_i(dram_write_data_i[channel]),
            .dram_write_mask_i(dram_write_mask_i[channel]),.dram_read_valid_o(dram_read_valid_o[channel]),
            .dram_read_ready_i(dram_read_ready_i[channel]),.dram_read_data_o(dram_read_data_o[channel]),
            .dram_timing_error_o(dram_timing_error_o[channel]),
            .crf_program_valid_i(crf_program_valid_i[channel]),
            .crf_program_ready_o(crf_program_ready_o[channel]),.crf_program_addr_i(crf_program_addr_i[channel]),
            .crf_program_data_i(crf_program_data_i[channel]),.crf_start_i(crf_start_i[channel]),
            .context_key_i(bank_context_key_i[channel]),.precision_i(bank_precision_i[channel]),
            .pim_row_i(pim_row_i[channel]),.pim_col_i(pim_col_i[channel]),
            .register_write_valid_i(register_write_valid_i[channel]),
            .register_write_block_i(register_write_block_i[channel]),
            .register_write_bank_i(register_write_bank_i[channel]),
            .register_write_index_i(register_write_index_i[channel]),
            .register_write_data_i(register_write_data_i[channel]),
            .srf_write_valid_i(srf_write_valid_i[channel]),.srf_write_block_i(srf_write_block_i[channel]),
            .srf_write_data_i(srf_write_data_i[channel]),.result_valid_o(block_result_valid[channel]),
            .result_ready_i(block_result_ready[channel]),.result_key_o(block_result_key[channel]),
            .result_destination_o(unused_destination[channel]),.result_index_o(unused_index[channel]),
            .result_data_o(block_result_data[channel]),.command_error_o(block_command_error[channel]),
            .crf_active_o(),.crf_done_o());
        logic_die_link_arbiter #(.INPUTS(PIM_BLOCKS),.KEY_WIDTH(KEY_WIDTH),
            .DATA_WIDTH(DATA_WIDTH)) u_local_result(
            .clk_i,.rst_ni,.input_valid_i(block_result_valid[channel]),
            .input_ready_o(block_result_ready[channel]),.input_key_i(block_result_key[channel]),
            .input_data_i(block_result_data[channel]),
            .input_route_i({PIM_BLOCKS{bank_result_to_logic_i[channel]}}),
            .output_valid_o(channel_result_valid[channel]),
            .output_ready_i(channel_result_ready[channel]),.output_key_o(channel_result_key[channel]),
            .output_data_o(channel_result_data[channel]),.output_source_o(),
            .output_route_o(channel_result_to_logic[channel]));
        assign logic_path_valid[channel] = channel_result_valid[channel] && channel_result_to_logic[channel];
        assign direct_path_valid[channel] = channel_result_valid[channel] && !channel_result_to_logic[channel];
        assign channel_result_ready[channel] = channel_result_to_logic[channel] ?
                                               logic_path_ready[channel] : direct_path_ready[channel];
    end endgenerate

    logic_die_link_arbiter #(.INPUTS(CHANNELS),.KEY_WIDTH(KEY_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),.INDEX_WIDTH(CHANNEL_WIDTH)) u_logic_operand_arbiter(
        .clk_i,.rst_ni,.input_valid_i(logic_path_valid),.input_ready_o(logic_path_ready),
        .input_key_i(channel_result_key),.input_data_i(channel_result_data),
        .input_route_i('0),
        .output_valid_o(logic_operand_valid),.output_ready_i(logic_operand_ready),
        .output_key_o(logic_operand_key),.output_data_o(logic_operand_src0),
        .output_source_o(logic_operand_channel),.output_route_o());

    logic_die_pim_top #(.CHANNELS(CHANNELS),.PCUS(PCUS),.DATA_WIDTH(DATA_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),.WEIGHT_BUFFER_BYTES(WEIGHT_BUFFER_BYTES)) u_logic_die(
        .clk_i,.rst_ni,.operand_valid_i(logic_operand_valid),.operand_ready_o(logic_operand_ready),
        .operand_channel_i(logic_operand_channel),
        .operand_tag_i({{(TAG_WIDTH-KEY_WIDTH){1'b0}},logic_operand_key}),
        .operand_precision_i(bank_precision_i[logic_operand_channel]),.operand_src0_i(logic_operand_src0),
        .operand_src1_i(logic_src1_i[logic_operand_channel]),.operand_src2_i(logic_src2_i[logic_operand_channel]),
        .operand_accum_i(logic_accum_i[logic_operand_channel]),.command_valid_i(logic_command_valid_i),
        .command_ready_o(logic_command_ready_o),.command_channel_i(logic_command_channel_i),
        .command_epoch_i(logic_command_epoch_i),.command_ordinal_i(logic_command_ordinal_i),
        .command_signature_i(logic_command_signature_i),.command_word_i(logic_command_word_i),
        .command_expected_mask_i(logic_command_expected_mask_i),
        .epoch_begin_valid_i,.epoch_begin_ready_o,.epoch_begin_id_i,
        .epoch_expected_mask_i,.epoch_fill_done_valid_i,.epoch_fill_done_channel_i,
        .epoch_execution_done_i,.epoch_release_valid_o,.epoch_release_id_o,.epoch_active_o,
        .weight_write_valid_i,.weight_write_ready_o,.weight_write_addr_i,.weight_write_data_i,
        .weight_write_mask_i,.weight_read_valid_i,.weight_read_ready_o,.weight_read_addr_i,
        .weight_response_valid_o,.weight_response_ready_i,.weight_response_data_o,
        .weight_context_commit_i,.weight_context_id_i,.weight_context_valid_o,
        .result_valid_o(logic_result_valid_o),
        .result_ready_i(logic_result_ready_i),.result_tag_o(logic_result_tag_o),
        .result_data_o(logic_result_data_o),.result_channel_o(unused_logic_result_channel),
        .reduced_result_valid_o(reduced_valid),.reduced_result_ready_i(reduced_ready),
        .reduced_result_tag_o(reduced_tag),.reduced_result_data_o(reduced_data),
        .reduced_destination_bank_o(reduced_destination_bank),
        .reduction_duplicate_error_o(reduction_dup),
        .reduction_context_error_o(reduction_context),
        .coalescer_duplicate_error_o(coal_dup),.coalescer_context_error_o(coal_context),
        .operand_context_error_o(operand_context),.coalescer_occupancy_o(unused_occupancy));

    channel_tsv_interconnect #(.CHANNELS(CHANNELS),.LANES(2),.DATA_WIDTH(DATA_WIDTH),
        .KEY_WIDTH(KEY_WIDTH)) u_direct_tsv(
        .clk_i,.rst_ni,.input_valid_i(direct_path_valid),.input_ready_o(direct_path_ready),
        .input_key_i(channel_result_key),.input_data_i(channel_result_data),
        .output_valid_o(direct_tsv_valid_o),.output_ready_i(direct_tsv_ready_i),
        .output_key_o(direct_tsv_key_o),.output_data_o(direct_tsv_data_o),
        .output_channel_o(direct_tsv_channel_o));

    logic_result_router #(.KEY_WIDTH(TAG_WIDTH),.DATA_WIDTH(DATA_WIDTH)) u_logic_result_router(
        .result_valid_i(reduced_valid),.result_ready_o(reduced_ready),
        .destination_bank_i(reduced_destination_bank),.result_key_i(reduced_tag),
        .result_data_i(reduced_data),.bank_valid_o(logic_bank_result_valid_o),
        .bank_ready_i(logic_bank_result_ready_i),.bank_key_o(logic_bank_result_tag_o),
        .bank_data_o(logic_bank_result_data_o),.host_valid_o(logic_host_result_valid_o),
        .host_ready_i(logic_host_result_ready_i),.host_key_o(logic_host_result_tag_o),
        .host_data_o(logic_host_result_data_o));
    logic_normalization_reduction_engine #(.BANKS(BANKS),.TAG_WIDTH(TAG_WIDTH))
        u_normalization_engine(
        .clk_i,.rst_ni,.begin_valid_i(normalization_begin_valid_i),
        .begin_ready_o(normalization_begin_ready_o),
        .begin_rms_norm_i(normalization_begin_rms_norm_i),
        .begin_tag_i(normalization_begin_tag_i),
        .begin_expected_mask_i(normalization_expected_bank_mask_i),
        .begin_inv_hidden_i(normalization_inv_hidden_i),
        .begin_epsilon_i(normalization_epsilon_i),
        .partial_valid_i(normalization_partial_valid_i),
        .partial_ready_o(normalization_partial_ready_o),
        .partial_bank_i(normalization_partial_bank_i),
        .partial_tag_i(normalization_partial_tag_i),
        .partial_sum_i(normalization_partial_sum_i),
        .partial_sumsq_i(normalization_partial_sumsq_i),
        .response_valid_o(normalization_broadcast_valid_o),
        .response_ready_i(normalization_broadcast_ready_i),
        .response_rms_norm_o(normalization_broadcast_rms_norm_o),
        .response_tag_o(normalization_broadcast_tag_o),
        .response_mean_o(normalization_broadcast_mean_o),
        .response_inv_std_o(normalization_broadcast_inv_std_o),
        .response_variance_clamped_o(normalization_variance_clamped_o),
        .duplicate_error_o(normalization_duplicate_error),
        .context_error_o(normalization_context_error));
    assign protocol_error_o = |block_command_error || coal_dup || coal_context || operand_context ||
                              reduction_dup || reduction_context || normalization_duplicate_error ||
                              normalization_context_error;
endmodule
