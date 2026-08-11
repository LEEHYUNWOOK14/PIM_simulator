module bank_side_pim_subsystem_tb;
    localparam PB=2, DW=256;
    logic clk=0,rst_n=0,dram_cmd_valid,dram_cmd_ready,dram_read_valid,dram_read_ready;
    logic [2:0] dram_cmd; logic [1:0] dram_bank; logic [2:0] dram_row,dram_col;
    logic [DW-1:0] dram_wdata,dram_rdata; logic [DW/8-1:0] dram_wmask; logic timing_error;
    logic prog_valid,prog_ready,start; logic [4:0] prog_addr; logic [31:0] prog_data;
    logic [31:0] context_key; logic [1:0] precision; logic [2:0] pim_row,pim_col;
    logic reg_valid,reg_bank; logic [0:0] reg_block,srf_block; logic [2:0] reg_index;
    logic [DW-1:0] reg_data,srf_data; logic srf_valid;
    logic [PB-1:0] result_valid,result_ready,cmd_error;
    logic [PB-1:0][31:0] result_key; logic [PB-1:0][2:0] result_dst;
    logic [PB-1:0][3:0] result_index; logic [PB-1:0][DW-1:0] result_data;
    logic active,done;
    integer seen;
    always #5 clk=~clk;
    bank_side_pim_subsystem #(.BANKS(4),.PIM_BLOCKS(PB),.ROWS(8),.COLS(8)) dut(
        .clk_i(clk),.rst_ni(rst_n),.dram_cmd_valid_i(dram_cmd_valid),
        .dram_cmd_ready_o(dram_cmd_ready),.dram_cmd_i(dram_cmd),.dram_bank_i(dram_bank),
        .dram_row_i(dram_row),.dram_col_i(dram_col),.dram_write_data_i(dram_wdata),
        .dram_write_mask_i(dram_wmask),.dram_read_valid_o(dram_read_valid),
        .dram_read_ready_i(dram_read_ready),.dram_read_data_o(dram_rdata),
        .dram_timing_error_o(timing_error),.crf_program_valid_i(prog_valid),
        .crf_program_ready_o(prog_ready),.crf_program_addr_i(prog_addr),
        .crf_program_data_i(prog_data),.crf_start_i(start),.context_key_i(context_key),
        .precision_i(precision),.pim_row_i(pim_row),.pim_col_i(pim_col),
        .register_write_valid_i(reg_valid),.register_write_block_i(reg_block),
        .register_write_bank_i(reg_bank),.register_write_index_i(reg_index),
        .register_write_data_i(reg_data),.srf_write_valid_i(srf_valid),
        .srf_write_block_i(srf_block),.srf_write_data_i(srf_data),
        .result_valid_o(result_valid),.result_ready_i(result_ready),.result_key_o(result_key),
        .result_destination_o(result_dst),.result_index_o(result_index),
        .result_data_o(result_data),.command_error_o(cmd_error),
        .crf_active_o(active),.crf_done_o(done));
    task automatic write_reg(input integer block_id,input logic bank_id,input logic [15:0] value);
        begin
            @(negedge clk);reg_block=block_id;reg_bank=bank_id;reg_index=0;reg_data='0;
            reg_data[15:0]=value;reg_valid=1;@(posedge clk);@(negedge clk);reg_valid=0;
        end
    endtask
    task automatic program_crf(input integer addr,input logic [31:0] word);
        begin
            @(negedge clk);prog_addr=addr;prog_data=word;prog_valid=1;
            @(posedge clk);@(negedge clk);prog_valid=0;
        end
    endtask
    always @(posedge clk) if(rst_n) begin
        if(result_valid[0]&&result_ready[0]) begin
            if(result_data[0][15:0]!==16'h4200) $fatal(1,"block0 result %h",result_data[0][15:0]);
        end
        if(result_valid[1]&&result_ready[1]) begin
            if(result_data[1][15:0]!==16'h4200) $fatal(1,"block1 result %h",result_data[1][15:0]);
        end
        seen <= seen + (result_valid[0]&&result_ready[0]) +
                       (result_valid[1]&&result_ready[1]);
    end
    initial begin
        dram_cmd_valid=0;dram_cmd=0;dram_bank=0;dram_row=0;dram_col=0;dram_wdata=0;
        dram_wmask='1;dram_read_ready=1;prog_valid=0;start=0;context_key=32'h55;
        precision=0;pim_row=0;pim_col=0;reg_valid=0;srf_valid=0;result_ready='1;seen=0;
        repeat(3)@(posedge clk);rst_n=1;
        write_reg(0,0,16'h3c00);write_reg(0,1,16'h4000);
        write_reg(1,0,16'h3c00);write_reg(1,1,16'h4000);
        program_crf(0,{4'h1,3'd5,3'd4,3'd5,19'b0});
        program_crf(1,32'hf0000000);
        @(negedge clk);start=1;@(posedge clk);@(negedge clk);start=0;
        repeat(20) begin @(posedge clk); if(done) begin
            if(seen!=2) $fatal(1,"expected 2 results got %0d",seen);
            if(|cmd_error) $fatal(1,"command error");
            $display("BANK_SIDE_PIM_SUBSYSTEM_TB PASS results[%0d]",seen);$finish;
        end end
        $fatal(1,"bank subsystem timeout");
    end
endmodule
