module mixed_precision_context_full_wrap_tb;
  localparam int N=4;logic clk=0,rst_n=0,av,ar,amode,lv,lh,lmode,lc,dup,miss;
  logic[15:0]atag,ltag;logic[31:0]ainv,aeps,linv,leps;logic[2:0]occupancy;
  always#5 clk=~clk;
  mixed_precision_row_context_table #(.ENTRIES(N))dut(.clk_i(clk),.rst_ni(rst_n),
    .allocate_valid_i(av),.allocate_ready_o(ar),.allocate_tag_i(atag),.allocate_rms_norm_i(amode),
    .allocate_inv_hidden_i(ainv),.allocate_epsilon_i(aeps),.lookup_valid_i(lv),.lookup_hit_o(lh),
    .lookup_tag_i(ltag),.lookup_rms_norm_o(lmode),.lookup_inv_hidden_o(linv),.lookup_epsilon_o(leps),
    .lookup_consume_i(lc),.duplicate_tag_error_o(dup),.lookup_miss_error_o(miss),.occupancy_o(occupancy));
  task automatic alloc(input logic[15:0]t);begin
    @(negedge clk);atag=t;amode=t[0];ainv={16'h3f00,t};aeps={16'h3700,t};av=1;
    @(posedge clk);if(!ar)$fatal(1,"allocation rejected tag=%h",t);@(negedge clk);av=0;
  end endtask
  task automatic consume(input logic[15:0]t);begin
    @(negedge clk);ltag=t;lv=1;lc=0;#1;if(!lh)$fatal(1,"lookup miss tag=%h",t);
    @(negedge clk);lc=1;@(negedge clk);lv=0;lc=0;
  end endtask
  initial begin av=0;lv=0;lc=0;atag=0;ltag=0;amode=0;ainv=0;aeps=0;
    repeat(3)@(negedge clk);rst_n=1;
    // Four simultaneously live tags cross 16-bit wraparound.
    alloc(16'hfffe);alloc(16'hffff);alloc(16'h0000);alloc(16'h0001);
    if(occupancy!=N||ar)$fatal(1,"full context did not backpressure occupancy=%0d ready=%b",occupancy,ar);
    @(negedge clk);atag=16'h0000;av=1;@(posedge clk);@(negedge clk);av=0;
    if(!dup)$fatal(1,"duplicate wrapped tag was not detected");
    consume(16'hffff);alloc(16'h0002);consume(16'h0000);consume(16'hfffe);consume(16'h0001);consume(16'h0002);
    if(occupancy!=0)$fatal(1,"context leak occupancy=%0d",occupancy);
    // Reset while full must synchronously discard every live context.
    alloc(16'h1000);alloc(16'h1001);@(negedge clk);rst_n=0;repeat(2)@(negedge clk);rst_n=1;
    if(occupancy!=0||dup||miss)$fatal(1,"reset did not clear context table");
    $display("MIXED_PRECISION_CONTEXT_FULL_WRAP_TB PASS entries=%0d full_bp=1 tags=fffe,ffff,0000,0001 reset_full=1",N);$finish;
  end
  initial begin repeat(500)@(negedge clk);$fatal(1,"timeout");end
endmodule
