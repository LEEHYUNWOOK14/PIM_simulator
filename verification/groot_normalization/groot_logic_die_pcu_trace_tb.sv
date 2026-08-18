module groot_logic_die_pcu_trace_tb #(parameter int L=4, SCALAR_ENGINES=4, LOCAL_REDUCE_CONTEXTS=2, TOP_CONTEXTS=8, APPLY_FIFO_DEPTH=16, parameter bit QUAD_LOCAL_AB=1'b0, parameter bit B2_REGISTERED_QUAD_COMPLETION=1'b0);
  localparam int B=16,MAX_HIDDEN=2048,MAX_ROWS=280,MAX_ELEMENTS=MAX_HIDDEN*MAX_ROWS;
  logic clk=0,rst_n=0;always#5 clk=~clk;
  logic invocation_v,invocation_r,begin_v,begin_r;logic[15:0]begin_tag,vectors_per_bank;logic[31:0]invh,eps;
  logic[B-1:0]rv,rr,av,ar,alast,ov,ordy;logic[B*L-1:0][15:0]rdata,ax,ag,ab,odata;logic[B-1:0][15:0]atag,otag;logic[B-1:0]olast;
  logic replay_request_v,replay_request_r,protocol_error;logic[15:0]replay_request_tag,replay_request_vectors;logic[B-1:0]replay_request_mask;logic[$clog2(TOP_CONTEXTS+1)-1:0]occupancy;
  logic[63:0]activation_bytes,affine_bytes,writeback_bytes,partial_bytes,scalar_bytes,external_bytes;
  logic[3:0]quad_rst_n;logic control_rst_n;assign control_rst_n=&quad_rst_n;
  logic[15:0]xmem[0:MAX_ELEMENTS-1],gmem[0:MAX_ELEMENTS-1],bmem[0:MAX_ELEMENTS-1],mixedmem[0:MAX_ELEMENTS-1],pymem[0:MAX_ELEMENTS-1],actual[0:MAX_ELEMENTS-1];
  integer row_vectors[0:MAX_ROWS-1];integer rows,hidden,vectors,outputs,mixed_mismatches,py_mismatches,cycles,max_occupancy,outfile,rms_mode,affine_per_row;string profile,xfile,gfile,bfile,mixedfile,pyfile,actualfile;

  for(genvar quad=0;quad<4;quad++)begin:g_quad_reset
    normalization_quad_reset_leaf u_reset_leaf(.clk_i(clk),.rst_ni(rst_n),.quad_rst_ni_o(quad_rst_n[quad]));
  end
  generate if(QUAD_LOCAL_AB)begin:g_b
  logic_die_normalization_quad_local_pcu_top #(.LANES(L),.SCALAR_ENGINES(SCALAR_ENGINES),.CONTEXTS(TOP_CONTEXTS),.LOCAL_REDUCE_CONTEXTS(LOCAL_REDUCE_CONTEXTS),.APPLY_FIFO_DEPTH(APPLY_FIFO_DEPTH),.REGISTERED_QUAD_COMPLETION(B2_REGISTERED_QUAD_COMPLETION)) dut(
    .clk_i(clk),.rst_ni(control_rst_n),.quad_rst_ni_i(quad_rst_n),.counter_clear_i(1'b0),.invocation_valid_i(invocation_v),.invocation_ready_o(invocation_r),
    .job_valid_i(begin_v),.job_ready_o(begin_r),.job_rms_norm_i(rms_mode[0]),.job_tag_i(begin_tag),.job_vectors_per_bank_i(vectors_per_bank),.job_inv_hidden_i(invh),.job_epsilon_i(eps),.job_bank_mask_i({B{1'b1}}),
    .reduction_valid_i(rv),.reduction_ready_o(rr),.reduction_data_i(rdata),
    .replay_request_valid_o(replay_request_v),.replay_request_ready_i(replay_request_r),.replay_request_tag_o(replay_request_tag),.replay_request_vectors_per_bank_o(replay_request_vectors),.replay_request_bank_mask_o(replay_request_mask),
    .replay_valid_i(av),.replay_ready_o(ar),.replay_tag_i(atag),.replay_x_i(ax),.replay_gamma_i(ag),.replay_beta_i(ab),.replay_last_i(alast),
    .writeback_valid_o(ov),.writeback_ready_i(ordy),.writeback_tag_o(otag),.writeback_data_o(odata),.writeback_last_o(olast),
    .bank_activation_read_bytes_o(activation_bytes),.bank_affine_read_bytes_o(affine_bytes),.bank_writeback_bytes_o(writeback_bytes),
    .bank_to_logic_partial_bytes_o(partial_bytes),.logic_to_bank_scalar_bytes_o(scalar_bytes),.external_control_bytes_o(external_bytes),
    .context_occupancy_o(occupancy),.protocol_error_o(protocol_error));
  end else begin:g_a
  logic_die_normalization_pcu_top #(.LANES(L),.SCALAR_ENGINES(SCALAR_ENGINES),.CONTEXTS(TOP_CONTEXTS),.LOCAL_REDUCE_CONTEXTS(LOCAL_REDUCE_CONTEXTS),.APPLY_FIFO_DEPTH(APPLY_FIFO_DEPTH)) dut(
    .clk_i(clk),.rst_ni(rst_n),.counter_clear_i(1'b0),.invocation_valid_i(invocation_v),.invocation_ready_o(invocation_r),
    .job_valid_i(begin_v),.job_ready_o(begin_r),.job_rms_norm_i(rms_mode[0]),.job_tag_i(begin_tag),.job_vectors_per_bank_i(vectors_per_bank),.job_inv_hidden_i(invh),.job_epsilon_i(eps),.job_bank_mask_i({B{1'b1}}),
    .reduction_valid_i(rv),.reduction_ready_o(rr),.reduction_data_i(rdata),
    .replay_request_valid_o(replay_request_v),.replay_request_ready_i(replay_request_r),.replay_request_tag_o(replay_request_tag),.replay_request_vectors_per_bank_o(replay_request_vectors),.replay_request_bank_mask_o(replay_request_mask),
    .replay_valid_i(av),.replay_ready_o(ar),.replay_tag_i(atag),.replay_x_i(ax),.replay_gamma_i(ag),.replay_beta_i(ab),.replay_last_i(alast),
    .writeback_valid_o(ov),.writeback_ready_i(ordy),.writeback_tag_o(otag),.writeback_data_o(odata),.writeback_last_o(olast),
    .bank_activation_read_bytes_o(activation_bytes),.bank_affine_read_bytes_o(affine_bytes),.bank_writeback_bytes_o(writeback_bytes),
    .bank_to_logic_partial_bytes_o(partial_bytes),.logic_to_bank_scalar_bytes_o(scalar_bytes),.external_control_bytes_o(external_bytes),
    .context_occupancy_o(occupancy),.protocol_error_o(protocol_error));
  end endgenerate

  always@(posedge clk)if(rst_n)begin integer row,vec,column,md,pd;cycles++;if(occupancy>max_occupancy)max_occupancy=occupancy;
    if(|(ov&ordy))begin
      if((ov&ordy)!={B{1'b1}})$fatal(1,"partial bank output valid=%h",ov&ordy);
      row=otag[0]-16'h6000;vec=row_vectors[row];md=0;pd=0;
      for(integer bank=0;bank<B;bank++)begin if(otag[bank]!==otag[0])$fatal(1,"output tag skew");for(integer lane=0;lane<L;lane++)begin column=vec*B*L+bank*L+lane;actual[row*hidden+column]=odata[bank*L+lane];if(odata[bank*L+lane]!==mixedmem[row*hidden+column])md++;if(odata[bank*L+lane]!==pymem[row*hidden+column])pd++;end end
      row_vectors[row]++;outputs+=B*L;mixed_mismatches+=md;py_mismatches+=pd;
    end
  end

  task automatic reduce_row(input integer row);begin
    @(negedge clk);begin_tag=16'h6000+row;begin_v=1;@(posedge clk);while(!begin_r)@(posedge clk);@(negedge clk);begin_v=0;rv=~0;
    for(integer vec=0;vec<vectors;vec++)begin for(integer bank=0;bank<B;bank++)for(integer lane=0;lane<L;lane++)rdata[bank*L+lane]=xmem[row*hidden+vec*B*L+bank*L+lane];@(posedge clk);while(rr!={B{1'b1}})@(posedge clk);@(negedge clk);end rv=0;
  end endtask
  task automatic apply_row(input logic[15:0]row_tag);integer row,affine_col;begin
    row=row_tag-16'h6000;@(negedge clk);av=~0;
      for(integer vec=0;vec<vectors;vec++)begin for(integer bank=0;bank<B;bank++)begin atag[bank]=row_tag;alast[bank]=vec==vectors-1;for(integer lane=0;lane<L;lane++)begin integer col;col=vec*B*L+bank*L+lane;affine_col=affine_per_row?row*hidden+col:col;ax[bank*L+lane]=xmem[row*hidden+col];ag[bank*L+lane]=gmem[affine_col];ab[bank*L+lane]=bmem[affine_col];end end @(posedge clk);while(ar!={B{1'b1}})@(posedge clk);@(negedge clk);end av=0;alast=0;
  end endtask

  initial begin logic[15:0]request_tag;
    rms_mode=0;affine_per_row=0;void'($value$plusargs("RMS=%d",rms_mode));void'($value$plusargs("AFFINE_PER_ROW=%d",affine_per_row));
    if(!$value$plusargs("PROFILE=%s",profile)||!$value$plusargs("ROWS=%d",rows)||!$value$plusargs("HIDDEN=%d",hidden)||!$value$plusargs("VECTORS=%d",vectors)||!$value$plusargs("INVH=%h",invh)||!$value$plusargs("EPS=%h",eps)||!$value$plusargs("X=%s",xfile)||!$value$plusargs("GAMMA=%s",gfile)||!$value$plusargs("BETA=%s",bfile)||!$value$plusargs("MIXED=%s",mixedfile)||!$value$plusargs("PYTORCH=%s",pyfile)||!$value$plusargs("ACTUAL=%s",actualfile))$fatal(1,"missing plusargs");
    $readmemh(xfile,xmem,0,rows*hidden-1);if(affine_per_row)begin $readmemh(gfile,gmem,0,rows*hidden-1);$readmemh(bfile,bmem,0,rows*hidden-1);end else begin $readmemh(gfile,gmem,0,hidden-1);$readmemh(bfile,bmem,0,hidden-1);end $readmemh(mixedfile,mixedmem,0,rows*hidden-1);$readmemh(pyfile,pymem,0,rows*hidden-1);
    invocation_v=0;begin_v=0;begin_tag=0;vectors_per_bank=vectors;rv=0;rdata=0;av=0;atag=0;ax=0;ag=0;ab=0;alast=0;ordy=~0;replay_request_r=1;outputs=0;mixed_mismatches=0;py_mismatches=0;cycles=0;max_occupancy=0;for(integer r=0;r<MAX_ROWS;r++)row_vectors[r]=0;
    repeat(3)@(negedge clk);rst_n=1;
    // B distributes reset through two-flop quad-local synchronizers.  Do not
    // present the invocation descriptor until the shared control domain and
    // all four local domains are released.
    wait(control_rst_n===1'b1);wait(invocation_r===1'b1);@(negedge clk);invocation_v=1;@(posedge clk);if(!invocation_r)$fatal(1,"invocation descriptor rejected");@(negedge clk);invocation_v=0;
    fork begin for(integer row=0;row<rows;row++)reduce_row(row);end begin for(integer n=0;n<rows;n++)begin while(!replay_request_v)@(posedge clk);request_tag=replay_request_tag;if(replay_request_vectors!=vectors||replay_request_mask!={B{1'b1}})$fatal(1,"bad replay request");apply_row(request_tag);end end join
    while(outputs<rows*hidden)@(negedge clk);repeat(3)@(negedge clk);outfile=$fopen(actualfile,"w");for(integer i=0;i<rows*hidden;i++)$fdisplay(outfile,"%04h",actual[i]);$fclose(outfile);
    if(protocol_error||mixed_mismatches)$fatal(1,"PCU_TRACE FAIL profile=%s lanes=%0d protocol=%b mixed=%0d",profile,L,protocol_error,mixed_mismatches);
    if(activation_bytes!=4*rows*hidden||affine_bytes!=4*rows*hidden||writeback_bytes!=2*rows*hidden)$fatal(1,"bank byte mismatch activation=%0d affine=%0d writeback=%0d",activation_bytes,affine_bytes,writeback_bytes);
    if(partial_bytes!=rows*B*8||scalar_bytes!=rows*B*8||external_bytes!=32)$fatal(1,"boundary byte mismatch partial=%0d scalar=%0d external=%0d",partial_bytes,scalar_bytes,external_bytes);
    $display("PCU_TRACE PASS variant=%0d profile=%s mode_rms=%0d affine_per_row=%0d lanes=%0d engines=%0d local_reduce_contexts=%0d top_contexts=%0d fifo=%0d rows=%0d hidden=%0d elements=%0d mixed_mismatches=%0d reference_bit_mismatches=%0d cycles=%0d max_contexts=%0d external_bytes=%0d bank_internal_bytes=%0d",QUAD_LOCAL_AB,profile,rms_mode,affine_per_row,L,SCALAR_ENGINES,LOCAL_REDUCE_CONTEXTS,TOP_CONTEXTS,APPLY_FIFO_DEPTH,rows,hidden,rows*hidden,mixed_mismatches,py_mismatches,cycles,max_occupancy,external_bytes,activation_bytes+affine_bytes+writeback_bytes);$finish;
  end
  initial begin#30000000;$fatal(1,"timeout profile=%s lanes=%0d outputs=%0d",profile,L,outputs);end
endmodule
