module logic_die_dual_link_arbiter_tb;
    localparam int INPUTS = 8;
    localparam int OUTPUTS = 2;
    localparam int KEY_WIDTH = 16;
    localparam int DATA_WIDTH = 32;
    localparam int INDEX_WIDTH = $clog2(INPUTS);

    logic clk = 0;
    logic rst_n = 0;
    logic [INPUTS-1:0] input_valid, input_ready;
    logic [INPUTS*KEY_WIDTH-1:0] input_key;
    logic [INPUTS*DATA_WIDTH-1:0] input_data;
    logic [OUTPUTS-1:0] output_valid, output_ready;
    logic [OUTPUTS*KEY_WIDTH-1:0] output_key;
    logic [OUTPUTS*DATA_WIDTH-1:0] output_data;
    logic [OUTPUTS*INDEX_WIDTH-1:0] output_source;

    always #5 clk = ~clk;

    logic_die_dual_link_arbiter #(
        .INPUTS(INPUTS), .OUTPUTS(OUTPUTS), .KEY_WIDTH(KEY_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk_i(clk), .rst_ni(rst_n), .input_valid_i(input_valid),
        .input_ready_o(input_ready), .input_key_i(input_key), .input_data_i(input_data),
        .output_valid_o(output_valid), .output_ready_i(output_ready),
        .output_key_o(output_key), .output_data_o(output_data),
        .output_source_o(output_source)
    );

    task automatic check_lane(input int lane, input int expected_source,
                              input int expected_data);
        if (!output_valid[lane] ||
            output_source[lane*INDEX_WIDTH +: INDEX_WIDTH] != expected_source ||
            output_data[lane*DATA_WIDTH +: DATA_WIDTH] != expected_data)
            $fatal(1, "lane %0d mismatch: source=%0d data=%0d", lane,
                   output_source[lane*INDEX_WIDTH +: INDEX_WIDTH],
                   output_data[lane*DATA_WIDTH +: DATA_WIDTH]);
    endtask

    initial begin
        input_valid = '0;
        input_key = '0;
        input_data = '0;
        output_ready = '1;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        input_valid[0] = 1'b1;
        input_valid[3] = 1'b1;
        input_valid[7] = 1'b1;
        input_data[0*DATA_WIDTH +: DATA_WIDTH] = 100;
        input_data[3*DATA_WIDTH +: DATA_WIDTH] = 103;
        input_data[7*DATA_WIDTH +: DATA_WIDTH] = 107;
        #1;
        check_lane(0, 0, 100);
        check_lane(1, 3, 103);
        @(posedge clk);

        @(negedge clk);
        input_valid[0] = 1'b0;
        input_valid[3] = 1'b0;
        #1;
        check_lane(0, 7, 107);
        if (output_valid[1]) $fatal(1, "single input unexpectedly occupied lane 1");
        @(posedge clk);

        @(negedge clk);
        input_valid = '0;
        input_valid[1] = 1'b1;
        input_valid[2] = 1'b1;
        input_data[1*DATA_WIDTH +: DATA_WIDTH] = 101;
        input_data[2*DATA_WIDTH +: DATA_WIDTH] = 102;
        output_ready = 2'b01;
        #1;
        if (|input_ready) $fatal(1, "partial output readiness released an input");
        check_lane(0, 1, 101);
        check_lane(1, 2, 102);
        repeat (2) @(posedge clk);
        #1;
        check_lane(0, 1, 101);
        check_lane(1, 2, 102);

        @(negedge clk);
        output_ready = 2'b11;
        @(posedge clk);
        $display("LOGIC_DIE_DUAL_LINK_ARBITER_TB PASS");
        $finish;
    end
endmodule
