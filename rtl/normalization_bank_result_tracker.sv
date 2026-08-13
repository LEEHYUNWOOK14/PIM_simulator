module normalization_bank_result_tracker #(
    parameter int unsigned BANKS=16,TAG_WIDTH=16,ENTRIES=16
)(
    input logic clk_i,input logic rst_ni,
    input logic allocate_valid_i,output logic allocate_ready_o,
    input logic[TAG_WIDTH-1:0]allocate_tag_i,input logic[BANKS-1:0]allocate_expected_mask_i,
    input logic[BANKS-1:0]bank_result_valid_i,output logic[BANKS-1:0]bank_result_ready_o,
    input logic[BANKS-1:0][TAG_WIDTH-1:0]bank_result_tag_i,
    output logic completion_valid_o,input logic completion_ready_i,
    output logic[TAG_WIDTH-1:0]completion_tag_o,
    output logic duplicate_tag_error_o,unknown_tag_error_o,duplicate_bank_error_o,zero_mask_error_o
);
    logic[ENTRIES-1:0]valid_q,complete_q;logic[TAG_WIDTH-1:0]tag_q[0:ENTRIES-1];
    logic[BANKS-1:0]expected_q[0:ENTRIES-1],received_q[0:ENTRIES-1],received_d[0:ENTRIES-1];
    logic duplicate,free_found,completion_found;integer free_idx,completion_idx;
    logic[BANKS-1:0]bank_match,bank_duplicate;
    always @* begin
      duplicate=0;free_found=0;free_idx=0;completion_found=0;completion_idx=0;
      completion_valid_o=0;completion_tag_o='0;bank_result_ready_o='0;bank_match='0;bank_duplicate='0;
      for(integer e=0;e<ENTRIES;e++)begin
        received_d[e]=received_q[e];
        if(valid_q[e]&&tag_q[e]==allocate_tag_i)duplicate=1;
        if(!valid_q[e]&&!free_found)begin free_found=1;free_idx=e;end
        if(valid_q[e]&&complete_q[e]&&!completion_found)begin completion_found=1;completion_idx=e;end
      end
      allocate_ready_o=free_found&&!duplicate&&(allocate_expected_mask_i!='0);
      if(completion_found)begin completion_valid_o=1;completion_tag_o=tag_q[completion_idx];end
      for(integer b=0;b<BANKS;b++)begin
        for(integer e=0;e<ENTRIES;e++)if(valid_q[e]&&tag_q[e]==bank_result_tag_i[b]&&!bank_match[b])begin
          bank_match[b]=1;
          bank_duplicate[b]=received_q[e][b]||!expected_q[e][b];
          bank_result_ready_o[b]=!complete_q[e]&&!bank_duplicate[b];
          if(bank_result_valid_i[b]&&bank_result_ready_o[b])received_d[e][b]=1;
        end
      end
    end
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin valid_q<='0;complete_q<='0;
        for(integer e=0;e<ENTRIES;e++)begin tag_q[e]<='0;expected_q[e]<='0;received_q[e]<='0;end
        duplicate_tag_error_o<=0;unknown_tag_error_o<=0;duplicate_bank_error_o<=0;zero_mask_error_o<=0;end
      else begin
        for(integer e=0;e<ENTRIES;e++)received_q[e]<=received_d[e];
        if(allocate_valid_i&&duplicate)duplicate_tag_error_o<=1;
        if(allocate_valid_i&&allocate_expected_mask_i=='0)zero_mask_error_o<=1;
        for(integer b=0;b<BANKS;b++)if(bank_result_valid_i[b])begin
          if(!bank_match[b])unknown_tag_error_o<=1;
          else if(bank_duplicate[b])duplicate_bank_error_o<=1;
        end
        for(integer e=0;e<ENTRIES;e++)if(valid_q[e]&&!complete_q[e]&&received_d[e]==expected_q[e])complete_q[e]<=1;
        if(completion_valid_o&&completion_ready_i)begin valid_q[completion_idx]<=0;complete_q[completion_idx]<=0;received_q[completion_idx]<='0;end
        if(allocate_valid_i&&allocate_ready_o)begin valid_q[free_idx]<=1;complete_q[free_idx]<=0;
          tag_q[free_idx]<=allocate_tag_i;expected_q[free_idx]<=allocate_expected_mask_i;received_q[free_idx]<='0;end
      end
    end
endmodule
