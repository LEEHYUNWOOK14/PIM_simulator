module pim_vector_alu #(
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned FP16_LANES = DATA_WIDTH / 16,
    parameter int unsigned INT8_LANES = DATA_WIDTH / 32
) (
    input  logic [3:0] opcode_i,
    input  logic [1:0] precision_i,
    input  logic [DATA_WIDTH-1:0] src0_i,
    input  logic [DATA_WIDTH-1:0] src1_i,
    input  logic [DATA_WIDTH-1:0] src2_i,
    input  logic [DATA_WIDTH-1:0] accum_i,
    output logic [DATA_WIDTH-1:0] result_o
);
`include "rtl/pim_rtl_constants.svh"
    logic [DATA_WIDTH-1:0] fp_product, fp_add_rhs, fp_result;

    for (genvar lane = 0; lane < FP16_LANES; lane++) begin : g_fp16
        fp16_mul u_mul(
            .lhs_i(src0_i[lane*16 +: 16]), .rhs_i(src1_i[lane*16 +: 16]),
            .result_o(fp_product[lane*16 +: 16]));
        always @* begin
            if (opcode_i == PIM_OP_ADD) fp_add_rhs[lane*16 +: 16] = src1_i[lane*16 +: 16];
            else if (opcode_i == PIM_OP_MAC) fp_add_rhs[lane*16 +: 16] = accum_i[lane*16 +: 16];
            else fp_add_rhs[lane*16 +: 16] = src2_i[lane*16 +: 16];
        end
        fp16_add u_add(
            .lhs_i(opcode_i == 4'h1 ? src0_i[lane*16 +: 16] :
                                                    fp_product[lane*16 +: 16]),
            .rhs_i(fp_add_rhs[lane*16 +: 16]),
            .result_o(fp_result[lane*16 +: 16]));
    end

    always @* begin
        result_o = '0;
        if (precision_i == PIM_PREC_FP16) begin
            if (opcode_i == PIM_OP_MUL) result_o = fp_product;
            else result_o = fp_result;
        end else begin
            for (integer lane = 0; lane < INT8_LANES; lane = lane + 1) begin
                if (opcode_i == PIM_OP_ADD)
                    result_o[lane*32 +: 32] =
                        $signed(src0_i[lane*32 +: 32]) + $signed(src1_i[lane*32 +: 32]);
                else if (opcode_i == PIM_OP_MUL)
                    result_o[lane*32 +: 32] =
                        $signed(src0_i[lane*8 +: 8]) * $signed(src1_i[lane*8 +: 8]);
                else if (opcode_i == PIM_OP_MAC)
                    result_o[lane*32 +: 32] =
                        $signed(src0_i[lane*8 +: 8]) * $signed(src1_i[lane*8 +: 8]) +
                        $signed(accum_i[lane*32 +: 32]);
                else if (opcode_i == PIM_OP_MAD)
                    result_o[lane*32 +: 32] =
                        $signed(src0_i[lane*8 +: 8]) * $signed(src1_i[lane*8 +: 8]) +
                        $signed(src2_i[lane*32 +: 32]);
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (DATA_WIDTH % 32 != 0) $fatal(1, "DATA_WIDTH must be divisible by 32");
    end
`endif
endmodule
