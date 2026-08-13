module hierarchical_normalization_scalar_return_top_tb;
  localparam int B=4,L=4,E=8;logic clk=0,rst_n=0,cv,cr,cmode;
  logic[15:0]ctag,vectors,cinvh,ceps;logic[B-1:0]mask,bv,br,bsv,bsr,bsmode,berr;
  logic[B*L*16-1:0]bdata;logic[B-1:0][15:0]bstag,bsmean,bsinv;
  logic tmerr,uberr,icerr,aerr,derr,merr,zerr;integer delivered[0:1][0:B-1];integer cycles;
  always#5 clk=~clk;
  always@(posedge clk)if(rst_n)begin cycles<=cycles+1;for(integer b=0;b<B;b++)if(bsv[b]&&bsr[b])begin
    integer row;row=bstag[b]-16'h8000;if(row<0||row>1)$fatal(1,"bad scalar tag");
    if(bsmean[b]!==0||bsinv[b]!==16'h3bfa||!bsmode[b])$fatal(1,"bad scalar payload");
    delivered[row][b]<=delivered[row][b]+1;end end
  initial begin#10000;$fatal(1,"scalar return timeout");end
  hierarchical_normalization_scalar_return_top #(.BANKS(B),.LANES(L),.SCALAR_ENGINES(E),.CONTEXT_ENTRIES(4))dut(.*,
    .clk_i(clk),.rst_ni(rst_n),.config_valid_i(cv),.config_ready_o(cr),.config_rms_norm_i(cmode),
    .config_tag_i(ctag),.config_expected_mask_i(mask),.config_vectors_per_bank_i(vectors),
    .config_inv_hidden_i(cinvh),.config_epsilon_i(ceps),.bank_vector_valid_i(bv),
    .bank_vector_ready_o(br),.bank_vector_data_i(bdata),.bank_scalar_valid_o(bsv),
    .bank_scalar_ready_i(bsr),.bank_scalar_rms_norm_o(bsmode),.bank_scalar_tag_o(bstag),
    .bank_scalar_mean_o(bsmean),.bank_scalar_inv_std_o(bsinv),.bank_protocol_error_o(berr),
    .tag_mismatch_error_o(tmerr),.unexpected_bank_error_o(uberr),.invalid_config_error_o(icerr),
    .allocation_error_o(aerr),.duplicate_tag_error_o(derr),.context_lookup_miss_error_o(merr),
    .zero_target_error_o(zerr));
  task automatic send_config(input[15:0]t,input[B-1:0]m);begin
    @(negedge clk);ctag=t;mask=m;cv=1;while(!cr)@(negedge clk);@(negedge clk);cv=0;
  end endtask
  task automatic send_vector(input integer bank,input integer delay);begin
    repeat(delay)@(negedge clk);bv[bank]=1;
    bdata[bank*L*16 +: L*16]={L{16'h3c00}};
    while(!br[bank])@(negedge clk);@(negedge clk);bv[bank]=0;
  end endtask
  initial begin
    cv=0;cmode=1;ctag=0;mask=0;vectors=1;cinvh=16'h3000;ceps=0;bv=0;bdata='0;bsr=0;cycles=0;
    for(integer r=0;r<2;r++)for(integer b=0;b<B;b++)delivered[r][b]=0;
    repeat(3)@(negedge clk);rst_n=1;
    send_config(16'h8000,4'b0101);fork send_vector(0,0);send_vector(2,2);join
    send_config(16'h8001,4'b1010);fork send_vector(1,1);send_vector(3,0);join
    while(bsv=='0)@(negedge clk);bsr=4'b0001;repeat(2)@(negedge clk);bsr=4'b1111;
    while(delivered[0][0]+delivered[0][2]+delivered[1][1]+delivered[1][3]<4)@(negedge clk);
    @(negedge clk);bsr=0;
    if(delivered[0][0]!=1||delivered[0][2]!=1||delivered[0][1]!=0||delivered[0][3]!=0)$fatal(1,"row0 mask delivery");
    if(delivered[1][1]!=1||delivered[1][3]!=1||delivered[1][0]!=0||delivered[1][2]!=0)$fatal(1,"row1 mask delivery");
    if(|berr||tmerr||uberr||icerr||aerr||derr||merr||zerr)$fatal(1,"unexpected errors");
    $display("HIERARCHICAL_NORMALIZATION_SCALAR_RETURN_TOP_TB PASS rows=2 masks=2 bank_stalls=1 cycles=%0d",cycles);$finish;
  end
endmodule
