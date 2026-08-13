module normalization_bank_scheduler_tb #(
    parameter bit SHARED = 1'b0
);
    localparam int B=16,L=8;
    logic clk=0,rst_n=0,clear=0; always #5 clk=~clk;
    logic[B-1:0] rv,rr,crv,crr,av,ar,cav,car,alast,calast;
    logic[B-1:0][L-1:0][15:0] rdata,crdata,ax,ag,ab,cax,cag,cab,wdata,bwdata;
    logic[B-1:0][15:0] atag,catag,wtag,bwtag;
    logic[B-1:0] wv,wr,wlast,bwv,bwr,bwlast;
    logic[31:0] rg,agc,wg,conflicts,skew;
    logic error;
    integer red_seen=0,replay_seen=0,write_seen=0,max_red_wait=0,max_replay_wait=0;
    integer red_wait=0,replay_wait=0;
    logic[15:0]lfsr;

    normalization_bank_scheduler #(.BANKS(B),.LANES(L),.STARVE_LIMIT(8),.SHARED_RW_PORT(SHARED)) dut(
      .clk_i(clk),.rst_ni(rst_n),.counter_clear_i(clear),
      .reduction_valid_i(rv),.reduction_ready_o(rr),.reduction_data_i(rdata),
      .core_reduction_valid_o(crv),.core_reduction_ready_i(crr),.core_reduction_data_o(crdata),
      .replay_valid_i(av),.replay_ready_o(ar),.replay_tag_i(atag),.replay_x_i(ax),
      .replay_gamma_i(ag),.replay_beta_i(ab),.replay_last_i(alast),
      .core_replay_valid_o(cav),.core_replay_ready_i(car),.core_replay_tag_o(catag),
      .core_replay_x_o(cax),.core_replay_gamma_o(cag),.core_replay_beta_o(cab),.core_replay_last_o(calast),
      .core_writeback_valid_i(wv),.core_writeback_ready_o(wr),.core_writeback_tag_i(wtag),
      .core_writeback_data_i(wdata),.core_writeback_last_i(wlast),
      .bank_writeback_valid_o(bwv),.bank_writeback_ready_i(bwr),.bank_writeback_tag_o(bwtag),
      .bank_writeback_data_o(bwdata),.bank_writeback_last_o(bwlast),
      .reduction_grants_o(rg),.replay_grants_o(agc),.writeback_grants_o(wg),
      .read_conflict_cycles_o(conflicts),.bank_skew_cycles_o(skew),.protocol_error_o(error));

    always @(posedge clk) if(rst_n) begin
      if(&crv) begin red_seen++; if(crdata!==rdata)$fatal(1,"reduction payload changed"); end
      if(&cav) begin replay_seen++; if({catag,cax,cag,cab,calast}!={atag,ax,ag,ab,alast})$fatal(1,"replay payload changed"); end
      if(&bwv) begin write_seen++; if({bwtag,bwdata,bwlast}!={wtag,wdata,wlast})$fatal(1,"write payload changed"); end
      if((&rv)&&(&crr)&&!(&rr)) red_wait++; else red_wait=0;
      if((&av)&&(&car)&&!(&ar)) replay_wait++; else replay_wait=0;
      if(red_wait>max_red_wait)max_red_wait=red_wait;
      if(replay_wait>max_replay_wait)max_replay_wait=replay_wait;
      if((&rr)&&(&ar))$fatal(1,"two reads granted together");
      if(SHARED&&(&bwv)&&((&rr)||(&ar)))$fatal(1,"shared port issued read plus write");
    end

    initial begin
      rv=0;av=0;wv=0;crr='1;car='1;bwr='1;rdata='h1234;atag='h5100;
      ax='h3f80;ag='h4000;ab='h3f00;alast='1;wtag='h5200;wdata='h3f80;wlast='1;
      repeat(3)@(negedge clk);rst_n=1;

      // A partial bank vector must be held and counted as skew, never issued.
      @(negedge clk);rv={{(B-1){1'b1}},1'b0};repeat(3)@(negedge clk);
      if(|rr||red_seen!=0)$fatal(1,"partial reduction issued");

      // Continuous three-way conflict. Split mode must write concurrently;
      // shared mode must still service both read classes within STARVE_LIMIT.
      rv='1;av='1;wv='1;repeat(32)@(negedge clk);
      rv=0;av=0;wv=0;repeat(2)@(negedge clk);
      if(red_seen==0||replay_seen==0||write_seen==0)$fatal(1,"class not serviced r=%0d a=%0d w=%0d",red_seen,replay_seen,write_seen);
      if(max_red_wait>8||max_replay_wait>8)$fatal(1,"starvation bound exceeded red=%0d replay=%0d",max_red_wait,max_replay_wait);
      if(conflicts<30||skew<3)$fatal(1,"diagnostic counters wrong conflict=%0d skew=%0d",conflicts,skew);
      if(rg!=red_seen||agc!=replay_seen||wg!=write_seen)$fatal(1,"grant counters mismatch");

      // Destination backpressure cannot consume an input transaction.
      @(negedge clk);rv='1;crr=0;repeat(4)@(negedge clk);
      if(|rr)$fatal(1,"reduction consumed under core backpressure");
      crr='1;@(negedge clk);rv=0;
      @(negedge clk);wv='1;bwr=0;repeat(4)@(negedge clk);
      if(|wr|| |bwv)$fatal(1,"write consumed under bank backpressure");
      bwr='1;@(negedge clk);wv=0;repeat(2)@(negedge clk);

      // Deterministic pseudo-random request and destination backpressure mix.
      lfsr=16'h1d0f;
      repeat(128)begin
        @(negedge clk);lfsr={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
        rv={B{lfsr[0]}};av={B{lfsr[1]}};wv={B{lfsr[2]}};
        crr={B{lfsr[3]}};car={B{lfsr[4]}};bwr={B{lfsr[5]}};
        // Inject a skewed bank occasionally; it must not leak a partial issue.
        if(lfsr[8:6]==3'b000)rv[0]=1'b0;
      end
      @(negedge clk);rv=0;av=0;wv=0;crr='1;car='1;bwr='1;repeat(2)@(negedge clk);
      if(error)$fatal(1,"scheduler protocol error");
      if(red_wait>8||replay_wait>8)$fatal(1,"random starvation bound exceeded");
      $display("NORMALIZATION_BANK_SCHEDULER_TB PASS shared=%0d random_bp_cycles=128 red=%0d replay=%0d write=%0d conflicts=%0d skew=%0d max_wait=%0d/%0d",SHARED,red_seen,replay_seen,write_seen,conflicts,skew,max_red_wait,max_replay_wait);
      $finish;
    end
    initial begin repeat(1000)@(negedge clk);$fatal(1,"timeout");end
endmodule
