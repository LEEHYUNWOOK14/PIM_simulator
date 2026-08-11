module bank_pim_core #(
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned KEY_WIDTH = 32
) (
    input logic clk_i, input logic rst_ni,
    input logic command_valid_i, output logic command_ready_o,
    input logic [31:0] command_i,
    input logic [1:0] precision_i,
    input logic [KEY_WIDTH-1:0] context_key_i,
    input logic [DATA_WIDTH-1:0] even_bank_data_i,
    input logic [DATA_WIDTH-1:0] odd_bank_data_i,
    input logic even_bank_valid_i,
    input logic odd_bank_valid_i,
    input logic register_write_valid_i,
    input logic register_write_bank_i,
    input logic [2:0] register_write_index_i,
    input logic [DATA_WIDTH-1:0] register_write_data_i,
    input logic srf_write_valid_i,
    input logic [DATA_WIDTH-1:0] srf_write_data_i,
    output logic result_valid_o, input logic result_ready_i,
    output logic [KEY_WIDTH-1:0] result_key_o,
    output logic [2:0] result_destination_o,
    output logic [3:0] result_index_o,
    output logic [DATA_WIDTH-1:0] result_data_o,
    output logic command_error_o
);
`include "rtl/pim_rtl_constants.svh"
    logic [DATA_WIDTH-1:0] grf_a [0:7];
    logic [DATA_WIDTH-1:0] grf_b [0:7];
    logic [DATA_WIDTH-1:0] srf_q, m_out_q, a_out_q;
    logic [3:0] opcode, dst_idx, src0_idx, src1_idx;
    logic [2:0] dst, src0_sel, src1_sel, src2_sel;
    logic auto_mode, relu, arithmetic, legal;
    logic [10:0] unused_loop_count, unused_loop_offset;
    logic [DATA_WIDTH-1:0] src0_data, src1_data, src2_data, dst_old, alu_result;
    logic [DATA_WIDTH-1:0] selected_result;
    logic operands_available;

    pim_command_decoder u_decode(
        .command_i(command_i), .opcode_o(opcode), .dst_o(dst), .src0_o(src0_sel),
        .src1_o(src1_sel), .src2_o(src2_sel), .auto_o(auto_mode), .relu_o(relu),
        .dst_idx_o(dst_idx), .src0_idx_o(src0_idx), .src1_idx_o(src1_idx),
        .loop_count_o(unused_loop_count), .loop_offset_o(unused_loop_offset),
        .arithmetic_o(arithmetic), .legal_o(legal));

    function automatic [DATA_WIDTH-1:0] operand_value(
        input logic [2:0] selector, input logic [3:0] index);
        logic [15:0] scalar;
        integer scalar_index;
        begin
            scalar = '0;
            scalar_index = index[2:0] % (DATA_WIDTH/16);
            case (selector)
                PIM_OPD_A_OUT: operand_value = a_out_q;
                PIM_OPD_M_OUT: operand_value = m_out_q;
                PIM_OPD_EVEN_BANK: operand_value = even_bank_data_i;
                PIM_OPD_ODD_BANK: operand_value = odd_bank_data_i;
                PIM_OPD_GRF_A: operand_value = grf_a[index[2:0]];
                PIM_OPD_GRF_B: operand_value = grf_b[index[2:0]];
                PIM_OPD_SRF_M: begin
                    scalar = srf_q[scalar_index*16 +: 16];
                    for (integer lane = 0; lane < DATA_WIDTH/16; lane = lane + 1)
                        operand_value[lane*16 +: 16] = scalar;
                end
                default: begin
                    scalar_index = (index[2:0] + 8) % (DATA_WIDTH/16);
                    scalar = srf_q[scalar_index*16 +: 16];
                    for (integer lane = 0; lane < DATA_WIDTH/16; lane = lane + 1)
                        operand_value[lane*16 +: 16] = scalar;
                end
            endcase
        end
    endfunction

    function automatic operand_available(input logic [2:0] selector);
        begin
            case (selector)
                PIM_OPD_EVEN_BANK: operand_available = even_bank_valid_i;
                PIM_OPD_ODD_BANK: operand_available = odd_bank_valid_i;
                default: operand_available = 1'b1;
            endcase
        end
    endfunction

    always @* begin
        src0_data = operand_value(src0_sel, src0_idx);
        src1_data = operand_value(src1_sel, src1_idx);
        src2_data = operand_value(src2_sel, 4'd0);
        dst_old = operand_value(dst, dst_idx);
        selected_result = (opcode == PIM_OP_MOV || opcode == PIM_OP_FILL) ? src0_data : alu_result;
        if (relu)
            for (integer lane = 0; lane < DATA_WIDTH/16; lane = lane + 1)
                if (selected_result[lane*16+15]) selected_result[lane*16 +: 16] = '0;
        operands_available = 1'b1;
        if (arithmetic || opcode == PIM_OP_MOV || opcode == PIM_OP_FILL)
            operands_available = operand_available(src0_sel);
        if (arithmetic)
            operands_available = operands_available && operand_available(src1_sel);
        if (opcode == PIM_OP_MAD)
            operands_available = operands_available && operand_available(src2_sel);
        if (opcode == PIM_OP_MAC)
            operands_available = operands_available && operand_available(dst);
        command_ready_o = (!result_valid_o || result_ready_i) && legal && operands_available;
        command_error_o = command_valid_i && !legal;
    end

    pim_vector_alu #(.DATA_WIDTH(DATA_WIDTH)) u_alu(
        .opcode_i(opcode), .precision_i(precision_i), .src0_i(src0_data),
        .src1_i(src1_data), .src2_i(src2_data), .accum_i(dst_old), .result_o(alu_result));

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            result_valid_o <= 1'b0;
            result_key_o <= '0;
            result_destination_o <= '0;
            result_index_o <= '0;
            result_data_o <= '0;
            m_out_q <= '0;
            a_out_q <= '0;
        end else begin
            if (result_valid_o && result_ready_i) result_valid_o <= 1'b0;
            if (register_write_valid_i) begin
                if (register_write_bank_i) grf_b[register_write_index_i] <= register_write_data_i;
                else grf_a[register_write_index_i] <= register_write_data_i;
            end
            if (srf_write_valid_i) srf_q <= srf_write_data_i;
            if (command_valid_i && command_ready_o &&
                (arithmetic || opcode == PIM_OP_MOV || opcode == PIM_OP_FILL)) begin
                case (dst)
                    PIM_OPD_A_OUT: a_out_q <= selected_result;
                    PIM_OPD_M_OUT: m_out_q <= selected_result;
                    PIM_OPD_GRF_A: grf_a[dst_idx[2:0]] <= selected_result;
                    PIM_OPD_GRF_B: grf_b[dst_idx[2:0]] <= selected_result;
                    default: begin end
                endcase
                result_valid_o <= 1'b1;
                result_key_o <= context_key_i;
                result_destination_o <= dst;
                result_index_o <= dst_idx;
                result_data_o <= selected_result;
            end
        end
    end
endmodule
