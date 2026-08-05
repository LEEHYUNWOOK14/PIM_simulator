module bank_local_fp16_reduction_tb;
    localparam int BANKS=1, ENTRIES=4, KEY_WIDTH=16, LANES=16;
    localparam int DATA_WIDTH=LANES*16, SLOT_WIDTH=$clog2(ENTRIES);
    logic clk=0, rst_n=0;
    logic [BANKS-1:0] update_valid,update_ready,update_first,update_last;
    logic [BANKS-1:0][KEY_WIDTH-1:0] update_key;
    logic [BANKS-1:0][SLOT_WIDTH-1:0] update_slot;
    logic [BANKS-1:0][DATA_WIDTH-1:0] update_partial,final_data;
    logic [BANKS-1:0] final_valid,final_ready,protocol_error;
    logic [BANKS-1:0][KEY_WIDTH-1:0] final_key;
    always #5 clk=~clk;
    bank_local_fp16_reduction #(.BANKS(BANKS),.ENTRIES_PER_BANK(ENTRIES),
        .KEY_WIDTH(KEY_WIDTH),.LANES(LANES),.SLOT_WIDTH(SLOT_WIDTH)) dut(
        .clk_i(clk),.rst_ni(rst_n),.update_valid_i(update_valid),
        .update_ready_o(update_ready),.update_key_i(update_key),
        .update_slot_i(update_slot),.update_partial_i(update_partial),
        .update_first_i(update_first),.update_last_i(update_last),
        .final_valid_o(final_valid),.final_ready_i(final_ready),
        .final_key_o(final_key),.final_data_o(final_data),
        .protocol_error_o(protocol_error));
    task automatic send_vector(input logic [15:0] value,input bit first,last);
        @(negedge clk);
        for(int lane=0;lane<LANES;lane++) update_partial[0][lane*16+:16]=value;
        update_valid[0]=1; update_first[0]=first; update_last[0]=last;
        do @(posedge clk); while(!update_ready[0]);
        @(negedge clk); update_valid[0]=0;
    endtask
    initial begin
        update_valid=0;update_key=16'h55aa;update_slot=1;update_partial=0;
        update_first=0;update_last=0;final_ready=1;
        repeat(2) @(posedge clk);rst_n=1;
        send_vector(16'h3c00,1,0);send_vector(16'h4000,0,0);
        send_vector(16'h4200,0,1);@(posedge clk);
        if(!final_valid[0]||final_key[0]!=16'h55aa)$fatal(1,"missing final");
        for(int lane=0;lane<LANES;lane++)
            if(final_data[0][lane*16+:16]!=16'h4600)
                $fatal(1,"lane %0d got %h",lane,final_data[0][lane*16+:16]);
        $display("BANK_LOCAL_FP16_REDUCTION_TB PASS lanes[%0d] sum[6.0]",LANES);
        $finish;
    end
endmodule
