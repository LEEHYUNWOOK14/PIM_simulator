module pim_vector_alu_tb;
    import pim_rtl_pkg::*;
    logic [3:0] opcode;
    logic [1:0] precision;
    logic [255:0] src0, src1, src2, accum, result;
    pim_vector_alu dut(.opcode_i(opcode), .precision_i(precision), .src0_i(src0),
        .src1_i(src1), .src2_i(src2), .accum_i(accum), .result_o(result));
    task automatic expect_lane(input logic [15:0] expected, input string label);
        if (result[15:0] !== expected) begin
            $display("FAIL %s got=%h expected=%h", label, result[15:0], expected);
            $fatal(1);
        end
    endtask
    initial begin
        precision=PIM_PREC_FP16; src0='0; src1='0; src2='0; accum='0;
        src0[15:0]=16'h4000; src1[15:0]=16'h4200; // 2, 3
        opcode=PIM_OP_MUL; #1; expect_lane(16'h4600, "fp16 mul 2*3");
        accum[15:0]=16'h3c00; opcode=PIM_OP_MAC; #1; expect_lane(16'h4700, "fp16 mac 2*3+1");
        src2[15:0]=16'hc000; opcode=PIM_OP_MAD; #1; expect_lane(16'h4400, "fp16 mad 2*3-2");
        src0[15:0]=16'hbc00; src1[15:0]=16'h4200; opcode=PIM_OP_MUL; #1;
        expect_lane(16'hc200, "fp16 signed mul");
        src0[15:0]=16'h0000; src1[15:0]=16'h7c00; #1; expect_lane(16'h7e00, "zero times inf");
        precision=PIM_PREC_INT8; src0='0; src1='0; accum='0;
        src0[7:0]=-8'sd3; src1[7:0]=8'd4; accum[31:0]=32'd20;
        opcode=PIM_OP_MAC; #1;
        if ($signed(result[31:0]) !== 8) $fatal(1, "INT8 MAC mismatch got %0d", $signed(result[31:0]));
        $display("PIM_VECTOR_ALU_TB PASS");
        $finish;
    end
endmodule
