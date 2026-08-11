module hierarchical_normalization_datapath_tb;
 localparam B=4;logic clk=0,rst_n=0;always #5 clk=~clk;
 logic bv,br,mode;logic[15:0]tag,invh,eps;logic[B-1:0]mask;
 logic[B-1:0][15:0]counts;logic[B-1:0]rv,rr;logic[B-1:0][15:0]rx;
 logic[B-1:0]av,ar,al,ov,ordy,ol;logic[B-1:0][15:0]atag,ax,ag,ab,otag,odata;
 logic configured,error;logic[15:0]mean,inv;integer bank,index,outputs,mismatches;
 hierarchical_normalization_datapath #(.BANKS(B)) dut(.clk_i(clk),.rst_ni(rst_n),
  .begin_valid_i(bv),.begin_ready_o(br),.rms_norm_i(mode),.tag_i(tag),
  .expected_bank_mask_i(mask),.bank_element_count_i(counts),
  .inv_hidden_i(invh),.epsilon_i(eps),.reduce_element_valid_i(rv),
  .reduce_element_ready_o(rr),.reduce_element_data_i(rx),.apply_element_valid_i(av),
  .apply_element_ready_o(ar),.apply_element_tag_i(atag),.apply_x_i(ax),
  .apply_gamma_i(ag),.apply_beta_i(ab),.apply_last_i(al),.result_valid_o(ov),
  .result_ready_i(ordy),.result_tag_o(otag),.result_data_o(odata),
  .result_last_o(ol),.scalar_configured_o(configured),.scalar_mean_o(mean),
  .scalar_inv_std_o(inv),.protocol_error_o(error));
 task start(input logic rms,input logic[15:0]rowtag);
  begin mode=rms;tag=rowtag;bv=1;do@(posedge clk);while(!br);@(negedge clk);bv=0;end endtask
 task reduce_one(input integer b,input logic[15:0]value);
  begin rv[b]=1;rx[b]=value;do@(posedge clk);while(!rr[b]);@(negedge clk);rv[b]=0;end endtask
 task apply_one(input integer b,input logic[15:0]value,input logic last,input logic[15:0]expected);
  begin av[b]=1;atag[b]=tag;ax[b]=value;ag[b]=16'h3c00;ab[b]=0;al[b]=last;
   do@(posedge clk);while(!ar[b]);@(negedge clk);av[b]=0;
   wait(ov[b]);if(odata[b]!==expected||otag[b]!==tag||ol[b]!==last)begin
    $display("HIER NORM FAIL bank=%0d expected=%h actual=%h",b,expected,odata[b]);mismatches=mismatches+1;end
   ordy[b]=1;@(posedge clk);@(negedge clk);ordy[b]=0;outputs=outputs+1;end endtask
 initial begin
  bv=0;mode=0;tag=0;mask='1;counts={B{16'd4}};invh=16'h2c00;eps=16'h0011;
  rv=0;rx=0;av=0;atag=0;ax=0;ag=0;ab=0;al=0;ordy=0;outputs=0;mismatches=0;
  repeat(3)@(posedge clk);@(negedge clk);rst_n=1;
  // RMSNorm: sixteen values of +1, mean-square=1, expected LUT result 0x3bfa.
  start(1,16'h101);
  for(index=0;index<4;index=index+1)for(bank=0;bank<B;bank=bank+1)
    reduce_one(bank,16'h3c00);
  wait(configured);if(mean!==0||inv!==16'h3bfa)begin
    $display("HIER RMS scalar mismatch mean=%h inv=%h",mean,inv);mismatches=mismatches+1;end
  for(bank=0;bank<B;bank=bank+1)for(index=0;index<4;index=index+1)
    apply_one(bank,16'h3c00,index==3,16'h3bfa);
  // LayerNorm: alternating -1/+1, mean=0 and variance=1.
  start(0,16'h202);
  for(index=0;index<4;index=index+1)for(bank=0;bank<B;bank=bank+1)
    reduce_one(bank,index[0]?16'h3c00:16'hbc00);
  wait(configured);if(mean!==0||inv!==16'h3bfa)begin
    $display("HIER LN scalar mismatch mean=%h inv=%h",mean,inv);mismatches=mismatches+1;end
  for(bank=0;bank<B;bank=bank+1)for(index=0;index<4;index=index+1)
    apply_one(bank,index[0]?16'h3c00:16'hbc00,index==3,index[0]?16'h3bfa:16'hbbfa);
  if(outputs!=32||error||mismatches)begin
    $display("HIER internal local_error=%b apply_error=%b norm_dup=%b norm_context=%b",
      dut.local_error,dut.apply_error,dut.norm_dup,dut.norm_context);
    $fatal(1,"HIERARCHICAL_NORMALIZATION_DATAPATH_TB FAIL outputs=%0d mismatches=%0d protocol=%b",outputs,mismatches,error);end
  $display("HIERARCHICAL_NORMALIZATION_DATAPATH_TB PASS rows=2 banks=4 outputs=32");$finish;
 end
 initial begin #100000;$fatal(1,"hier normalization timeout");end
endmodule
