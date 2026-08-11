module logic_control_network_tb;
    localparam CH=4,DW=256;
    logic clk=0,rst_n=0;
    always #5 clk=~clk;
    logic ep_begin,ep_begin_ready,fill_valid,exec_done,release_valid,ep_active,unexpected;
    logic [15:0] ep_id,release_id; logic [CH-1:0] ep_expected,ready_mask; logic [1:0] fill_ch;
    logic wb_wvalid,wb_wready,wb_rvalid,wb_rready,wb_resp_valid,wb_resp_ready,ctx_commit,ctx_valid;
    logic [2:0] wb_waddr,wb_raddr; logic [DW-1:0] wb_wdata,wb_rdata; logic [DW/8-1:0] wb_mask;
    logic [15:0] ctx_id,resident_ctx;
    logic red_begin,red_begin_ready,partial_valid,partial_ready,red_result_valid,red_result_ready;
    logic [31:0] red_begin_key,partial_key,red_key; logic [CH-1:0] red_expected;
    logic [1:0] partial_ch; logic [DW-1:0] partial_data,red_data; logic dup,ctx_err;
    logic [CH-1:0] tsv_in_valid,tsv_in_ready; logic [CH-1:0][31:0] tsv_in_key;
    logic [CH-1:0][DW-1:0] tsv_in_data; logic [1:0] tsv_out_valid,tsv_out_ready;
    logic [1:0][31:0] tsv_out_key; logic [1:0][DW-1:0] tsv_out_data; logic [1:0][1:0] tsv_out_ch;
    logic_epoch_barrier #(.CHANNELS(CH)) epoch_dut(.clk_i(clk),.rst_ni(rst_n),
        .begin_valid_i(ep_begin),.begin_ready_o(ep_begin_ready),.begin_epoch_i(ep_id),
        .begin_expected_mask_i(ep_expected),.fill_done_valid_i(fill_valid),
        .fill_done_channel_i(fill_ch),.execution_done_i(exec_done),.release_valid_o(release_valid),
        .release_epoch_o(release_id),.ready_mask_o(ready_mask),.active_o(ep_active),
        .unexpected_channel_error_o(unexpected));
    logic_shared_buffer #(.DATA_WIDTH(DW),.BYTES(256)) wb_dut(.clk_i(clk),.rst_ni(rst_n),
        .write_valid_i(wb_wvalid),.write_ready_o(wb_wready),.write_addr_i(wb_waddr),
        .write_data_i(wb_wdata),.write_mask_i(wb_mask),.read_valid_i(wb_rvalid),
        .read_ready_o(wb_rready),.read_addr_i(wb_raddr),.response_valid_o(wb_resp_valid),
        .response_ready_i(wb_resp_ready),.response_data_o(wb_rdata),
        .context_commit_i(ctx_commit),.context_id_i(ctx_id),.context_valid_o(ctx_valid),
        .resident_context_o(resident_ctx));
    cross_channel_reduction #(.CHANNELS(CH),.DATA_WIDTH(DW)) red_dut(.clk_i(clk),.rst_ni(rst_n),
        .begin_valid_i(red_begin),.begin_ready_o(red_begin_ready),.begin_key_i(red_begin_key),
        .begin_expected_mask_i(red_expected),.partial_valid_i(partial_valid),
        .partial_ready_o(partial_ready),.partial_channel_i(partial_ch),.partial_key_i(partial_key),
        .partial_data_i(partial_data),.result_valid_o(red_result_valid),
        .result_ready_i(red_result_ready),.result_key_o(red_key),.result_data_o(red_data),
        .duplicate_error_o(dup),.context_error_o(ctx_err));
    channel_tsv_interconnect #(.CHANNELS(CH),.DATA_WIDTH(DW),.KEY_WIDTH(32)) tsv_dut(
        .clk_i(clk),.rst_ni(rst_n),.input_valid_i(tsv_in_valid),.input_ready_o(tsv_in_ready),
        .input_key_i(tsv_in_key),.input_data_i(tsv_in_data),.output_valid_o(tsv_out_valid),
        .output_ready_i(tsv_out_ready),.output_key_o(tsv_out_key),.output_data_o(tsv_out_data),
        .output_channel_o(tsv_out_ch));
    task automatic fill(input integer ch);
        begin @(negedge clk);fill_ch=ch;fill_valid=1;@(posedge clk);@(negedge clk);fill_valid=0;end
    endtask
    task automatic partial(input integer ch,input logic [15:0] value);
        begin @(negedge clk);partial_ch=ch;partial_data='0;partial_data[15:0]=value;partial_valid=1;
        do @(posedge clk);while(!partial_ready);@(negedge clk);partial_valid=0;end
    endtask
    initial begin
        ep_begin=0;fill_valid=0;exec_done=0;ep_id=16'd9;ep_expected=4'b1011;fill_ch=0;
        wb_wvalid=0;wb_rvalid=0;wb_resp_ready=1;ctx_commit=0;ctx_id=16'd7;wb_waddr=2;wb_raddr=2;
        wb_wdata='0;wb_wdata[31:0]=32'hcafebabe;wb_mask='1;
        red_begin=0;partial_valid=0;red_result_ready=1;red_begin_key=32'h44;partial_key=32'h44;
        red_expected=4'b1011;partial_ch=0;partial_data=0;
        tsv_in_valid=0;tsv_in_key=0;tsv_in_data=0;tsv_out_ready=0;
        repeat(3)@(posedge clk);rst_n=1;
        @(negedge clk);ep_begin=1;@(posedge clk);@(negedge clk);ep_begin=0;
        fill(0);fill(1);if(release_valid)$fatal(1,"epoch released early");fill(3);
        @(posedge clk);if(!release_valid||release_id!=9)$fatal(1,"epoch did not release");
        @(negedge clk);exec_done=1;@(posedge clk);@(negedge clk);exec_done=0;
        @(negedge clk);wb_wvalid=1;ctx_commit=1;@(posedge clk);@(negedge clk);wb_wvalid=0;ctx_commit=0;
        if(!ctx_valid||resident_ctx!=7)$fatal(1,"weight context mismatch");
        wb_rvalid=1;do @(posedge clk);while(!wb_rready);@(negedge clk);wb_rvalid=0;
        wait(wb_resp_valid);if(wb_rdata[31:0]!==32'hcafebabe)$fatal(1,"weight read mismatch");
        @(negedge clk);red_begin=1;@(posedge clk);@(negedge clk);red_begin=0;
        partial(0,16'h3c00);partial(1,16'h4000);partial(3,16'h4200);
        wait(red_result_valid);if(red_data[15:0]!==16'h4600)$fatal(1,"reduction mismatch %h",red_data[15:0]);
        @(negedge clk);tsv_in_valid=4'b0011;tsv_in_key[0]=10;tsv_in_key[1]=11;
        tsv_in_data[0][31:0]=32'ha0;tsv_in_data[1][31:0]=32'hb1;tsv_out_ready=2'b10;
        @(posedge clk);#1;if(tsv_in_ready!==4'b0010)$fatal(1,"independent lane ready mismatch %b",tsv_in_ready);
        @(negedge clk);tsv_in_valid=4'b0001;tsv_out_ready=2'b11;
        @(posedge clk);#1;if(!tsv_out_valid[0]||tsv_out_data[0][31:0]!==32'ha0)
            $fatal(1,"stalled lane payload lost");
        if(unexpected||dup||ctx_err)$fatal(1,"unexpected protocol error");
        $display("LOGIC_CONTROL_NETWORK_TB PASS");$finish;
    end
    initial begin #5000;$fatal(1,"control network timeout");end
endmodule
