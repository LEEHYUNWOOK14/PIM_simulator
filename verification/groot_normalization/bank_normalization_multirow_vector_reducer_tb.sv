module bank_normalization_multirow_vector_reducer_tb #(
    parameter int FIFO_DEPTH=8
);
    localparam int LANES=4,ROWS=FIFO_DEPTH;
    logic clk=0,rst_n=0,begin_valid,begin_ready,vector_valid,vector_ready;
    logic[15:0]begin_tag,begin_vector_count;
    logic[LANES-1:0][15:0]vector_data;
    logic result_valid,result_ready,protocol_error;
    logic[15:0]result_tag,result_sum,result_sumsq;
    integer cycle,last_vector_cycle,first_result_cycle,results;
    logic[15:0]held_tag,held_sum,held_sumsq;
    always#5 clk=~clk;always@(posedge clk)if(rst_n)begin
      cycle<=cycle+1;if(result_valid&&first_result_cycle<0)first_result_cycle<=cycle;
    end
    bank_normalization_multirow_vector_reducer #(.LANES(LANES),.RESULT_FIFO_DEPTH(FIFO_DEPTH))dut(
      .clk_i(clk),.rst_ni(rst_n),.begin_valid_i(begin_valid),.begin_ready_o(begin_ready),
      .begin_tag_i(begin_tag),.begin_vector_count_i(begin_vector_count),
      .vector_valid_i(vector_valid),.vector_ready_o(vector_ready),.vector_data_i(vector_data),
      .result_valid_o(result_valid),.result_ready_i(result_ready),.result_tag_o(result_tag),
      .result_sum_o(result_sum),.result_sumsq_o(result_sumsq),.protocol_error_o(protocol_error));
    initial begin
      begin_valid=0;begin_tag=0;begin_vector_count=1;vector_valid=0;vector_data='0;
      result_ready=0;cycle=0;last_vector_cycle=-1;first_result_cycle=-1;results=0;
      repeat(3)@(negedge clk);rst_n=1;
      @(negedge clk);begin_valid=1;begin_tag=16'h1000;
      @(posedge clk);if(!begin_ready)$fatal(1,"initial begin rejected");
      for(integer row=0;row<ROWS;row++)begin
        @(negedge clk);vector_valid=1;
        for(integer lane=0;lane<LANES;lane++)vector_data[lane]=(row%2)?16'h4000:16'h3c00;
        if(row+1<ROWS)begin begin_valid=1;begin_tag=16'h1000+row+1;end
        else begin_valid=0;
        @(posedge clk);
        if(!vector_ready)$fatal(1,"row %0d vector bubble",row);
        if(row+1<ROWS&&!begin_ready)$fatal(1,"row %0d overlap begin rejected",row);
        if(row==ROWS-1)last_vector_cycle=cycle;
      end
      @(negedge clk);vector_valid=0;begin_valid=0;
      while(!result_valid)@(negedge clk);
      held_tag=result_tag;held_sum=result_sum;held_sumsq=result_sumsq;
      repeat(3)begin @(negedge clk);if(!result_valid||result_tag!==held_tag||
        result_sum!==held_sum||result_sumsq!==held_sumsq)$fatal(1,"stall payload changed");end
      if(held_tag!==16'h1000||held_sum!==16'h4400||held_sumsq!==16'h4400)
        $fatal(1,"first stalled result bad");
      results=1;
      result_ready=1;
      while(results<ROWS)begin
        @(negedge clk);
        if(result_valid)begin
          if(result_tag!==16'h1000+results)$fatal(1,"result order/tag %h",result_tag);
          if(results%2)begin
            if(result_sum!==16'h4800||result_sumsq!==16'h4c00)$fatal(1,"row2 values bad");
          end else if(result_sum!==16'h4400||result_sumsq!==16'h4400)$fatal(1,"row1 values bad");
          results=results+1;
        end
      end
      if(protocol_error)$fatal(1,"unexpected protocol error");
      $display("BANK_NORMALIZATION_MULTIROW_VECTOR_REDUCER_TB PASS rows=%0d row_II=1 first_result_before_last=%0d",
        ROWS,first_result_cycle<last_vector_cycle);
      $finish;
    end
endmodule
