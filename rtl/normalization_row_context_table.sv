module normalization_row_context_table #(
    parameter int unsigned BANKS=16,
    parameter int unsigned TAG_WIDTH=16,
    parameter int unsigned ENTRIES=16
)(
    input logic clk_i,input logic rst_ni,
    input logic allocate_valid_i,output logic allocate_ready_o,
    input logic[TAG_WIDTH-1:0]allocate_tag_i,
    input logic[BANKS-1:0]allocate_target_mask_i,
    input logic lookup_valid_i,output logic lookup_hit_o,
    input logic[TAG_WIDTH-1:0]lookup_tag_i,
    output logic[BANKS-1:0]lookup_target_mask_o,
    input logic lookup_consume_i,
    output logic duplicate_tag_error_o,lookup_miss_error_o
);
    logic[ENTRIES-1:0]valid_q;
    logic[ENTRIES-1:0][TAG_WIDTH-1:0]tag_q;
    logic[ENTRIES-1:0][BANKS-1:0]mask_q;
    logic duplicate,free_found;integer free_idx,lookup_idx;
    always_comb begin
      duplicate=0;free_found=0;free_idx=0;lookup_hit_o=0;lookup_idx=0;lookup_target_mask_o='0;
      for(integer e=0;e<ENTRIES;e++)begin
        if(valid_q[e]&&tag_q[e]==allocate_tag_i)duplicate=1;
        if(!valid_q[e]&&!free_found)begin free_found=1;free_idx=e;end
        if(valid_q[e]&&tag_q[e]==lookup_tag_i&&!lookup_hit_o)begin
          lookup_hit_o=1;lookup_idx=e;lookup_target_mask_o=mask_q[e];
        end
      end
      allocate_ready_o=free_found&&!duplicate;
    end
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin valid_q<='0;tag_q<='0;mask_q<='0;duplicate_tag_error_o<=0;lookup_miss_error_o<=0;end
      else begin
        if(allocate_valid_i&&duplicate)duplicate_tag_error_o<=1;
        if(lookup_valid_i&&!lookup_hit_o)lookup_miss_error_o<=1;
        if(lookup_valid_i&&lookup_hit_o&&lookup_consume_i)valid_q[lookup_idx]<=0;
        if(allocate_valid_i&&allocate_ready_o)begin
          valid_q[free_idx]<=1;tag_q[free_idx]<=allocate_tag_i;mask_q[free_idx]<=allocate_target_mask_i;
        end
      end
    end
endmodule
