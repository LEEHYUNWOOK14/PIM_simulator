module logic_operand_context_buffer #(
    parameter int unsigned CHANNELS = 64,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned TAG_WIDTH = 64,
    parameter int unsigned CHANNEL_WIDTH = CHANNELS > 1 ? $clog2(CHANNELS) : 1
) (
    input logic clk_i, input logic rst_ni,
    input logic write_valid_i, output logic write_ready_o,
    input logic [CHANNEL_WIDTH-1:0] write_channel_i,
    input logic [TAG_WIDTH-1:0] write_tag_i,
    input logic [1:0] write_precision_i,
    input logic [DATA_WIDTH-1:0] write_src0_i,
    input logic [DATA_WIDTH-1:0] write_src1_i,
    input logic [DATA_WIDTH-1:0] write_src2_i,
    input logic [DATA_WIDTH-1:0] write_accum_i,
    input logic [CHANNELS-1:0] consume_mask_i,
    input logic [CHANNELS-1:0] read_mask_i,
    output logic [CHANNELS-1:0] valid_o,
    output logic [CHANNELS-1:0][TAG_WIDTH-1:0] tag_o,
    output logic [CHANNELS-1:0][1:0] precision_o,
    output logic [CHANNELS-1:0][DATA_WIDTH-1:0] src0_o,
    output logic [CHANNELS-1:0][DATA_WIDTH-1:0] src1_o,
    output logic [CHANNELS-1:0][DATA_WIDTH-1:0] src2_o,
    output logic [CHANNELS-1:0][DATA_WIDTH-1:0] accum_o,
    output logic missing_context_error_o
);
    logic [CHANNELS-1:0] valid_q;
    logic [TAG_WIDTH-1:0] tag_q [0:CHANNELS-1];
    logic [1:0] precision_q [0:CHANNELS-1];
    logic [DATA_WIDTH-1:0] src0_q [0:CHANNELS-1], src1_q [0:CHANNELS-1];
    logic [DATA_WIDTH-1:0] src2_q [0:CHANNELS-1], accum_q [0:CHANNELS-1];
    assign write_ready_o = !valid_q[write_channel_i] || consume_mask_i[write_channel_i];
    assign valid_o = valid_q;
    assign missing_context_error_o = |(read_mask_i & ~valid_q);
    for (genvar channel = 0; channel < CHANNELS; channel++) begin : g_read
        assign tag_o[channel] = tag_q[channel];
        assign precision_o[channel] = precision_q[channel];
        assign src0_o[channel] = src0_q[channel];
        assign src1_o[channel] = src1_q[channel];
        assign src2_o[channel] = src2_q[channel];
        assign accum_o[channel] = accum_q[channel];
    end
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) valid_q <= '0;
        else begin
            valid_q <= valid_q & ~consume_mask_i;
            if (write_valid_i && write_ready_o) begin
                valid_q[write_channel_i] <= 1'b1;
                tag_q[write_channel_i] <= write_tag_i;
                precision_q[write_channel_i] <= write_precision_i;
                src0_q[write_channel_i] <= write_src0_i;
                src1_q[write_channel_i] <= write_src1_i;
                src2_q[write_channel_i] <= write_src2_i;
                accum_q[write_channel_i] <= write_accum_i;
            end
        end
    end
endmodule
