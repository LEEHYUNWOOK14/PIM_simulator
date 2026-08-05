module logic_die_64ch_fp16_timed_payload_tb;
    localparam int CHANNELS=64, PIM_BLOCKS=8, SOURCES=CHANNELS*PIM_BLOCKS;
    localparam int ENTRIES=16, KEY_WIDTH=64, DATA_WIDTH=16, TRACE_WIDTH=256;
    localparam int SLOT_WIDTH=$clog2(ENTRIES), CHANNEL_WIDTH=$clog2(CHANNELS);
    localparam int EVENTS=24576, FINALS=8192, FIFO_DEPTH=64, HASH_SIZE=16384;
    logic clk=0, rst_n=0;
    logic [SOURCES-1:0] update_valid,update_ready,update_first,update_last;
    logic [SOURCES*KEY_WIDTH-1:0] update_key;
    logic [SOURCES*SLOT_WIDTH-1:0] update_slot;
    logic [SOURCES*DATA_WIDTH-1:0] update_partial,add_lhs,add_rhs,add_result;
    logic [1:0] link_valid,link_ready;
    logic [2*KEY_WIDTH-1:0] link_key;
    logic [2*DATA_WIDTH-1:0] link_data;
    logic [2*CHANNEL_WIDTH-1:0] link_channel;
    logic [SOURCES-1:0] protocol_error;

    integer event_cycle[0:EVENTS-1], event_source[0:EVENTS-1];
    integer event_tap[0:EVENTS-1], event_slot[0:EVENTS-1];
    reg [KEY_WIDTH-1:0] event_key[0:EVENTS-1];
    reg [DATA_WIDTH-1:0] event_data[0:EVENTS-1];
    reg [KEY_WIDTH-1:0] expected_key_hash[0:HASH_SIZE-1];
    reg [DATA_WIDTH-1:0] expected_data_hash[0:HASH_SIZE-1];
    reg expected_valid_hash[0:HASH_SIZE-1];
    integer source_fifo[0:SOURCES-1][0:FIFO_DEPTH-1];
    integer fifo_head[0:SOURCES-1],fifo_tail[0:SOURCES-1],fifo_count[0:SOURCES-1];
    integer accepted=0,emitted=0,full_cycles=0,partial_cycles=0;

    always #5 clk=~clk;
    assign add_result='0;
    logic_die_64ch_reduction_top #(
        .CHANNELS(CHANNELS),.PIM_BLOCKS(PIM_BLOCKS),.ENTRIES_PER_BANK(ENTRIES),
        .KEY_WIDTH(KEY_WIDTH),.DATA_WIDTH(DATA_WIDTH),.USE_INTERNAL_FP16(1'b1)
    ) dut(
        .clk_i(clk),.rst_ni(rst_n),.update_valid_i(update_valid),
        .update_ready_o(update_ready),.update_key_i(update_key),
        .update_slot_i(update_slot),.update_partial_i(update_partial),
        .update_first_i(update_first),.update_last_i(update_last),
        .add_lhs_o(add_lhs),.add_rhs_o(add_rhs),.add_result_i(add_result),
        .link_valid_o(link_valid),.link_ready_i(link_ready),.link_key_o(link_key),
        .link_data_o(link_data),.link_channel_o(link_channel),
        .protocol_error_o(protocol_error));

    task automatic insert_expected(input reg[KEY_WIDTH-1:0] key,
                                   input reg[DATA_WIDTH-1:0] data);
        integer index,tries;
        begin
            index=key % HASH_SIZE;
            for(tries=0;tries<HASH_SIZE;tries=tries+1) begin
                if(!expected_valid_hash[index]||expected_key_hash[index]==key) begin
                    expected_valid_hash[index]=1;expected_key_hash[index]=key;
                    expected_data_hash[index]=data;tries=HASH_SIZE;
                end else index=(index+1)%HASH_SIZE;
            end
        end
    endtask

    task automatic check_output(input reg[KEY_WIDTH-1:0] key,
                                input reg[DATA_WIDTH-1:0] data);
        integer index,tries; reg found;
        begin
            index=key % HASH_SIZE;found=0;
            for(tries=0;tries<HASH_SIZE;tries=tries+1) begin
                if(expected_valid_hash[index]&&expected_key_hash[index]==key) begin
                    found=1;
                    if(expected_data_hash[index]!==data)
                        $fatal(1,"payload mismatch key=%h got=%h expected=%h",
                               key,data,expected_data_hash[index]);
                    tries=HASH_SIZE;
                end else if(!expected_valid_hash[index]) tries=HASH_SIZE;
                else index=(index+1)%HASH_SIZE;
            end
            if(!found)$fatal(1,"unexpected output key=%h",key);
        end
    endtask

    always @(posedge clk) if(rst_n) begin
        for(integer accepted_source=0;accepted_source<SOURCES;
            accepted_source=accepted_source+1)
            if(update_valid[accepted_source]&&update_ready[accepted_source])begin
                fifo_head[accepted_source]=(fifo_head[accepted_source]+1)%FIFO_DEPTH;
                fifo_count[accepted_source]=fifo_count[accepted_source]-1;
                accepted=accepted+1;
            end
        if(link_valid==2'b11)full_cycles=full_cycles+1;
        else if(|link_valid)partial_cycles=partial_cycles+1;
        for(integer lane=0;lane<2;lane=lane+1) if(link_valid[lane]) begin
            check_output(link_key[lane*KEY_WIDTH+:KEY_WIDTH],
                         link_data[lane*DATA_WIDTH+:DATA_WIDTH]);
            emitted=emitted+1;
        end
        if(|protocol_error)$fatal(1,"protocol error in timed payload replay");
    end

    initial begin
        integer fd,parsed,event_sequence,cycle_value,channel,rank,pim_block;
        integer tap_index,tap_count,event_index,replay_cycle,source,queued_event;
        integer first_cycle,hash_index;
        reg[KEY_WIDTH-1:0] key;
        reg[TRACE_WIDTH-1:0] partial_wide,expected_wide;
        reg[2047:0] header;
        update_valid='0;update_key='0;update_slot='0;update_partial='0;
        update_first='0;update_last='0;link_ready=2'b11;
        for(source=0;source<SOURCES;source=source+1)begin
            fifo_head[source]=0;fifo_tail[source]=0;fifo_count[source]=0;
        end
        for(hash_index=0;hash_index<HASH_SIZE;hash_index=hash_index+1)
            expected_valid_hash[hash_index]=0;
        fd=$fopen("experiment/results/depthwise_actual_payload_trace.csv.payload.csv","r");
        if(!fd)$fatal(1,"unable to open C++ payload trace");
        parsed=$fgets(header,fd);
        for(event_index=0;event_index<EVENTS;event_index=event_index+1)begin
            parsed=$fscanf(fd,"%d,%d,%d,%d,%d,%d,%d,%d,%h,%h\n",
                event_sequence,cycle_value,channel,rank,pim_block,key,
                tap_index,tap_count,partial_wide,expected_wide);
            if(parsed!=10||event_sequence!=event_index||tap_count!=3)
                $fatal(1,"invalid payload trace at %0d",event_index);
            event_cycle[event_index]=cycle_value;
            event_source[event_index]=channel*PIM_BLOCKS+pim_block;
            event_tap[event_index]=tap_index;
            event_slot[event_index]=(event_sequence/SOURCES)%ENTRIES;
            event_key[event_index]=key;event_data[event_index]=partial_wide[15:0];
            if(tap_index==tap_count)insert_expected(key,expected_wide[15:0]);
        end
        $fclose(fd);first_cycle=event_cycle[0];event_index=0;replay_cycle=0;
        repeat(2)@(posedge clk);rst_n=1;
        while(emitted<FINALS&&replay_cycle<30000)begin
            @(negedge clk);
            while(event_index<EVENTS&&event_cycle[event_index]-first_cycle<=replay_cycle)begin
                source=event_source[event_index];
                if(fifo_count[source]>=FIFO_DEPTH)$fatal(1,"source FIFO overflow %0d",source);
                source_fifo[source][fifo_tail[source]]=event_index;
                fifo_tail[source]=(fifo_tail[source]+1)%FIFO_DEPTH;
                fifo_count[source]=fifo_count[source]+1;event_index=event_index+1;
            end
            update_valid='0;
            for(source=0;source<SOURCES;source=source+1)if(fifo_count[source]!=0)begin
                queued_event=source_fifo[source][fifo_head[source]];
                update_valid[source]=1;
                update_key[source*KEY_WIDTH+:KEY_WIDTH]=event_key[queued_event];
                update_slot[source*SLOT_WIDTH+:SLOT_WIDTH]=event_slot[queued_event];
                update_partial[source*DATA_WIDTH+:DATA_WIDTH]=event_data[queued_event];
                update_first[source]=event_tap[queued_event]==1;
                update_last[source]=event_tap[queued_event]==3;
            end
            replay_cycle=replay_cycle+1;
        end
        if(accepted!=EVENTS||emitted!=FINALS)
            $fatal(1,"count mismatch accepted=%0d emitted=%0d cycle=%0d",
                   accepted,emitted,replay_cycle);
        $display("LOGIC_DIE_64CH_FP16_TIMED_PAYLOAD_TB PASS partials[%0d] finals[%0d] checked_lanes[1] full_cycles[%0d] partial_cycles[%0d] replay_cycles[%0d]",
                 accepted,emitted,full_cycles,partial_cycles,replay_cycle);
        $finish;
    end
endmodule
