module hierarchical_normalization_bank_core_top_tb;
  localparam int B=4,L=4,E=8,DW=256;logic clk=0,rst_n=0,cv,cr,mode;
  logic[15:0]tag,vectors,invh,eps;logic[B-1:0]mask,bv,br,av,gwv,rv,rr,done,cerr,berr;
  logic[B*L*16-1:0]bdata;logic[B*DW-1:0]adata,gwdata,rdata;logic[B*3-1:0]gwidx,rdst;
  logic[B*32-1:0]rkey;logic[B*4-1:0]ridx;logic tmerr,uberr,icerr,aerr,derr,merr,zerr;
  logic completion_valid,completion_ready;logic[15:0]completion_tag;
  logic final_unknown_error,duplicate_final_error;
  integer finals[0:1][0:B-1],all_results,cycles,result_fires,completion_count;
  logic[15:0]completion_order[0:1];
  always @* begin result_fires=0;for(integer b=0;b<B;b++)result_fires=result_fires+(rv[b]&&rr[b]);end
  always#5 clk=~clk;initial begin#20000;$display("TIMEOUT cv=%b cr=%b bv=%b br=%b rv=%b rr=%b finals=%0d,%0d,%0d,%0d completions=%0d cvalid=%b ctag=%h errors=%b%b%b%b%b%b%b%b%b",
    cv,cr,bv,br,rv,rr,finals[0][0],finals[0][2],finals[1][1],finals[1][3],completion_count,
    completion_valid,completion_tag,tmerr,uberr,icerr,aerr,derr,merr,zerr,final_unknown_error,duplicate_final_error);
    $display("INTERNAL issue_v=%b issue_r=%b tracker_av=%b tracker_ar=%b tracker_valid=%b tracker_complete=%b cmd_v=%b cmd_r=%b srf_v=%b done=%b",
      dut.issue_config_valid,dut.issue_config_ready,dut.tracker_allocate_valid,dut.tracker_allocate_ready,
      dut.u_result_tracker.valid_q,dut.u_result_tracker.complete_q,dut.cmd_v,dut.cmd_r,dut.srf_v,done);
    $fatal(1,"bank core e2e timeout");end
  always@(posedge clk)if(rst_n)begin cycles<=cycles+1;all_results<=all_results+result_fires;
  for(integer b=0;b<B;b++)if(rv[b]&&rr[b])begin
    integer row;row=rkey[b*32+:16]-16'hb000;
    if(rdst[b*3+:3]==3'd1)begin finals[row][b]<=finals[row][b]+1;
      for(integer l=0;l<DW/16;l++)begin
        if(row==0&&rdata[b*DW+l*16+:16]!==16'h3ffa)$fatal(1,"rms final bank=%0d lane=%0d got=%h",b,l,rdata[b*DW+l*16+:16]);
        if(row==1&&rdata[b*DW+l*16+:16]!==16'h3800)$fatal(1,"layer final bank=%0d lane=%0d got=%h",b,l,rdata[b*DW+l*16+:16]);
      end
    end
  end
  if(completion_valid&&completion_ready)begin
    if(completion_count>=2)$fatal(1,"unexpected extra completion tag=%h",completion_tag);
    completion_order[completion_count]<=completion_tag;
    if(completion_tag==16'hb000&&finals[0][0]+finals[0][2]!=2)$fatal(1,"row0 completed before final write-back");
    if(completion_tag==16'hb001&&finals[1][1]+finals[1][3]!=2)$fatal(1,"row1 completed before final write-back");
    completion_count<=completion_count+1;
  end end
  hierarchical_normalization_bank_core_top #(.BANKS(B),.LANES(L),.SCALAR_ENGINES(E),
    .CONTEXT_ENTRIES(4),.RESULT_TRACKER_ENTRIES(2),.DATA_WIDTH(DW))dut(.clk_i(clk),.rst_ni(rst_n),.config_valid_i(cv),
    .config_ready_o(cr),.config_rms_norm_i(mode),.config_tag_i(tag),.config_expected_mask_i(mask),
    .config_vectors_per_bank_i(vectors),.config_inv_hidden_i(invh),.config_epsilon_i(eps),
    .bank_vector_valid_i(bv),.bank_vector_ready_o(br),.bank_vector_data_i(bdata),
    .activation_data_i(adata),.activation_valid_i(av),.grf_write_valid_i(gwv),
    .grf_write_index_i(gwidx),.grf_write_data_i(gwdata),.gamma_grf_b_index_i(3'd0),
    .beta_grf_b_index_i(3'd1),.result_valid_o(rv),.result_ready_i(rr),.result_key_o(rkey),
    .result_destination_o(rdst),.result_index_o(ridx),.result_data_o(rdata),
    .transaction_done_o(done),.command_error_o(cerr),.bank_protocol_error_o(berr),
    .row_completion_valid_o(completion_valid),.row_completion_ready_i(completion_ready),
    .row_completion_tag_o(completion_tag),
    .tag_mismatch_error_o(tmerr),.unexpected_bank_error_o(uberr),.invalid_config_error_o(icerr),
    .allocation_error_o(aerr),.duplicate_tag_error_o(derr),.context_lookup_miss_error_o(merr),
    .zero_target_error_o(zerr),.final_result_unknown_tag_error_o(final_unknown_error),
    .duplicate_final_result_error_o(duplicate_final_error));
  task automatic preload(input[2:0]idx,input[15:0]value);begin @(negedge clk);gwv='1;
    for(integer b=0;b<B;b++)begin gwidx[b*3+:3]=idx;for(integer l=0;l<DW/16;l++)gwdata[b*DW+l*16+:16]=value;end
    @(negedge clk);gwv=0;end endtask
  task automatic send_config(input[15:0]t,input[B-1:0]m,input logic rms,input[15:0]epsilon);begin
    @(negedge clk);tag=t;mask=m;mode=rms;eps=epsilon;cv=1;#1;while(!cr)@(negedge clk);@(negedge clk);cv=0;end endtask
  task automatic send_bank_vectors(input integer bank,input integer delay);begin repeat(delay)@(negedge clk);
    for(integer v=0;v<4;v++)begin bv[bank]=1;bdata[bank*L*16+:L*16]={L{16'h3c00}};
      while(!br[bank])@(negedge clk);@(negedge clk);bv[bank]=0;end end endtask
  initial begin
    cv=0;mode=0;tag=0;mask=0;vectors=4;invh=16'h2800;eps=0;bv=0;bdata=0;
    adata={B*(DW/16){16'h3c00}};av='1;gwv=0;gwidx=0;gwdata=0;rr='1;completion_ready=1;
    all_results=0;cycles=0;completion_count=0;completion_order[0]=0;completion_order[1]=0;
    for(integer r=0;r<2;r++)for(integer b=0;b<B;b++)finals[r][b]=0;
    repeat(3)@(negedge clk);rst_n=1;preload(0,16'h4000);preload(1,16'h3800);
    rr[2]=0;send_config(16'hb000,4'b0101,1,0);
    fork send_bank_vectors(0,0);send_bank_vectors(2,2);join
    send_config(16'hb001,4'b1010,0,16'h3c00);
    @(negedge clk);tag=16'hb002;mask=4'b0001;mode=1;cv=1;#1;
    repeat(3)begin if(cr)$fatal(1,"tracker full accepted a third row");@(negedge clk);end cv=0;
    fork send_bank_vectors(1,1);send_bank_vectors(3,0);join
    while(completion_count<1)@(negedge clk);
    if(completion_order[0]!==16'hb001)$fatal(1,"expected out-of-order row1 completion got=%h",completion_order[0]);
    if(finals[0][0]!=1||finals[0][2]!=0)$fatal(1,"row0 write-back stall was not preserved");
    while(!rv[2])@(negedge clk);repeat(2)@(negedge clk);
    if(completion_count!=1)$fatal(1,"row0 completed while bank2 write-back stalled");
    rr[2]=1;while(completion_count<2)@(negedge clk);@(negedge clk);
    if(completion_order[1]!==16'hb000)$fatal(1,"expected row0 second completion got=%h",completion_order[1]);
    for(integer b=0;b<B;b++)begin
      if(finals[0][b]!=(b==0||b==2)||finals[1][b]!=(b==1||b==3))$fatal(1,"final mask bank=%0d",b);
    end
    send_config(16'hb010,4'b0001,1,0);@(negedge clk);rst_n=0;cv=0;bv=0;
    repeat(2)@(negedge clk);rst_n=1;tag=16'hb011;mask=4'b0001;#1;
    repeat(2)begin if(completion_valid)$fatal(1,"stale completion after reset");@(negedge clk);end
    if(!cr)$fatal(1,"config path did not recover after reset");
    if(all_results!=12|| |cerr|| |berr||tmerr||uberr||icerr||aerr||derr||merr||zerr||
      final_unknown_error||duplicate_final_error)$fatal(1,"count/error results=%0d",all_results);
    $display("HIERARCHICAL_NORMALIZATION_BANK_CORE_TOP_TB PASS rows=2 active_banks=4 results=12 completions=2 out_of_order=1 tracker_full=1 writeback_stalls=1 active_reset=1 cycles=%0d",cycles);$finish;
  end
endmodule
