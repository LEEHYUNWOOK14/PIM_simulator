module logic_die_link_arbiter_tb;
    localparam int INPUTS = 8;
    localparam int KEY_WIDTH = 16;
    localparam int DATA_WIDTH = 32;
    localparam int INDEX_WIDTH = $clog2(INPUTS);

    logic clk = 0;
    logic rst_n = 0;
    logic [INPUTS-1:0] input_valid, input_ready;
    logic [INPUTS*KEY_WIDTH-1:0] input_key;
    logic [INPUTS*DATA_WIDTH-1:0] input_data;
    logic [INPUTS-1:0] input_route;
    logic output_valid, output_ready;
    logic [KEY_WIDTH-1:0] output_key;
    logic [DATA_WIDTH-1:0] output_data;
    logic [INDEX_WIDTH-1:0] output_source;
    logic output_route;

    always #5 clk = ~clk;

    logic_die_link_arbiter #(
        .INPUTS(INPUTS), .KEY_WIDTH(KEY_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk_i(clk), .rst_ni(rst_n), .input_valid_i(input_valid),
        .input_ready_o(input_ready), .input_key_i(input_key), .input_data_i(input_data),
        .input_route_i(input_route),
        .output_valid_o(output_valid), .output_ready_i(output_ready),
        .output_key_o(output_key), .output_data_o(output_data),
        .output_source_o(output_source),.output_route_o(output_route)
    );

    task automatic expect_transfer(input int expected_source, input int expected_data);
        #1;
        if (!output_valid || output_source != expected_source || output_data != expected_data)
            $fatal(1, "unexpected arbitration result: source=%0d data=%0d",
                   output_source, output_data);
        @(posedge clk);
    endtask

    initial begin
        input_valid = '0;
        input_key = '0;
        input_data = '0;
        input_route = '0;
        output_ready = 1'b1;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        input_valid[0] = 1'b1;
        input_valid[1] = 1'b1;
        input_key[0*KEY_WIDTH +: KEY_WIDTH] = 16'h1000;
        input_key[1*KEY_WIDTH +: KEY_WIDTH] = 16'h1001;
        input_data[0*DATA_WIDTH +: DATA_WIDTH] = 100;
        input_data[1*DATA_WIDTH +: DATA_WIDTH] = 101;
        expect_transfer(0, 100);
        @(negedge clk);
        input_valid[0] = 1'b0;
        expect_transfer(1, 101);
        @(negedge clk);
        input_valid[1] = 1'b0;

        input_valid[7] = 1'b1;
        input_data[7*DATA_WIDTH +: DATA_WIDTH] = 107;
        input_route[7] = 1'b1;
        output_ready = 1'b0;
        #1;
        if (!output_valid || input_ready[7])
            $fatal(1, "backpressure did not hold source 7");
        repeat (2) @(posedge clk);
        input_route[7] = 1'b0;
        #1;
        if(!output_route)$fatal(1,"stalled transaction route metadata changed");
        output_ready = 1'b1;
        expect_transfer(7, 107);

        $display("LOGIC_DIE_LINK_ARBITER_TB PASS");
        $finish;
    end
endmodule
