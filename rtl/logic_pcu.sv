module logic_pcu #(
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned TAG_WIDTH = 64,
    parameter int unsigned LATENCY = 2
) (
    input logic clk_i, input logic rst_ni,
    input logic request_valid_i, output logic request_ready_o,
    input logic [3:0] opcode_i, input logic [1:0] precision_i,
    input logic [TAG_WIDTH-1:0] tag_i,
    input logic [DATA_WIDTH-1:0] src0_i, src1_i, src2_i, accum_i,
    output logic response_valid_o, input logic response_ready_i,
    output logic [TAG_WIDTH-1:0] response_tag_o,
    output logic [DATA_WIDTH-1:0] response_data_o
);
    logic [DATA_WIDTH-1:0] alu_result;
    logic [LATENCY-1:0] valid_q;
    logic [LATENCY-1:0][TAG_WIDTH-1:0] tag_q;
    logic [LATENCY-1:0][DATA_WIDTH-1:0] data_q;
    logic advance;

    pim_vector_alu #(.DATA_WIDTH(DATA_WIDTH)) u_alu(
        .opcode_i, .precision_i, .src0_i, .src1_i, .src2_i, .accum_i,
        .result_o(alu_result));
    assign advance = !valid_q[LATENCY-1] || response_ready_i;
    assign request_ready_o = advance;
    assign response_valid_o = valid_q[LATENCY-1];
    assign response_tag_o = tag_q[LATENCY-1];
    assign response_data_o = data_q[LATENCY-1];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_q <= '0;
        end else if (advance) begin
            for (integer stage = LATENCY-1; stage > 0; stage = stage - 1) begin
                valid_q[stage] <= valid_q[stage-1];
                tag_q[stage] <= tag_q[stage-1];
                data_q[stage] <= data_q[stage-1];
            end
            valid_q[0] <= request_valid_i && request_ready_o;
            tag_q[0] <= tag_i;
            data_q[0] <= alu_result;
        end
    end

`ifndef SYNTHESIS
    initial if (LATENCY < 1) $fatal(1, "LATENCY must be at least one");
`endif
endmodule
