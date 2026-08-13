module normalization_bank_result_tracker_tb;
  localparam int B=4,N=4;logic clk=0,rst_n=0,av,ar,cv,cr,derr,uerr,berr,zerr;
  logic[15:0]atag,ctag;logic[B-1:0]amask,bv,br;logic[B*16-1:0]btag;integer completions;
  always#5 clk=~clk;initial begin#4000;$fatal(1,"tracker timeout");end
  normalization_bank_result_tracker #(.BANKS(B),.ENTRIES(N))dut(.clk_i(clk),.rst_ni(rst_n),
    .allocate_valid_i(av),.allocate_ready_o(ar),.allocate_tag_i(atag),.allocate_expected_mask_i(amask),
    .bank_result_valid_i(bv),.bank_result_ready_o(br),.bank_result_tag_i(btag),
    .completion_valid_o(cv),.completion_ready_i(cr),.completion_tag_o(ctag),
    .duplicate_tag_error_o(derr),.unknown_tag_error_o(uerr),.duplicate_bank_error_o(berr),.zero_mask_error_o(zerr));
  task automatic alloc(input[15:0]t,input[B-1:0]m);begin @(negedge clk);atag=t;amask=m;av=1;
    #1;while(!ar)@(negedge clk);@(negedge clk);av=0;end endtask
  task automatic result(input integer bank,input[15:0]t);begin @(negedge clk);btag[bank*16+:16]=t;bv[bank]=1;
    #1;while(!br[bank])@(negedge clk);@(negedge clk);bv[bank]=0;end endtask
  initial begin
    av=0;atag=0;amask=0;bv=0;btag=0;cr=0;completions=0;repeat(3)@(negedge clk);rst_n=1;
    alloc(16'hc000,4'b0101);alloc(16'hc001,4'b1010);
    fork result(2,16'hc000);result(1,16'hc001);join
    result(0,16'hc000);while(!cv)@(negedge clk);if(ctag!==16'hc000)$fatal(1,"first completion");
    repeat(2)begin@(negedge clk);if(!cv||ctag!==16'hc000)$fatal(1,"completion stall");end
    cr=1;@(negedge clk);cr=0;completions=1;
    result(3,16'hc001);while(!cv)@(negedge clk);if(ctag!==16'hc001)$fatal(1,"second completion");
    cr=1;@(negedge clk);cr=0;completions=2;
    @(negedge clk);btag[0+:16]=16'hdead;bv[0]=1;@(negedge clk);bv[0]=0;if(!uerr)$fatal(1,"unknown tag");
    alloc(16'hc010,4'b0001);result(0,16'hc010);@(negedge clk);btag[0+:16]=16'hc010;bv[0]=1;
    @(negedge clk);bv[0]=0;if(!berr)$fatal(1,"duplicate bank");
    @(negedge clk);atag=16'hc010;amask=1;av=1;@(negedge clk);av=0;if(!derr)$fatal(1,"duplicate tag");
    @(negedge clk);atag=16'hc020;amask=0;av=1;@(negedge clk);av=0;if(!zerr)$fatal(1,"zero mask");
    alloc(16'hc011,4'b0010);alloc(16'hc012,4'b0100);alloc(16'hc013,4'b1000);
    @(negedge clk);atag=16'hc014;amask=1;av=1;#1;
    repeat(2)begin if(ar)$fatal(1,"full tracker reported ready");@(negedge clk);end av=0;
    rst_n=0;repeat(2)@(negedge clk);rst_n=1;@(negedge clk);
    if(cv||derr||uerr||berr||zerr)$fatal(1,"reset did not clear active state/errors");
    alloc(16'hc100,4'b0101);result(0,16'hc100);
    repeat(2)begin @(negedge clk);if(cv)$fatal(1,"missing bank caused early completion");end
    result(2,16'hc100);while(!cv)@(negedge clk);if(ctag!==16'hc100)$fatal(1,"post-reset completion");
    cr=1;@(negedge clk);cr=0;completions=3;
    alloc(16'hc101,4'b0010);result(1,16'hc101);while(!cv)@(negedge clk);
    if(ctag!==16'hc101)$fatal(1,"entry reuse completion");cr=1;@(negedge clk);cr=0;completions=4;
    if(completions!=4)$fatal(1,"completion count");
    $display("NORMALIZATION_BANK_RESULT_TRACKER_TB PASS entries=4 completions=4 out_of_order=1 completion_stall=1 full=1 active_reset=1 missing_wait=1 reuse=1 errors=4");$finish;
  end
endmodule
