module full_pim_system_top_tb;
    localparam CH=2,PB=2,PCU=2,DW=256;
    logic clk=0,rst_n=0;always #5 clk=~clk;
    logic [CH-1:0] dcv,dcr,drv,drr,dte;logic [CH-1:0][2:0] dc;
    logic [CH-1:0][1:0] db;logic [CH-1:0][2:0] dr,dcoll;
    logic [CH-1:0][DW-1:0] dwd,drd;logic [CH-1:0][DW/8-1:0] dwm;
    logic [CH-1:0] pv,pr,cs,regv,regbank,srfv;logic [CH-1:0][4:0] pa;
    logic [CH-1:0][31:0] pd,key;logic [CH-1:0][1:0] prec;
    logic [CH-1:0][2:0] prow,pcol,regidx;logic [CH-1:0][0:0] regblock,srfblock;
    logic [CH-1:0][DW-1:0] regdata,srfdata,l_src1,l_src2,l_acc;
    logic [CH-1:0] to_logic;
    logic lcmdv,lcmdr;logic lcmdch;logic [15:0] lepoch,lordinal;
    logic [31:0] lsig,lword;logic [CH-1:0] lexpected;
    logic [PCU-1:0] lresv,lresr;logic [PCU-1:0][63:0] ltag;
    logic [PCU-1:0][DW-1:0] ldata;
    logic bank_out_valid,host_out_valid;logic [63:0] bank_out_tag,host_out_tag;
    logic [DW-1:0] bank_out_data,host_out_data;
    logic [1:0] tvalid,tready;logic [1:0][31:0] tkey;
    logic [1:0][DW-1:0] tdata;logic [1:0][0:0] tch;
    logic protocol_error;
    logic ep_begin,ep_begin_ready,ep_fill,ep_exec,ep_release,ep_active;logic ep_fill_ch;
    logic [15:0] ep_begin_id,ep_release_id;logic [CH-1:0] ep_mask;
    logic wwv,wwr,wrv,wrr,wrespv,wrespr,wcommit,wctxvalid;logic [10:0] wwaddr,wraddr;
    logic [DW-1:0] wwdata,wrespdata;logic [DW/8-1:0] wwmask;logic [15:0] wctx;
    logic nbegin,nbegin_ready,nmode,npartial,npartial_ready,nbvalid,nbready,nbmode,nclamped;
    logic [63:0] ntag,nptag,nbtag;logic [3:0] nmask;logic [1:0] npbank;
    logic [15:0] ninv,neps,npsum,npsumsq,nbmean,nbinv;
    integer direct_seen,logic_seen,host_seen;
    logic [DW-1:0] one_vector,two_vector;
    full_pim_system_top #(.CHANNELS(CH),.BANKS(4),.PIM_BLOCKS(PB),.PCUS(PCU),
        .ROWS(8),.COLS(8)) dut(
        .clk_i(clk),.rst_ni(rst_n),.dram_cmd_valid_i(dcv),.dram_cmd_ready_o(dcr),
        .dram_cmd_i(dc),.dram_bank_i(db),.dram_row_i(dr),.dram_col_i(dcoll),
        .dram_write_data_i(dwd),.dram_write_mask_i(dwm),.dram_read_valid_o(drv),
        .dram_read_ready_i(drr),.dram_read_data_o(drd),.dram_timing_error_o(dte),
        .crf_program_valid_i(pv),.crf_program_ready_o(pr),.crf_program_addr_i(pa),
        .crf_program_data_i(pd),.crf_start_i(cs),.bank_context_key_i(key),
        .bank_precision_i(prec),.pim_row_i(prow),.pim_col_i(pcol),
        .register_write_valid_i(regv),.register_write_block_i(regblock),
        .register_write_bank_i(regbank),.register_write_index_i(regidx),
        .register_write_data_i(regdata),.srf_write_valid_i(srfv),
        .srf_write_block_i(srfblock),.srf_write_data_i(srfdata),
        .bank_result_to_logic_i(to_logic),.logic_src1_i(l_src1),.logic_src2_i(l_src2),
        .logic_accum_i(l_acc),.logic_command_valid_i(lcmdv),.logic_command_ready_o(lcmdr),
        .logic_command_channel_i(lcmdch),.logic_command_epoch_i(lepoch),
        .logic_command_ordinal_i(lordinal),.logic_command_signature_i(lsig),
        .logic_command_word_i(lword),.logic_command_expected_mask_i(lexpected),
        .epoch_begin_valid_i(ep_begin),.epoch_begin_ready_o(ep_begin_ready),
        .epoch_begin_id_i(ep_begin_id),.epoch_expected_mask_i(ep_mask),
        .epoch_fill_done_valid_i(ep_fill),.epoch_fill_done_channel_i(ep_fill_ch),
        .epoch_execution_done_i(ep_exec),.epoch_release_valid_o(ep_release),
        .epoch_release_id_o(ep_release_id),.epoch_active_o(ep_active),
        .weight_write_valid_i(wwv),.weight_write_ready_o(wwr),.weight_write_addr_i(wwaddr),
        .weight_write_data_i(wwdata),.weight_write_mask_i(wwmask),
        .weight_read_valid_i(wrv),.weight_read_ready_o(wrr),.weight_read_addr_i(wraddr),
        .weight_response_valid_o(wrespv),.weight_response_ready_i(wrespr),
        .weight_response_data_o(wrespdata),.weight_context_commit_i(wcommit),
        .weight_context_id_i(wctx),.weight_context_valid_o(wctxvalid),
        .logic_result_valid_o(lresv),.logic_result_ready_i(lresr),
        .logic_result_tag_o(ltag),.logic_result_data_o(ldata),
        .logic_bank_result_valid_o(bank_out_valid),.logic_bank_result_ready_i(1'b1),
        .logic_bank_result_tag_o(bank_out_tag),.logic_bank_result_data_o(bank_out_data),
        .logic_host_result_valid_o(host_out_valid),.logic_host_result_ready_i(1'b1),
        .logic_host_result_tag_o(host_out_tag),.logic_host_result_data_o(host_out_data),
        .direct_tsv_valid_o(tvalid),.direct_tsv_ready_i(tready),
        .direct_tsv_key_o(tkey),.direct_tsv_data_o(tdata),
        .direct_tsv_channel_o(tch),
        .normalization_begin_valid_i(nbegin),.normalization_begin_ready_o(nbegin_ready),
        .normalization_begin_rms_norm_i(nmode),.normalization_begin_tag_i(ntag),
        .normalization_expected_bank_mask_i(nmask),.normalization_inv_hidden_i(ninv),
        .normalization_epsilon_i(neps),.normalization_partial_valid_i(npartial),
        .normalization_partial_ready_o(npartial_ready),.normalization_partial_bank_i(npbank),
        .normalization_partial_tag_i(nptag),.normalization_partial_sum_i(npsum),
        .normalization_partial_sumsq_i(npsumsq),.normalization_broadcast_valid_o(nbvalid),
        .normalization_broadcast_ready_i(nbready),.normalization_broadcast_rms_norm_o(nbmode),
        .normalization_broadcast_tag_o(nbtag),.normalization_broadcast_mean_o(nbmean),
        .normalization_broadcast_inv_std_o(nbinv),.normalization_variance_clamped_o(nclamped),
        .protocol_error_o(protocol_error));
    task automatic pulse_registers(input logic block_id,input logic bank_id,input logic [DW-1:0] value);
        begin @(negedge clk);regblock={CH{block_id}};regbank={CH{bank_id}};
        regdata={CH{value}};regv='1;@(posedge clk);@(negedge clk);regv=0;end
    endtask
    task automatic pulse_program(input logic [4:0] addr,input logic [31:0] word);
        begin @(negedge clk);pa={CH{addr}};pd={CH{word}};pv='1;
        @(posedge clk);@(negedge clk);pv=0;end
    endtask
    always @(posedge clk) if(!rst_n) begin direct_seen<=0;logic_seen<=0;host_seen<=0;end else begin
        if(tvalid[0]&&tready[0]&&tdata[0][15:0]!==16'h4200)$fatal(1,"direct lane0 bad");
        if(tvalid[1]&&tready[1]&&tdata[1][15:0]!==16'h4200)$fatal(1,"direct lane1 bad");
        direct_seen<=direct_seen+(tvalid[0]&&tready[0])+(tvalid[1]&&tready[1]);
        if(lresv[0]&&lresr[0]&&ldata[0][15:0]!==16'h4400)$fatal(1,"logic pcu0 bad %h",ldata[0][15:0]);
        if(lresv[1]&&lresr[1]&&ldata[1][15:0]!==16'h4400)$fatal(1,"logic pcu1 bad %h",ldata[1][15:0]);
        if(host_out_valid && host_out_data[15:0]!==16'h4400)$fatal(1,"reduced host result bad");
        if(host_out_valid && host_out_tag!==64'h11)$fatal(1,"reduced host tag bad %h",host_out_tag);
        if(bank_out_valid)$fatal(1,"unexpected bank-routed result");
        host_seen<=host_seen+host_out_valid;
        logic_seen<=logic_seen+(lresv[0]&&lresr[0])+(lresv[1]&&lresr[1]);
    end
    initial begin
        dcv=0;dc=0;db=0;dr=0;dcoll=0;dwd=0;dwm='1;drr='1;pv=0;pa=0;pd=0;cs=0;
        key[0]=32'h10;key[1]=32'h11;prec=0;prow=0;pcol=0;regv=0;regblock=0;
        regbank=0;regidx=0;regdata=0;srfv=0;srfblock=0;srfdata=0;to_logic=2'b10;
        one_vector=0;two_vector=0;one_vector[15:0]=16'h3c00;two_vector[15:0]=16'h4000;
        // Deliberately differ from the shared weight. A 4.0 result proves that
        // the PCU consumed weight-buffer 1.0 rather than external src1 2.0.
        l_src1={CH{two_vector}};l_src2=0;l_acc=0;lcmdv=0;lcmdch=1;lepoch=1;
        lordinal=0;lsig=32'h55aa;lword=32'h10000000;lexpected=2'b10;lresr='1;tready='1;
        ep_begin=0;ep_begin_id=0;ep_mask=0;ep_fill=0;ep_fill_ch=0;ep_exec=0;
        wwv=0;wwaddr=0;wwdata=0;wwmask='1;wrv=0;wraddr=0;wrespr=1;wcommit=0;wctx=0;
        nbegin=0;nmode=1;ntag=64'h55;nmask=4'hf;ninv=16'h3400;neps=16'h0011;
        npartial=0;npbank=0;nptag=64'h55;npsum=0;npsumsq=16'h3c00;nbready=0;
        repeat(3)@(posedge clk);rst_n=1;
        @(negedge clk);nbegin=1;do @(posedge clk);while(!nbegin_ready);@(negedge clk);nbegin=0;
        for(integer norm_bank=0;norm_bank<4;norm_bank=norm_bank+1)begin
            @(negedge clk);npbank=norm_bank;npartial=1;
            do @(posedge clk);while(!npartial_ready);@(negedge clk);npartial=0;
        end
        wait(nbvalid);repeat(2)begin @(posedge clk);@(negedge clk);
            if(!nbvalid||nbmode!==1'b1||nbtag!==64'h55||nbmean!==16'h0000||
               nbinv!==16'h3bfa||nclamped)$fatal(1,"normalization broadcast bad");end
        nbready=1;@(posedge clk);@(negedge clk);nbready=0;
        // Populate and commit shared weight context 1, then prefetch address 0.
        @(negedge clk);wctx=1;wwaddr=0;wwdata=one_vector;wwv=1;wcommit=1;
        do @(posedge clk);while(!wwr);
        @(negedge clk);wwv=0;wcommit=0;
        @(negedge clk);wraddr=0;wrv=1;
        do @(posedge clk);while(!wrr);
        @(negedge clk);wrv=0;
        wait(wrespv);@(posedge clk);
        pulse_registers(0,0,one_vector);pulse_registers(0,1,two_vector);
        pulse_registers(1,0,one_vector);pulse_registers(1,1,two_vector);
        pulse_program(0,{4'h1,3'd5,3'd4,3'd5,19'b0});pulse_program(1,32'hf0000000);
        @(negedge clk);cs='1;@(posedge clk);@(negedge clk);cs=0;
        repeat(8)@(posedge clk);
        @(negedge clk);ep_begin_id=1;ep_mask=2'b10;ep_begin=1;
        @(posedge clk);@(negedge clk);ep_begin=0;
        @(negedge clk);ep_fill_ch=1;ep_fill=1;
        @(posedge clk);@(negedge clk);ep_fill=0;
        wait(ep_release);
        @(negedge clk);lcmdv=1;do @(posedge clk);while(!lcmdr);@(negedge clk);lcmdv=0;
        repeat(60)@(posedge clk);
        if(direct_seen!=2)$fatal(1,"direct results expected2 got%0d",direct_seen);
        if(logic_seen!=1)$fatal(1,"logic results expected1 got%0d",logic_seen);
        if(host_seen!=1)$fatal(1,"host reduced results expected1 got%0d",host_seen);
        if(protocol_error)$fatal(1,"full-system protocol error");
        $display("FULL_PIM_SYSTEM_TOP_TB PASS direct[%0d] logic[%0d]",direct_seen,logic_seen);$finish;
    end
    initial begin #10000;$fatal(1,"full system timeout");end
endmodule
