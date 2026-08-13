module fp_bf16_add_pipe2_tb;
  logic clk=0,rst_n=0,vi; logic vo16,vob; logic[15:0]a,b,r16,rb,ref16,refb; integer i; integer errors;
  always #5 clk=~clk;
  fp16_add u_ref16(.lhs_i(a),.rhs_i(b),.result_o(ref16));
  bf16_add u_refb(.lhs_i(a),.rhs_i(b),.result_o(refb));
  fp16_add_pipe2 u_p16(.clk_i(clk),.rst_ni(rst_n),.valid_i(vi),.valid_o(vo16),.lhs_i(a),.rhs_i(b),.result_o(r16));
  bf16_add_pipe2 u_pb(.clk_i(clk),.rst_ni(rst_n),.valid_i(vi),.valid_o(vob),.lhs_i(a),.rhs_i(b),.result_o(rb));
  task automatic check(input[15:0]x,input[15:0]y); reg[15:0]e16,eb; begin
    @(negedge clk); a=x;b=y;#1;e16=ref16;eb=refb;vi=1;
    @(posedge clk); #1; vi=0;
    @(posedge clk); #1;
    if(!vo16||!vob||r16!==e16||rb!==eb) begin
      $display("FAIL x=%h y=%h ref16=%h got16=%h refb=%h gotb=%h v=%b/%b",x,y,e16,r16,eb,rb,vo16,vob);errors=errors+1;
    end
  end endtask
  initial begin
    vi=0;a=0;b=0;errors=0;repeat(3)@(negedge clk);rst_n=1;
    check(16'h0000,16'h8000);check(16'h3c00,16'h3c00);check(16'h7c00,16'h3c00);
    check(16'h7e00,16'h3c00);check(16'h0400,16'h0400);check(16'hbc00,16'h3c00);
    for(i=0;i<1000;i=i+1) check($urandom,$urandom);
    if(errors!=0)$fatal(1,"pipe2 mismatches=%0d",errors);
    $display("FP_BF16_ADD_PIPE2_TB PASS vectors=%0d II=1 latency=1",1006);$finish;
  end
endmodule
