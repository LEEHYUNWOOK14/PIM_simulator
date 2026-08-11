module logic_normalization_dispatcher_top_tb;
    localparam int E=4,B=2,ROWS=4;
    logic clk=0,rst_n=0,bv,br,mode,pv,pr,rv,rr,rmode,clamp,dup,unmatched,eperr;
    logic[15:0]btag,ptag,rtag,invh,eps,psum,psq,mean,inv;
    logic[B-1:0]mask;logic[0:0]pbank;
    logic[ROWS-1:0]seen;integer responses,cycles;
    always#5 clk=~clk;always@(posedge clk)if(rst_n)cycles<=cycles+1;
    initial begin #5000;$fatal(1,"dispatcher test timeout responses=%0d seen=%b",responses,seen);end
    logic_normalization_dispatcher_top #(.ENGINES(E),.BANKS(B))dut(
      .clk_i(clk),.rst_ni(rst_n),.begin_valid_i(bv),.begin_ready_o(br),
      .begin_rms_norm_i(mode),.begin_tag_i(btag),.begin_expected_mask_i(mask),
      .begin_inv_hidden_i(invh),.begin_epsilon_i(eps),.partial_valid_i(pv),
      .partial_ready_o(pr),.partial_tag_i(ptag),.partial_bank_i(pbank),
      .partial_sum_i(psum),.partial_sumsq_i(psq),.response_valid_o(rv),
      .response_ready_i(rr),.response_rms_norm_o(rmode),.response_tag_o(rtag),
      .response_mean_o(mean),.response_inv_std_o(inv),
      .response_variance_clamped_o(clamp),.duplicate_begin_error_o(dup),
      .unmatched_partial_error_o(unmatched),.engine_protocol_error_o(eperr));
    task automatic send_begin(input[15:0]tag);
      begin @(negedge clk);btag=tag;bv=1;while(!br)begin @(negedge clk);
        if(cycles%20==0)$display("wait begin tag=%h active=%b ebr=%b rr=%0d",tag,dut.active_q,dut.e_br,dut.begin_rr_q);end @(negedge clk);bv=0;
        $display("sent begin %h cycle=%0d",tag,cycles);end
    endtask
    task automatic send_partial(input[15:0]tag,input bit bank);
      begin @(negedge clk);ptag=tag;pbank=bank;pv=1;while(!pr)@(negedge clk);@(negedge clk);pv=0;
        $display("sent partial %h bank=%0d cycle=%0d",tag,bank,cycles);end
    endtask
    initial begin
      bv=0;btag=0;mode=1;mask='1;invh=16'h3800;eps=0;pv=0;ptag=0;pbank=0;
      psum=0;psq=16'h3c00;rr=0;seen=0;responses=0;cycles=0;
      repeat(3)@(negedge clk);rst_n=1;
      for(integer row=0;row<ROWS;row++)send_begin(16'h3000+row);
      // Interleave rows across the shared partial stream.
      for(integer bank=0;bank<B;bank++)
        for(integer row=0;row<ROWS;row++)send_partial(16'h3000+row,bank);
      while(!rv)@(negedge clk);
      repeat(2)begin @(negedge clk);if(!rv)$fatal(1,"response lost under stall");end
      begin
        integer index;index=rtag-16'h3000;
        if(index<0||index>=ROWS||!rmode||mean!==0||inv!==16'h3bfa)
          $fatal(1,"bad first stalled response");
        seen[index]=1;responses=1;
      end
      rr=1;
      while(responses<ROWS)begin
        @(negedge clk);if(rv)begin
          integer index;index=rtag-16'h3000;
          if(index<0||index>=ROWS||seen[index])$fatal(1,"bad/duplicate tag %h",rtag);
          if(!rmode||mean!==0||inv!==16'h3bfa)$fatal(1,"bad scalar response");
          seen[index]=1;responses=responses+1;
          $display("dispatcher response tag=%h responses=%0d",rtag,responses);
        end
      end
      if(seen!=='1||dup||unmatched||eperr)$fatal(1,"coverage/error flags bad seen=%b",seen);
      $display("LOGIC_NORMALIZATION_DISPATCHER_TOP_TB PASS rows=%0d responses=%0d cycles=%0d",ROWS,responses,cycles);
      $finish;
    end
endmodule
