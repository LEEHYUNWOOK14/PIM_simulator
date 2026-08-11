module dram_extended_timing_tb;
  localparam BANKS=5,DW=32;
  logic clk=0,rst_n=0,cv,cr,rv,rr=1,terr;
  logic [2:0] cmd; logic [2:0] bank; logic row,col;
  logic [DW-1:0] wd,rd; logic [DW/8-1:0] wm='1;
  always #5 clk=~clk;
  dram_bank_array_model #(.BANKS(BANKS),.ROWS(2),.COLS(2),.DATA_WIDTH(DW),
    .TRCD_RD(0),.TRCD_WR(0),.TRAS(0),.TRP(0),.TWR(3),.TCCD(2),
    .TRRD(1),.TFAW(10),.TRFC(3),.TWTR(3),.TRTW(3),.READ_LATENCY(1),
    .PIM_READ_PORTS(1)) dut(
    .clk_i(clk),.rst_ni(rst_n),.cmd_valid_i(cv),.cmd_ready_o(cr),.cmd_i(cmd),
    .bank_i(bank),.row_i(row),.col_i(col),.write_data_i(wd),.write_mask_i(wm),
    .read_valid_o(rv),.read_ready_i(rr),.read_data_o(rd),.timing_error_o(terr),
    .pim_read_enable_i('0),.pim_read_bank_i('0),.pim_read_row_i('0),
    .pim_read_col_i('0),.pim_read_valid_o(),.pim_read_data_o());
  task accept(input [2:0] op,input [2:0] b);
    begin @(negedge clk);cmd=op;bank=b;cv=1;do @(posedge clk);while(!cr);@(negedge clk);cv=0;end
  endtask
  task reject_now(input [2:0] op,input [2:0] b,input [127:0] why);
    begin @(negedge clk);cmd=op;bank=b;cv=1;#1;
      if(cr||!terr)$fatal(1,"timing command unexpectedly accepted: %s",why);
      cv=0;end
  endtask
  initial begin
    cv=0;cmd=0;bank=0;row=0;col=0;wd=32'h12345678;
    repeat(3)@(posedge clk);rst_n=1;
    // Four rapid ACTs are allowed; the fifth is blocked by tFAW.
    for(integer b=0;b<4;b++)accept(3'd1,b);
    reject_now(3'd1,4,"tFAW");
    repeat(6)@(posedge clk);accept(3'd1,4);
    // A write blocks PRE until tWR and RD until write-to-read turnaround.
    accept(3'd3,0);
    reject_now(3'd4,0,"tWR");
    reject_now(3'd2,0,"tWTR/tCCD");
    repeat(3)@(posedge clk);accept(3'd2,0);wait(rv);@(posedge clk);
    accept(3'd4,0);
    for(integer b=1;b<BANKS;b++)accept(3'd4,b);
    accept(3'd5,0);
    reject_now(3'd1,0,"tRFC");
    repeat(3)@(posedge clk);accept(3'd1,0);
    $display("AUDIT_FIX PASS: tWR/tCCD/tRRD/tFAW/tRFC/turnaround enforced");$finish;
  end
  initial begin #10000;
    $display("actgap=%0d age3=%0d open=%b pre=%0d",dut.since_last_act_q,
      dut.act_age_q[3],dut.open_valid_q[bank],dut.since_pre_q[bank]);
    $fatal(1,"extended DRAM timing timeout cmd=%0d bank=%0d ready=%b refresh=%b colgap=%0d",
      cmd,bank,cr,dut.refresh_busy_q,dut.since_col_q);end
endmodule
