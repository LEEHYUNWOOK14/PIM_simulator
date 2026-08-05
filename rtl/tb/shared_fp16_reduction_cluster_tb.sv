module shared_fp16_reduction_cluster_tb;
    parameter int PIPELINES = 1;
    localparam int SOURCES=8, ENTRIES=4, KEY_WIDTH=16, LANES=16;
    localparam int DATA_WIDTH=LANES*16, SLOT_WIDTH=$clog2(ENTRIES);
    logic clk=0,rst_n=0;
    logic [SOURCES-1:0] source_valid,source_ready,source_first,source_last;
    logic [SOURCES*KEY_WIDTH-1:0] source_key;
    logic [SOURCES*SLOT_WIDTH-1:0] source_slot;
    logic [SOURCES*DATA_WIDTH-1:0] source_partial;
    logic [SOURCES-1:0] final_valid,final_ready,protocol_error;
    logic [SOURCES*KEY_WIDTH-1:0] final_key;
    logic [SOURCES*DATA_WIDTH-1:0] final_data;
    integer accepted_per_source[0:SOURCES-1];
    integer service_cycles=0,finals=0;
    always #5 clk=~clk;

    shared_fp16_reduction_cluster #(
        .SOURCES(SOURCES),.PIPELINES(PIPELINES),.ENTRIES_PER_SOURCE(ENTRIES),
        .KEY_WIDTH(KEY_WIDTH),.LANES(LANES),.SLOT_WIDTH(SLOT_WIDTH)
    ) dut(
        .clk_i(clk),.rst_ni(rst_n),.source_valid_i(source_valid),
        .source_ready_o(source_ready),.source_key_i(source_key),
        .source_slot_i(source_slot),.source_partial_i(source_partial),
        .source_first_i(source_first),.source_last_i(source_last),
        .final_valid_o(final_valid),.final_ready_i(final_ready),
        .final_key_o(final_key),.final_data_o(final_data),
        .protocol_error_o(protocol_error));

    always @(posedge clk) if(rst_n) begin
        service_cycles=service_cycles+1;
        if(|protocol_error)$fatal(1,"protocol error");
        for(integer source=0;source<SOURCES;source=source+1) begin
            if(source_valid[source]&&source_ready[source])
                accepted_per_source[source]=accepted_per_source[source]+1;
            if(final_valid[source]) begin
                if(final_key[source*KEY_WIDTH+:KEY_WIDTH]!==source||
                   final_data[source*DATA_WIDTH+:16]!==16'h4600)
                    $fatal(1,"bad final source=%0d key=%h data=%h",source,
                           final_key[source*KEY_WIDTH+:KEY_WIDTH],
                           final_data[source*DATA_WIDTH+:16]);
                for(integer lane=0;lane<LANES;lane=lane+1)
                    if(final_data[source*DATA_WIDTH+lane*16+:16]!==16'h4600)
                        $fatal(1,"bad lane source=%0d lane=%0d",source,lane);
                finals=finals+1;
            end
        end
    end

    initial begin
        integer active;
        source_valid='0;source_key='0;source_slot='0;source_partial='0;
        source_first='0;source_last='0;final_ready='1;
        for(integer source=0;source<SOURCES;source=source+1)begin
            accepted_per_source[source]=0;
            source_key[source*KEY_WIDTH+:KEY_WIDTH]=source;
            source_slot[source*SLOT_WIDTH+:SLOT_WIDTH]=0;
        end
        repeat(2)@(posedge clk);rst_n=1;
        while(finals<SOURCES&&service_cycles<100)begin
            @(negedge clk);active=0;
            for(integer source=0;source<SOURCES;source=source+1)begin
                source_valid[source]=accepted_per_source[source]<3;
                source_first[source]=accepted_per_source[source]==0;
                source_last[source]=accepted_per_source[source]==2;
                case(accepted_per_source[source])
                    0: source_partial[source*DATA_WIDTH+:DATA_WIDTH]={LANES{16'h3c00}};
                    1: source_partial[source*DATA_WIDTH+:DATA_WIDTH]={LANES{16'h4000}};
                    default: source_partial[source*DATA_WIDTH+:DATA_WIDTH]={LANES{16'h4200}};
                endcase
                if(source_valid[source])active=active+1;
            end
        end
        @(negedge clk);source_valid='0;
        for(integer source=0;source<SOURCES;source=source+1)
            if(accepted_per_source[source]!=3)
                $fatal(1,"source %0d accepted %0d",source,accepted_per_source[source]);
        if(finals!=SOURCES)$fatal(1,"final count %0d",finals);
        $display("SHARED_FP16_REDUCTION_CLUSTER_TB PASS pipelines[%0d] partials[24] finals[8] service_cycles[%0d]",
                 PIPELINES,service_cycles);
        $finish;
    end
endmodule
