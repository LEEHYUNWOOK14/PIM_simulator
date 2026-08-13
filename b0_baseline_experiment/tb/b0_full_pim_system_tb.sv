`timescale 1ns/1ps
module b0_full_pim_system_tb;
    localparam int CH=1, BANKS=2, PB=1, PCU=1, ROWS=1, COLS=1, DW=32;
    logic clk=0, rst_n=0;
    always #5 clk=~clk;

    logic [CH-1:0] dram_cmd_valid,dram_cmd_ready,dram_read_valid,dram_read_ready,dram_timing_error;
    logic [CH-1:0][2:0] dram_cmd;
    logic [CH-1:0][0:0] dram_bank,dram_row,dram_col;
    logic [CH-1:0][DW-1:0] dram_write_data,dram_read_data;
    logic [CH-1:0][DW/8-1:0] dram_write_mask;
    logic [CH-1:0] crf_program_valid,crf_program_ready,crf_start;
    logic [CH-1:0][0:0] crf_program_addr;
    logic [CH-1:0][31:0] crf_program_data,bank_context_key;
    logic [CH-1:0][1:0] bank_precision;
    logic [CH-1:0][0:0] pim_row,pim_col,register_write_block,srf_write_block;
    logic [CH-1:0] register_write_valid,register_write_bank,srf_write_valid,bank_result_to_logic;
    logic [CH-1:0][2:0] register_write_index;
    logic [CH-1:0][DW-1:0] register_write_data,srf_write_data,logic_src1,logic_src2,logic_accum;

    logic logic_command_valid,logic_command_ready;
    logic [0:0] logic_command_channel;
    logic [15:0] logic_command_epoch,logic_command_ordinal;
    logic [31:0] logic_command_signature,logic_command_word;
    logic [CH-1:0] logic_command_expected_mask;
    logic epoch_begin_valid,epoch_begin_ready,epoch_fill_done_valid,epoch_execution_done;
    logic [15:0] epoch_begin_id,epoch_release_id;
    logic [CH-1:0] epoch_expected_mask;
    logic [0:0] epoch_fill_done_channel;
    logic epoch_release_valid,epoch_active;
    logic weight_write_valid,weight_write_ready,weight_read_valid,weight_read_ready;
    logic [1:0] weight_write_addr,weight_read_addr;
    logic [DW-1:0] weight_write_data,weight_response_data;
    logic [DW/8-1:0] weight_write_mask;
    logic weight_response_valid,weight_response_ready,weight_context_commit,weight_context_valid;
    logic [15:0] weight_context_id;
    logic [PCU-1:0] logic_result_valid,logic_result_ready;
    logic [PCU-1:0][63:0] logic_result_tag;
    logic [PCU-1:0][DW-1:0] logic_result_data;
    logic logic_bank_result_valid,logic_bank_result_ready,logic_host_result_valid,logic_host_result_ready;
    logic [63:0] logic_bank_result_tag,logic_host_result_tag;
    logic [DW-1:0] logic_bank_result_data,logic_host_result_data;
    logic [1:0] direct_tsv_valid,direct_tsv_ready;
    logic [1:0][31:0] direct_tsv_key;
    logic [1:0][DW-1:0] direct_tsv_data;
    logic [1:0][0:0] direct_tsv_channel;

    logic normalization_begin_valid,normalization_begin_ready,normalization_begin_rms_norm;
    logic [63:0] normalization_begin_tag,normalization_partial_tag,normalization_broadcast_tag;
    logic [BANKS-1:0] normalization_expected_bank_mask;
    logic [15:0] normalization_inv_hidden,normalization_epsilon;
    logic normalization_partial_valid,normalization_partial_ready;
    logic [0:0] normalization_partial_bank;
    logic [15:0] normalization_partial_sum,normalization_partial_sumsq;
    logic normalization_broadcast_valid,normalization_broadcast_ready,normalization_broadcast_rms_norm;
    logic [15:0] normalization_broadcast_mean,normalization_broadcast_inv_std;
    logic normalization_variance_clamped,protocol_error;

    integer direct_seen=0;
    integer direct_route0_seen=0;
    integer direct_route1_seen=0;
    logic current_route;

    full_pim_system_top #(
        .CHANNELS(CH),.BANKS(BANKS),.PIM_BLOCKS(PB),.PCUS(PCU),.ROWS(ROWS),.COLS(COLS),
        .DATA_WIDTH(DW),.CRF_DEPTH(2),.WEIGHT_BUFFER_BYTES(16),
        .ENABLE_LOGIC_DIE_PCU(1'b0),.ENABLE_NORMALIZATION_ENGINE(1'b0)
    ) dut (
        .clk_i(clk),.rst_ni(rst_n),
        .dram_cmd_valid_i(dram_cmd_valid),.dram_cmd_ready_o(dram_cmd_ready),.dram_cmd_i(dram_cmd),
        .dram_bank_i(dram_bank),.dram_row_i(dram_row),.dram_col_i(dram_col),
        .dram_write_data_i(dram_write_data),.dram_write_mask_i(dram_write_mask),
        .dram_read_valid_o(dram_read_valid),.dram_read_ready_i(dram_read_ready),
        .dram_read_data_o(dram_read_data),.dram_timing_error_o(dram_timing_error),
        .crf_program_valid_i(crf_program_valid),.crf_program_ready_o(crf_program_ready),
        .crf_program_addr_i(crf_program_addr),.crf_program_data_i(crf_program_data),.crf_start_i(crf_start),
        .bank_context_key_i(bank_context_key),.bank_precision_i(bank_precision),.pim_row_i(pim_row),.pim_col_i(pim_col),
        .register_write_valid_i(register_write_valid),.register_write_block_i(register_write_block),
        .register_write_bank_i(register_write_bank),.register_write_index_i(register_write_index),
        .register_write_data_i(register_write_data),.srf_write_valid_i(srf_write_valid),
        .srf_write_block_i(srf_write_block),.srf_write_data_i(srf_write_data),
        .bank_result_to_logic_i(bank_result_to_logic),.logic_src1_i(logic_src1),.logic_src2_i(logic_src2),
        .logic_accum_i(logic_accum),.logic_command_valid_i(logic_command_valid),
        .logic_command_ready_o(logic_command_ready),.logic_command_channel_i(logic_command_channel),
        .logic_command_epoch_i(logic_command_epoch),.logic_command_ordinal_i(logic_command_ordinal),
        .logic_command_signature_i(logic_command_signature),.logic_command_word_i(logic_command_word),
        .logic_command_expected_mask_i(logic_command_expected_mask),
        .epoch_begin_valid_i(epoch_begin_valid),.epoch_begin_ready_o(epoch_begin_ready),
        .epoch_begin_id_i(epoch_begin_id),.epoch_expected_mask_i(epoch_expected_mask),
        .epoch_fill_done_valid_i(epoch_fill_done_valid),.epoch_fill_done_channel_i(epoch_fill_done_channel),
        .epoch_execution_done_i(epoch_execution_done),.epoch_release_valid_o(epoch_release_valid),
        .epoch_release_id_o(epoch_release_id),.epoch_active_o(epoch_active),
        .weight_write_valid_i(weight_write_valid),.weight_write_ready_o(weight_write_ready),
        .weight_write_addr_i(weight_write_addr),.weight_write_data_i(weight_write_data),
        .weight_write_mask_i(weight_write_mask),.weight_read_valid_i(weight_read_valid),
        .weight_read_ready_o(weight_read_ready),.weight_read_addr_i(weight_read_addr),
        .weight_response_valid_o(weight_response_valid),.weight_response_ready_i(weight_response_ready),
        .weight_response_data_o(weight_response_data),.weight_context_commit_i(weight_context_commit),
        .weight_context_id_i(weight_context_id),.weight_context_valid_o(weight_context_valid),
        .logic_result_valid_o(logic_result_valid),.logic_result_ready_i(logic_result_ready),
        .logic_result_tag_o(logic_result_tag),.logic_result_data_o(logic_result_data),
        .logic_bank_result_valid_o(logic_bank_result_valid),.logic_bank_result_ready_i(logic_bank_result_ready),
        .logic_bank_result_tag_o(logic_bank_result_tag),.logic_bank_result_data_o(logic_bank_result_data),
        .logic_host_result_valid_o(logic_host_result_valid),.logic_host_result_ready_i(logic_host_result_ready),
        .logic_host_result_tag_o(logic_host_result_tag),.logic_host_result_data_o(logic_host_result_data),
        .direct_tsv_valid_o(direct_tsv_valid),.direct_tsv_ready_i(direct_tsv_ready),
        .direct_tsv_key_o(direct_tsv_key),.direct_tsv_data_o(direct_tsv_data),
        .direct_tsv_channel_o(direct_tsv_channel),
        .normalization_begin_valid_i(normalization_begin_valid),.normalization_begin_ready_o(normalization_begin_ready),
        .normalization_begin_rms_norm_i(normalization_begin_rms_norm),.normalization_begin_tag_i(normalization_begin_tag),
        .normalization_expected_bank_mask_i(normalization_expected_bank_mask),
        .normalization_inv_hidden_i(normalization_inv_hidden),.normalization_epsilon_i(normalization_epsilon),
        .normalization_partial_valid_i(normalization_partial_valid),.normalization_partial_ready_o(normalization_partial_ready),
        .normalization_partial_bank_i(normalization_partial_bank),.normalization_partial_tag_i(normalization_partial_tag),
        .normalization_partial_sum_i(normalization_partial_sum),.normalization_partial_sumsq_i(normalization_partial_sumsq),
        .normalization_broadcast_valid_o(normalization_broadcast_valid),
        .normalization_broadcast_ready_i(normalization_broadcast_ready),
        .normalization_broadcast_rms_norm_o(normalization_broadcast_rms_norm),
        .normalization_broadcast_tag_o(normalization_broadcast_tag),
        .normalization_broadcast_mean_o(normalization_broadcast_mean),
        .normalization_broadcast_inv_std_o(normalization_broadcast_inv_std),
        .normalization_variance_clamped_o(normalization_variance_clamped),.protocol_error_o(protocol_error)
    );

    task automatic write_reg(input logic bank_sel,input logic [15:0] value);
        begin
            @(negedge clk); register_write_bank=bank_sel; register_write_data=value;
            register_write_valid=1'b1; @(posedge clk); @(negedge clk); register_write_valid=0;
        end
    endtask
    task automatic program_crf(input logic addr,input logic [31:0] word);
        begin
            @(negedge clk); crf_program_addr=addr; crf_program_data=word;
            crf_program_valid=1'b1; @(posedge clk); @(negedge clk); crf_program_valid=0;
        end
    endtask
    task automatic run_once(input logic requested_logic_route,input logic [31:0] key);
        integer before_count;
        integer wait_cycles;
        begin
            before_count=direct_seen; current_route=requested_logic_route;
            bank_result_to_logic=requested_logic_route; bank_context_key=key;
            @(negedge clk); crf_start=1'b1; @(posedge clk); @(negedge clk); crf_start=0;
            wait_cycles=0;
            while(direct_seen!=before_count+1 && wait_cycles<100) begin
                @(posedge clk); wait_cycles=wait_cycles+1;
            end
            if(direct_seen!=before_count+1)
                $fatal(1,"B0 direct TSV timeout route=%0d",requested_logic_route);
            repeat(2) @(posedge clk);
        end
    endtask

    always @(posedge clk) if(rst_n) begin
        if(|logic_result_valid || logic_bank_result_valid || logic_host_result_valid)
            $fatal(1,"B0 disabled logic path produced a result");
        if(logic_command_ready || epoch_begin_ready || epoch_release_valid || epoch_active ||
           weight_write_ready || weight_read_ready || weight_response_valid || weight_context_valid)
            $fatal(1,"B0 disabled logic control interface not idle");
        if(normalization_begin_ready || normalization_partial_ready || normalization_broadcast_valid)
            $fatal(1,"B0 disabled normalization interface not idle");
        if(protocol_error) $fatal(1,"B0 protocol_error asserted");
        if(direct_tsv_valid[0] && direct_tsv_ready[0]) begin
            if(direct_tsv_data[0][15:0] !== 16'h4200)
                $fatal(1,"B0 result mismatch direct=%h channel=%h block=%h core=%h src0=%h src1=%h",
                       direct_tsv_data[0],dut.channel_result_data[0],dut.block_result_data[0][0],
                       dut.g_channel[0].u_bank.g_block[0].u_core.result_data_o,
                       dut.g_channel[0].u_bank.g_block[0].u_core.src0_data,
                       dut.g_channel[0].u_bank.g_block[0].u_core.src1_data);
            if(direct_tsv_key[0] !== bank_context_key[0]) $fatal(1,"B0 key mismatch");
            direct_seen <= direct_seen+1;
            if(current_route) direct_route1_seen <= direct_route1_seen+1;
            else direct_route0_seen <= direct_route0_seen+1;
        end
        if(direct_tsv_valid[1]) $fatal(1,"unexpected second TSV lane use");
    end

    initial begin
        $dumpfile("b0_baseline_experiment/results/functional/b0_activity.vcd");
        $dumpvars(0,b0_full_pim_system_tb);
        dram_cmd_valid=0;dram_cmd=0;dram_bank=0;dram_row=0;dram_col=0;dram_write_data=0;
        dram_write_mask='1;dram_read_ready='1;crf_program_valid=0;crf_program_addr=0;
        crf_program_data=0;crf_start=0;bank_context_key=32'h100;bank_precision=0;pim_row=0;pim_col=0;
        register_write_valid=0;register_write_block=0;register_write_bank=0;register_write_index=0;
        register_write_data=0;srf_write_valid=0;srf_write_block=0;srf_write_data=0;
        bank_result_to_logic=0;logic_src1=0;logic_src2=0;logic_accum=0;logic_command_valid=1;
        logic_command_channel=0;logic_command_epoch=0;logic_command_ordinal=0;
        logic_command_signature=0;logic_command_word=0;logic_command_expected_mask='1;
        epoch_begin_valid=1;epoch_begin_id=0;epoch_expected_mask='1;epoch_fill_done_valid=1;
        epoch_fill_done_channel=0;epoch_execution_done=1;weight_write_valid=1;weight_write_addr=0;
        weight_write_data=0;weight_write_mask='1;weight_read_valid=1;weight_read_addr=0;
        weight_response_ready=1;weight_context_commit=1;weight_context_id=0;logic_result_ready='1;
        logic_bank_result_ready=1;logic_host_result_ready=1;direct_tsv_ready='1;
        normalization_begin_valid=1;normalization_begin_rms_norm=0;normalization_begin_tag=0;
        normalization_expected_bank_mask='1;normalization_inv_hidden=16'h3c00;normalization_epsilon=0;
        normalization_partial_valid=1;normalization_partial_bank=0;normalization_partial_tag=0;
        normalization_partial_sum=0;normalization_partial_sumsq=0;normalization_broadcast_ready=1;
        repeat(4) @(posedge clk); rst_n=1;
        write_reg(1'b0,16'h3c00); // FP16 1.0
        write_reg(1'b1,16'h4000); // FP16 2.0
        if(dut.g_channel[0].u_bank.g_block[0].u_core.grf_a[0][15:0]!==16'h3c00 ||
           dut.g_channel[0].u_bank.g_block[0].u_core.grf_b[0][15:0]!==16'h4000)
            $fatal(1,"B0 register preload mismatch A=%h B=%h",
                   dut.g_channel[0].u_bank.g_block[0].u_core.grf_a[0][15:0],
                   dut.g_channel[0].u_bank.g_block[0].u_core.grf_b[0][15:0]);
        program_crf(1'b0,{4'h1,3'd5,3'd4,3'd5,19'b0}); // ADD GRF_A + GRF_B
        program_crf(1'b1,32'hf0000000);                 // EXIT
        run_once(1'b0,32'h00000100);
        // The ADD destination is GRF_B. Restore the same operand pair so that
        // route=0 and route=1 exercise exactly the same amount of work.
        write_reg(1'b0,16'h3c00);
        write_reg(1'b1,16'h4000);
        run_once(1'b1,32'h00000101); // must bypass because Logic PCU is disabled
        if(direct_seen!=2 || direct_route0_seen!=1 || direct_route1_seen!=1)
            $fatal(1,"B0 counts bad total=%0d route0=%0d route1=%0d",direct_seen,direct_route0_seen,direct_route1_seen);
        if(|dram_timing_error) $fatal(1,"unexpected DRAM timing error");
        $display("B0_FULL_PIM_SYSTEM_TB PASS total=%0d route0=%0d route1_bypassed=%0d",direct_seen,direct_route0_seen,direct_route1_seen);
        $finish;
    end
    initial begin #20000; $fatal(1,"B0 test timeout"); end
endmodule
