module crf_repeat_semantics_tb;
  logic clk=0,rst_n=0,prog_v,prog_r,start,cmd_v,active,done;
  logic [2:0] addr,pc; logic [31:0] pdata,cmd;
  integer total,nop_seen,fill_seen,auto_seen,exit_seen;
  always #5 clk=~clk;
  pim_crf #(.DEPTH(8)) dut(.clk_i(clk),.rst_ni(rst_n),.program_valid_i(prog_v),
    .program_ready_o(prog_r),.program_addr_i(addr),.program_data_i(pdata),
    .start_i(start),.command_ready_i(1'b1),.command_valid_o(cmd_v),
    .command_o(cmd),.active_o(active),.done_o(done),.pc_o(pc));
  task put(input [2:0] a,input [31:0] d);
    begin @(negedge clk);addr=a;pdata=d;prog_v=1;@(posedge clk);@(negedge clk);prog_v=0;end
  endtask
  always @(posedge clk) if(rst_n && cmd_v) begin
    total<=total+1;
    case(cmd[31:28])
      4'h0:nop_seen<=nop_seen+1;
      4'h9:fill_seen<=fill_seen+1;
      4'h1:begin if(!cmd[15])$fatal(1,"AUTO bit lost");auto_seen<=auto_seen+1;end
      4'hf:exit_seen<=exit_seen+1;
    endcase
  end
  initial begin
    prog_v=0;start=0;addr=0;pdata=0;
    total=0;nop_seen=0;fill_seen=0;auto_seen=0;exit_seen=0;
    repeat(3)@(posedge clk);rst_n=1;
    put(0,{4'h0,17'd0,11'd3}); // C++: loopCounter+1 = four executions.
    put(1,32'h90000000);       // C++: FILL always executes eight times.
    put(2,32'h10008000);       // C++: arithmetic AUTO executes eight times.
    put(3,32'hf0000000);
    @(negedge clk);start=1;@(posedge clk);@(negedge clk);start=0;
    repeat(40)begin
      @(posedge clk);
      if(done)begin
        if(total!=21||nop_seen!=4||fill_seen!=8||auto_seen!=8||exit_seen!=1)
          $fatal(1,"repeat mismatch total=%0d nop=%0d fill=%0d auto=%0d exit=%0d",
                 total,nop_seen,fill_seen,auto_seen,exit_seen);
        $display("AUDIT_FIX PASS: CRF NOP/FILL/AUTO repeat semantics match C++");
        $finish;
      end
    end
    $fatal(1,"repeat program timeout pc=%0d total=%0d",pc,total);
  end
endmodule
