module logic_normalization_barrier_tree_top_tb;
  localparam int B=4,E=8;
  logic clk=0,rst_n=0,cv,cr,cmode,rv,rr,rmode,clamp,tmerr,uberr,icerr,aerr;
  logic[15:0]ctag,rtag,cinvh,ceps,mean,inv;
  logic[B-1:0]cmask,bv,br;logic[B-1:0][15:0]btag,bsum,bsq;
  integer responses,cycles;logic[1:0]seen;logic mismatch_seen;
  always#5 clk=~clk;always@(posedge clk)if(rst_n)begin cycles<=cycles+1;if(tmerr)mismatch_seen<=1;end
  initial begin#5000;$fatal(1,"barrier tree timeout responses=%0d",responses);end
  logic_normalization_barrier_tree_top #(.BANKS(B),.SCALAR_ENGINES(E))dut(
    .clk_i(clk),.rst_ni(rst_n),.config_valid_i(cv),.config_ready_o(cr),
    .config_rms_norm_i(cmode),.config_tag_i(ctag),.config_expected_mask_i(cmask),
    .config_inv_hidden_i(cinvh),.config_epsilon_i(ceps),.bank_valid_i(bv),
    .bank_ready_o(br),.bank_tag_i(btag),.bank_sum_i(bsum),.bank_sumsq_i(bsq),
    .response_valid_o(rv),.response_ready_i(rr),.response_rms_norm_o(rmode),
    .response_tag_o(rtag),.response_mean_o(mean),.response_inv_std_o(inv),
    .response_variance_clamped_o(clamp),.tag_mismatch_error_o(tmerr),
    .unexpected_bank_error_o(uberr),.invalid_config_error_o(icerr),.allocation_error_o(aerr));
  task automatic send_config(input[15:0]tag);
    begin @(negedge clk);ctag=tag;cv=1;@(posedge clk);while(!cr)@(posedge clk);@(negedge clk);cv=0;end
  endtask
  task automatic present_bank(input integer bank,input[15:0]tag);
    begin @(negedge clk);bv[bank]=1;btag[bank]=tag;bsum[bank]=0;bsq[bank]=16'h3c00;end
  endtask
  task automatic wait_row_consume;
    begin @(posedge clk);while(br!=='1)@(posedge clk);@(negedge clk);bv='0;end
  endtask
  initial begin
    cv=0;cmode=1;ctag=0;cmask='1;cinvh=16'h3400;ceps=0;bv=0;btag='0;bsum='0;bsq='0;
    rr=0;responses=0;cycles=0;seen=0;mismatch_seen=0;
    repeat(3)@(negedge clk);rst_n=1;
    send_config(16'h5000);
    present_bank(2,16'h5000);repeat(2)@(negedge clk);
    if(br!==0)$fatal(1,"barrier consumed incomplete row");
    present_bank(0,16'h5000);present_bank(3,16'h5000);present_bank(1,16'h5000);
    wait_row_consume();
    send_config(16'h5001);
    present_bank(0,16'h5001);present_bank(1,16'h5001);
    present_bank(2,16'h5bad);present_bank(3,16'h5001);
    repeat(2)@(negedge clk);if(!tmerr)$fatal(1,"wrong tag not detected");
    btag[2]=16'h5001;wait_row_consume();
    while(!rv)@(negedge clk);repeat(2)begin@(negedge clk);if(!rv)$fatal(1,"stall lost response");end
    begin integer idx;idx=rtag-16'h5000;if(idx<0||idx>1)$fatal(1,"first tag");seen[idx]=1;responses=1;end
    rr=1;
    while(responses<2)begin@(negedge clk);if(rv)begin integer idx;idx=rtag-16'h5000;
      if(idx<0||idx>1||seen[idx]||!rmode||mean!==0||inv!==16'h3bfa)$fatal(1,"bad response");
      seen[idx]=1;responses=responses+1;end end
    if(seen!==2'b11||!mismatch_seen||uberr||icerr||aerr)$fatal(1,"coverage/error flags bad");
    $display("LOGIC_NORMALIZATION_BARRIER_TREE_TOP_TB PASS rows=2 skew_cycles=2 mismatch_detected=1 cycles=%0d",cycles);
    $finish;
  end
endmodule
