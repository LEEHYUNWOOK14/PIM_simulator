module mixed_precision_interleaved_reducer_tb;
  logic clk=0,rst_n=0,bv,br,vv,vr,ov,ordy,error;always#5 clk=~clk;
  logic[15:0]tag,count;logic[3:0][15:0]data;logic[15:0]ot;logic[31:0]sum,sumsq;integer errors=0,cycles=0;
  mixed_precision_bank_reducer4_interleaved dut(.clk_i(clk),.rst_ni(rst_n),.begin_valid_i(bv),.begin_ready_o(br),.begin_tag_i(tag),.begin_vector_count_i(count),.vector_valid_i(vv),.vector_ready_o(vr),.vector_data_i(data),.result_valid_o(ov),.result_ready_i(ordy),.result_tag_o(ot),.result_sum_o(sum),.result_sumsq_o(sumsq),.protocol_error_o(error));
  always@(posedge clk)if(rst_n)cycles++;
  function automatic[15:0]bf(input integer v);case(v)1:bf=16'h3f80;2:bf=16'h4000;3:bf=16'h4040;4:bf=16'h4080;5:bf=16'h40a0;6:bf=16'h40c0;7:bf=16'h40e0;default:bf=16'h4100;endcase endfunction
  task automatic run_case(input integer vectors,input logic[31:0]esum,input logic[31:0]esq);begin
    count=vectors;tag=16'h4000+vectors;@(negedge clk);bv=1;#1;if(!br)$fatal(1,"begin not ready");@(negedge clk);bv=0;vv=1;
    for(integer v=1;v<=vectors;v++)begin data={4{bf(v)}};#1;if(!vr)$fatal(1,"vector not ready v=%0d",v);@(negedge clk);end
    vv=0;while(!ov)@(negedge clk);if(sum!==esum||sumsq!==esq||ot!==tag)begin $display("case=%0d sum=%h/%h sq=%h/%h",vectors,sum,esum,sumsq,esq);errors++;end
    repeat(2)@(negedge clk);ordy=1;@(negedge clk);ordy=0;
  end endtask
  initial begin bv=0;vv=0;ordy=0;tag=0;count=0;data=0;repeat(3)@(negedge clk);rst_n=1;
    run_case(1,32'h40800000,32'h40800000);run_case(6,32'h42a80000,32'h43b60000);run_case(8,32'h43100000,32'h444c0000);
    if(error||errors)$fatal(1,"INTERLEAVED_REDUCER_TB FAIL error=%0d mismatches=%0d",error,errors);
    $display("MIXED_PRECISION_INTERLEAVED_REDUCER_TB PASS cases=3 II=1 cycles=%0d",cycles);$finish;
  end
  initial begin#100000;$fatal(1,"timeout");end
endmodule

