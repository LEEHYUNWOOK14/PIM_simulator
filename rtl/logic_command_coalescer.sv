module logic_command_coalescer #(
    parameter int unsigned CHANNELS = 64,
    parameter int unsigned ENTRIES = 128,
    parameter int unsigned EPOCH_WIDTH = 16,
    parameter int unsigned ORDINAL_WIDTH = 16,
    parameter int unsigned SIGNATURE_WIDTH = 32,
    parameter int unsigned COMMAND_WIDTH = 32,
    parameter int unsigned ENTRY_WIDTH = ENTRIES > 1 ? $clog2(ENTRIES) : 1,
    parameter int unsigned CHANNEL_WIDTH = CHANNELS > 1 ? $clog2(CHANNELS) : 1
) (
    input logic clk_i, input logic rst_ni,
    input logic request_valid_i, output logic request_ready_o,
    input logic [CHANNEL_WIDTH-1:0] request_channel_i,
    input logic [EPOCH_WIDTH-1:0] request_epoch_i,
    input logic [ORDINAL_WIDTH-1:0] request_ordinal_i,
    input logic [SIGNATURE_WIDTH-1:0] request_signature_i,
    input logic [COMMAND_WIDTH-1:0] request_command_i,
    input logic [CHANNELS-1:0] request_expected_mask_i,
    output logic command_valid_o, input logic command_ready_i,
    output logic [EPOCH_WIDTH-1:0] command_epoch_o,
    output logic [ORDINAL_WIDTH-1:0] command_ordinal_o,
    output logic [SIGNATURE_WIDTH-1:0] command_signature_o,
    output logic [COMMAND_WIDTH-1:0] command_o,
    output logic [CHANNELS-1:0] command_channel_mask_o,
    output logic [$clog2(ENTRIES+1)-1:0] occupancy_o,
    output logic duplicate_error_o,
    output logic context_error_o
);
    logic [ENTRIES-1:0] valid_q;
    logic [EPOCH_WIDTH-1:0] epoch_q [0:ENTRIES-1];
    logic [ORDINAL_WIDTH-1:0] ordinal_q [0:ENTRIES-1];
    logic [SIGNATURE_WIDTH-1:0] signature_q [0:ENTRIES-1];
    logic [COMMAND_WIDTH-1:0] command_q [0:ENTRIES-1];
    logic [CHANNELS-1:0] mask_q [0:ENTRIES-1];
    logic [CHANNELS-1:0] expected_q [0:ENTRIES-1];
    logic found_match, found_free, found_complete;
    logic [ENTRY_WIDTH-1:0] match_index, free_index, complete_index;

    always @* begin
        found_match = 1'b0; found_free = 1'b0; found_complete = 1'b0;
        match_index = '0; free_index = '0; complete_index = '0;
        occupancy_o = '0;
        for (integer entry = 0; entry < ENTRIES; entry = entry + 1) begin
            if (valid_q[entry]) occupancy_o = occupancy_o + 1'b1;
            if (!found_match && valid_q[entry] && epoch_q[entry] == request_epoch_i &&
                ordinal_q[entry] == request_ordinal_i && signature_q[entry] == request_signature_i) begin
                found_match = 1'b1;
                match_index = entry[ENTRY_WIDTH-1:0];
            end
            if (!found_free && !valid_q[entry]) begin
                found_free = 1'b1;
                free_index = entry[ENTRY_WIDTH-1:0];
            end
            if (!found_complete && valid_q[entry] && mask_q[entry] == expected_q[entry]) begin
                found_complete = 1'b1;
                complete_index = entry[ENTRY_WIDTH-1:0];
            end
        end
        request_ready_o = found_match || found_free;
        command_valid_o = found_complete;
        command_epoch_o = found_complete ? epoch_q[complete_index] : '0;
        command_ordinal_o = found_complete ? ordinal_q[complete_index] : '0;
        command_signature_o = found_complete ? signature_q[complete_index] : '0;
        command_o = found_complete ? command_q[complete_index] : '0;
        command_channel_mask_o = found_complete ? mask_q[complete_index] : '0;
        duplicate_error_o = request_valid_i && found_match && mask_q[match_index][request_channel_i];
        context_error_o = request_valid_i &&
            (!request_expected_mask_i[request_channel_i] ||
             (found_match && (expected_q[match_index] != request_expected_mask_i ||
                              command_q[match_index] != request_command_i)));
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) valid_q <= '0;
        else begin
            if (command_valid_o && command_ready_i) valid_q[complete_index] <= 1'b0;
            if (request_valid_i && request_ready_o && !duplicate_error_o && !context_error_o) begin
                if (found_match) mask_q[match_index][request_channel_i] <= 1'b1;
                else begin
                    valid_q[free_index] <= 1'b1;
                    epoch_q[free_index] <= request_epoch_i;
                    ordinal_q[free_index] <= request_ordinal_i;
                    signature_q[free_index] <= request_signature_i;
                    command_q[free_index] <= request_command_i;
                    expected_q[free_index] <= request_expected_mask_i;
                    mask_q[free_index] <= {{(CHANNELS-1){1'b0}},1'b1} << request_channel_i;
                end
            end
        end
    end
endmodule
