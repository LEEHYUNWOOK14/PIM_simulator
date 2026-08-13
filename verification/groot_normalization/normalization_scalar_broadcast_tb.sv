module normalization_scalar_broadcast_tb;
  localparam int B=4;
  logic clk=0,rst_n=0,iv,ir,mode,zerr;
  logic[B-1:0]mask,bv,br,bmode;
  logic[15:0]tag,mean,inv;
  logic[B-1:0][15:0]btag,bmean,binv;
  integer count[0:B-1];integer cycles;
  always#5 clk=~clk;
  always@(posedge clk)if(rst_n)begin
    cycles<=cycles+1;
    for(integer b=0;b<B;b++)if(bv[b]&&br[b])count[b]<=count[b]+1;
  end
  initial begin#3000;$fatal(1,"broadcast timeout");end
  normalization_scalar_broadcast #(.BANKS(B))dut(.*,
    .clk_i(clk),.rst_ni(rst_n),.input_valid_i(iv),.input_ready_o(ir),
    .target_mask_i(mask),.rms_norm_i(mode),.tag_i(tag),.mean_i(mean),.inv_std_i(inv),
    .bank_valid_o(bv),.bank_ready_i(br),.bank_rms_norm_o(bmode),.bank_tag_o(btag),
    .bank_mean_o(bmean),.bank_inv_std_o(binv),.zero_target_error_o(zerr));
  task automatic send(input[B-1:0]m,input[15:0]t);
    begin @(negedge clk);mask=m;tag=t;iv=1;while(!ir)@(negedge clk);@(negedge clk);iv=0;end
  endtask
  initial begin
    iv=0;mask=0;mode=1;tag=0;mean=16'h1111;inv=16'h3bfa;br=0;cycles=0;
    for(integer b=0;b<B;b++)count[b]=0;
    repeat(3)@(negedge clk);rst_n=1;
    send(4'b1101,16'h6000);
    repeat(2)begin@(negedge clk);if(ir||bv!==4'b1101)$fatal(1,"source/pending protocol");end
    br=4'b0001;@(negedge clk);br=0;
    if(bv!==4'b1100)$fatal(1,"bank0 not retired");
    repeat(2)begin
      @(negedge clk);
      if(btag[2]!==16'h6000||bmean[2]!==16'h1111||binv[2]!==16'h3bfa||!bmode[2])$fatal(1,"payload changed under stall");
    end
    br=4'b0100;@(negedge clk);br=0;if(bv!==4'b1000)$fatal(1,"bank2 not retired");
    repeat(3)@(negedge clk);br=4'b1000;@(negedge clk);br=0;
    @(negedge clk);if(!ir||bv!=='0)$fatal(1,"broadcast did not complete");
    for(integer b=0;b<B;b++)if(count[b]!=(b==0||b==2||b==3))$fatal(1,"delivery count bank=%0d count=%0d",b,count[b]);
    send('0,16'h6001);@(negedge clk);if(!zerr||bv!=='0)$fatal(1,"zero mask handling");
    $display("NORMALIZATION_SCALAR_BROADCAST_TB PASS banks=4 independent_stalls=1 exactly_once=1 cycles=%0d",cycles);
    $finish;
  end
endmodule
