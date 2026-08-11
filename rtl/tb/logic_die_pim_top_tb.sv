module logic_die_pim_top_tb;
    localparam CH=4; localparam PCU=2; localparam DW=256; localparam TW=64;
    logic clk=0,rst_n=0,operand_valid,operand_ready,command_valid,command_ready;
    logic [1:0] operand_channel,command_channel,operand_precision;
    logic [TW-1:0] operand_tag;
    logic [DW-1:0] src0,src1,src2,accum;
    logic [15:0] epoch,ordinal; logic [31:0] signature,command_word; logic [CH-1:0] expected;
    logic [PCU-1:0] result_valid,result_ready; logic [PCU-1:0][TW-1:0] result_tag;
    logic [PCU-1:0][DW-1:0] result_data; logic [PCU-1:0][1:0] result_channel;
    logic reduced_valid,reduced_dst,reduction_dup,reduction_ctx;
    logic [TW-1:0] reduced_tag; logic [DW-1:0] reduced_data;
    logic dup_err,ctx_err,operand_err; logic [7:0] occupancy;
    integer results,reduced_results;
    always #5 clk=~clk;
    initial begin #10000; $fatal(1,"global timeout"); end
    logic_die_pim_top #(.CHANNELS(CH),.PCUS(PCU),.DATA_WIDTH(DW),.TAG_WIDTH(TW),
        .REQUIRE_EPOCH(1'b0),.USE_SHARED_WEIGHT(1'b0)) dut(
        .clk_i(clk),.rst_ni(rst_n),.operand_valid_i(operand_valid),.operand_ready_o(operand_ready),
        .operand_channel_i(operand_channel),.operand_tag_i(operand_tag),
        .operand_precision_i(operand_precision),.operand_src0_i(src0),.operand_src1_i(src1),
        .operand_src2_i(src2),.operand_accum_i(accum),.command_valid_i(command_valid),
        .command_ready_o(command_ready),.command_channel_i(command_channel),
        .command_epoch_i(epoch),.command_ordinal_i(ordinal),.command_signature_i(signature),
        .command_word_i(command_word),.command_expected_mask_i(expected),
        .result_valid_o(result_valid),.result_ready_i(result_ready),.result_tag_o(result_tag),
        .result_data_o(result_data),.result_channel_o(result_channel),
        .reduced_result_valid_o(reduced_valid),.reduced_result_ready_i(1'b1),
        .reduced_result_tag_o(reduced_tag),.reduced_result_data_o(reduced_data),
        .reduced_destination_bank_o(reduced_dst),
        .reduction_duplicate_error_o(reduction_dup),
        .reduction_context_error_o(reduction_ctx),
        .coalescer_duplicate_error_o(dup_err),.coalescer_context_error_o(ctx_err),
        .operand_context_error_o(operand_err),.coalescer_occupancy_o(occupancy));
    task automatic put_operand(input integer ch);
        begin
            @(negedge clk); operand_channel=ch; operand_tag=64'h700; operand_valid=1;
            do @(posedge clk); while(!operand_ready); @(negedge clk); operand_valid=0;
            $display("operand accepted ch=%0d time=%0t",ch,$time);
        end
    endtask
    task automatic put_command(input integer ch);
        begin
            @(negedge clk); command_channel=ch; command_valid=1;
            do @(posedge clk); while(!command_ready); @(negedge clk); command_valid=0;
            $display("command accepted ch=%0d time=%0t",ch,$time);
        end
    endtask
    always @(posedge clk) begin
        if(!rst_n) begin results <= 0; reduced_results <= 0; end
        else begin
        if(result_valid[0]&&result_ready[0]) begin
            if(result_data[0][15:0]!==16'h4200) $fatal(1,"bad ADD result %h",result_data[0][15:0]);
            if(result_channel[0]>=CH) $fatal(1,"invalid source channel");
        end
        if(result_valid[1]&&result_ready[1]) begin
            if(result_data[1][15:0]!==16'h4200) $fatal(1,"bad ADD result %h",result_data[1][15:0]);
            if(result_channel[1]>=CH) $fatal(1,"invalid source channel");
        end
        results <= results + (result_valid[0]&&result_ready[0]) +
                           (result_valid[1]&&result_ready[1]);
        if(reduced_valid) begin
            if(reduced_data[15:0]!==16'h4a00)$fatal(1,"bad reduced result %h",reduced_data[15:0]);
            if(reduced_tag!==64'h700)$fatal(1,"bad reduced tag %h",reduced_tag);
            if(reduced_dst)$fatal(1,"unexpected bank destination");
            reduced_results<=reduced_results+1;
        end
        end
    end
    initial begin
        operand_valid=0;command_valid=0;operand_precision=0;src0='0;src1='0;src2='0;accum='0;
        src0[15:0]=16'h3c00;src1[15:0]=16'h4000;epoch=7;ordinal=3;signature=32'h12345678;
        command_word=32'h10000000;expected=4'b1111;result_ready='1;
        repeat(3)@(posedge clk);rst_n=1;@(posedge clk);
        for(integer ch=0;ch<CH;ch++) put_operand(ch);
        for(integer ch=0;ch<CH;ch++) put_command(ch);
        repeat(30) begin @(posedge clk); if(results==4 && reduced_results==1) begin
            if(dup_err||ctx_err||operand_err||reduction_dup||reduction_ctx)
                $fatal(1,"unexpected protocol error");
            $display("LOGIC_DIE_PIM_TOP_TB PASS results[%0d] reduced[%0d]",results,reduced_results);$finish;
        end end
        $fatal(1,"timeout results=%0d reduced=%0d",results,reduced_results);
    end
endmodule
