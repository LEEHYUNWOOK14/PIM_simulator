module bank_normalization_engines_tb;
    logic clk=0,rst_n=0;always #5 clk=~clk;
    logic rbv,rbr,rev,rer,rrv,rrr,rerr;logic[15:0]rbtag,rcount,redata,rrtag,rrsum,rrsumsq;
    logic acv,acr,amode,aev,aer,ael,arv,arr,arl,aerr;logic[15:0]actag,amean,ainv,aetag,aex,aeg,aeb,artag,ardata;
    logic[127:0]meta[0:127];logic[63:0]elements[0:2047];integer row,idx,mismatches;
    bank_normalization_local_reducer reducer(.clk_i(clk),.rst_ni(rst_n),.begin_valid_i(rbv),
      .begin_ready_o(rbr),.begin_tag_i(rbtag),.begin_element_count_i(rcount),
      .element_valid_i(rev),.element_ready_o(rer),.element_data_i(redata),
      .result_valid_o(rrv),.result_ready_i(rrr),.result_tag_o(rrtag),
      .result_sum_o(rrsum),.result_sumsq_o(rrsumsq),.protocol_error_o(rerr));
    bank_normalization_apply apply(.clk_i(clk),.rst_ni(rst_n),.config_valid_i(acv),
      .config_ready_o(acr),.config_rms_norm_i(amode),.config_tag_i(actag),
      .config_mean_i(amean),.config_inv_std_i(ainv),.element_valid_i(aev),
      .element_ready_o(aer),.element_tag_i(aetag),.element_x_i(aex),
      .element_gamma_i(aeg),.element_beta_i(aeb),.element_last_i(ael),
      .result_valid_o(arv),.result_ready_i(arr),.result_tag_o(artag),
      .result_data_o(ardata),.result_last_o(arl),.context_error_o(aerr));
    task send_reducer_element(input integer element_index);
      begin rev=1;redata=elements[element_index][63:48];do@(posedge clk);while(!rer);@(negedge clk);rev=0;end
    endtask
    task send_apply_element(input integer element_index,input logic last);
      begin aev=1;aetag=row;aex=elements[element_index][63:48];aeg=elements[element_index][47:32];
        aeb=elements[element_index][31:16];ael=last;do@(posedge clk);while(!aer);@(negedge clk);aev=0;
        wait(arv);if(ardata!==elements[element_index][15:0]||artag!==row||arl!==last)begin
          if(mismatches<20)$display("BANK APPLY FAIL row=%0d idx=%0d exp=%h got=%h",row,element_index,elements[element_index][15:0],ardata);
          mismatches=mismatches+1;end
        arr=1;@(posedge clk);@(negedge clk);arr=0;end
    endtask
    initial begin
      $readmemh("verification/groot_normalization/bank_normalization_meta.hex",meta);
      $readmemh("verification/groot_normalization/bank_normalization_elements.hex",elements);
      rbv=0;rev=0;rrr=0;acv=0;aev=0;arr=0;mismatches=0;rbtag=0;rcount=0;redata=0;
      amode=0;actag=0;amean=0;ainv=0;aetag=0;aex=0;aeg=0;aeb=0;ael=0;
      repeat(3)@(posedge clk);@(negedge clk);rst_n=1;
      rev=1;redata=16'h3c00;@(posedge clk);@(negedge clk);rev=0;
      if(!rerr)begin $display("BANK REDUCE FAIL missing protocol error");mismatches=mismatches+1;end
      aev=1;aetag=16'hffff;aex=16'h3c00;aeg=16'h3c00;aeb=0;ael=1;
      @(posedge clk);@(negedge clk);aev=0;
      if(!aerr)begin $display("BANK APPLY FAIL missing context error");mismatches=mismatches+1;end
      for(row=0;row<128;row=row+1)begin
        rbv=1;rbtag=row;rcount=meta[row][126:120];do@(posedge clk);while(!rbr);@(negedge clk);rbv=0;
        acv=1;amode=meta[row][127];actag=row;amean=meta[row][119:104];ainv=meta[row][103:88];
        do@(posedge clk);while(!acr);@(negedge clk);acv=0;
        for(idx=0;idx<meta[row][126:120];idx=idx+1)begin
          send_reducer_element(row*16+idx);send_apply_element(row*16+idx,idx==meta[row][126:120]-1);
        end
        wait(rrv);repeat(2)begin@(posedge clk);@(negedge clk);if(!rrv)mismatches=mismatches+1;end
        if(rrtag!==row||rrsum!==meta[row][87:72]||rrsumsq!==meta[row][71:56])begin
          if(mismatches<20)$display("BANK REDUCE FAIL row=%0d sum=%h/%h sumsq=%h/%h",row,rrsum,meta[row][87:72],rrsumsq,meta[row][71:56]);
          mismatches=mismatches+1;end
        rrr=1;@(posedge clk);@(negedge clk);rrr=0;
      end
      if(mismatches)$fatal(1,"BANK_NORMALIZATION_ENGINES_TB FAIL mismatches=%0d",mismatches);
      $display("BANK_NORMALIZATION_ENGINES_TB PASS rows=128 logical_elements=1088");$finish;
    end
endmodule
