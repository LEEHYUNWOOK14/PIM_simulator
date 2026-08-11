module invalid_crf_deadlock_repro_tb;
  localparam DW=32;
  logic clk=0,rst_n=0,prog_v,prog_r,start,result_v,cmd_err,active,done;
  logic [1:0] paddr; logic [31:0] pdata;
  integer error_seen;
  always #5 clk=~clk;
  bank_side_pim_subsystem #(.BANKS(2),.PIM_BLOCKS(1),.ROWS(4),.COLS(4),
    .DATA_WIDTH(DW),.CRF_DEPTH(4)) dut(
    .clk_i(clk),.rst_ni(rst_n),.dram_cmd_valid_i(1'b0),.dram_cmd_i('0),
    .dram_bank_i('0),.dram_row_i('0),.dram_col_i('0),.dram_write_data_i('0),
    .dram_write_mask_i('0),.dram_read_ready_i(1'b1),
    .crf_program_valid_i(prog_v),.crf_program_ready_o(prog_r),
    .crf_program_addr_i(paddr),.crf_program_data_i(pdata),.crf_start_i(start),
    .context_key_i(32'h55),.precision_i('0),.pim_row_i('0),.pim_col_i('0),
    .register_write_valid_i(1'b0),.register_write_block_i('0),
    .register_write_bank_i('0),.register_write_index_i('0),
    .register_write_data_i('0),.srf_write_valid_i(1'b0),
    .srf_write_block_i('0),.srf_write_data_i('0),
    .result_valid_o(result_v),.result_ready_i(1'b1),
    .command_error_o(cmd_err),.crf_active_o(active),.crf_done_o(done));
  task put(input [1:0] a,input [31:0] d);
    begin @(negedge clk);paddr=a;pdata=d;prog_v=1;@(posedge clk);@(negedge clk);prog_v=0;end
  endtask
  always @(posedge clk) if(rst_n && cmd_err) error_seen<=error_seen+1;
  initial begin
    prog_v=0;start=0;paddr=0;pdata=0;error_seen=0;
    repeat(3)@(posedge clk);rst_n=1;
    put(0,32'ha0000000); // Reserved opcode must report and retire.
    put(1,32'hf0000000);
    @(negedge clk);start=1;@(posedge clk);@(negedge clk);start=0;
    repeat(12) begin
      @(posedge clk);
      if(done) begin
        if(error_seen==0)$fatal(1,"illegal word retired without visible error");
        if(result_v)$fatal(1,"illegal word committed a result");
        $display("AUDIT_FIX PASS: illegal CRF word reported an error and retired");
        $finish;
      end
    end
    $fatal(1,"illegal CRF word deadlocked active=%b errors=%0d",active,error_seen);
  end
endmodule
