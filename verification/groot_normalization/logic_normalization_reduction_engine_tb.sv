module logic_normalization_reduction_engine_tb;
    localparam int BANKS=16;
    logic clk=0,rst_n=0;
    logic begin_valid,begin_ready,begin_mode;
    logic [15:0] begin_tag,begin_mask,begin_inv,begin_eps;
    logic partial_valid,partial_ready;
    logic [3:0] partial_bank;
    logic [15:0] partial_tag,partial_sum,partial_sumsq;
    logic response_valid,response_ready,response_mode,response_clamped;
    logic [15:0] response_tag,response_mean,response_inv;
    logic duplicate_error,context_error;
    logic [127:0] meta[0:511];
    logic [31:0] partials[0:8191];
    integer tx,bank,mismatches,error_checks;

    always #5 clk=~clk;
    logic_normalization_reduction_engine #(.BANKS(BANKS),.TAG_WIDTH(16)) dut(
        .clk_i(clk),.rst_ni(rst_n),.begin_valid_i(begin_valid),.begin_ready_o(begin_ready),
        .begin_rms_norm_i(begin_mode),.begin_tag_i(begin_tag),
        .begin_expected_mask_i(begin_mask),.begin_inv_hidden_i(begin_inv),
        .begin_epsilon_i(begin_eps),.partial_valid_i(partial_valid),
        .partial_ready_o(partial_ready),.partial_bank_i(partial_bank),
        .partial_tag_i(partial_tag),.partial_sum_i(partial_sum),
        .partial_sumsq_i(partial_sumsq),.response_valid_o(response_valid),
        .response_ready_i(response_ready),.response_rms_norm_o(response_mode),
        .response_tag_o(response_tag),.response_mean_o(response_mean),
        .response_inv_std_o(response_inv),.response_variance_clamped_o(response_clamped),
        .duplicate_error_o(duplicate_error),.context_error_o(context_error));

    task automatic send_begin(input integer index);
        begin
            begin_valid=1;begin_mode=meta[index][127];begin_tag=index;
            begin_mask=meta[index][111:96];begin_inv=meta[index][95:80];
            begin_eps=meta[index][79:64];
            do @(posedge clk);while(!begin_ready);
            @(negedge clk);begin_valid=0;
        end
    endtask
    task automatic send_partial(input integer index,input integer bank_index,
                                input logic [15:0] tag_value);
        begin
            partial_valid=1;partial_bank=bank_index;partial_tag=tag_value;
            partial_sum=partials[index*16+bank_index][31:16];
            partial_sumsq=partials[index*16+bank_index][15:0];
            do @(posedge clk);while(!partial_ready);
            @(negedge clk);partial_valid=0;
        end
    endtask

    initial begin
        $readmemh("verification/groot_normalization/normalization_reduction_meta.hex",meta);
        $readmemh("verification/groot_normalization/normalization_reduction_partials.hex",partials);
        begin_valid=0;partial_valid=0;response_ready=0;begin_mode=0;begin_tag=0;
        begin_mask=0;begin_inv=0;begin_eps=0;partial_bank=0;partial_tag=0;
        partial_sum=0;partial_sumsq=0;mismatches=0;error_checks=0;
        repeat(3)@(posedge clk);@(negedge clk);rst_n=1;
        for(tx=0;tx<512;tx=tx+1)begin
            if(tx%64==0)$display("REDUCTION progress tx=%0d time=%0t",tx,$time);
            send_begin(tx);
            if(tx==0)begin
                partial_valid=1;partial_bank=0;partial_tag=16'hffff;
                partial_sum=partials[0][31:16];partial_sumsq=partials[0][15:0];
                @(posedge clk);@(negedge clk);partial_valid=0;
                if(!context_error)begin $display("REDUCTION FAIL context not reported");mismatches=mismatches+1;end
                else error_checks=error_checks+1;
            end
            for(bank=0;bank<16;bank=bank+1)if(meta[tx][96+bank])begin
                send_partial(tx,bank,tx[15:0]);
                if(tx==0&&bank==0)begin
                    partial_valid=1;partial_bank=bank;partial_tag=tx;
                    partial_sum=partials[bank][31:16];partial_sumsq=partials[bank][15:0];
                    @(posedge clk);@(negedge clk);partial_valid=0;
                    if(!duplicate_error)begin $display("REDUCTION FAIL duplicate not reported");mismatches=mismatches+1;end
                    else error_checks=error_checks+1;
                end
            end
            response_ready=0;
            wait(response_valid);repeat(2)begin
                @(posedge clk);@(negedge clk);
                if(!response_valid)begin $display("REDUCTION FAIL response stall");mismatches=mismatches+1;end
            end
            if(response_mode!==meta[tx][127]||response_tag!==tx[15:0]||
               response_clamped!==meta[tx][31]||response_mean!==meta[tx][63:48]||
               response_inv!==meta[tx][47:32])begin
                if(mismatches<20)$display("REDUCTION FAIL tx=%0d mode=%b/%b mean=%h/%h inv=%h/%h",
                    tx,response_mode,meta[tx][127],response_mean,meta[tx][63:48],
                    response_inv,meta[tx][47:32]);
                mismatches=mismatches+1;
            end
            response_ready=1;@(posedge clk);@(negedge clk);response_ready=0;
        end
        if(mismatches)$fatal(1,"LOGIC_NORMALIZATION_REDUCTION_ENGINE_TB FAIL mismatches=%0d",mismatches);
        $display("LOGIC_NORMALIZATION_REDUCTION_ENGINE_TB PASS transactions=512 duplicate_checks=%0d",error_checks);
        $finish;
    end
endmodule
