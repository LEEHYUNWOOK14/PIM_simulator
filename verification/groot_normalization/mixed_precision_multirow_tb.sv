module mixed_precision_multirow_tb#(parameter int LANES=4,SCALAR_ENGINES=4);
  localparam int B=16,V=4,ROWS=8;localparam logic[15:0] VECTOR_COUNT=V;localparam int TOTAL=ROWS*V*B*LANES;
  logic clk=0,rst_n=0;always#5 clk=~clk;logic begin_v,begin_r;logic[15:0]begin_tag;logic[31:0]invh;
  logic[B-1:0]rv,rr,av,ar,alast,ov,ordy=~0;logic[B*LANES-1:0][15:0]rdata,ax,ag,ab,odata;logic[B-1:0][15:0]atag,otag;logic[B-1:0]olast;
  logic configured,protocol_error;logic[15:0]configured_tag;logic[4:0]occupancy;integer outputs=0,errors=0,max_occupancy=0;logic overlap_seen=0;
  mixed_precision_multirow_datapath #(.LANES(LANES),.SCALAR_ENGINES(SCALAR_ENGINES),.CONTEXTS(16))dut(.clk_i(clk),.rst_ni(rst_n),.begin_valid_i(begin_v),.begin_ready_o(begin_r),.rms_norm_i(1'b0),.tag_i(begin_tag),.vectors_per_bank_i(VECTOR_COUNT),.inv_hidden_i(invh),.epsilon_i(32'h3727c5ac),
    .reduce_valid_i(rv),.reduce_ready_o(rr),.reduce_data_i(rdata),.apply_valid_i(av),.apply_ready_o(ar),.apply_tag_i(atag),.apply_x_i(ax),.apply_gamma_i(ag),.apply_beta_i(ab),.apply_last_i(alast),
    .result_valid_o(ov),.result_ready_i(ordy),.result_tag_o(otag),.result_data_o(odata),.result_last_o(olast),.scalar_configured_o(configured),.scalar_configured_tag_o(configured_tag),.context_occupancy_o(occupancy),.protocol_error_o(protocol_error));
  function automatic[15:0]row_value(input integer row);case(row%4)0:row_value=16'h3f80;1:row_value=16'h4000;2:row_value=16'h4040;default:row_value=16'h4080;endcase endfunction
  always@(posedge clk)if(rst_n)begin
    if(occupancy>max_occupancy)max_occupancy=occupancy;
    for(integer b=0;b<B;b++)if(ov[b]&&ordy[b])begin for(integer lane=0;lane<LANES;lane++)if(odata[b*LANES+lane]!==16'h0000)begin if(errors<8)$display("nonzero output tag=%h bank=%0d lane=%0d data=%h",otag[b],b,lane,odata[b*LANES+lane]);errors++;end outputs+=LANES;end
  end
  initial begin wait(outputs>=B*LANES*2);@(negedge clk);ordy=0;repeat(12)@(negedge clk);ordy=~0;end
  task automatic send_reduction_row(input integer row);begin
    @(negedge clk);begin_tag=16'h8000+row;begin_v=1;@(posedge clk);while(!begin_r)@(posedge clk);if(row>0&&outputs==0)overlap_seen=1;@(negedge clk);begin_v=0;
    rv=~0;for(integer vec=0;vec<V;vec++)begin for(integer b=0;b<B;b++)for(integer lane=0;lane<LANES;lane++)rdata[b*LANES+lane]=row_value(row);@(posedge clk);while(rr!={B{1'b1}})@(posedge clk);@(negedge clk);end rv=0;
  end endtask
  task automatic send_apply_row(input logic[15:0]tag);integer row;begin
    row=tag-16'h8000;av=~0;for(integer vec=0;vec<V;vec++)begin for(integer b=0;b<B;b++)begin atag[b]=tag;alast[b]=vec==V-1;for(integer lane=0;lane<LANES;lane++)begin ax[b*LANES+lane]=row_value(row);ag[b*LANES+lane]=16'h3f80;ab[b*LANES+lane]=0;end end @(posedge clk);while(ar!={B{1'b1}})@(posedge clk);@(negedge clk);end av=0;alast=0;
  end endtask
  initial begin begin_v=0;begin_tag=0;rv=0;rdata=0;av=0;alast=0;atag=0;ax=0;ag=0;ab=0;case(LANES)4:invh=32'h3b800000;8:invh=32'h3b000000;default:invh=32'h3a800000;endcase repeat(3)@(negedge clk);rst_n=1;
    fork begin for(integer row=0;row<ROWS;row++)send_reduction_row(row);end begin for(integer row=0;row<ROWS;row++)begin wait(configured);send_apply_row(configured_tag);@(negedge clk);end end join
    while(outputs<TOTAL)@(negedge clk);repeat(3)@(negedge clk);if(protocol_error||errors||!overlap_seen||max_occupancy<2)$fatal(1,"MULTIROW_TB FAIL lanes=%0d engines=%0d errors=%0d protocol=%b overlap=%b max_occ=%0d outputs=%0d",LANES,SCALAR_ENGINES,errors,protocol_error,overlap_seen,max_occupancy,outputs);
    $display("MULTIROW_TB PASS lanes=%0d engines=%0d rows=%0d outputs=%0d overlap=1 max_contexts=%0d stall=12",LANES,SCALAR_ENGINES,ROWS,outputs,max_occupancy);$finish;end
  initial begin repeat(20000)@(negedge clk);$fatal(1,"timeout lanes=%0d outputs=%0d occ=%0d configured=%b tag=%h",LANES,outputs,occupancy,configured,configured_tag);end
endmodule
