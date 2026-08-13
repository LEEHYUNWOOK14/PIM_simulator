module hierarchical_normalization_streaming_top_tb;
  localparam int B=4,L=4,E=8,ROWS=2;
  logic clk=0,rst_n=0,cv,cr,cmode,rv,rr,rmode,clamp,tmerr,uberr,icerr,aerr;
  logic[15:0]ctag,vectors,cinvh,ceps,rtag,mean,inv;
  logic[B-1:0]mask,bv,br,berr;logic[B*L*16-1:0]bdata;
  logic[ROWS-1:0]seen;integer responses,cycles;integer accept_cycle[0:B-1];
  always#5 clk=~clk;always@(posedge clk)if(rst_n)cycles<=cycles+1;
  initial begin#8000;$fatal(1,"streaming top timeout responses=%0d",responses);end
  hierarchical_normalization_streaming_top #(.BANKS(B),.LANES(L),.SCALAR_ENGINES(E))dut(
    .clk_i(clk),.rst_ni(rst_n),.config_valid_i(cv),.config_ready_o(cr),
    .config_rms_norm_i(cmode),.config_tag_i(ctag),.config_expected_mask_i(mask),
    .config_vectors_per_bank_i(vectors),.config_inv_hidden_i(cinvh),.config_epsilon_i(ceps),
    .bank_vector_valid_i(bv),.bank_vector_ready_o(br),.bank_vector_data_i(bdata),
    .response_valid_o(rv),.response_ready_i(rr),.response_rms_norm_o(rmode),
    .response_tag_o(rtag),.response_mean_o(mean),.response_inv_std_o(inv),
    .response_variance_clamped_o(clamp),.bank_protocol_error_o(berr),
    .tag_mismatch_error_o(tmerr),.unexpected_bank_error_o(uberr),
    .invalid_config_error_o(icerr),.allocation_error_o(aerr));
  task automatic send_config(input[15:0]tag);
    begin@(negedge clk);ctag=tag;cv=1;@(posedge clk);while(!cr)@(posedge clk);@(negedge clk);cv=0;end
  endtask
  task automatic send_bank(input integer bank,input integer delay_cycles);
    begin repeat(delay_cycles)@(negedge clk);@(negedge clk);bv[bank]=1;
      bdata[bank*L*16 +: L*16]={L{16'h3c00}};
      @(posedge clk);while(!br[bank])@(posedge clk);accept_cycle[bank]=cycles;
      @(negedge clk);bv[bank]=0;end
  endtask
  task automatic send_skewed_row;
    begin fork send_bank(0,0);send_bank(1,1);send_bank(2,2);send_bank(3,3);join end
  endtask
  initial begin
    cv=0;cmode=1;ctag=0;mask='1;vectors=1;cinvh=16'h2c00;ceps=0;
    bv=0;bdata='0;rr=0;seen=0;responses=0;cycles=0;
    for(integer b=0;b<B;b++)accept_cycle[b]=-1;
    repeat(3)@(negedge clk);rst_n=1;
    send_config(16'h6000);send_skewed_row();
    send_config(16'h6001);send_skewed_row();
    while(!rv)@(negedge clk);repeat(2)begin@(negedge clk);if(!rv)$fatal(1,"stall lost response");end
    begin integer idx;idx=rtag-16'h6000;if(idx<0||idx>=ROWS)$fatal(1,"first tag");seen[idx]=1;responses=1;end
    rr=1;
    while(responses<ROWS)begin@(negedge clk);if(rv)begin integer idx;idx=rtag-16'h6000;
      if(idx<0||idx>=ROWS||seen[idx]||!rmode||mean!==0||inv!==16'h3bfa)$fatal(1,"bad response");
      seen[idx]=1;responses=responses+1;end end
    if(seen!=='1|| |berr||tmerr||uberr||icerr||aerr)$fatal(1,"coverage/error flags");
    $display("HIERARCHICAL_NORMALIZATION_STREAMING_TOP_TB PASS rows=%0d raw_vectors=%0d skew_span=%0d cycles=%0d",
      ROWS,ROWS*B,accept_cycle[3]-accept_cycle[0],cycles);
    $finish;
  end
endmodule
