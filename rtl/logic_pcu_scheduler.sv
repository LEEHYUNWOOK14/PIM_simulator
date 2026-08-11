module logic_pcu_scheduler #(
    parameter int unsigned PCUS = 16,
    parameter int unsigned ISSUE_PORTS = 16,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned TAG_WIDTH = 64,
    parameter int unsigned LATENCY = 2,
    parameter int unsigned PCU_WIDTH = PCUS > 1 ? $clog2(PCUS) : 1
) (
    input logic clk_i, input logic rst_ni,
    input logic [ISSUE_PORTS-1:0] request_valid_i,
    output logic [ISSUE_PORTS-1:0] request_ready_o,
    input logic [ISSUE_PORTS-1:0][3:0] request_opcode_i,
    input logic [ISSUE_PORTS-1:0][1:0] request_precision_i,
    input logic [ISSUE_PORTS-1:0][TAG_WIDTH-1:0] request_tag_i,
    input logic [ISSUE_PORTS-1:0][DATA_WIDTH-1:0] request_src0_i,
    input logic [ISSUE_PORTS-1:0][DATA_WIDTH-1:0] request_src1_i,
    input logic [ISSUE_PORTS-1:0][DATA_WIDTH-1:0] request_src2_i,
    input logic [ISSUE_PORTS-1:0][DATA_WIDTH-1:0] request_accum_i,
    output logic [PCUS-1:0] response_valid_o,
    input logic [PCUS-1:0] response_ready_i,
    output logic [PCUS-1:0][TAG_WIDTH-1:0] response_tag_o,
    output logic [PCUS-1:0][DATA_WIDTH-1:0] response_data_o,
    output logic [ISSUE_PORTS-1:0][PCU_WIDTH-1:0] granted_pcu_o,
    output logic [PCUS-1:0] busy_o
);
    logic [PCUS-1:0] pcu_request_ready;

    for (genvar unit = 0; unit < PCUS; unit++) begin : g_pcu
        logic_pcu #(.DATA_WIDTH(DATA_WIDTH), .TAG_WIDTH(TAG_WIDTH), .LATENCY(LATENCY)) u_pcu(
            .clk_i, .rst_ni, .request_valid_i(request_valid_i[unit]),
            .request_ready_o(pcu_request_ready[unit]), .opcode_i(request_opcode_i[unit]),
            .precision_i(request_precision_i[unit]), .tag_i(request_tag_i[unit]),
            .src0_i(request_src0_i[unit]), .src1_i(request_src1_i[unit]),
            .src2_i(request_src2_i[unit]), .accum_i(request_accum_i[unit]),
            .response_valid_o(response_valid_o[unit]),
            .response_ready_i(response_ready_i[unit]), .response_tag_o(response_tag_o[unit]),
            .response_data_o(response_data_o[unit]));
        assign busy_o[unit] = !pcu_request_ready[unit] || response_valid_o[unit];
        assign request_ready_o[unit] = pcu_request_ready[unit];
        assign granted_pcu_o[unit] = unit[PCU_WIDTH-1:0];
    end

`ifndef SYNTHESIS
    initial if (ISSUE_PORTS != PCUS) $fatal(1, "fixed scheduler requires ISSUE_PORTS=PCUS");
`endif
endmodule
