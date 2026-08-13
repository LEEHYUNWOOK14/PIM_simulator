module normalization_special_values_tb #(
    parameter int DATA_FORMAT=0
);
    logic clk=0,rst_n=0;always #5 clk=~clk;
    logic request_valid,request_ready,mode;
    logic[15:0]tag,sum,sumsq,inv_hidden,epsilon;
    logic response_valid,response_ready,response_mode,clamped;
    logic[15:0]response_tag,mean,inv_std;
    integer errors,cases;
    logic[15:0]one,two,pos_inf,qnan,max_finite,expected_subnormal_rsqrt;

    logic_normalization_scalar_engine #(.DATA_FORMAT(DATA_FORMAT)) dut(
      .clk_i(clk),.rst_ni(rst_n),.request_valid_i(request_valid),.request_ready_o(request_ready),
      .rms_norm_i(mode),.request_tag_i(tag),.sum_i(sum),.sumsq_i(sumsq),
      .inv_hidden_i(inv_hidden),.epsilon_i(epsilon),.response_valid_o(response_valid),
      .response_ready_i(response_ready),.response_rms_norm_o(response_mode),
      .response_tag_o(response_tag),.mean_o(mean),.inv_std_o(inv_std),
      .variance_clamped_o(clamped));

    task run_case(input logic rms,input logic[15:0]sum_v,input logic[15:0]sumsq_v,
      input logic[15:0]inv_hidden_v,input logic[15:0]epsilon_v,
      input logic[15:0]expected_mean,input logic[15:0]expected_inv,input logic expected_clamp);
      begin
        mode=rms;sum=sum_v;sumsq=sumsq_v;inv_hidden=inv_hidden_v;epsilon=epsilon_v;
        tag=cases;request_valid=1;do@(posedge clk);while(!request_ready);
        @(negedge clk);request_valid=0;wait(response_valid);@(negedge clk);
        if(response_mode!==rms||response_tag!==cases||mean!==expected_mean||
           inv_std!==expected_inv||clamped!==expected_clamp)begin
          $display("SPECIAL FAIL f=%0d case=%0d mode=%b mean=%h/%h inv=%h/%h clamp=%b/%b",
            DATA_FORMAT,cases,response_mode,mean,expected_mean,inv_std,expected_inv,clamped,expected_clamp);
          errors=errors+1;end
        response_ready=1;@(posedge clk);@(negedge clk);response_ready=0;cases=cases+1;
      end
    endtask

    initial begin
      one=DATA_FORMAT?16'h3f80:16'h3c00;two=16'h4000;
      pos_inf=DATA_FORMAT?16'h7f80:16'h7c00;qnan=DATA_FORMAT?16'h7fc0:16'h7e00;
      max_finite=DATA_FORMAT?16'h7f7f:16'h7bff;
      expected_subnormal_rsqrt=DATA_FORMAT?16'h60b5:16'h6bfa;
      request_valid=0;response_ready=0;mode=0;tag=0;sum=0;sumsq=0;inv_hidden=one;
      epsilon=0;errors=0;cases=0;repeat(3)@(posedge clk);@(negedge clk);rst_n=1;
      run_case(1,0,0,one,0,0,pos_inf,0);                    // zero argument
      run_case(1,0,0,one,16'h0001,0,expected_subnormal_rsqrt,0); // min subnormal epsilon
      run_case(1,0,pos_inf,one,0,0,0,0);                  // +Inf statistic
      run_case(1,0,qnan,one,0,0,qnan,0);                  // NaN statistic
      run_case(1,0,{1'b1,one[14:0]},one,0,0,qnan,0);      // negative RMS statistic
      run_case(0,one,0,one,0,one,pos_inf,1);              // negative variance clamps to zero
      run_case(1,0,max_finite,two,0,0,0,0);               // multiplication overflow to Inf
      if(errors)$fatal(1,"NORMALIZATION_SPECIAL_VALUES_TB FAIL format=%0d errors=%0d",DATA_FORMAT,errors);
      $display("NORMALIZATION_SPECIAL_VALUES_TB PASS format=%0d cases=%0d",DATA_FORMAT,cases);$finish;
    end
    initial begin #20000;$fatal(1,"normalization special values timeout");end
endmodule
