module groot_multirow_trace_tb#(parameter int L=4,SCALAR_ENGINES=4);
  localparam int B=16,MAX_HIDDEN=2048,MAX_ROWS=280,MAX_ELEMENTS=MAX_HIDDEN*MAX_ROWS;
  logic clk=0,rst_n=0;always#5 clk=~clk;logic begin_v,begin_r;logic[15:0]begin_tag,vectors_per_bank;logic[31:0]invh,eps;
  logic[B-1:0]rv,rr,av,ar,alast,ov,ordy;logic[B*L-1:0][15:0]rdata,ax,ag,ab,odata;logic[B-1:0][15:0]atag,otag;logic[B-1:0]olast;
  logic configured,protocol_error;logic[15:0]configured_tag;logic[4:0]occupancy;
  logic[15:0]xmem[0:MAX_ELEMENTS-1],gmem[0:MAX_HIDDEN-1],bmem[0:MAX_HIDDEN-1],mixedmem[0:MAX_ELEMENTS-1],pymem[0:MAX_ELEMENTS-1],actual[0:MAX_ELEMENTS-1];
  integer row_vectors[0:MAX_ROWS-1];integer rows,hidden,vectors,outputs,mixed_mismatches,py_mismatches,cycles,max_occupancy,outfile;string profile,xfile,gfile,bfile,mixedfile,pyfile,actualfile;
  mixed_precision_multirow_datapath #(.LANES(L),.SCALAR_ENGINES(SCALAR_ENGINES),.CONTEXTS(16))dut(.clk_i(clk),.rst_ni(rst_n),.begin_valid_i(begin_v),.begin_ready_o(begin_r),.rms_norm_i(1'b0),.tag_i(begin_tag),.vectors_per_bank_i(vectors_per_bank),.inv_hidden_i(invh),.epsilon_i(eps),
    .reduce_valid_i(rv),.reduce_ready_o(rr),.reduce_data_i(rdata),.apply_valid_i(av),.apply_ready_o(ar),.apply_tag_i(atag),.apply_x_i(ax),.apply_gamma_i(ag),.apply_beta_i(ab),.apply_last_i(alast),
    .result_valid_o(ov),.result_ready_i(ordy),.result_tag_o(otag),.result_data_o(odata),.result_last_o(olast),.scalar_configured_o(configured),.scalar_configured_tag_o(configured_tag),.context_occupancy_o(occupancy),.protocol_error_o(protocol_error));
  always@(posedge clk)if(rst_n)begin integer row,vec,column,md,pd;cycles++;if(occupancy>max_occupancy)max_occupancy=occupancy;
    if(|(ov&ordy))begin
      if((ov&ordy)!={B{1'b1}})begin $display("partial bank output valid=%h",ov&ordy);$fatal(1);end
      row=otag[0]-16'h6000;vec=row_vectors[row];md=0;pd=0;
      for(integer bank=0;bank<B;bank++)begin if(otag[bank]!==otag[0])$fatal(1,"output tag skew");for(integer lane=0;lane<L;lane++)begin column=vec*B*L+bank*L+lane;actual[row*hidden+column]=odata[bank*L+lane];if(odata[bank*L+lane]!==mixedmem[row*hidden+column])md++;if(odata[bank*L+lane]!==pymem[row*hidden+column])pd++;end end
      row_vectors[row]++;outputs+=B*L;mixed_mismatches+=md;py_mismatches+=pd;
    end
  end
  task automatic reduce_row(input integer row);begin
    @(negedge clk);begin_tag=16'h6000+row;begin_v=1;@(posedge clk);while(!begin_r)@(posedge clk);@(negedge clk);begin_v=0;rv=~0;
    for(integer vec=0;vec<vectors;vec++)begin for(integer bank=0;bank<B;bank++)for(integer lane=0;lane<L;lane++)rdata[bank*L+lane]=xmem[row*hidden+vec*B*L+bank*L+lane];@(posedge clk);while(rr!={B{1'b1}})@(posedge clk);@(negedge clk);end rv=0;
  end endtask
  task automatic apply_row(input logic[15:0]row_tag);integer row;begin
    row=row_tag-16'h6000;@(negedge clk);av=~0;
    for(integer vec=0;vec<vectors;vec++)begin for(integer bank=0;bank<B;bank++)begin atag[bank]=row_tag;alast[bank]=vec==vectors-1;for(integer lane=0;lane<L;lane++)begin integer col;col=vec*B*L+bank*L+lane;ax[bank*L+lane]=xmem[row*hidden+col];ag[bank*L+lane]=gmem[col];ab[bank*L+lane]=bmem[col];end end @(posedge clk);while(ar!={B{1'b1}})@(posedge clk);@(negedge clk);end av=0;alast=0;
  end endtask
  initial begin
    if(!$value$plusargs("PROFILE=%s",profile)||!$value$plusargs("ROWS=%d",rows)||!$value$plusargs("HIDDEN=%d",hidden)||!$value$plusargs("VECTORS=%d",vectors)||!$value$plusargs("INVH=%h",invh)||!$value$plusargs("EPS=%h",eps)||!$value$plusargs("X=%s",xfile)||!$value$plusargs("GAMMA=%s",gfile)||!$value$plusargs("BETA=%s",bfile)||!$value$plusargs("MIXED=%s",mixedfile)||!$value$plusargs("PYTORCH=%s",pyfile)||!$value$plusargs("ACTUAL=%s",actualfile))$fatal(1,"missing plusargs");
    $readmemh(xfile,xmem,0,rows*hidden-1);$readmemh(gfile,gmem,0,hidden-1);$readmemh(bfile,bmem,0,hidden-1);$readmemh(mixedfile,mixedmem,0,rows*hidden-1);$readmemh(pyfile,pymem,0,rows*hidden-1);
    begin_v=0;begin_tag=0;vectors_per_bank=vectors;rv=0;rdata=0;av=0;atag=0;ax=0;ag=0;ab=0;alast=0;ordy=~0;outputs=0;mixed_mismatches=0;py_mismatches=0;cycles=0;max_occupancy=0;for(integer r=0;r<MAX_ROWS;r++)row_vectors[r]=0;
    repeat(3)@(negedge clk);rst_n=1;
    fork begin for(integer row=0;row<rows;row++)reduce_row(row);end begin for(integer n=0;n<rows;n++)begin while(!configured)@(posedge clk);apply_row(configured_tag);end end join
    while(outputs<rows*hidden)@(negedge clk);repeat(3)@(negedge clk);outfile=$fopen(actualfile,"w");for(integer i=0;i<rows*hidden;i++)$fdisplay(outfile,"%04h",actual[i]);$fclose(outfile);
    if(protocol_error||mixed_mismatches)$fatal(1,"MULTIROW_TRACE FAIL profile=%s lanes=%0d engines=%0d protocol=%b mixed=%0d",profile,L,SCALAR_ENGINES,protocol_error,mixed_mismatches);
    $display("MULTIROW_TRACE PASS profile=%s lanes=%0d engines=%0d rows=%0d hidden=%0d elements=%0d mixed_mismatches=%0d pytorch_bit_mismatches=%0d cycles=%0d max_contexts=%0d",profile,L,SCALAR_ENGINES,rows,hidden,rows*hidden,mixed_mismatches,py_mismatches,cycles,max_occupancy);$finish;
  end
  initial begin#30000000;$fatal(1,"timeout profile=%s lanes=%0d outputs=%0d",profile,L,outputs);end
endmodule
