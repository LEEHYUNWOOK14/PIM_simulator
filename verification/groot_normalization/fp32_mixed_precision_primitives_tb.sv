module fp32_mixed_precision_primitives_tb;
  localparam int N=20225;
  logic[143:0]vectors[0:N-1];
  logic[31:0]lhs,rhs,expected_add,expected_mul,actual_add,actual_mul,expanded;
  logic[15:0]expected_bf16,actual_bf16;
  integer errors=0;
  fp32_add u_add(.lhs_i(lhs),.rhs_i(rhs),.result_o(actual_add));
  fp32_mul u_mul(.lhs_i(lhs),.rhs_i(rhs),.result_o(actual_mul));
  fp32_to_bf16_rne u_narrow(.fp32_i(lhs),.bf16_o(actual_bf16));
  bf16_to_fp32 u_expand(.bf16_i(lhs[31:16]),.fp32_o(expanded));
  initial begin
    $readmemh("verification/groot_normalization/fp32_mixed_precision_vectors.hex",vectors);
    for(integer i=0;i<N;i++)begin
      {lhs,rhs,expected_add,expected_mul,expected_bf16}=vectors[i];#1;
      if(actual_add!==expected_add)begin
        if(errors<8)$display("FP32_ADD mismatch i=%0d lhs=%h rhs=%h actual=%h expected=%h",i,lhs,rhs,actual_add,expected_add);
        errors++;
      end
      if(actual_mul!==expected_mul)begin
        if(errors<8)$display("FP32_MUL mismatch i=%0d lhs=%h rhs=%h actual=%h expected=%h",i,lhs,rhs,actual_mul,expected_mul);
        errors++;
      end
      if(actual_bf16!==expected_bf16)begin
        if(errors<8)$display("FP32_TO_BF16 mismatch i=%0d input=%h actual=%h expected=%h",i,lhs,actual_bf16,expected_bf16);
        errors++;
      end
      if(expanded!=={lhs[31:16],16'h0000})begin
        if(errors<8)$display("BF16_TO_FP32 mismatch i=%0d",i);errors++;
      end
    end
    if(errors)$fatal(1,"FP32_MIXED_PRECISION_PRIMITIVES_TB FAIL errors=%0d",errors);
    $display("FP32_MIXED_PRECISION_PRIMITIVES_TB PASS vectors=%0d",N);$finish;
  end
endmodule

