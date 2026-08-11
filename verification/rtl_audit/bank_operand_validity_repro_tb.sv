module bank_operand_validity_repro_tb;
  localparam DW=32;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic dram_v,dram_r,dram_rv,dram_rr=1,timing,prog_v,prog_r,start;
  logic [2:0] dram_cmd; logic dram_bank; logic [1:0] row,col;
  logic [DW-1:0] wdata,rdata; logic [DW/8-1:0] wmask='1;
  logic [1:0] paddr; logic [31:0] pdata;
  logic reg_v=0,reg_bank=0,reg_block=0,srf_v=0,srf_block=0;
  logic [2:0] reg_idx=0; logic [DW-1:0] reg_data=0,srf_data=0;
  logic result_v,result_r=1,cmd_err,active,done;
  logic [31:0] result_key; logic [2:0] result_dst; logic [3:0] result_idx;
  logic [DW-1:0] result_data;
  bank_side_pim_subsystem #(.BANKS(2),.PIM_BLOCKS(1),.ROWS(4),.COLS(4),
    .DATA_WIDTH(DW),.CRF_DEPTH(4)) dut(
    .clk_i(clk),.rst_ni(rst_n),.dram_cmd_valid_i(dram_v),.dram_cmd_ready_o(dram_r),
    .dram_cmd_i(dram_cmd),.dram_bank_i(dram_bank),.dram_row_i(row),.dram_col_i(col),
    .dram_write_data_i(wdata),.dram_write_mask_i(wmask),.dram_read_valid_o(dram_rv),
    .dram_read_ready_i(dram_rr),.dram_read_data_o(rdata),.dram_timing_error_o(timing),
    .crf_program_valid_i(prog_v),.crf_program_ready_o(prog_r),.crf_program_addr_i(paddr),
    .crf_program_data_i(pdata),.crf_start_i(start),.context_key_i(32'h55),
    .precision_i(2'd0),.pim_row_i(row),.pim_col_i(col),
    .register_write_valid_i(reg_v),.register_write_block_i(reg_block),
    .register_write_bank_i(reg_bank),.register_write_index_i(reg_idx),
    .register_write_data_i(reg_data),.srf_write_valid_i(srf_v),
    .srf_write_block_i(srf_block),.srf_write_data_i(srf_data),
    .result_valid_o(result_v),.result_ready_i(result_r),.result_key_o(result_key),
    .result_destination_o(result_dst),.result_index_o(result_idx),.result_data_o(result_data),
    .command_error_o(cmd_err),.crf_active_o(active),.crf_done_o(done));
  task program_word(input [1:0] a,input [31:0] d);
    begin @(negedge clk);paddr=a;pdata=d;prog_v=1;@(posedge clk);@(negedge clk);prog_v=0;end
  endtask
  initial begin
    dram_v=0;dram_cmd=0;dram_bank=0;row=0;col=0;wdata=0;prog_v=0;start=0;
    repeat(3) @(posedge clk); rst_n=1;
    // ADD A_OUT = EVEN_BANK + ODD_BANK. Neither bank has received ACT.
    program_word(0,{4'h1,3'd0,3'd2,3'd3,19'd0});
    program_word(1,32'hf0000000);
    @(negedge clk);start=1;@(posedge clk);@(negedge clk);start=0;
    repeat(8) begin
      @(posedge clk);
      if(result_v)$fatal(1,"bank command issued without valid bank operands");
    end
    $display("AUDIT_FIX PASS: bank command remained blocked while referenced operands were invalid");
    $finish;
  end
endmodule
