module shared_channel_reduction_path #(
    parameter int unsigned SOURCES=8, PIPELINES=2, ENTRIES_PER_SOURCE=16,
    parameter int unsigned KEY_WIDTH=64, LANES=16,
    parameter int unsigned DATA_WIDTH=LANES*16,
    parameter int unsigned SLOT_WIDTH=ENTRIES_PER_SOURCE > 1 ? $clog2(ENTRIES_PER_SOURCE) : 1,
    parameter int unsigned SOURCE_WIDTH=SOURCES > 1 ? $clog2(SOURCES) : 1
) (
    input logic clk_i,input logic rst_ni,
    input logic [SOURCES-1:0] source_valid_i,
    output logic [SOURCES-1:0] source_ready_o,
    input logic [SOURCES-1:0][KEY_WIDTH-1:0] source_key_i,
    input logic [SOURCES-1:0][SLOT_WIDTH-1:0] source_slot_i,
    input logic [SOURCES-1:0][DATA_WIDTH-1:0] source_partial_i,
    input logic [SOURCES-1:0] source_first_i,input logic [SOURCES-1:0] source_last_i,
    output logic link_valid_o,input logic link_ready_i,
    output logic [KEY_WIDTH-1:0] link_key_o,
    output logic [DATA_WIDTH-1:0] link_data_o,
    output logic [SOURCE_WIDTH-1:0] link_source_o,
    output logic [SOURCES-1:0] protocol_error_o
);
    logic [SOURCES-1:0] final_valid,final_ready;
    logic [SOURCES-1:0][KEY_WIDTH-1:0] final_key;
    logic [SOURCES-1:0][DATA_WIDTH-1:0] final_data;
    shared_fp16_reduction_cluster #(
        .SOURCES(SOURCES),.PIPELINES(PIPELINES),.ENTRIES_PER_SOURCE(ENTRIES_PER_SOURCE),
        .KEY_WIDTH(KEY_WIDTH),.LANES(LANES),.DATA_WIDTH(DATA_WIDTH),
        .SLOT_WIDTH(SLOT_WIDTH),.SOURCE_WIDTH(SOURCE_WIDTH)
    ) cluster(
        .clk_i,.rst_ni,.source_valid_i,.source_ready_o,.source_key_i,.source_slot_i,
        .source_partial_i,.source_first_i,.source_last_i,.final_valid_o(final_valid),
        .final_ready_i(final_ready),.final_key_o(final_key),.final_data_o(final_data),
        .protocol_error_o);
    logic_die_link_arbiter #(
        .INPUTS(SOURCES),.KEY_WIDTH(KEY_WIDTH),.DATA_WIDTH(DATA_WIDTH),
        .INDEX_WIDTH(SOURCE_WIDTH)
    ) channel_link(
        .clk_i,.rst_ni,.input_valid_i(final_valid),.input_ready_o(final_ready),
        .input_key_i(final_key),.input_data_i(final_data),.input_route_i('0),
        .output_valid_o(link_valid_o),
        .output_ready_i(link_ready_i),.output_key_o(link_key_o),
        .output_data_o(link_data_o),.output_source_o(link_source_o),.output_route_o());
endmodule
