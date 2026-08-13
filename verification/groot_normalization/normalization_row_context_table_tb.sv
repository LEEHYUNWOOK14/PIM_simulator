module normalization_row_context_table_tb;
  localparam int B=4,N=4;logic clk=0,rst_n=0,av,ar,lv,lh,lc,derr,merr;
  logic[15:0]atag,ltag;logic[B-1:0]amask,lmask;
  always#5 clk=~clk;initial begin#2000;$fatal(1,"context timeout");end
  normalization_row_context_table #(.BANKS(B),.ENTRIES(N))dut(
    .clk_i(clk),.rst_ni(rst_n),.allocate_valid_i(av),.allocate_ready_o(ar),
    .allocate_tag_i(atag),.allocate_target_mask_i(amask),.lookup_valid_i(lv),
    .lookup_hit_o(lh),.lookup_tag_i(ltag),.lookup_target_mask_o(lmask),
    .lookup_consume_i(lc),.duplicate_tag_error_o(derr),.lookup_miss_error_o(merr));
  task automatic alloc(input[15:0]t,input[B-1:0]m);begin
    @(negedge clk);atag=t;amask=m;av=1;@(posedge clk);if(!ar)$fatal(1,"allocation rejected");@(negedge clk);av=0;
  end endtask
  task automatic consume(input[15:0]t,input[B-1:0]m);begin
    @(negedge clk);ltag=t;lv=1;lc=0;#1;if(!lh||lmask!==m)$fatal(1,"lookup mismatch tag=%h",t);
    @(negedge clk);lc=1;@(negedge clk);lv=0;lc=0;
  end endtask
  initial begin
    av=0;lv=0;lc=0;atag=0;amask=0;ltag=0;repeat(3)@(negedge clk);rst_n=1;
    alloc(16'h7000,4'b0011);alloc(16'h7001,4'b1100);alloc(16'h7002,4'b1010);
    consume(16'h7002,4'b1010);consume(16'h7000,4'b0011);consume(16'h7001,4'b1100);
    @(negedge clk);ltag=16'h7bad;lv=1;@(negedge clk);lv=0;if(!merr)$fatal(1,"miss error absent");
    alloc(16'h7010,4'b1111);@(negedge clk);atag=16'h7010;av=1;@(negedge clk);if(ar)$fatal(1,"duplicate ready");
    @(negedge clk);av=0;if(!derr)$fatal(1,"duplicate error absent");
    $display("NORMALIZATION_ROW_CONTEXT_TABLE_TB PASS entries=4 out_of_order=1 duplicate=1 miss=1");$finish;
  end
endmodule
