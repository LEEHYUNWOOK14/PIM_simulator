module logic_die_random_stress_tb;
    localparam CH=8,PCU=4,DW=256,TW=64,BATCHES=40;
    logic clk=0,rst_n=0;always #5 clk=~clk;
    logic opv,opr;logic [2:0] opch;logic [TW-1:0] optag;logic [1:0] precision;
    logic [DW-1:0] src0,src1,src2,accum;
    logic cmdv,cmdr;logic [2:0] cmdch;logic [15:0] epoch,ordinal;
    logic [31:0] signature,cmdword;logic [CH-1:0] expected;
    logic [PCU-1:0] resv,resr;logic [PCU-1:0][TW-1:0] restag;
    logic [PCU-1:0][DW-1:0] resdata;logic [PCU-1:0][2:0] resch;
    logic dup,ctxerr,operr;logic [7:0] occupancy;
    logic [31:0] lfsr;integer total_results;
    logic [CH-1:0] received_mask [0:BATCHES-1];
    logic_die_pim_top #(.CHANNELS(CH),.PCUS(PCU),.DATA_WIDTH(DW),.TAG_WIDTH(TW),
        .REQUIRE_EPOCH(1'b0),.USE_SHARED_WEIGHT(1'b0)) dut(
        .clk_i(clk),.rst_ni(rst_n),.operand_valid_i(opv),.operand_ready_o(opr),
        .operand_channel_i(opch),.operand_tag_i(optag),.operand_precision_i(precision),
        .operand_src0_i(src0),.operand_src1_i(src1),.operand_src2_i(src2),.operand_accum_i(accum),
        .command_valid_i(cmdv),.command_ready_o(cmdr),.command_channel_i(cmdch),
        .command_epoch_i(epoch),.command_ordinal_i(ordinal),.command_signature_i(signature),
        .command_word_i(cmdword),.command_expected_mask_i(expected),
        .epoch_begin_valid_i(1'b0),.epoch_begin_ready_o(),.epoch_begin_id_i('0),
        .epoch_expected_mask_i('0),.epoch_fill_done_valid_i(1'b0),
        .epoch_fill_done_channel_i('0),.epoch_execution_done_i(1'b0),
        .epoch_release_valid_o(),.epoch_release_id_o(),.epoch_active_o(),
        .weight_write_valid_i(1'b0),.weight_write_ready_o(),.weight_write_addr_i('0),
        .weight_write_data_i('0),.weight_write_mask_i('0),.weight_read_valid_i(1'b0),
        .weight_read_ready_o(),.weight_read_addr_i('0),.weight_response_valid_o(),
        .weight_response_ready_i(1'b1),.weight_response_data_o(),
        .weight_context_commit_i(1'b0),.weight_context_id_i('0),.weight_context_valid_o(),
        .result_valid_o(resv),.result_ready_i(resr),.result_tag_o(restag),
        .result_data_o(resdata),.result_channel_o(resch),
        .reduced_result_ready_i(1'b1),
        .coalescer_duplicate_error_o(dup),.coalescer_context_error_o(ctxerr),
        .operand_context_error_o(operr),.coalescer_occupancy_o(occupancy));
    task automatic put_operand(input integer batch,input integer ch);
        begin @(negedge clk);opch=ch;optag=(batch<<8);opv=1;
        do @(posedge clk);while(!opr);@(negedge clk);opv=0;end
    endtask
    task automatic put_command(input integer batch,input integer ch);
        begin @(negedge clk);cmdch=ch;epoch=batch;signature=32'h80000000|batch;cmdv=1;
        do @(posedge clk);while(!cmdr);@(negedge clk);cmdv=0;end
    endtask
    task automatic check_result(input logic [TW-1:0] tag,input integer source_channel,
                                input logic [DW-1:0] data);
        integer batch_id,channel_id;
        begin
            batch_id=tag>>8;channel_id=source_channel;
            if(batch_id<0||batch_id>=BATCHES||channel_id<0||channel_id>=CH)$fatal(1,"bad tag");
            if(received_mask[batch_id][channel_id])$fatal(1,"duplicate result b%0d c%0d",batch_id,channel_id);
            if(data[15:0]!==16'h4200)$fatal(1,"bad stress data");
            received_mask[batch_id][channel_id]=1'b1;
        end
    endtask
    always @(negedge clk) if(rst_n) begin
        lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
        resr=lfsr[PCU-1:0];
        if(resr==0)resr[0]=1'b1;
    end
    always @(posedge clk) if(!rst_n) total_results<=0;else begin
        if(resv[0]&&resr[0])check_result(restag[0],resch[0],resdata[0]);
        if(resv[1]&&resr[1])check_result(restag[1],resch[1],resdata[1]);
        if(resv[2]&&resr[2])check_result(restag[2],resch[2],resdata[2]);
        if(resv[3]&&resr[3])check_result(restag[3],resch[3],resdata[3]);
        total_results<=total_results+(resv[0]&&resr[0])+(resv[1]&&resr[1])+
                       (resv[2]&&resr[2])+(resv[3]&&resr[3]);
    end
    initial begin
        opv=0;cmdv=0;precision=0;src0=0;src1=0;src2=0;accum=0;
        src0[15:0]=16'h3c00;src1[15:0]=16'h4000;ordinal=0;cmdword=32'h10000000;
        expected='1;resr=1;lfsr=32'h1acebeef;total_results=0;
        for(integer b=0;b<BATCHES;b++)received_mask[b]=0;
        repeat(3)@(posedge clk);rst_n=1;
        for(integer b=0;b<BATCHES;b++)begin
            for(integer c=0;c<CH;c++)put_operand(b,c);
            for(integer c=0;c<CH;c++)put_command(b,c);
            wait(total_results==(b+1)*CH);
            if(received_mask[b]!=='1)$fatal(1,"incomplete batch %0d mask %h",b,received_mask[b]);
            if(dup||ctxerr||operr)$fatal(1,"protocol error during stress");
        end
        $display("LOGIC_DIE_RANDOM_STRESS_TB PASS batches[%0d] results[%0d]",BATCHES,total_results);
        $finish;
    end
    initial begin #200000;$fatal(1,"random stress timeout results=%0d mask0=%h resv=%h resr=%h resch=%h dup=%b ctx=%b op=%b",
        total_results,received_mask[0],resv,resr,resch,dup,ctxerr,operr);end
endmodule
