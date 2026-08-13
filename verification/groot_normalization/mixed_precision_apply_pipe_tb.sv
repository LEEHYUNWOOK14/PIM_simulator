module mixed_precision_apply_pipe_tb;
  localparam int N=64;logic clk=0,rst_n=0;always#5 clk=~clk;
  logic cfg_v,cfg_mode;logic[15:0]cfg_tag;logic[31:0]cfg_mean,cfg_inv;logic cfg_r0,cfg_r1;
  logic vec_v,vec_last;logic[15:0]vec_tag;logic[3:0][15:0]x,gamma,beta;logic vec_r0,vec_r1;
  logic ov0,ov1,last0,last1,err0,err1,new_ready=1;logic[15:0]tag0,tag1;logic[3:0][15:0]out0,out1;
  logic[63:0]expected_data[0:N-1];logic[15:0]expected_tag[0:N-1];logic expected_last[0:N-1];
  integer old_count=0,new_count=0,errors=0;
  initial begin
    repeat(2000)@(negedge clk);
    $fatal(1,"APPLY_PIPE timeout old=%0d new=%0d cfg_ready=%b%b vec_ready=%b%b active=%b%b ov=%b%b",old_count,new_count,cfg_r0,cfg_r1,vec_r0,vec_r1,old_dut.active_q,new_dut.active_q,ov0,ov1);
  end
  mixed_precision_bank_apply4 old_dut(.clk_i(clk),.rst_ni(rst_n),.config_valid_i(cfg_v),.config_ready_o(cfg_r0),
    .config_rms_norm_i(cfg_mode),.config_tag_i(cfg_tag),.config_mean_i(cfg_mean),.config_inv_std_i(cfg_inv),
    .vector_valid_i(vec_v),.vector_ready_o(vec_r0),.vector_tag_i(vec_tag),.x_i(x),.gamma_i(gamma),.beta_i(beta),.vector_last_i(vec_last),
    .result_valid_o(ov0),.result_ready_i(1'b1),.result_tag_o(tag0),.result_data_o(out0),.result_last_o(last0),.context_error_o(err0));
  mixed_precision_bank_apply4_pipe new_dut(.clk_i(clk),.rst_ni(rst_n),.config_valid_i(cfg_v),.config_ready_o(cfg_r1),
    .config_rms_norm_i(cfg_mode),.config_tag_i(cfg_tag),.config_mean_i(cfg_mean),.config_inv_std_i(cfg_inv),
    .vector_valid_i(vec_v),.vector_ready_o(vec_r1),.vector_tag_i(vec_tag),.x_i(x),.gamma_i(gamma),.beta_i(beta),.vector_last_i(vec_last),
    .result_valid_o(ov1),.result_ready_i(new_ready),.result_tag_o(tag1),.result_data_o(out1),.result_last_o(last1),.context_error_o(err1));
  always@(negedge clk)if(rst_n)begin
    if(ov0)begin expected_data[old_count]=out0;expected_tag[old_count]=tag0;expected_last[old_count]=last0;old_count=old_count+1;end
    if(ov1&&new_ready)begin
      if(new_count>=old_count)begin $display("new output preceded reference index=%0d",new_count);errors=errors+1;end
      else begin
        if(out1!==expected_data[new_count])begin $display("data mismatch index=%0d new=%h old=%h",new_count,out1,expected_data[new_count]);errors=errors+1;end
        if(tag1!==expected_tag[new_count]||last1!==expected_last[new_count])begin $display("metadata mismatch index=%0d",new_count);errors=errors+1;end
      end
      new_count=new_count+1;
    end
  end
  initial begin
    wait(new_count==8);@(negedge clk);new_ready=0;repeat(20)@(negedge clk);new_ready=1;
  end
  task automatic send_config(input logic mode,input logic[15:0]tag);
    begin
      while(!(cfg_r0&&cfg_r1))@(negedge clk);cfg_mode=mode;cfg_tag=tag;cfg_mean=32'h3e99999a;cfg_inv=32'h3f4ccccd;cfg_v=1;
      @(negedge clk);cfg_v=0;
    end
  endtask
  task automatic send_vectors(input integer base,input logic[15:0]tag);
    begin
      for(integer i=0;i<32;i++)begin
        vec_v=0;vec_tag=tag;
        while(!(vec_r0&&vec_r1))@(negedge clk);
        vec_v=1;vec_last=i==31;
        for(integer lane=0;lane<4;lane++)begin
          x[lane]=16'h3e80+((base+i*4+lane)%64);gamma[lane]=16'h3f40+((i+lane)%16);beta[lane]=16'h3c00+((i*3+lane)%32);
        end
        @(negedge clk);
      end
      vec_v=0;vec_last=0;
    end
  endtask
  initial begin
    cfg_v=0;cfg_mode=0;cfg_tag=0;cfg_mean=0;cfg_inv=0;vec_v=0;vec_last=0;vec_tag=0;x=0;gamma=0;beta=0;
    repeat(3)@(negedge clk);rst_n=1;
    send_config(0,16'h1101);send_vectors(0,16'h1101);
    while(new_count<32)@(negedge clk);
    send_config(1,16'h2202);send_vectors(64,16'h2202);
    while(new_count<N)@(negedge clk);repeat(2)@(negedge clk);
    if(err0||err1)begin $display("context error old=%b new=%b",err0,err1);errors=errors+1;end
    if(old_count!=N)begin $display("reference count=%0d",old_count);errors=errors+1;end
    if(errors)$fatal(1,"MIXED_PRECISION_APPLY_PIPE_TB FAIL errors=%0d",errors);
    $display("MIXED_PRECISION_APPLY_PIPE_TB PASS vectors=%0d latency=12 II=1 output_stall=20",N);$finish;
  end
endmodule
