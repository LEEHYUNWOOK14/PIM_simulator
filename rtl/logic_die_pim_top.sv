module logic_die_pim_top #(
    parameter int unsigned CHANNELS = 64,
    parameter int unsigned PCUS = 16,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned TAG_WIDTH = 64,
    parameter int unsigned CHANNEL_WIDTH = CHANNELS > 1 ? $clog2(CHANNELS) : 1,
    parameter int unsigned EPOCH_WIDTH = 16,
    parameter int unsigned ORDINAL_WIDTH = 16,
    parameter int unsigned WEIGHT_BUFFER_BYTES = 65536,
    parameter int unsigned WEIGHT_ADDR_WIDTH = WEIGHT_BUFFER_BYTES/(DATA_WIDTH/8) > 1 ?
                                               $clog2(WEIGHT_BUFFER_BYTES/(DATA_WIDTH/8)) : 1,
    parameter int unsigned PCU_WIDTH = PCUS > 1 ? $clog2(PCUS) : 1,
    parameter bit REQUIRE_EPOCH = 1'b1,
    parameter bit USE_SHARED_WEIGHT = 1'b1
) (
    input logic clk_i, input logic rst_ni,
    input logic operand_valid_i, output logic operand_ready_o,
    input logic [CHANNEL_WIDTH-1:0] operand_channel_i,
    input logic [TAG_WIDTH-1:0] operand_tag_i,
    input logic [1:0] operand_precision_i,
    input logic [DATA_WIDTH-1:0] operand_src0_i, operand_src1_i,
    input logic [DATA_WIDTH-1:0] operand_src2_i, operand_accum_i,
    input logic command_valid_i, output logic command_ready_o,
    input logic [CHANNEL_WIDTH-1:0] command_channel_i,
    input logic [EPOCH_WIDTH-1:0] command_epoch_i,
    input logic [ORDINAL_WIDTH-1:0] command_ordinal_i,
    input logic [31:0] command_signature_i,
    input logic [31:0] command_word_i,
    input logic [CHANNELS-1:0] command_expected_mask_i,
    input logic epoch_begin_valid_i, output logic epoch_begin_ready_o,
    input logic [EPOCH_WIDTH-1:0] epoch_begin_id_i,
    input logic [CHANNELS-1:0] epoch_expected_mask_i,
    input logic epoch_fill_done_valid_i,
    input logic [CHANNEL_WIDTH-1:0] epoch_fill_done_channel_i,
    input logic epoch_execution_done_i,
    output logic epoch_release_valid_o,
    output logic [EPOCH_WIDTH-1:0] epoch_release_id_o,
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
    output logic [PCUS-1:0] result_valid_o,
    input logic [PCUS-1:0] result_ready_i,
    output logic [PCUS-1:0][TAG_WIDTH-1:0] result_tag_o,
    output logic [PCUS-1:0][DATA_WIDTH-1:0] result_data_o,
    output logic [PCUS-1:0][CHANNEL_WIDTH-1:0] result_channel_o,
    output logic reduced_result_valid_o, input logic reduced_result_ready_i,
    output logic [TAG_WIDTH-1:0] reduced_result_tag_o,
    output logic [DATA_WIDTH-1:0] reduced_result_data_o,
    output logic reduced_destination_bank_o,
    output logic reduction_duplicate_error_o,
    output logic reduction_context_error_o,
    output logic coalescer_duplicate_error_o,
    output logic coalescer_context_error_o,
    output logic operand_context_error_o,
    output logic [$clog2(129)-1:0] coalescer_occupancy_o
);
`include "rtl/pim_rtl_constants.svh"
    logic coalesced_valid, coalesced_ready;
    logic [EPOCH_WIDTH-1:0] coalesced_epoch;
    logic [ORDINAL_WIDTH-1:0] coalesced_ordinal;
    logic [31:0] coalesced_signature, coalesced_command;
    logic [CHANNELS-1:0] coalesced_mask;
    logic dispatch_active_q;
    logic [CHANNELS-1:0] dispatch_remaining_q;
    logic [31:0] dispatch_command_q;
    logic [CHANNELS-1:0] context_valid;
    logic [CHANNELS-1:0][TAG_WIDTH-1:0] context_tag;
    logic [CHANNELS-1:0][1:0] context_precision;
    logic [CHANNELS-1:0][DATA_WIDTH-1:0] context_src0, context_src1;
    logic [CHANNELS-1:0][DATA_WIDTH-1:0] context_src2, context_accum;
    logic [PCUS-1:0] issue_valid, issue_ready;
    logic [PCUS-1:0][3:0] issue_opcode;
    logic [PCUS-1:0][1:0] issue_precision;
    logic [PCUS-1:0][TAG_WIDTH-1:0] issue_tag;
    localparam int unsigned META_WIDTH = TAG_WIDTH + CHANNEL_WIDTH;
    logic [PCUS-1:0][META_WIDTH-1:0] issue_meta, response_meta;
    logic [PCUS-1:0][DATA_WIDTH-1:0] response_data;
    logic [PCUS-1:0] response_valid;
    logic [PCUS-1:0] response_accept_ready, reduction_partial_ready;
    logic [PCUS-1:0][CHANNEL_WIDTH-1:0] reduction_partial_channel;
    logic [PCUS-1:0][TAG_WIDTH-1:0] reduction_partial_key;
    logic [PCUS-1:0][DATA_WIDTH-1:0] issue_src0, issue_src1, issue_src2, issue_accum;
    logic [CHANNELS-1:0] selected_mask, consumed_mask;
    logic [PCUS-1:0][CHANNEL_WIDTH-1:0] selected_channel;
    logic [PCUS-1:0][PCU_WIDTH-1:0] unused_grant;
    logic [PCUS-1:0] unused_busy;
    logic [CHANNELS-1:0] unused_epoch_ready_mask;
    logic epoch_unexpected_channel_error;
    logic epoch_authorized_q;
    logic [EPOCH_WIDTH-1:0] authorized_epoch_q;
    logic epoch_matches, contexts_complete, context_tags_match;
    logic [TAG_WIDTH-1:0] dispatch_tag;
    logic reduction_begin_ready;
    logic reduced_destination_bank_q;
    logic weight_operand_valid_q;
    logic [DATA_WIDTH-1:0] weight_operand_data_q;

    logic_command_coalescer #(.CHANNELS(CHANNELS)) u_coalescer(
        .clk_i, .rst_ni, .request_valid_i(command_valid_i), .request_ready_o(command_ready_o),
        .request_channel_i(command_channel_i), .request_epoch_i(command_epoch_i),
        .request_ordinal_i(command_ordinal_i), .request_signature_i(command_signature_i),
        .request_command_i(command_word_i), .request_expected_mask_i(command_expected_mask_i),
        .command_valid_o(coalesced_valid), .command_ready_i(coalesced_ready),
        .command_epoch_o(coalesced_epoch), .command_ordinal_o(coalesced_ordinal),
        .command_signature_o(coalesced_signature), .command_o(coalesced_command),
        .command_channel_mask_o(coalesced_mask), .occupancy_o(coalescer_occupancy_o),
        .duplicate_error_o(coalescer_duplicate_error_o),
        .context_error_o(coalescer_context_error_o));
    always @* begin
        logic found_tag;
        contexts_complete = coalesced_valid &&
                            ((context_valid & coalesced_mask) == coalesced_mask);
        context_tags_match = 1'b1;
        dispatch_tag = '0;
        found_tag = 1'b0;
        for (integer tag_channel = 0; tag_channel < CHANNELS; tag_channel = tag_channel + 1)
            if (coalesced_mask[tag_channel] && context_valid[tag_channel]) begin
                if (!found_tag) begin
                    found_tag = 1'b1;
                    dispatch_tag = context_tag[tag_channel];
                end else if (context_tag[tag_channel] != dispatch_tag)
                    context_tags_match = 1'b0;
            end
        epoch_matches = !REQUIRE_EPOCH ||
            ((epoch_authorized_q && authorized_epoch_q == coalesced_epoch) ||
             (epoch_release_valid_o && epoch_release_id_o == coalesced_epoch));
    end
    assign coalesced_ready = !dispatch_active_q && contexts_complete &&
                             context_tags_match && epoch_matches && reduction_begin_ready &&
                             (!USE_SHARED_WEIGHT ||
                              (weight_context_valid_o && weight_operand_valid_q));

    logic_epoch_barrier #(.CHANNELS(CHANNELS),.EPOCH_WIDTH(EPOCH_WIDTH)) u_epoch_barrier(
        .clk_i,.rst_ni,.begin_valid_i(epoch_begin_valid_i),.begin_ready_o(epoch_begin_ready_o),
        .begin_epoch_i(epoch_begin_id_i),.begin_expected_mask_i(epoch_expected_mask_i),
        .fill_done_valid_i(epoch_fill_done_valid_i),
        .fill_done_channel_i(epoch_fill_done_channel_i),.execution_done_i(epoch_execution_done_i),
        .release_valid_o(epoch_release_valid_o),.release_epoch_o(epoch_release_id_o),
        .ready_mask_o(unused_epoch_ready_mask),.active_o(epoch_active_o),
        .unexpected_channel_error_o(epoch_unexpected_channel_error));

    logic_shared_buffer #(.DATA_WIDTH(DATA_WIDTH),.BYTES(WEIGHT_BUFFER_BYTES)) u_weight_buffer(
        .clk_i,.rst_ni,.write_valid_i(weight_write_valid_i),.write_ready_o(weight_write_ready_o),
        .write_addr_i(weight_write_addr_i),.write_data_i(weight_write_data_i),
        .write_mask_i(weight_write_mask_i),.read_valid_i(weight_read_valid_i),
        .read_ready_o(weight_read_ready_o),.read_addr_i(weight_read_addr_i),
        .response_valid_o(weight_response_valid_o),.response_ready_i(weight_response_ready_i),
        .response_data_o(weight_response_data_o),.context_commit_i(weight_context_commit_i),
        .context_id_i(weight_context_id_i),.context_valid_o(weight_context_valid_o),
        .resident_context_o());

    logic_operand_context_buffer #(.CHANNELS(CHANNELS), .DATA_WIDTH(DATA_WIDTH),
        .TAG_WIDTH(TAG_WIDTH)) u_context(
        .clk_i, .rst_ni, .write_valid_i(operand_valid_i), .write_ready_o(operand_ready_o),
        .write_channel_i(operand_channel_i), .write_tag_i(operand_tag_i),
        .write_precision_i(operand_precision_i), .write_src0_i(operand_src0_i),
        .write_src1_i(operand_src1_i), .write_src2_i(operand_src2_i),
        .write_accum_i(operand_accum_i), .consume_mask_i(consumed_mask),
        .read_mask_i(dispatch_remaining_q), .valid_o(context_valid), .tag_o(context_tag),
        .precision_o(context_precision), .src0_o(context_src0), .src1_o(context_src1),
        .src2_o(context_src2), .accum_o(context_accum),
        .missing_context_error_o(operand_context_error_o));

    always @* begin
        selected_mask = '0; selected_channel = '0; issue_valid = '0;
        issue_opcode = '0; issue_precision = '0; issue_tag = '0; issue_meta = '0;
        issue_src0 = '0; issue_src1 = '0; issue_src2 = '0; issue_accum = '0;
        for (integer port = 0; port < PCUS; port = port + 1) begin
            logic found;
            found = 1'b0;
            for (integer channel = 0; channel < CHANNELS; channel = channel + 1)
                if (!found && dispatch_remaining_q[channel] && !selected_mask[channel] &&
                    context_valid[channel]) begin
                    found = 1'b1; selected_mask[channel] = 1'b1;
                    selected_channel[port] = channel[CHANNEL_WIDTH-1:0];
                    issue_valid[port] = 1'b1;
                    issue_opcode[port] = dispatch_command_q[31:28];
                    issue_precision[port] = context_precision[channel];
                    issue_tag[port] = context_tag[channel];
                    issue_meta[port] = {context_tag[channel],channel[CHANNEL_WIDTH-1:0]};
                    issue_src0[port] = context_src0[channel];
                    issue_src1[port] = USE_SHARED_WEIGHT ? weight_operand_data_q :
                                                          context_src1[channel];
                    issue_src2[port] = context_src2[channel];
                    issue_accum[port] = context_accum[channel];
                end
        end
        consumed_mask = '0;
        for (integer port = 0; port < PCUS; port = port + 1)
            if (issue_valid[port] && issue_ready[port])
                consumed_mask[selected_channel[port]] = 1'b1;
    end

    logic_pcu_scheduler #(.PCUS(PCUS), .ISSUE_PORTS(PCUS), .DATA_WIDTH(DATA_WIDTH),
        .TAG_WIDTH(META_WIDTH), .LATENCY(2)) u_scheduler(
        .clk_i, .rst_ni, .request_valid_i(issue_valid), .request_ready_o(issue_ready),
        .request_opcode_i(issue_opcode), .request_precision_i(issue_precision),
        .request_tag_i(issue_meta), .request_src0_i(issue_src0), .request_src1_i(issue_src1),
        .request_src2_i(issue_src2), .request_accum_i(issue_accum),
        .response_valid_o(response_valid), .response_ready_i(response_accept_ready),
        .response_tag_o(response_meta), .response_data_o(response_data),
        .granted_pcu_o(unused_grant), .busy_o(unused_busy));

    for (genvar unit = 0; unit < PCUS; unit++) begin : g_result_metadata
        assign response_accept_ready[unit] = result_ready_i[unit] && reduction_partial_ready[unit];
        assign result_valid_o[unit] = response_valid[unit] && reduction_partial_ready[unit];
        assign result_tag_o[unit] = response_meta[unit][META_WIDTH-1:CHANNEL_WIDTH];
        assign result_channel_o[unit] = response_meta[unit][CHANNEL_WIDTH-1:0];
        assign result_data_o[unit] = response_data[unit];
        assign reduction_partial_key[unit] = response_meta[unit][META_WIDTH-1:CHANNEL_WIDTH];
        assign reduction_partial_channel[unit] = response_meta[unit][CHANNEL_WIDTH-1:0];
    end

    cross_channel_reduction_network #(.CHANNELS(CHANNELS),.PORTS(PCUS),
        .DATA_WIDTH(DATA_WIDTH),.KEY_WIDTH(TAG_WIDTH)) u_reduction(
        .clk_i,.rst_ni,.begin_valid_i(coalesced_valid && coalesced_ready),
        .begin_ready_o(reduction_begin_ready),.begin_key_i(dispatch_tag),
        .begin_expected_mask_i(coalesced_mask),
        .partial_valid_i(response_valid & result_ready_i),
        .partial_ready_o(reduction_partial_ready),
        .partial_channel_i(reduction_partial_channel),
        .partial_key_i(reduction_partial_key),
        .partial_data_i(response_data),.result_valid_o(reduced_result_valid_o),
        .result_ready_i(reduced_result_ready_i),.result_key_o(reduced_result_tag_o),
        .result_data_o(reduced_result_data_o),
        .duplicate_error_o(reduction_duplicate_error_o),
        .context_error_o(reduction_context_error_o));
    assign reduced_destination_bank_o = reduced_destination_bank_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            dispatch_active_q <= 1'b0; dispatch_remaining_q <= '0; dispatch_command_q <= '0;
            epoch_authorized_q <= 1'b0; authorized_epoch_q <= '0;
            reduced_destination_bank_q <= 1'b0;
            weight_operand_valid_q <= 1'b0; weight_operand_data_q <= '0;
        end else begin
            if (weight_context_commit_i) weight_operand_valid_q <= 1'b0;
            if (weight_response_valid_o && weight_response_ready_i) begin
                weight_operand_valid_q <= 1'b1;
                weight_operand_data_q <= weight_response_data_o;
            end
            if (epoch_release_valid_o) begin
                epoch_authorized_q <= 1'b1;
                authorized_epoch_q <= epoch_release_id_o;
            end
            if (epoch_execution_done_i) epoch_authorized_q <= 1'b0;
            if (coalesced_valid && coalesced_ready) begin
                dispatch_active_q <= 1'b1;
                dispatch_remaining_q <= coalesced_mask;
                dispatch_command_q <= coalesced_command;
                reduced_destination_bank_q <=
                    coalesced_command[27:25] == PIM_OPD_EVEN_BANK ||
                    coalesced_command[27:25] == PIM_OPD_ODD_BANK;
            end else if (dispatch_active_q) begin
                dispatch_remaining_q <= dispatch_remaining_q & ~consumed_mask;
                if ((dispatch_remaining_q & ~consumed_mask) == 0) dispatch_active_q <= 1'b0;
            end
        end
    end
endmodule
