`timescale 1ns/1ps
module b1_hierarchical_tb;
  localparam int CHANNELS=1, BANKS=2, PIM_BLOCKS=1, PCUS=1;
  localparam int ROWS=1, COLS=1, DATA_WIDTH=32, KEY_WIDTH=32, TAG_WIDTH=64;
  localparam int CRF_DEPTH=2, WEIGHT_BUFFER_BYTES=16;
  logic clk_i=0, rst_ni=0;
  always #5 clk_i=~clk_i;

  logic [CHANNELS-1:0] dram_cmd_valid_i,dram_cmd_ready_o,dram_read_valid_o,dram_read_ready_i,dram_timing_error_o;
  logic [CHANNELS-1:0][2:0] dram_cmd_i;
  logic [CHANNELS-1:0][0:0] dram_bank_i,dram_row_i,dram_col_i;
  logic [CHANNELS-1:0][DATA_WIDTH-1:0] dram_write_data_i,dram_read_data_o;
  logic [CHANNELS-1:0][DATA_WIDTH/8-1:0] dram_write_mask_i;
  logic [CHANNELS-1:0] crf_program_valid_i,crf_program_ready_o,crf_start_i;
  logic [CHANNELS-1:0][0:0] crf_program_addr_i;
  logic [CHANNELS-1:0][31:0] crf_program_data_i;
  logic [CHANNELS-1:0][KEY_WIDTH-1:0] bank_context_key_i;
  logic [CHANNELS-1:0][1:0] bank_precision_i;
  logic [CHANNELS-1:0][0:0] pim_row_i,pim_col_i,register_write_block_i,srf_write_block_i;
  logic [CHANNELS-1:0] register_write_valid_i,register_write_bank_i,srf_write_valid_i,bank_result_to_logic_i;
  logic [CHANNELS-1:0][2:0] register_write_index_i;
  logic [CHANNELS-1:0][DATA_WIDTH-1:0] register_write_data_i,srf_write_data_i;
  logic [CHANNELS-1:0][DATA_WIDTH-1:0] logic_src1_i,logic_src2_i,logic_accum_i;
  logic logic_command_valid_i,logic_command_ready_o;
  logic [0:0] logic_command_channel_i;
  logic [15:0] logic_command_epoch_i,logic_command_ordinal_i;
  logic [31:0] logic_command_signature_i,logic_command_word_i;
  logic [CHANNELS-1:0] logic_command_expected_mask_i;
  logic epoch_begin_valid_i,epoch_begin_ready_o;
  logic [15:0] epoch_begin_id_i;
  logic [CHANNELS-1:0] epoch_expected_mask_i;
  logic epoch_fill_done_valid_i;
  logic [0:0] epoch_fill_done_channel_i;
  logic epoch_execution_done_i,epoch_release_valid_o,epoch_active_o;
  logic [15:0] epoch_release_id_o;
  logic weight_write_valid_i,weight_write_ready_o;
  logic [1:0] weight_write_addr_i,weight_read_addr_i;
  logic [DATA_WIDTH-1:0] weight_write_data_i,weight_response_data_o;
  logic [DATA_WIDTH/8-1:0] weight_write_mask_i;
  logic weight_read_valid_i,weight_read_ready_o,weight_response_valid_o,weight_response_ready_i;
  logic weight_context_commit_i;
  logic [15:0] weight_context_id_i;
  logic weight_context_valid_o;
  logic [PCUS-1:0] logic_result_valid_o,logic_result_ready_i;
  logic [PCUS-1:0][TAG_WIDTH-1:0] logic_result_tag_o;
  logic [PCUS-1:0][DATA_WIDTH-1:0] logic_result_data_o;
  logic logic_bank_result_valid_o,logic_bank_result_ready_i;
  logic [TAG_WIDTH-1:0] logic_bank_result_tag_o;
  logic [DATA_WIDTH-1:0] logic_bank_result_data_o;
  logic logic_host_result_valid_o,logic_host_result_ready_i;
  logic [TAG_WIDTH-1:0] logic_host_result_tag_o;
  logic [DATA_WIDTH-1:0] logic_host_result_data_o;
  logic [1:0] direct_tsv_valid_o,direct_tsv_ready_i;
  logic [1:0][KEY_WIDTH-1:0] direct_tsv_key_o;
  logic [1:0][DATA_WIDTH-1:0] direct_tsv_data_o;
  logic [1:0][0:0] direct_tsv_channel_o;
  logic normalization_begin_valid_i,normalization_begin_ready_o,normalization_begin_rms_norm_i;
  logic [TAG_WIDTH-1:0] normalization_begin_tag_i;
  logic [BANKS-1:0] normalization_expected_bank_mask_i;
  logic [15:0] normalization_inv_hidden_i,normalization_epsilon_i;
  logic normalization_partial_valid_i,normalization_partial_ready_o;
  logic [0:0] normalization_partial_bank_i;
  logic [TAG_WIDTH-1:0] normalization_partial_tag_i;
  logic [15:0] normalization_partial_sum_i,normalization_partial_sumsq_i;
  logic normalization_broadcast_valid_o,normalization_broadcast_ready_i,normalization_broadcast_rms_norm_o;
  logic [TAG_WIDTH-1:0] normalization_broadcast_tag_o;
  logic [15:0] normalization_broadcast_mean_o,normalization_broadcast_inv_std_o;
  logic normalization_variance_clamped_o,protocol_error_o;

  integer cycles=0;
  always @(posedge clk_i) begin
    cycles <= cycles+1;
    if (rst_ni) begin
      if (normalization_begin_ready_o || normalization_partial_ready_o ||
          normalization_broadcast_valid_o || normalization_broadcast_rms_norm_o ||
          normalization_broadcast_tag_o != 0 || normalization_broadcast_mean_o != 0 ||
          normalization_broadcast_inv_std_o != 0 || normalization_variance_clamped_o)
        $fatal(1,"normalization sideband was not idle in B1");
      if (protocol_error_o) $fatal(1,"protocol_error_o asserted");
    end
  end

  full_pim_system_top #(
    .CHANNELS(CHANNELS),.BANKS(BANKS),.PIM_BLOCKS(PIM_BLOCKS),.PCUS(PCUS),
    .ROWS(ROWS),.COLS(COLS),.DATA_WIDTH(DATA_WIDTH),.KEY_WIDTH(KEY_WIDTH),
    .TAG_WIDTH(TAG_WIDTH),.CRF_DEPTH(CRF_DEPTH),.WEIGHT_BUFFER_BYTES(WEIGHT_BUFFER_BYTES),
    .ENABLE_LOGIC_DIE_PCU(1'b1),.ENABLE_NORMALIZATION_ENGINE(1'b0)) dut (.*);

  task automatic pulse(input integer kind);
    begin
      @(negedge clk_i);
      case(kind)
        0: weight_write_valid_i=1;
        1: weight_read_valid_i=1;
        2: weight_context_commit_i=1;
        3: epoch_begin_valid_i=1;
        4: epoch_fill_done_valid_i=1;
        5: register_write_valid_i[0]=1;
        6: crf_start_i[0]=1;
        7: epoch_execution_done_i=1;
      endcase
      @(posedge clk_i); @(negedge clk_i);
      case(kind)
        0: weight_write_valid_i=0;
        1: weight_read_valid_i=0;
        2: weight_context_commit_i=0;
        3: epoch_begin_valid_i=0;
        4: epoch_fill_done_valid_i=0;
        5: register_write_valid_i[0]=0;
        6: crf_start_i[0]=0;
        7: epoch_execution_done_i=0;
      endcase
    end
  endtask

  task automatic program_crf(input logic addr,input logic [31:0] word);
    begin
      @(negedge clk_i); crf_program_addr_i[0]=addr;crf_program_data_i[0]=word;crf_program_valid_i[0]=1;
      do @(posedge clk_i); while(!crf_program_ready_o[0]);
      @(negedge clk_i);crf_program_valid_i[0]=0;
    end
  endtask

  initial begin
    $dumpfile("b1_logic_die_experiment/artifacts/b1_hierarchical.vcd");
    $dumpvars(0,b1_hierarchical_tb.dut);
    dram_cmd_valid_i=0;dram_cmd_i=0;dram_bank_i=0;dram_row_i=0;dram_col_i=0;
    dram_write_data_i=0;dram_write_mask_i='1;dram_read_ready_i='1;
    crf_program_valid_i=0;crf_program_addr_i=0;crf_program_data_i=0;crf_start_i=0;
    bank_context_key_i[0]=32'h55;bank_precision_i=0;pim_row_i=0;pim_col_i=0;
    register_write_valid_i=0;register_write_block_i=0;register_write_bank_i=0;
    register_write_index_i=0;register_write_data_i=32'h3c003c00;
    srf_write_valid_i=0;srf_write_block_i=0;srf_write_data_i=0;bank_result_to_logic_i='1;
    logic_src1_i=0;logic_src2_i=0;logic_accum_i=0;
    logic_command_valid_i=0;logic_command_channel_i=0;logic_command_epoch_i=7;
    logic_command_ordinal_i=0;logic_command_signature_i=32'hb1000001;
    logic_command_word_i=32'h10000000;logic_command_expected_mask_i='1;
    epoch_begin_valid_i=0;epoch_begin_id_i=7;epoch_expected_mask_i='1;
    epoch_fill_done_valid_i=0;epoch_fill_done_channel_i=0;epoch_execution_done_i=0;
    weight_write_valid_i=0;weight_write_addr_i=0;weight_write_data_i=32'h3c003c00;weight_write_mask_i='1;
    weight_read_valid_i=0;weight_read_addr_i=0;weight_response_ready_i=0;
    weight_context_commit_i=0;weight_context_id_i=7;
    logic_result_ready_i='1;logic_bank_result_ready_i=0;logic_host_result_ready_i=0;
    direct_tsv_ready_i='1;
    normalization_begin_valid_i=1;normalization_begin_rms_norm_i=1;normalization_begin_tag_i='1;
    normalization_expected_bank_mask_i='1;normalization_inv_hidden_i='1;normalization_epsilon_i='1;
    normalization_partial_valid_i=1;normalization_partial_bank_i=0;normalization_partial_tag_i='1;
    normalization_partial_sum_i='1;normalization_partial_sumsq_i='1;normalization_broadcast_ready_i=1;
    repeat(4) @(posedge clk_i); rst_ni=1;

    pulse(0);
    pulse(2); #1;if(!weight_context_valid_o)$fatal(1,"weight context commit failed");
    pulse(1);
    wait(weight_response_valid_o); #1;
    if(weight_response_data_o!==32'h3c003c00)$fatal(1,"shared-buffer read mismatch");
    repeat(3) begin @(posedge clk_i); #1; if(!weight_response_valid_o||weight_response_data_o!==32'h3c003c00)$fatal(1,"shared-buffer backpressure hold failed"); end
    @(negedge clk_i);weight_response_ready_i=1;@(posedge clk_i);@(negedge clk_i);weight_response_ready_i=0;

    pulse(3); #1;if(!epoch_active_o)$fatal(1,"epoch did not become active");
    pulse(4);wait(epoch_release_valid_o);#1;
    if(epoch_release_id_o!=16'd7)$fatal(1,"epoch release/order mismatch");

    pulse(5);
    program_crf(0,{4'h1,3'd0,3'd4,3'd4,19'd0});
    program_crf(1,32'hf0000000);
    @(negedge clk_i);logic_command_valid_i=1;
    do @(posedge clk_i);while(!logic_command_ready_o);
    @(negedge clk_i);logic_command_valid_i=0;
    pulse(6);

    fork
      begin
        wait(logic_result_valid_o[0]);#1;
        if(logic_result_tag_o[0]!==64'h55||logic_result_data_o[0]!==32'h42004200)
          $fatal(1,"logic PCU tag/data mismatch tag=%h data=%h",logic_result_tag_o[0],logic_result_data_o[0]);
      end
      begin
        wait(logic_host_result_valid_o);#1;
        if(logic_bank_result_valid_o)$fatal(1,"router selected both destinations");
        if(logic_host_result_tag_o!==64'h55||logic_host_result_data_o!==32'h42004200)
          $fatal(1,"host result tag/data mismatch");
        repeat(3) begin @(posedge clk_i);#1;if(!logic_host_result_valid_o||logic_host_result_data_o!==32'h42004200)$fatal(1,"result router backpressure hold failed");end
        @(negedge clk_i);logic_host_result_ready_i=1;@(posedge clk_i);@(negedge clk_i);logic_host_result_ready_i=0;
      end
    join
    pulse(7);repeat(2)@(posedge clk_i);#1;
    if(epoch_active_o)$fatal(1,"epoch did not retire");
    if(|direct_tsv_valid_o)$fatal(1,"logic-routed result leaked to direct TSV path");
    $display("B1_HIERARCHICAL_TB PASS cycles=%0d bank_to_logic=1 shared_buffer_bp=3 result_bp=3 tag_order=1 epoch=1 norm_idle=1 protocol_errors=0",cycles);
    $finish;
  end

  initial begin repeat(500)@(posedge clk_i);$fatal(1,"deadlock timeout");end
endmodule
