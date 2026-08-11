module bf16_arithmetic_random_tb;
    localparam integer CASES = 20256;
    logic [63:0] vectors [0:CASES-1];
    logic [15:0] lhs, rhs, add_result, mul_result;
    integer index, errors;
    bf16_add add_dut(.lhs_i(lhs), .rhs_i(rhs), .result_o(add_result));
    bf16_mul mul_dut(.lhs_i(lhs), .rhs_i(rhs), .result_o(mul_result));
    initial begin
        $readmemh("verification/groot_normalization/bf16_arithmetic_vectors.hex", vectors);
        lhs=0; rhs=0; errors=0;
        for(index=0; index<CASES; index=index+1) begin
            lhs=vectors[index][63:48]; rhs=vectors[index][47:32]; #1;
            if(add_result!==vectors[index][31:16]) begin
                if(errors<20) $display("BF16 ADD FAIL i=%0d a=%h b=%h got=%h exp=%h",index,lhs,rhs,add_result,vectors[index][31:16]);
                errors=errors+1;
            end
            if(mul_result!==vectors[index][15:0]) begin
                if(errors<20) $display("BF16 MUL FAIL i=%0d a=%h b=%h got=%h exp=%h",index,lhs,rhs,mul_result,vectors[index][15:0]);
                errors=errors+1;
            end
        end
        if(errors) $fatal(1,"BF16_ARITHMETIC_RANDOM_TB FAIL errors=%0d",errors);
        $display("BF16_ARITHMETIC_RANDOM_TB PASS vectors=%0d",CASES);
        $finish;
    end
endmodule
