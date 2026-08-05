module shared_fp16_reduction_cluster #(
    parameter int unsigned SOURCES = 8,
    parameter int unsigned PIPELINES = 1,
    parameter int unsigned ENTRIES_PER_SOURCE = 16,
    parameter int unsigned KEY_WIDTH = 64,
    parameter int unsigned LANES = 16,
    parameter int unsigned DATA_WIDTH = LANES * 16,
    parameter int unsigned SLOT_WIDTH = $clog2(ENTRIES_PER_SOURCE),
    parameter int unsigned SOURCE_WIDTH = $clog2(SOURCES)
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [SOURCES-1:0] source_valid_i,
    output logic [SOURCES-1:0] source_ready_o,
    input  logic [SOURCES-1:0][KEY_WIDTH-1:0] source_key_i,
    input  logic [SOURCES-1:0][SLOT_WIDTH-1:0] source_slot_i,
    input  logic [SOURCES-1:0][DATA_WIDTH-1:0] source_partial_i,
    input  logic [SOURCES-1:0] source_first_i,
    input  logic [SOURCES-1:0] source_last_i,
    output logic [SOURCES-1:0] final_valid_o,
    input  logic [SOURCES-1:0] final_ready_i,
    output logic [SOURCES-1:0][KEY_WIDTH-1:0] final_key_o,
    output logic [SOURCES-1:0][DATA_WIDTH-1:0] final_data_o,
    output logic [SOURCES-1:0] protocol_error_o
);
    logic [SOURCES-1:0] buffer_update_valid, buffer_update_ready;
    logic [SOURCES-1:0][DATA_WIDTH-1:0] add_lhs, add_rhs, add_result;
    logic [SOURCES-1:0] eligible;

    always @* begin
        eligible = source_valid_i & buffer_update_ready;
        source_ready_o = buffer_update_valid & buffer_update_ready;
    end

    shared_fp16_pipeline_fabric #(
        .SOURCES(SOURCES), .PIPELINES(PIPELINES), .LANES(LANES),
        .DATA_WIDTH(DATA_WIDTH), .SOURCE_WIDTH(SOURCE_WIDTH)
    ) fabric (
        .clk_i, .rst_ni, .request_valid_i(eligible),
        .request_grant_o(buffer_update_valid), .lhs_i(add_lhs),
        .rhs_i(add_rhs), .result_o(add_result)
    );

    bank_local_reduction_buffer #(
        .BANKS(SOURCES), .ENTRIES_PER_BANK(ENTRIES_PER_SOURCE),
        .KEY_WIDTH(KEY_WIDTH), .DATA_WIDTH(DATA_WIDTH), .SLOT_WIDTH(SLOT_WIDTH)
    ) entries (
        .clk_i, .rst_ni,
        .update_valid_i(buffer_update_valid), .update_ready_o(buffer_update_ready),
        .update_key_i(source_key_i), .update_slot_i(source_slot_i),
        .update_partial_i(source_partial_i), .update_first_i(source_first_i),
        .update_last_i(source_last_i), .add_lhs_o(add_lhs), .add_rhs_o(add_rhs),
        .add_result_i(add_result), .final_valid_o, .final_ready_i,
        .final_key_o, .final_data_o, .protocol_error_o
    );

`ifndef SYNTHESIS
    initial begin
        if (SOURCES < 2 || (SOURCES & (SOURCES - 1)) != 0)
            $fatal(1, "SOURCES must be a power of two");
        if (PIPELINES == 0 || PIPELINES > SOURCES)
            $fatal(1, "PIPELINES must be in [1, SOURCES]");
        if (DATA_WIDTH != LANES * 16)
            $fatal(1, "DATA_WIDTH must equal LANES * 16");
    end
`endif
endmodule
