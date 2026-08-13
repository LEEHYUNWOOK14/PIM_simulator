module mixed_precision_global_pipe_tb;
  logic clk=0,rst_n=0,iv,ir,ov,ordy;always#5 clk=~clk;logic[15:0]it,ot;logic[15:0][31:0]ps,pq;logic[31:0]sum,sq;integer cycles=0;
  mixed_precision_global_reducer16_pipe dut(.clk_i(clk),.rst_ni(rst_n),.input_valid_i(iv),.input_ready_o(ir),.input_tag_i(it),.partial_sum_i(ps),.partial_sumsq_i(pq),.output_valid_o(ov),.output_ready_i(ordy),.output_tag_o(ot),.sum_o(sum),.sumsq_o(sq));
  always@(posedge clk)if(rst_n)cycles++;
  function automatic[31:0]f(input integer n);begin case(n)
    1:f=32'h3f800000;2:f=32'h40000000;3:f=32'h40400000;4:f=32'h40800000;5:f=32'h40a00000;6:f=32'h40c00000;7:f=32'h40e00000;8:f=32'h41000000;
    9:f=32'h41100000;10:f=32'h41200000;11:f=32'h41300000;12:f=32'h41400000;13:f=32'h41500000;14:f=32'h41600000;15:f=32'h41700000;default:f=32'h41800000;endcase end endfunction
  initial begin iv=0;ordy=0;it=16'h55aa;for(integer i=0;i<16;i++)begin ps[i]=f(i+1);pq[i]=f(i+1);end
    repeat(3)@(negedge clk);rst_n=1;@(negedge clk);iv=1;#1;if(!ir)$fatal(1,"not ready");@(negedge clk);iv=0;
    while(!ov)@(negedge clk);if(sum!==32'h43080000||sq!==32'h43080000||ot!==it)$fatal(1,"bad result sum=%h sq=%h tag=%h",sum,sq,ot);
    repeat(3)@(negedge clk);if(!ov||sum!==32'h43080000)$fatal(1,"backpressure hold failed");ordy=1;@(negedge clk);
    $display("MIXED_PRECISION_GLOBAL_PIPE_TB PASS latency_cycles=%0d stall=3",cycles);$finish;
  end
endmodule
