module bank_normalization_pipelined_vector_reducer_tb #(
    parameter int LANES = 4,
    parameter int DATA_FORMAT = 0
);
    logic clk=0, rst_n=0, begin_valid, begin_ready, vector_valid, vector_ready;
    logic [15:0] begin_tag, begin_vector_count;
    logic [LANES-1:0][15:0] vector_data;
    logic result_valid, result_ready, protocol_error;
    logic [15:0] result_tag, result_sum, result_sumsq;
    integer cycle, first_accept_cycle, second_accept_cycle, result_cycle;
    always #5 clk=~clk;
    always @(posedge clk) if(rst_n) cycle<=cycle+1;

    bank_normalization_pipelined_vector_reducer #(.LANES(LANES),.DATA_FORMAT(DATA_FORMAT)) dut(
        .clk_i(clk),.rst_ni(rst_n),.begin_valid_i(begin_valid),.begin_ready_o(begin_ready),
        .begin_tag_i(begin_tag),.begin_vector_count_i(begin_vector_count),
        .vector_valid_i(vector_valid),.vector_ready_o(vector_ready),.vector_data_i(vector_data),
        .result_valid_o(result_valid),.result_ready_i(result_ready),.result_tag_o(result_tag),
        .result_sum_o(result_sum),.result_sumsq_o(result_sumsq),.protocol_error_o(protocol_error));

    function automatic [15:0] expected_sum;
        if(DATA_FORMAT) case(LANES)
            2:expected_sum=16'h40c0;4:expected_sum=16'h4140;
            8:expected_sum=16'h41c0;default:expected_sum=16'h4240;
        endcase else case(LANES)
            2:expected_sum=16'h4600;4:expected_sum=16'h4a00;
            8:expected_sum=16'h4e00;default:expected_sum=16'h5200;
        endcase
    endfunction
    function automatic [15:0] expected_sumsq;
        if(DATA_FORMAT) case(LANES)
            2:expected_sumsq=16'h4120;4:expected_sumsq=16'h41a0;
            8:expected_sumsq=16'h4220;default:expected_sumsq=16'h42a0;
        endcase else case(LANES)
            2:expected_sumsq=16'h4900;4:expected_sumsq=16'h4d00;
            8:expected_sumsq=16'h5100;default:expected_sumsq=16'h5500;
        endcase
    endfunction

    initial begin
        begin_valid=0;begin_tag=0;begin_vector_count=0;vector_valid=0;vector_data='0;
        result_ready=1;cycle=0;first_accept_cycle=-1;second_accept_cycle=-1;result_cycle=-1;
        repeat(3)@(negedge clk);rst_n=1;
        @(negedge clk);begin_valid=1;begin_tag=16'h5678;begin_vector_count=2;
        @(negedge clk);begin_valid=0;
        for(integer lane=0;lane<LANES;lane++)vector_data[lane]=DATA_FORMAT?16'h3f80:16'h3c00;
        vector_valid=1;
        @(posedge clk);if(!vector_ready)$fatal(1,"first vector not ready");first_accept_cycle=cycle;
        @(negedge clk);for(integer lane=0;lane<LANES;lane++)vector_data[lane]=16'h4000;
        @(posedge clk);if(!vector_ready)$fatal(1,"second vector not ready");second_accept_cycle=cycle;
        @(negedge clk);vector_valid=0;
        if(second_accept_cycle-first_accept_cycle!=1)$fatal(1,"II is not 1");
        while(!result_valid)@(negedge clk);
        result_cycle=cycle;
        if(result_tag!==16'h5678||result_sum!==expected_sum()||result_sumsq!==expected_sumsq())
            $fatal(1,"bad result tag=%h sum=%h sumsq=%h",result_tag,result_sum,result_sumsq);
        result_ready=0; repeat(2)begin @(negedge clk);if(!result_valid)$fatal(1,"stall lost valid");end
        result_ready=1;@(negedge clk);
        if(protocol_error)$fatal(1,"unexpected protocol error");
        $display("BANK_NORMALIZATION_PIPELINED_VECTOR_REDUCER_TB PASS format=%0d lanes=%0d II=1 latency_from_last=%0d",
                 DATA_FORMAT,LANES,result_cycle-second_accept_cycle);
        $finish;
    end
endmodule
