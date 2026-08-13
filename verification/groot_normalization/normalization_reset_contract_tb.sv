module normalization_reset_contract_tb #(
    parameter int DATA_FORMAT = 0
);
    localparam int BANKS = 2;
    logic clk=0,rst_n=0;always #5 clk=~clk;
    logic begin_valid,begin_ready,begin_mode;
    logic[15:0]begin_tag,inv_hidden,epsilon;
    logic[BANKS-1:0]expected_mask;
    logic partial_valid,partial_ready;
    logic partial_bank;
    logic[15:0]partial_tag,partial_sum,partial_sumsq;
    logic response_valid,response_ready,response_mode,response_clamped;
    logic[15:0]response_tag,response_mean,response_inv;
    logic duplicate_error,context_error;
    integer errors;
    logic[48:0]held_response;

    logic_normalization_reduction_engine #(.BANKS(BANKS),.DATA_FORMAT(DATA_FORMAT)) dut(
      .clk_i(clk),.rst_ni(rst_n),.begin_valid_i(begin_valid),.begin_ready_o(begin_ready),
      .begin_rms_norm_i(begin_mode),.begin_tag_i(begin_tag),.begin_expected_mask_i(expected_mask),
      .begin_inv_hidden_i(inv_hidden),.begin_epsilon_i(epsilon),.partial_valid_i(partial_valid),
      .partial_ready_o(partial_ready),.partial_bank_i(partial_bank),.partial_tag_i(partial_tag),
      .partial_sum_i(partial_sum),.partial_sumsq_i(partial_sumsq),
      .response_valid_o(response_valid),.response_ready_i(response_ready),
      .response_rms_norm_o(response_mode),.response_tag_o(response_tag),
      .response_mean_o(response_mean),.response_inv_std_o(response_inv),
      .response_variance_clamped_o(response_clamped),.duplicate_error_o(duplicate_error),
      .context_error_o(context_error));

    function automatic[15:0] one;one=DATA_FORMAT?16'h3f80:16'h3c00;endfunction
    function automatic[15:0] half;half=DATA_FORMAT?16'h3f00:16'h3800;endfunction
    function automatic[15:0] expected_inv;expected_inv=DATA_FORMAT?16'h3f7f:16'h3bfa;endfunction

    task start_context(input logic[15:0]tag_value);
      begin
        begin_tag=tag_value;begin_valid=1;
        do@(posedge clk);while(!begin_ready);
        @(negedge clk);begin_valid=0;
      end
    endtask
    task send_partial(input logic bank,input logic[15:0]tag_value);
      begin
        partial_bank=bank;partial_tag=tag_value;partial_sum=0;partial_sumsq=one();partial_valid=1;
        do@(posedge clk);while(!partial_ready);
        @(negedge clk);partial_valid=0;
      end
    endtask
    task reset_now;
      begin
        rst_n=0;#1;
        if(response_valid||duplicate_error||context_error)errors=errors+1;
        repeat(2)@(posedge clk);@(negedge clk);rst_n=1;
      end
    endtask

    initial begin
      begin_valid=0;begin_mode=1;begin_tag=0;expected_mask=2'b11;
      inv_hidden=half();epsilon=DATA_FORMAT?16'h0001:16'h0001;
      partial_valid=0;partial_bank=0;partial_tag=0;partial_sum=0;partial_sumsq=0;
      response_ready=0;errors=0;repeat(3)@(posedge clk);@(negedge clk);rst_n=1;

      // Reset while only one of two bank partials has arrived.
      start_context(16'h10);send_partial(0,16'h10);reset_now();
      partial_bank=1;partial_tag=16'h10;partial_sumsq=one();partial_valid=1;
      @(posedge clk);@(negedge clk);partial_valid=0;
      if(!context_error)errors=errors+1;

      // Reset while the scalar engine is in flight after the mask completed.
      start_context(16'h20);send_partial(0,16'h20);send_partial(1,16'h20);
      repeat(2)@(posedge clk);reset_now();
      repeat(8)begin@(posedge clk);@(negedge clk);if(response_valid)errors=errors+1;end

      // Complete a response, hold it stalled, and verify stable payload.
      start_context(16'h30);send_partial(0,16'h30);send_partial(1,16'h30);
      wait(response_valid);@(negedge clk);
      held_response={response_mode,response_tag,response_mean,response_inv};
      repeat(3)begin
        @(posedge clk);@(negedge clk);
        if(!response_valid||{response_mode,response_tag,response_mean,response_inv}!==held_response)
          errors=errors+1;
      end
      if(!response_mode||response_tag!==16'h30||response_mean!==0||
         response_inv!==expected_inv()||response_clamped)errors=errors+1;
      reset_now();

      // A fresh transaction after all reset phases must complete normally.
      start_context(16'h40);send_partial(0,16'h40);send_partial(1,16'h40);
      wait(response_valid);@(negedge clk);
      if(response_tag!==16'h40||response_inv!==expected_inv())errors=errors+1;
      response_ready=1;@(posedge clk);@(negedge clk);response_ready=0;
      if(response_valid)errors=errors+1;

      if(errors)$fatal(1,"NORMALIZATION_RESET_CONTRACT_TB FAIL format=%0d errors=%0d",DATA_FORMAT,errors);
      $display("NORMALIZATION_RESET_CONTRACT_TB PASS format=%0d partial scalar stalled_response recovery",DATA_FORMAT);
      $finish;
    end
    initial begin #20000;$fatal(1,"normalization reset contract timeout");end
endmodule
