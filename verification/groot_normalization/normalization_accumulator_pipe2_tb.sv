module normalization_accumulator_pipe2_tb;
  logic clk=0,rst_n=0,clear,iv,last,ready16,readyb,rv16,rvb,rr; logic[15:0] ps,psq,rs16,rsq16,rsb,rsqb; integer errors;
  always #5 clk=~clk;
  normalization_accumulator_pipe2 #(.DATA_FORMAT(0)) u16(.clk_i(clk),.rst_ni(rst_n),.clear_i(clear),.partial_valid_i(iv),.partial_ready_o(ready16),.partial_sum_i(ps),.partial_sumsq_i(psq),.partial_last_i(last),.result_valid_o(rv16),.result_ready_i(rr),.result_sum_o(rs16),.result_sumsq_o(rsq16));
  normalization_accumulator_pipe2 #(.DATA_FORMAT(1)) ub(.clk_i(clk),.rst_ni(rst_n),.clear_i(clear),.partial_valid_i(iv),.partial_ready_o(readyb),.partial_sum_i(ps),.partial_sumsq_i(psq),.partial_last_i(last),.result_valid_o(rvb),.result_ready_i(rr),.result_sum_o(rsb),.result_sumsq_o(rsqb));
  task automatic feed(input[15:0]x,input[15:0]y,input bit l); begin
    @(negedge clk);ps=x;psq=y;last=l;iv=1;while(!(ready16&&readyb))@(negedge clk);@(negedge clk);iv=0;
  end endtask
  initial begin
    clear=0;iv=0;last=0;ps=0;psq=0;rr=1;errors=0;repeat(3)@(negedge clk);rst_n=1;
    @(negedge clk);clear=1;@(negedge clk);clear=0;
    feed(16'h3c00,16'h3c00,0);feed(16'h4000,16'h4400,1);
    while(!rv16||!rvb)@(negedge clk);
    // The shared stimulus is FP16-coded: FP16 expects 1+2=3 and 1+4=5;
    // the same bit patterns are valid BF16 values and therefore have a
    // different, independently checked rounded result.
    if(rs16!==16'h4200||rsq16!==16'h4500||rsb!==16'h4000||rsqb!==16'h4400) begin $display("FAIL result fp=%h/%h bf=%h/%h",rs16,rsq16,rsb,rsqb);errors=errors+1;end
    rr=0;@(negedge clk);if(!rv16||!rvb)begin $display("FAIL stall lost valid");errors=errors+1;end
    repeat(2)@(negedge clk);if(!rv16||!rvb)begin $display("FAIL stall hold");errors=errors+1;end
    rr=1;@(negedge clk);if(errors!=0)$fatal(1,"accumulator errors=%0d",errors);
    $display("NORMALIZATION_ACCUMULATOR_PIPE2_TB PASS FP16_BF16 II=2 backpressure=1");$finish;
  end
endmodule
