module shared_channel_actual_trace_tb;
    parameter int PIPELINES=2;
    localparam int SOURCES=8,ENTRIES=16,KEY_WIDTH=64,DATA_WIDTH=16,TRACE_WIDTH=256;
    localparam int SLOT_WIDTH=$clog2(ENTRIES),EVENTS=384,FINALS=128,FIFO_DEPTH=32;
    logic clk=0,rst_n=0;
    logic [SOURCES-1:0] source_valid,source_ready,source_first,source_last,protocol_error;
    logic [SOURCES*KEY_WIDTH-1:0] source_key;
    logic [SOURCES*SLOT_WIDTH-1:0] source_slot;
    logic [SOURCES*DATA_WIDTH-1:0] source_partial;
    logic link_valid,link_ready;logic [KEY_WIDTH-1:0] link_key;
    logic [DATA_WIDTH-1:0] link_data;logic [$clog2(SOURCES)-1:0] link_source;
    integer event_cycle[0:EVENTS-1],event_source[0:EVENTS-1],event_tap[0:EVENTS-1];
    integer event_slot[0:EVENTS-1],fifo[0:SOURCES-1][0:FIFO_DEPTH-1];
    integer head[0:SOURCES-1],tail[0:SOURCES-1],count[0:SOURCES-1];
    reg[KEY_WIDTH-1:0] event_key[0:EVENTS-1],expected_key[0:FINALS-1];
    reg[DATA_WIDTH-1:0] event_data[0:EVENTS-1],expected_data[0:FINALS-1];
    integer accepted=0,emitted=0,peak_fifo=0,source_wait_cycles=0;
    always #5 clk=~clk;
    shared_channel_reduction_path #(.SOURCES(SOURCES),.PIPELINES(PIPELINES),
        .ENTRIES_PER_SOURCE(ENTRIES),.KEY_WIDTH(KEY_WIDTH),.LANES(1),
        .DATA_WIDTH(DATA_WIDTH),.SLOT_WIDTH(SLOT_WIDTH)) dut(
        .clk_i(clk),.rst_ni(rst_n),.source_valid_i(source_valid),
        .source_ready_o(source_ready),.source_key_i(source_key),.source_slot_i(source_slot),
        .source_partial_i(source_partial),.source_first_i(source_first),
        .source_last_i(source_last),.link_valid_o(link_valid),.link_ready_i(link_ready),
        .link_key_o(link_key),.link_data_o(link_data),.link_source_o(link_source),
        .protocol_error_o(protocol_error));

    task automatic check_final(input reg[KEY_WIDTH-1:0] key,input reg[DATA_WIDTH-1:0] data);
        integer index;reg found;
        begin found=0;
            for(index=0;index<FINALS;index=index+1)
                if(expected_key[index]==key)begin
                    found=1;if(expected_data[index]!==data)
                        $fatal(1,"payload mismatch key=%h got=%h expected=%h",key,data,expected_data[index]);
                    index=FINALS;
                end
            if(!found)$fatal(1,"unexpected key=%h",key);
        end
    endtask

    always @(posedge clk)if(rst_n)begin
        for(integer source=0;source<SOURCES;source=source+1)
            if(source_valid[source]&&source_ready[source])begin
                head[source]=(head[source]+1)%FIFO_DEPTH;count[source]=count[source]-1;
                accepted=accepted+1;
            end
        if(link_valid&&link_ready)begin check_final(link_key,link_data);emitted=emitted+1;end
        if(|protocol_error)$fatal(1,"protocol error");
    end

    initial begin
        integer fd,parsed,trace_row,cycle_value,channel,rank,block,tap,tap_count;
        integer loaded,final_index,event_index,replay_cycle,source,queued,total_queued;
        reg[KEY_WIDTH-1:0] key;reg[TRACE_WIDTH-1:0] partial_wide,final_wide;
        reg[2047:0] header;
        source_valid='0;source_key='0;source_slot='0;source_partial='0;
        source_first='0;source_last='0;link_ready=1;loaded=0;final_index=0;
        for(source=0;source<SOURCES;source=source+1)begin head[source]=0;tail[source]=0;count[source]=0;end
        fd=$fopen("experiment/results/depthwise_actual_payload_trace.csv.payload.csv","r");
        if(!fd)$fatal(1,"missing payload trace");parsed=$fgets(header,fd);
        for(trace_row=0;trace_row<24576;trace_row=trace_row+1)begin
            parsed=$fscanf(fd,"%d,%d,%d,%d,%d,%d,%d,%d,%h,%h\n",
                event_index,cycle_value,channel,rank,block,key,tap,tap_count,partial_wide,final_wide);
            if(parsed!=10)$fatal(1,"trace parse failure");
            if(channel==0)begin
                event_cycle[loaded]=cycle_value;event_source[loaded]=block;event_tap[loaded]=tap;
                event_slot[loaded]=(event_index/512)%ENTRIES;event_key[loaded]=key;
                event_data[loaded]=partial_wide[15:0];
                if(tap==3)begin expected_key[final_index]=key;expected_data[final_index]=final_wide[15:0];final_index=final_index+1;end
                loaded=loaded+1;
            end
        end
        $fclose(fd);if(loaded!=EVENTS||final_index!=FINALS)$fatal(1,"trace count mismatch");
        event_index=0;replay_cycle=0;repeat(2)@(posedge clk);rst_n=1;
        while(emitted<FINALS&&replay_cycle<30000)begin
            @(negedge clk);
            while(event_index<EVENTS&&event_cycle[event_index]-event_cycle[0]<=replay_cycle)begin
                source=event_source[event_index];
                if(count[source]>=FIFO_DEPTH)$fatal(1,"FIFO overflow source=%0d",source);
                fifo[source][tail[source]]=event_index;tail[source]=(tail[source]+1)%FIFO_DEPTH;
                count[source]=count[source]+1;event_index=event_index+1;
            end
            source_valid='0;total_queued=0;
            for(source=0;source<SOURCES;source=source+1)begin
                total_queued=total_queued+count[source];
                if(count[source]!=0)begin queued=fifo[source][head[source]];source_valid[source]=1;
                    source_key[source*KEY_WIDTH+:KEY_WIDTH]=event_key[queued];
                    source_slot[source*SLOT_WIDTH+:SLOT_WIDTH]=event_slot[queued];
                    source_partial[source*DATA_WIDTH+:DATA_WIDTH]=event_data[queued];
                    source_first[source]=event_tap[queued]==1;source_last[source]=event_tap[queued]==3;
                end
            end
            if(total_queued>peak_fifo)peak_fifo=total_queued;
            source_wait_cycles=source_wait_cycles+total_queued;replay_cycle=replay_cycle+1;
        end
        if(accepted!=EVENTS||emitted!=FINALS)$fatal(1,"count mismatch accepted=%0d emitted=%0d",accepted,emitted);
        $display("SHARED_CHANNEL_ACTUAL_TRACE_TB PASS pipelines[%0d] partials[%0d] finals[%0d] peak_fifo[%0d] source_wait_cycles[%0d] replay_cycles[%0d] checked_lanes[1]",
            PIPELINES,accepted,emitted,peak_fifo,source_wait_cycles,replay_cycle);
        $finish;
    end
endmodule
