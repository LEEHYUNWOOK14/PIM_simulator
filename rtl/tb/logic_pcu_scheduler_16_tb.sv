module logic_pcu_scheduler_16_tb;
    localparam N=16,DW=256,TW=64;
    logic clk=0,rst_n=0; always #5 clk=~clk;
    logic [N-1:0] req_valid,req_ready,resp_valid,resp_ready,busy;
    logic [N-1:0][3:0] opcode; logic [N-1:0][1:0] precision;
    logic [N-1:0][TW-1:0] req_tag,resp_tag;
    logic [N-1:0][DW-1:0] src0,src1,src2,accum,resp_data;
    logic [N-1:0][3:0] grant;
    logic [DW-1:0] one_vector,two_vector;
    logic_pcu_scheduler #(.PCUS(N),.ISSUE_PORTS(N),.DATA_WIDTH(DW),.TAG_WIDTH(TW)) dut(
        .clk_i(clk),.rst_ni(rst_n),.request_valid_i(req_valid),.request_ready_o(req_ready),
        .request_opcode_i(opcode),.request_precision_i(precision),.request_tag_i(req_tag),
        .request_src0_i(src0),.request_src1_i(src1),.request_src2_i(src2),
        .request_accum_i(accum),.response_valid_o(resp_valid),.response_ready_i(resp_ready),
        .response_tag_o(resp_tag),.response_data_o(resp_data),.granted_pcu_o(grant),.busy_o(busy));
    initial begin
        req_valid=0;resp_ready=0;opcode={N{4'h1}};precision='0;req_tag='0;src2='0;accum='0;
        one_vector='0;two_vector='0;one_vector[15:0]=16'h3c00;two_vector[15:0]=16'h4000;
        src0={N{one_vector}};src1={N{two_vector}};req_tag[15]=15;
        repeat(3)@(posedge clk);rst_n=1;
        @(negedge clk);req_valid='1;#1;if(req_ready!=='1)$fatal(1,"not all 16 PCUs ready %h",req_ready);
        @(posedge clk);@(negedge clk);req_valid=0;
        repeat(2)@(posedge clk);#1;
        if(resp_valid!=='1)$fatal(1,"not all 16 responses valid %h",resp_valid);
        if(resp_data[0][15:0]!==16'h4200||resp_data[15][15:0]!==16'h4200)
            $fatal(1,"16-PCU arithmetic mismatch");
        if(resp_tag[0]!=0||resp_tag[15]!=15)$fatal(1,"16-PCU tags mismatch");
        repeat(3)begin @(posedge clk);#1;if(resp_valid!=='1)$fatal(1,"response lost under stall");end
        @(negedge clk);resp_ready='1;@(posedge clk);@(negedge clk);
        if(resp_valid!=='0)$fatal(1,"responses did not retire");
        $display("LOGIC_PCU_SCHEDULER_16_TB PASS simultaneous[16]");$finish;
    end
    initial begin #3000;$fatal(1,"16-PCU timeout");end
endmodule
