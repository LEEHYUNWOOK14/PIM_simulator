module logic_normalization_engine_array_tb;
    localparam int E=4,B=2;
    logic clk=0,rst_n=0;
    logic[E-1:0]bv,br,mode,pv,pr,rv,rr,rmode,clamp,dup,ctx;
    logic[E-1:0][15:0]btag,ptag,rtag,mean,inv;
    logic[E-1:0][B-1:0]mask;
    logic[E-1:0][15:0]invh,eps,psum,psq;
    logic[E-1:0][0:0]pbank;
    integer responses,cycle;
    always#5 clk=~clk;always@(posedge clk)if(rst_n)cycle<=cycle+1;
    logic_normalization_engine_array #(.ENGINES(E),.BANKS(B))dut(
      .clk_i(clk),.rst_ni(rst_n),.begin_valid_i(bv),.begin_ready_o(br),
      .begin_rms_norm_i(mode),.begin_tag_i(btag),.begin_expected_bank_mask_i(mask),
      .begin_inv_hidden_i(invh),.begin_epsilon_i(eps),.partial_valid_i(pv),
      .partial_ready_o(pr),.partial_tag_i(ptag),.partial_bank_i(pbank),
      .partial_sum_i(psum),.partial_sumsq_i(psq),.response_valid_o(rv),
      .response_ready_i(rr),.response_rms_norm_o(rmode),.response_tag_o(rtag),
      .response_mean_o(mean),.response_inv_std_o(inv),
      .response_variance_clamped_o(clamp),.duplicate_error_o(dup),.context_error_o(ctx));
    initial begin
      bv=0;mode='1;btag='0;mask='1;invh={E{16'h3800}};eps='0; // 1/2
      pv=0;ptag='0;pbank='0;psum='0;psq='0;rr='1;responses=0;cycle=0;
      for(integer e=0;e<E;e++)btag[e]=16'h2000+e;
      repeat(3)@(negedge clk);rst_n=1;
      @(negedge clk);bv='1;@(negedge clk);bv=0;
      for(integer bank=0;bank<B;bank++)begin
        @(negedge clk);pv='1;
        for(integer e=0;e<E;e++)begin
          ptag[e]=16'h2000+e;pbank[e]=bank;psum[e]=16'h0000;psq[e]=16'h3c00; // each bank 1
        end
        @(negedge clk);pv=0;
      end
      while(rv!=='1)@(negedge clk);
      for(integer e=0;e<E;e++)
        if(rtag[e]!==16'h2000+e||mean[e]!==16'h0000||inv[e]!==16'h3bfa)
          $fatal(1,"engine %0d initial result bad tag=%h mean=%h inv=%h",e,rtag[e],mean[e],inv[e]);
      rr=4'b1110;repeat(2)@(negedge clk);
      if(!rv[0]||rtag[0]!==16'h2000||inv[0]!==16'h3bfa)
        $fatal(1,"stalled engine response changed");
      responses=4;rr='1;@(negedge clk);
      if(|dup|| |ctx)$fatal(1,"unexpected errors");
      $display("LOGIC_NORMALIZATION_ENGINE_ARRAY_TB PASS engines=%0d parallel_responses=%0d cycles=%0d",E,responses,cycle);
      $finish;
    end
endmodule
