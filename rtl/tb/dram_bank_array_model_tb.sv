module dram_bank_array_model_tb;
    import pim_rtl_pkg::*;
    logic clk=0, rst_n=0, cmd_valid, cmd_ready, read_valid, read_ready, timing_error;
    logic [2:0] cmd;
    logic [1:0] bank; logic [2:0] row, col;
    logic [31:0] wdata, rdata; logic [3:0] wmask;
    always #5 clk=~clk;
    dram_bank_array_model #(.BANKS(4),.ROWS(8),.COLS(8),.DATA_WIDTH(32),
        .TRCD_RD(2),.TRCD_WR(2),.TRAS(3),.TRP(2),.READ_LATENCY(2)) dut(
        .clk_i(clk),.rst_ni(rst_n),.cmd_valid_i(cmd_valid),.cmd_ready_o(cmd_ready),
        .cmd_i(cmd),.bank_i(bank),.row_i(row),.col_i(col),.write_data_i(wdata),
        .write_mask_i(wmask),.read_valid_o(read_valid),.read_ready_i(read_ready),
        .read_data_o(rdata),.timing_error_o(timing_error));
    task automatic send(input logic [2:0] op);
        begin cmd=op; cmd_valid=1; while(!cmd_ready) @(posedge clk); @(posedge clk); cmd_valid=0; end
    endtask
    initial begin
        cmd_valid=0; cmd=0; bank=1; row=3; col=2; wdata=32'hdeadbeef; wmask='1; read_ready=1;
        repeat(2) @(posedge clk); rst_n=1; @(posedge clk);
        send(DRAM_CMD_ACT);
        cmd=DRAM_CMD_RD; cmd_valid=1; #1;
        if (!timing_error || cmd_ready) $fatal(1,"early read was not rejected");
        cmd_valid=0; repeat(2) @(posedge clk);
        send(DRAM_CMD_WR); send(DRAM_CMD_RD);
        wait(read_valid); #1; if(rdata!==32'hdeadbeef) $fatal(1,"read mismatch %h",rdata);
        @(posedge clk); repeat(2) @(posedge clk); send(DRAM_CMD_PRE);
        $display("DRAM_BANK_ARRAY_MODEL_TB PASS"); $finish;
    end
endmodule
