module pim_crf #(
    parameter int unsigned DEPTH = 32,
    parameter int unsigned ADDR_WIDTH = DEPTH > 1 ? $clog2(DEPTH) : 1
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic program_valid_i,
    output logic program_ready_o,
    input  logic [ADDR_WIDTH-1:0] program_addr_i,
    input  logic [31:0] program_data_i,
    input  logic start_i,
    input  logic command_ready_i,
    output logic command_valid_o,
    output logic [31:0] command_o,
    output logic active_o,
    output logic done_o,
    output logic [ADDR_WIDTH-1:0] pc_o
);
`include "rtl/pim_rtl_constants.svh"
    logic [31:0] memory [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0] pc_q;
    logic [16:0] jump_remaining_q;
    logic jump_active_q;
    logic [ADDR_WIDTH-1:0] jump_pc_q;
    logic [10:0] repeat_remaining_q;
    logic repeat_active_q;
    logic [ADDR_WIDTH-1:0] repeat_pc_q;
    logic active_q;
    wire [3:0] opcode = memory[pc_q][31:28];
    wire [16:0] encoded_jump_count = memory[pc_q][27:11];
    wire [10:0] encoded_jump_offset = memory[pc_q][10:0];

    assign program_ready_o = !active_q;
    assign command_valid_o = active_q;
    assign command_o = memory[pc_q];
    assign active_o = active_q;
    assign pc_o = pc_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pc_q <= '0;
            jump_remaining_q <= '0;
            jump_active_q <= 1'b0;
            jump_pc_q <= '0;
            repeat_remaining_q <= '0;
            repeat_active_q <= 1'b0;
            repeat_pc_q <= '0;
            active_q <= 1'b0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (program_valid_i && program_ready_o)
                memory[program_addr_i] <= program_data_i;
            if (start_i && !active_q) begin
                pc_q <= '0;
                jump_remaining_q <= '0;
                jump_active_q <= 1'b0;
                repeat_remaining_q <= '0;
                repeat_active_q <= 1'b0;
                active_q <= 1'b1;
            end else if (command_valid_o && command_ready_i) begin
                if (opcode == PIM_OP_EXIT) begin
                    active_q <= 1'b0;
                    done_o <= 1'b1;
                end else if (opcode == PIM_OP_JUMP) begin
                    if (!jump_active_q || jump_pc_q != pc_q) begin
                        jump_active_q <= encoded_jump_count != 0;
                        jump_pc_q <= pc_q;
                        if (encoded_jump_count != 0 && encoded_jump_offset <= pc_q) begin
                            jump_remaining_q <= encoded_jump_count - 1'b1;
                            pc_q <= pc_q - encoded_jump_offset[ADDR_WIDTH-1:0];
                        end else begin
                            jump_remaining_q <= '0;
                            pc_q <= pc_q + 1'b1;
                        end
                    end else if (jump_remaining_q != 0 && encoded_jump_offset <= pc_q) begin
                        jump_remaining_q <= jump_remaining_q - 1'b1;
                        pc_q <= pc_q - encoded_jump_offset[ADDR_WIDTH-1:0];
                    end else begin
                        jump_active_q <= 1'b0;
                        jump_remaining_q <= '0;
                        pc_q <= pc_q + 1'b1;
                    end
                end else if (opcode == PIM_OP_NOP || opcode == PIM_OP_FILL ||
                             ((opcode == PIM_OP_ADD || opcode == PIM_OP_MUL ||
                               opcode == PIM_OP_MAC || opcode == PIM_OP_MAD) &&
                              memory[pc_q][15])) begin
                    if (!repeat_active_q || repeat_pc_q != pc_q) begin
                        repeat_active_q <= (opcode == PIM_OP_FILL) ||
                                           memory[pc_q][15] || memory[pc_q][10:0] != 0;
                        repeat_pc_q <= pc_q;
                        if (opcode == PIM_OP_FILL || memory[pc_q][15]) begin
                            repeat_remaining_q <= 11'd6;
                            pc_q <= pc_q;
                        end else if (memory[pc_q][10:0] != 0) begin
                            repeat_remaining_q <= memory[pc_q][10:0] - 1'b1;
                            pc_q <= pc_q;
                        end else begin
                            repeat_remaining_q <= '0;
                            pc_q <= pc_q + 1'b1;
                        end
                    end else if (repeat_remaining_q != 0) begin
                        repeat_remaining_q <= repeat_remaining_q - 1'b1;
                        pc_q <= pc_q;
                    end else begin
                        repeat_active_q <= 1'b0;
                        repeat_remaining_q <= '0;
                        pc_q <= pc_q + 1'b1;
                    end
                end else begin
                    repeat_active_q <= 1'b0;
                    pc_q <= pc_q + 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial if (DEPTH < 2 || 2**ADDR_WIDTH < DEPTH) $fatal(1, "invalid CRF dimensions");
`endif
endmodule
