module fp16_add_tb;
    logic [15:0] lhs, rhs, result;
    fp16_add dut(.lhs_i(lhs), .rhs_i(rhs), .result_o(result));
    task automatic check(input logic [15:0] a, b, expected);
        lhs = a; rhs = b; #1;
        if (result !== expected)
            $fatal(1, "lhs=%h rhs=%h got=%h expected=%h", a,b,result,expected);
    endtask
    initial begin
        check(16'h3c00,16'h4000,16'h4200);
        check(16'hbc00,16'h4000,16'h3c00);
        check(16'h3c00,16'hbc00,16'h0000);
        check(16'h3800,16'h3400,16'h3a00);
        check(16'h4900,16'h4d00,16'h4f80);
        check(16'h3c00,16'h1000,16'h3c00);
        check(16'h3c01,16'h1000,16'h3c02);
        check(16'h7c00,16'hfc00,16'h7e00);
        $display("FP16_ADD_TB PASS"); $finish;
    end
endmodule
