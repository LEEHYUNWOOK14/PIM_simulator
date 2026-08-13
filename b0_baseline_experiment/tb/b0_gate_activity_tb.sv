`timescale 1ns/1ps
module b0_gate_activity_tb;
  reg clk_i=0; always #5 clk_i=~clk_i;
  reg rst_ni;
  reg epoch_begin_valid_i,epoch_execution_done_i,epoch_fill_done_valid_i;
  reg logic_bank_result_ready_i,logic_command_valid_i,logic_host_result_ready_i;
  reg normalization_begin_rms_norm_i,normalization_begin_valid_i,normalization_broadcast_ready_i;
  reg normalization_partial_valid_i,weight_context_commit_i,weight_read_valid_i;
  reg weight_response_ready_i,weight_write_valid_i;
  reg [31:0] bank_context_key_i,crf_program_data_i,dram_write_data_i,logic_accum_i;
  reg [1:0] bank_precision_i,direct_tsv_ready_i,normalization_expected_bank_mask_i,weight_read_addr_i,weight_write_addr_i;
  reg bank_result_to_logic_i,crf_program_addr_i,crf_program_valid_i,crf_start_i;
  reg dram_bank_i,dram_cmd_valid_i,dram_col_i,dram_read_ready_i,dram_row_i;
  reg [2:0] dram_cmd_i,register_write_index_i;
  reg [3:0] dram_write_mask_i,weight_write_mask_i;
  reg [15:0] epoch_begin_id_i,logic_command_epoch_i,logic_command_ordinal_i;
  reg epoch_expected_mask_i,epoch_fill_done_channel_i,logic_command_channel_i,logic_command_expected_mask_i;
  reg [31:0] logic_command_signature_i,logic_command_word_i,logic_src1_i,logic_src2_i;
  reg [63:0] normalization_begin_tag_i,normalization_partial_tag_i;
  reg [15:0] normalization_epsilon_i,normalization_inv_hidden_i,normalization_partial_sum_i,normalization_partial_sumsq_i;
  reg normalization_partial_bank_i,pim_col_i,pim_row_i,register_write_bank_i,register_write_block_i,register_write_valid_i;
  reg srf_write_block_i,srf_write_valid_i;
  reg [31:0] register_write_data_i,srf_write_data_i,weight_write_data_i;
  reg [15:0] weight_context_id_i;
  reg logic_result_ready_i;

  wire epoch_active_o,epoch_begin_ready_o,epoch_release_valid_o,logic_bank_result_valid_o;
  wire logic_command_ready_o,logic_host_result_valid_o,normalization_begin_ready_o;
  wire normalization_broadcast_rms_norm_o,normalization_broadcast_valid_o,normalization_partial_ready_o;
  wire normalization_variance_clamped_o,protocol_error_o,weight_context_valid_o,weight_read_ready_o;
  wire weight_response_valid_o,weight_write_ready_o;
  wire crf_program_ready_o,dram_cmd_ready_o,dram_read_valid_o,dram_timing_error_o;
  wire [1:0] direct_tsv_channel_o,direct_tsv_valid_o;
  wire [63:0] direct_tsv_data_o,direct_tsv_key_o;
  wire [31:0] dram_read_data_o,logic_bank_result_data_o,logic_host_result_data_o,logic_result_data_o,weight_response_data_o;
  wire [15:0] epoch_release_id_o,normalization_broadcast_inv_std_o,normalization_broadcast_mean_o;
  wire [63:0] logic_bank_result_tag_o,logic_host_result_tag_o,logic_result_tag_o,normalization_broadcast_tag_o;
  wire logic_result_valid_o;

  full_pim_system_top dut(.*);

  task write_reg(input bank_sel,input [15:0] value);
    begin @(negedge clk_i); register_write_bank_i=bank_sel; register_write_data_i={16'b0,value}; register_write_valid_i=1;
      @(posedge clk_i); @(negedge clk_i); register_write_valid_i=0; end
  endtask
  task program_crf(input addr,input [31:0] word);
    begin @(negedge clk_i); crf_program_addr_i=addr;crf_program_data_i=word;crf_program_valid_i=1;
      @(posedge clk_i);@(negedge clk_i);crf_program_valid_i=0; end
  endtask
  task run_once(input route,input [31:0] key);
    begin bank_result_to_logic_i=route;bank_context_key_i=key;
      @(negedge clk_i);crf_start_i=1;@(posedge clk_i);@(negedge clk_i);crf_start_i=0;
      repeat(30) @(posedge clk_i); end
  endtask

  initial begin
    $dumpfile("b0_baseline_experiment/results/power/b0_gate_activity.vcd");
    $dumpvars(0,dut);
    rst_ni=0;epoch_begin_valid_i=0;epoch_execution_done_i=0;epoch_fill_done_valid_i=0;
    logic_bank_result_ready_i=1;logic_command_valid_i=0;logic_host_result_ready_i=1;
    normalization_begin_rms_norm_i=0;normalization_begin_valid_i=0;normalization_broadcast_ready_i=1;
    normalization_partial_valid_i=0;weight_context_commit_i=0;weight_read_valid_i=0;
    weight_response_ready_i=1;weight_write_valid_i=0;bank_context_key_i=0;crf_program_data_i=0;
    dram_write_data_i=0;logic_accum_i=0;bank_precision_i=0;direct_tsv_ready_i=2'b11;
    normalization_expected_bank_mask_i=0;weight_read_addr_i=0;weight_write_addr_i=0;
    bank_result_to_logic_i=0;crf_program_addr_i=0;crf_program_valid_i=0;crf_start_i=0;
    dram_bank_i=0;dram_cmd_valid_i=0;dram_col_i=0;dram_read_ready_i=1;dram_row_i=0;
    dram_cmd_i=0;register_write_index_i=0;dram_write_mask_i='1;weight_write_mask_i='1;
    epoch_begin_id_i=0;logic_command_epoch_i=0;logic_command_ordinal_i=0;epoch_expected_mask_i=0;
    epoch_fill_done_channel_i=0;logic_command_channel_i=0;logic_command_expected_mask_i=0;
    logic_command_signature_i=0;logic_command_word_i=0;logic_src1_i=0;logic_src2_i=0;
    normalization_begin_tag_i=0;normalization_partial_tag_i=0;normalization_epsilon_i=0;
    normalization_inv_hidden_i=0;normalization_partial_sum_i=0;normalization_partial_sumsq_i=0;
    normalization_partial_bank_i=0;pim_col_i=0;pim_row_i=0;register_write_bank_i=0;
    register_write_block_i=0;register_write_valid_i=0;srf_write_block_i=0;srf_write_valid_i=0;
    register_write_data_i=0;srf_write_data_i=0;weight_write_data_i=0;weight_context_id_i=0;
    logic_result_ready_i=1;
    repeat(5) @(posedge clk_i); rst_ni=1;
    write_reg(0,16'h3c00);write_reg(1,16'h4000);
    program_crf(0,{4'h1,3'd5,3'd4,3'd5,19'b0});program_crf(1,32'hf0000000);
    run_once(0,32'h100);
    write_reg(0,16'h3c00);write_reg(1,16'h4000);
    run_once(1,32'h101);
    repeat(10) @(posedge clk_i);
    $display("B0_GATE_ACTIVITY_TB PASS");$finish;
  end
  initial begin #20000;$fatal(1,"gate activity timeout");end
endmodule
