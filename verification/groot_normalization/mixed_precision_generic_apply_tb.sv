module mixed_precision_generic_apply_tb#(parameter int LANES=4);
  localparam int GROUPS=LANES/4,N=64;logic clk=0,rst_n=0;always#5 clk=~clk;
  logic cfg_v,cfg_mode,cfg_ready;logic[GROUPS-1:0]rcfg_ready;logic[15:0]cfg_tag;logic[31:0]cfg_mean,cfg_inv;
  logic vec_v,vec_last,vec_ready;logic[GROUPS-1:0]rvec_ready;logic[15:0]vec_tag;logic[LANES-1:0][15:0]x,gamma,beta;
  logic ov,last,error,out_ready=1;logic[GROUPS-1:0]rov,rlast,rerror;logic[15:0]ot;logic[GROUPS-1:0][15:0]rot;logic[LANES-1:0][15:0]out;logic[GROUPS-1:0][3:0][15:0]rout;
  integer outputs=0,errors=0;
  mixed_precision_bank_apply_pipe #(.LANES(LANES))dut(.clk_i(clk),.rst_ni(rst_n),.config_valid_i(cfg_v),.config_ready_o(cfg_ready),.config_rms_norm_i(cfg_mode),.config_tag_i(cfg_tag),.config_mean_i(cfg_mean),.config_inv_std_i(cfg_inv),.vector_valid_i(vec_v),.vector_ready_o(vec_ready),.vector_tag_i(vec_tag),.x_i(x),.gamma_i(gamma),.beta_i(beta),.vector_last_i(vec_last),.result_valid_o(ov),.result_ready_i(out_ready),.result_tag_o(ot),.result_data_o(out),.result_last_o(last),.context_error_o(error));
  for(genvar g=0;g<GROUPS;g++)begin:g_ref
    mixed_precision_bank_apply4_pipe refdut(.clk_i(clk),.rst_ni(rst_n),.config_valid_i(cfg_v),.config_ready_o(rcfg_ready[g]),.config_rms_norm_i(cfg_mode),.config_tag_i(cfg_tag),.config_mean_i(cfg_mean),.config_inv_std_i(cfg_inv),.vector_valid_i(vec_v),.vector_ready_o(rvec_ready[g]),.vector_tag_i(vec_tag),.x_i(x[g*4+:4]),.gamma_i(gamma[g*4+:4]),.beta_i(beta[g*4+:4]),.vector_last_i(vec_last),.result_valid_o(rov[g]),.result_ready_i(out_ready),.result_tag_o(rot[g]),.result_data_o(rout[g]),.result_last_o(rlast[g]),.context_error_o(rerror[g]));
  end
  always@(negedge clk)if(rst_n&&ov&&out_ready)begin
    if(!(&rov)||out!==rout||ot!==rot[0]||last!==rlast[0])begin $display("apply mismatch lanes=%0d output=%0d generic=%h ref=%h",LANES,outputs,out,rout);errors++;end
    outputs++;
  end
  initial begin wait(outputs==8);@(negedge clk);out_ready=0;repeat(20)@(negedge clk);out_ready=1;end
  task automatic send_config(input logic mode,input logic[15:0]tag);begin while(!(cfg_ready && (&rcfg_ready)))@(negedge clk);cfg_mode=mode;cfg_tag=tag;cfg_v=1;@(negedge clk);cfg_v=0;end endtask
  task automatic send_vectors(input integer base,input logic[15:0]tag);begin
    for(integer i=0;i<32;i++)begin vec_v=0;vec_tag=tag;while(!(vec_ready && (&rvec_ready)))@(negedge clk);vec_v=1;vec_last=i==31;for(integer lane=0;lane<LANES;lane++)begin x[lane]=16'h3e80+((base+i*LANES+lane)%64);gamma[lane]=16'h3f40+((i+lane)%16);beta[lane]=16'h3c00+((i*3+lane)%32);end @(negedge clk);end vec_v=0;vec_last=0;
  end endtask
  initial begin cfg_v=0;cfg_mode=0;cfg_tag=0;cfg_mean=32'h3e99999a;cfg_inv=32'h3f4ccccd;vec_v=0;vec_last=0;vec_tag=0;x=0;gamma=0;beta=0;repeat(3)@(negedge clk);rst_n=1;
    send_config(0,16'h6101);send_vectors(0,16'h6101);while(outputs<32)@(negedge clk);send_config(1,16'h6202);send_vectors(64,16'h6202);while(outputs<N)@(negedge clk);repeat(2)@(negedge clk);
    if(error||(|rerror)||errors)$fatal(1,"GENERIC_APPLY_TB FAIL lanes=%0d errors=%0d",LANES,errors);$display("GENERIC_APPLY_TB PASS lanes=%0d vectors=%0d stall=20",LANES,N);$finish;end
  initial begin repeat(3000)@(negedge clk);$fatal(1,"timeout lanes=%0d outputs=%0d",LANES,outputs);end
endmodule
