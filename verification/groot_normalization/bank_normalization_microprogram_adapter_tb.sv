module bank_normalization_microprogram_adapter_tb;
  localparam int DW=256,L=16;logic clk=0,rst_n=0,sv,sr,smode,srfv,cmdv,cmdr,done;
  logic[15:0]stag,smean,sinv;logic[DW-1:0]srfdata,even,odd,wrdata,result;logic wrvalid;logic[2:0]wridx;
  logic[31:0]cmd,key,rkey;logic[1:0]prec;logic rv;logic[2:0]rdst;logic[3:0]ridx;
  logic cerr;integer commands,done_count;logic[DW-1:0]rms_expected,ln_expected;
  always#5 clk=~clk;initial begin#5000;$fatal(1,"adapter timeout");end
  bank_normalization_microprogram_adapter #(.DATA_WIDTH(DW))adapter(
    .clk_i(clk),.rst_ni(rst_n),.scalar_valid_i(sv),.scalar_ready_o(sr),.scalar_rms_norm_i(smode),
    .scalar_tag_i(stag),.scalar_mean_i(smean),.scalar_inv_std_i(sinv),.gamma_grf_b_index_i(3'd0),
    .beta_grf_b_index_i(3'd1),.srf_write_valid_o(srfv),.srf_write_ready_i(1'b1),
    .srf_write_data_o(srfdata),.command_valid_o(cmdv),.command_ready_i(cmdr),.command_o(cmd),
    .precision_o(prec),.context_key_o(key),.transaction_done_o(done));
  bank_pim_core #(.DATA_WIDTH(DW))core(.clk_i(clk),.rst_ni(rst_n),
    .command_valid_i(cmdv),.command_ready_o(cmdr),.command_i(cmd),.precision_i(prec),.context_key_i(key),
    .even_bank_data_i(even),.odd_bank_data_i(odd),.even_bank_valid_i(1'b1),.odd_bank_valid_i(1'b0),
    .register_write_valid_i(wrvalid),.register_write_bank_i(1'b1),
    .register_write_index_i(wridx),.register_write_data_i(wrdata),
    .srf_write_valid_i(srfv),.srf_write_data_i(srfdata),.result_valid_o(rv),.result_ready_i(1'b1),
    .result_key_o(rkey),.result_destination_o(rdst),.result_index_o(ridx),.result_data_o(result),
    .command_error_o(cerr));
  always@(posedge clk)if(rst_n)begin if(cmdv&&cmdr)commands<=commands+1;if(done)done_count<=done_count+1;end
  task automatic load_grf(input logic idx,input[15:0]value);begin
    @(negedge clk);wrdata='0;wrvalid=1;wridx=idx;
    for(integer l=0;l<L;l++)wrdata[l*16 +:16]=value;
    @(negedge clk);wrvalid=0;wrdata='0;
  end endtask
  task automatic send_scalar(input logic mode,input[15:0]tag,mean,inv);begin
    @(negedge clk);smode=mode;stag=tag;smean=mean;sinv=inv;sv=1;while(!sr)@(negedge clk);@(negedge clk);sv=0;
  end endtask
  task automatic wait_final(input[15:0]tag,input[DW-1:0]expected);begin
    while(!(rv&&rdst==3'd1))@(negedge clk);
    if(rkey[15:0]!==tag||result!==expected)$fatal(1,"final mismatch tag=%h got=%h",tag,result);
    @(negedge clk);
  end endtask
  initial begin
    sv=0;smode=0;stag=0;smean=0;sinv=0;even='0;odd=0;wrdata=0;wrvalid=0;wridx=0;commands=0;done_count=0;
    rms_expected='0;ln_expected='0;
    for(integer l=0;l<L;l++)begin even[l*16+:16]=16'h4000;rms_expected[l*16+:16]=16'h4000;ln_expected[l*16+:16]=16'h4100;end
    repeat(3)@(negedge clk);rst_n=1;
    load_grf(0,16'h4000);load_grf(1,16'h3800);
    send_scalar(1,16'h9000,0,16'h3800);wait_final(16'h9000,rms_expected);
    send_scalar(0,16'h9001,16'h3c00,16'h3c00);wait_final(16'h9001,ln_expected);
    if(commands!=6||done_count!=2||cerr)$fatal(1,"counts/error commands=%0d done=%0d",commands,done_count);
    $display("BANK_NORMALIZATION_MICROPROGRAM_ADAPTER_TB PASS transactions=2 commands=6 lanes=16");$finish;
  end
endmodule
