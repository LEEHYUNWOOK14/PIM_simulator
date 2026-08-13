module mixed_precision_scalar_pipe_tb;
  localparam int N=16;logic clk=0,rst_n=0;always#5 clk=~clk;
  logic req_v,mode;logic[15:0]tag;logic[31:0]sum,sumsq,inv_hidden,epsilon;logic rr0,rr1;
  logic ov0,ov1;logic om0,om1,cl0,cl1;logic[15:0]ot0,ot1;logic[31:0]mean0,mean1,inv0,inv1;
  logic[N-1:0][80:0]expected;integer old_count=0,new_count=0,errors=0;
  mixed_precision_scalar_nr2 old_dut(.clk_i(clk),.rst_ni(rst_n),.request_valid_i(req_v),.request_ready_o(rr0),.request_rms_norm_i(mode),.request_tag_i(tag),.sum_i(sum),.sumsq_i(sumsq),.inv_hidden_i(inv_hidden),.epsilon_i(epsilon),.response_valid_o(ov0),.response_ready_i(1'b1),.response_rms_norm_o(om0),.response_tag_o(ot0),.mean_o(mean0),.inv_std_o(inv0),.variance_clamped_o(cl0));
  mixed_precision_scalar_nr2_pipe new_dut(.clk_i(clk),.rst_ni(rst_n),.request_valid_i(req_v),.request_ready_o(rr1),.request_rms_norm_i(mode),.request_tag_i(tag),.sum_i(sum),.sumsq_i(sumsq),.inv_hidden_i(inv_hidden),.epsilon_i(epsilon),.response_valid_o(ov1),.response_ready_i(1'b1),.response_rms_norm_o(om1),.response_tag_o(ot1),.mean_o(mean1),.inv_std_o(inv1),.variance_clamped_o(cl1));
  always@(negedge clk)if(rst_n)begin
    if(ov0)begin expected[old_count]={om0,ot0,mean0,inv0};old_count=old_count+1;end
    if(ov1)begin
      if(new_count>=old_count||{om1,ot1,mean1,inv1}!==expected[new_count])begin $display("scalar mismatch index=%0d new=%h expected=%h",new_count,{om1,ot1,mean1,inv1},expected[new_count]);errors=errors+1;end
      if(cl1!==cl0)begin $display("clamp mismatch index=%0d",new_count);errors=errors+1;end
      new_count=new_count+1;
    end
  end
  initial begin
    req_v=0;mode=0;tag=0;sum=0;sumsq=0;inv_hidden=32'h3c800000;epsilon=32'h3727c5ac;
    repeat(3)@(negedge clk);rst_n=1;
    for(integer i=0;i<N;i++)begin
      while(!(rr0&&rr1))@(negedge clk);mode=i[0];tag=16'h3000+i;sum=32'h42000000;sumsq=32'h42c80000+(i<<16);req_v=1;
      @(negedge clk);req_v=0;
    end
    while(new_count<N)@(negedge clk);repeat(2)@(negedge clk);
    if(old_count!=N)errors=errors+1;
    if(errors)$fatal(1,"MIXED_PRECISION_SCALAR_PIPE_TB FAIL errors=%0d",errors);
    $display("MIXED_PRECISION_SCALAR_PIPE_TB PASS requests=%0d NR=2",N);$finish;
  end
  initial begin repeat(5000)@(negedge clk);$fatal(1,"SCALAR_PIPE timeout old=%0d new=%0d",old_count,new_count);end
endmodule
