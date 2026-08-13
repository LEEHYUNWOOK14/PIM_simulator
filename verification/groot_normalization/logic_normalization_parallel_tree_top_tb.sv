module logic_normalization_parallel_tree_top_tb;
  localparam int B=4,E=8,ROWS=8;
  logic clk=0,rst_n=0,v,rdy,mode,ov,ordy,omode,clamp,aerr;
  logic[15:0]tag,otag,invh,eps,mean,inv;
  logic[B-1:0]mask;logic[B-1:0][15:0]psum,psq;
  logic[ROWS-1:0]seen;integer accepted,responses,cycle,first_accept,last_accept;
  always#5 clk=~clk;always@(posedge clk)if(rst_n)cycle<=cycle+1;
  initial begin#5000;$fatal(1,"parallel tree timeout accepted=%0d responses=%0d",accepted,responses);end
  logic_normalization_parallel_tree_top #(.BANKS(B),.SCALAR_ENGINES(E))dut(
    .clk_i(clk),.rst_ni(rst_n),.row_valid_i(v),.row_ready_o(rdy),.row_rms_norm_i(mode),
    .row_tag_i(tag),.row_bank_mask_i(mask),.row_partial_sum_i(psum),.row_partial_sumsq_i(psq),
    .row_inv_hidden_i(invh),.row_epsilon_i(eps),.response_valid_o(ov),.response_ready_i(ordy),
    .response_rms_norm_o(omode),.response_tag_o(otag),.response_mean_o(mean),
    .response_inv_std_o(inv),.response_variance_clamped_o(clamp),.allocation_error_o(aerr));
  initial begin
    v=0;mode=1;tag=0;mask='1;psum='0;psq={B{16'h3c00}};invh=16'h3400;eps=0;
    ordy=0;seen=0;accepted=0;responses=0;cycle=0;first_accept=-1;last_accept=-1;
    repeat(3)@(negedge clk);rst_n=1;
    for(integer row=0;row<ROWS;row++)begin
      @(negedge clk);v=1;tag=16'h4000+row;
      @(posedge clk);if(!rdy)$fatal(1,"row %0d not ready",row);
      if(row==0)first_accept=cycle;if(row==ROWS-1)last_accept=cycle;accepted=accepted+1;
    end
    @(negedge clk);v=0;
    while(!ov)@(negedge clk);repeat(3)begin@(negedge clk);if(!ov)$fatal(1,"stall lost response");end
    begin integer idx;idx=otag-16'h4000;if(idx<0||idx>=ROWS)$fatal(1,"first tag");seen[idx]=1;responses=1;end
    ordy=1;
    while(responses<ROWS)begin
      @(negedge clk);if(ov)begin integer idx;idx=otag-16'h4000;
        if(idx<0||idx>=ROWS||seen[idx]||!omode||mean!==0||inv!==16'h3bfa)$fatal(1,"bad response");
        seen[idx]=1;responses=responses+1;
      end
    end
    if(seen!=='1||aerr||last_accept-first_accept!=ROWS-1)$fatal(1,"coverage/II error");
    $display("LOGIC_NORMALIZATION_PARALLEL_TREE_TOP_TB PASS rows=%0d row_II=1 engines=%0d cycles=%0d",ROWS,E,cycle);
    $finish;
  end
endmodule
