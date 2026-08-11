module pim_command_decoder (
    input  logic [31:0] command_i,
    output logic [3:0]  opcode_o,
    output logic [2:0]  dst_o,
    output logic [2:0]  src0_o,
    output logic [2:0]  src1_o,
    output logic [2:0]  src2_o,
    output logic        auto_o,
    output logic        relu_o,
    output logic [3:0]  dst_idx_o,
    output logic [3:0]  src0_idx_o,
    output logic [3:0]  src1_idx_o,
    output logic [10:0] loop_count_o,
    output logic [10:0] loop_offset_o,
    output logic        arithmetic_o,
    output logic        legal_o
);
`include "rtl/pim_rtl_constants.svh"
    always @* begin
        opcode_o = command_i[31:28];
        dst_o = command_i[27:25];
        src0_o = command_i[24:22];
        src1_o = command_i[21:19];
        src2_o = command_i[18:16];
        auto_o = command_i[15];
        relu_o = command_i[12];
        dst_idx_o = command_i[11:8];
        src0_idx_o = command_i[7:4];
        src1_idx_o = command_i[3:0];
        loop_count_o = command_i[10:0];
        loop_offset_o = command_i[10:0];
        arithmetic_o = opcode_o == PIM_OP_ADD || opcode_o == PIM_OP_MUL ||
                       opcode_o == PIM_OP_MAC || opcode_o == PIM_OP_MAD;
        legal_o = arithmetic_o || opcode_o == PIM_OP_NOP || opcode_o == PIM_OP_MOV ||
                  opcode_o == PIM_OP_FILL || opcode_o == PIM_OP_JUMP ||
                  opcode_o == PIM_OP_EXIT;
        if ((dst_o == PIM_OPD_GRF_A || dst_o == PIM_OPD_GRF_B) && dst_idx_o >= 8)
            legal_o = 1'b0;
        if ((src0_o == PIM_OPD_GRF_A || src0_o == PIM_OPD_GRF_B) && src0_idx_o >= 8)
            legal_o = 1'b0;
        if ((src1_o == PIM_OPD_GRF_A || src1_o == PIM_OPD_GRF_B) && src1_idx_o >= 8)
            legal_o = 1'b0;
    end
endmodule
