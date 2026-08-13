module mixed_precision_protocol_tb;
  localparam int B=16,L=4;
  logic clk=0,rst_n=0;always #5 clk=~clk;
  logic bv,br;logic[15:0]tag=16'h1234;logic[B-1:0]rv,rr,av,ar,al,ov,ordy,ol;
  logic[B*L-1:0][15:0]rd,ax,ag,ab,od;logic[B-1:0][15:0]at,ot;
  logic configured,error;logic[31:0]mean,inv;integer outputs=0,errors=0;logic[1023:0]held;
  mixed_precision_normalization_datapath dut(.clk_i(clk),.rst_ni(rst_n),.begin_valid_i(bv),.begin_ready_o(br),.rms_norm_i(1'b0),.tag_i(tag),
    .vectors_per_bank_i(16'd1),.inv_hidden_i(32'h3c800000),.epsilon_i(32'h3727c5ac),.reduce_valid_i(rv),.reduce_ready_o(rr),.reduce_data_i(rd),
    .apply_valid_i(av),.apply_ready_o(ar),.apply_tag_i(at),.apply_x_i(ax),.apply_gamma_i(ag),.apply_beta_i(ab),.apply_last_i(al),
    .result_valid_o(ov),.result_ready_i(ordy),.result_tag_o(ot),.result_data_o(od),.result_last_o(ol),.scalar_configured_o(configured),
    .scalar_mean_o(mean),.scalar_inv_std_o(inv),.protocol_error_o(error));
  always@(posedge clk)if(rst_n&&|(ov&ordy))outputs<=outputs+B*L;
  task automatic begin_row;begin @(negedge clk);bv=1;#1;while(!br)@(negedge clk);@(negedge clk);bv=0;end endtask
  initial begin
    bv=0;rv=0;av=0;at={B{tag}};al='1;ordy=0;rd=0;ax=0;ag={B*L{16'h3f80}};ab=0;
    for(integer i=0;i<B*L;i++)begin rd[i]=i[0]?16'hbf80:16'h3f80;ax[i]=rd[i];end
    repeat(3)@(negedge clk);rst_n=1;begin_row();
    // Abort an active context and prove reset recovery.
    @(negedge clk);rst_n=0;repeat(2)@(negedge clk);rst_n=1;begin_row();
    @(negedge clk);rv='1;#1;if(rr!=='1)$fatal(1,"reducer not ready");@(negedge clk);rv=0;
    while(!configured)@(negedge clk);if(mean!==32'h00000000)$fatal(1,"mean mismatch %h",mean);
    @(negedge clk);av='1;#1;if(ar!=='1)$fatal(1,"apply not ready");@(negedge clk);av=0;
    while(ov!=='1)@(negedge clk);held=od;
    repeat(3)begin @(negedge clk);if(ov!=='1||od!==held)errors++;end
    ordy='1;while(outputs<B*L)@(negedge clk);@(negedge clk);
    for(integer i=0;i<B*L;i++)if(held[i*16+:16]!== (i[0]?16'hbf80:16'h3f80))errors++;
    if(error||errors)$fatal(1,"MIXED_PRECISION_PROTOCOL_TB FAIL protocol=%0d errors=%0d",error,errors);
    $display("MIXED_PRECISION_PROTOCOL_TB PASS active_reset=1 output_stall_cycles=3 outputs=%0d",outputs);$finish;
  end
  initial begin#100000;$fatal(1,"timeout");end
endmodule

