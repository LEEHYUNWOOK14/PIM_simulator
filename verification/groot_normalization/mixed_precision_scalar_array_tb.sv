module mixed_precision_scalar_array_tb#(parameter int ENGINES=4);
  localparam int N=ENGINES*3;logic clk=0,rst_n=0;always#5 clk=~clk;
  logic req_v,req_ready,resp_v,resp_ready=1,mode,clamped;logic[15:0]tag,resp_tag;logic[31:0]sum,sumsq,invh,eps,mean,inv;
  logic ref_req,ref_ready,ref_v;logic[31:0]ref_mean,ref_inv;logic[N-1:0]seen,accepted_seen;integer sent=0,accepted=0,received=0,errors=0;
  mixed_precision_scalar_engine_array #(.ENGINES(ENGINES))dut(.clk_i(clk),.rst_ni(rst_n),.request_valid_i(req_v),.request_ready_o(req_ready),.request_rms_norm_i(mode),.request_tag_i(tag),.sum_i(sum),.sumsq_i(sumsq),.inv_hidden_i(invh),.epsilon_i(eps),.response_valid_o(resp_v),.response_ready_i(resp_ready),.response_rms_norm_o(),.response_tag_o(resp_tag),.mean_o(mean),.inv_std_o(inv),.variance_clamped_o(clamped));
  mixed_precision_scalar_nr2_pipe refdut(.clk_i(clk),.rst_ni(rst_n),.request_valid_i(ref_req),.request_ready_o(ref_ready),.request_rms_norm_i(1'b0),.request_tag_i(16'h7000),.sum_i(sum),.sumsq_i(sumsq),.inv_hidden_i(invh),.epsilon_i(eps),.response_valid_o(ref_v),.response_ready_i(1'b1),.response_rms_norm_o(),.response_tag_o(),.mean_o(ref_mean),.inv_std_o(ref_inv),.variance_clamped_o());
  always@(posedge clk)if(rst_n&&resp_v&&resp_ready)begin integer index;index=resp_tag-16'h7100;if(index<0||index>=N||seen[index])begin $display("bad/duplicate tag=%h",resp_tag);errors++;end else seen[index]=1;if(mean!==ref_mean||inv!==ref_inv||clamped)begin $display("result mismatch tag=%h mean=%h/%h inv=%h/%h",resp_tag,mean,ref_mean,inv,ref_inv);errors++;end received++;end
  always@(posedge clk)if(rst_n&&req_v&&req_ready)begin integer index;index=tag-16'h7100;if(index>=0&&index<N)accepted_seen[index]=1;accepted++;end
  initial begin wait(received==2);@(negedge clk);resp_ready=0;repeat(10)@(negedge clk);resp_ready=1;end
  initial begin req_v=0;ref_req=0;mode=0;tag=0;sum=32'h42000000;sumsq=32'h42c80000;invh=32'h3c800000;eps=32'h3727c5ac;seen=0;accepted_seen=0;repeat(3)@(negedge clk);rst_n=1;
    while(!ref_ready)@(negedge clk);ref_req=1;@(negedge clk);ref_req=0;while(!ref_v)@(negedge clk);@(negedge clk);
    for(integer i=0;i<N;i++)begin @(negedge clk);tag=16'h7100+i;req_v=1;@(posedge clk);while(!req_ready)@(posedge clk);@(negedge clk);req_v=0;sent++;end
    while(received<N)@(negedge clk);repeat(2)@(negedge clk);if(errors||seen!={N{1'b1}})$fatal(1,"SCALAR_ARRAY_TB FAIL engines=%0d errors=%0d seen=%h",ENGINES,errors,seen);
    $display("SCALAR_ARRAY_TB PASS engines=%0d requests=%0d stall=10",ENGINES,N);$finish;end
  initial begin repeat(10000)@(negedge clk);$fatal(1,"timeout engines=%0d sent=%0d accepted=%0d received=%0d accepted_seen=%h seen=%h req_ready=%b engine_req_ready=%b engine_resp_valid=%b",ENGINES,sent,accepted,received,accepted_seen,seen,req_ready,dut.engine_req_ready,dut.engine_resp_valid);end
endmodule
