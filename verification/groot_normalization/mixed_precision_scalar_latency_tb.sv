module mixed_precision_scalar_latency_tb;
  logic clk=0,rst_n=0,req_v,req_r,mode,resp_v;always#5 clk=~clk;
  logic[15:0]tag,resp_tag;logic[31:0]sum,sumsq,invh,eps,mean,inv;
  logic resp_mode,clamped;integer cycle=0,start_cycle,rms_latency,ln_latency;
  mixed_precision_scalar_nr2_pipe dut(.clk_i(clk),.rst_ni(rst_n),.request_valid_i(req_v),.request_ready_o(req_r),
    .request_rms_norm_i(mode),.request_tag_i(tag),.sum_i(sum),.sumsq_i(sumsq),.inv_hidden_i(invh),.epsilon_i(eps),
    .response_valid_o(resp_v),.response_ready_i(1'b1),.response_rms_norm_o(resp_mode),.response_tag_o(resp_tag),
    .mean_o(mean),.inv_std_o(inv),.variance_clamped_o(clamped));
  always@(posedge clk)if(rst_n)cycle++;
  task automatic run(input logic m,input logic[15:0]t);begin
    @(negedge clk);while(!req_r)@(negedge clk);mode=m;tag=t;req_v=1;start_cycle=cycle;
    @(negedge clk);req_v=0;while(!resp_v)@(negedge clk);
    if(resp_mode!==m||resp_tag!==t)$fatal(1,"response metadata mismatch");
    if(m&&mean!==0)$fatal(1,"RMS mean was not omitted mean=%h",mean);
    if(m)rms_latency=cycle-start_cycle;else ln_latency=cycle-start_cycle;
  end endtask
  initial begin req_v=0;mode=0;tag=0;sum=32'h42800000;sumsq=32'h42800000;invh=32'h3c000000;eps=32'h3727c5ac;
    repeat(3)@(negedge clk);rst_n=1;run(1,16'h7001);run(0,16'h7002);
    $display("MIXED_PRECISION_SCALAR_LATENCY_TB PASS rms_cycles=%0d layernorm_cycles=%0d rms_mean=%h",rms_latency,ln_latency,32'h0);$finish;
  end
  initial begin repeat(1000)@(negedge clk);$fatal(1,"timeout");end
endmodule
