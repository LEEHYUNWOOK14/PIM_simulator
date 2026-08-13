module fp32_add_pipe4_tb;
  localparam int N=20225;logic clk=0,rst_n=0,valid,ov;always#5 clk=~clk;
  logic[143:0]vectors[0:N-1];logic[31:0]lhs,rhs,out;integer errors=0;
  fp32_add_pipe4 dut(.clk_i(clk),.rst_ni(rst_n),.enable_i(1'b1),.valid_i(valid),.valid_o(ov),.lhs_i(lhs),.rhs_i(rhs),.result_o(out));
  initial begin
    $readmemh("verification/groot_normalization/fp32_mixed_precision_vectors.hex",vectors);valid=0;lhs=0;rhs=0;
    repeat(3)@(negedge clk);rst_n=1;
    for(integer i=0;i<N;i++)begin
      @(negedge clk);valid=1;lhs=vectors[i][143:112];rhs=vectors[i][111:80];
      @(negedge clk);valid=0;while(!ov)@(negedge clk);
      if(out!==vectors[i][79:48])begin if(errors<8)$display("PIPE4 mismatch i=%0d out=%h expected=%h",i,out,vectors[i][79:48]);errors++;end
    end
    if(errors)$fatal(1,"FP32_ADD_PIPE4_TB FAIL errors=%0d",errors);$display("FP32_ADD_PIPE4_TB PASS vectors=%0d latency=3 II=1",N);$finish;
  end
endmodule
