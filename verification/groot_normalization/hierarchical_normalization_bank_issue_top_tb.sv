module hierarchical_normalization_bank_issue_top_tb;
  localparam int B=4,L=4,E=8,DW=256;logic clk=0,rst_n=0,cv,cr,mode;
  logic[15:0]tag,vectors,invh,eps;logic[B-1:0]mask,bv,br,srfv,srfr,cmdv,cmdr,done,berr;
  logic[B*L*16-1:0]bdata;logic[B*DW-1:0]srfdata;logic[B*32-1:0]cmd,key;
  logic[B*2-1:0]prec;logic tmerr,uberr,icerr,aerr,derr,merr,zerr;
  integer cmds[0:1][0:B-1],srfs[0:1][0:B-1],dones[0:1][0:B-1];integer cycles;
  always#5 clk=~clk;initial begin#10000;$fatal(1,"bank issue timeout");end
  always@(posedge clk)if(rst_n)begin cycles<=cycles+1;for(integer b=0;b<B;b++)begin
    if(cmdv[b]&&cmdr[b])begin integer r;r=key[b*32+:16]-16'ha000;if(r<0||r>1)$fatal(1,"command tag");cmds[r][b]<=cmds[r][b]+1;end
    if(srfv[b]&&srfr[b])begin integer r;r=key[b*32+:16]-16'ha000;srfs[r][b]<=srfs[r][b]+1;
      if(r==0&&srfdata[b*DW+:16]!==16'h3bfa)$fatal(1,"rms srf");
      if(r==1&&(srfdata[b*DW+:16]!==16'hbc00||srfdata[b*DW+16+:16]!==16'h3bfa))$fatal(1,"layer srf");end
    if(done[b])begin integer r;r=key[b*32+:16]-16'ha000;dones[r][b]<=dones[r][b]+1;end end end
  hierarchical_normalization_bank_issue_top #(.BANKS(B),.LANES(L),.SCALAR_ENGINES(E),
    .CONTEXT_ENTRIES(4),.DATA_WIDTH(DW))dut(.clk_i(clk),.rst_ni(rst_n),.config_valid_i(cv),
    .config_ready_o(cr),.config_rms_norm_i(mode),.config_tag_i(tag),.config_expected_mask_i(mask),
    .config_vectors_per_bank_i(vectors),.config_inv_hidden_i(invh),.config_epsilon_i(eps),
    .bank_vector_valid_i(bv),.bank_vector_ready_o(br),.bank_vector_data_i(bdata),
    .gamma_grf_b_index_i(3'd0),.beta_grf_b_index_i(3'd1),.srf_write_valid_o(srfv),
    .srf_write_ready_i(srfr),.srf_write_data_o(srfdata),.command_valid_o(cmdv),
    .command_ready_i(cmdr),.command_o(cmd),.precision_o(prec),.context_key_o(key),
    .transaction_done_o(done),.bank_protocol_error_o(berr),.tag_mismatch_error_o(tmerr),
    .unexpected_bank_error_o(uberr),.invalid_config_error_o(icerr),.allocation_error_o(aerr),
    .duplicate_tag_error_o(derr),.context_lookup_miss_error_o(merr),.zero_target_error_o(zerr));
  task automatic send_config(input[15:0]t,input[B-1:0]m,input logic rms,input[15:0]epsilon);begin
    @(negedge clk);tag=t;mask=m;mode=rms;eps=epsilon;cv=1;while(!cr)@(negedge clk);@(negedge clk);cv=0;
  end endtask
  task automatic send_vector(input integer bank,input integer delay);begin repeat(delay)@(negedge clk);
    bv[bank]=1;bdata[bank*L*16+:L*16]={L{16'h3c00}};while(!br[bank])@(negedge clk);@(negedge clk);bv[bank]=0;end endtask
  initial begin
    cv=0;mode=0;tag=0;mask=0;vectors=1;invh=16'h3000;eps=0;bv=0;bdata=0;srfr=0;cmdr='1;cycles=0;
    for(integer r=0;r<2;r++)for(integer b=0;b<B;b++)begin cmds[r][b]=0;srfs[r][b]=0;dones[r][b]=0;end
    repeat(3)@(negedge clk);rst_n=1;
    send_config(16'ha000,4'b0101,1,0);fork send_vector(0,0);send_vector(2,2);join
    while(srfv=='0)@(negedge clk);srfr=4'b0001;repeat(2)@(negedge clk);srfr='1;
    while(dones[0][0]+dones[0][2]<2)@(negedge clk);
    send_config(16'ha001,4'b1010,0,16'h3c00);fork send_vector(1,1);send_vector(3,0);join
    while(dones[1][1]+dones[1][3]<2)@(negedge clk);@(negedge clk);
    for(integer b=0;b<B;b++)begin
      if(cmds[0][b]!=(b==0||b==2)*2||srfs[0][b]!=(b==0||b==2)||dones[0][b]!=(b==0||b==2))$fatal(1,"rms bank counts b=%0d",b);
      if(cmds[1][b]!=(b==1||b==3)*4||srfs[1][b]!=(b==1||b==3)||dones[1][b]!=(b==1||b==3))$fatal(1,"layer bank counts b=%0d",b);
    end
    if(|berr||tmerr||uberr||icerr||aerr||derr||merr||zerr)$fatal(1,"unexpected errors");
    $display("HIERARCHICAL_NORMALIZATION_BANK_ISSUE_TOP_TB PASS rows=2 banks=4 commands=12 stalls=1 cycles=%0d",cycles);$finish;
  end
endmodule
