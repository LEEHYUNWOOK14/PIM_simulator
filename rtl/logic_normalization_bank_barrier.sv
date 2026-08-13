module logic_normalization_bank_barrier #(
    parameter int unsigned BANKS=16,
    parameter int unsigned TAG_WIDTH=16
)(
    input logic clk_i,input logic rst_ni,
    input logic config_valid_i,output logic config_ready_o,
    input logic config_rms_norm_i,input logic[TAG_WIDTH-1:0]config_tag_i,
    input logic[BANKS-1:0]config_expected_mask_i,
    input logic[15:0]config_inv_hidden_i,config_epsilon_i,
    input logic[BANKS-1:0]bank_valid_i,output logic[BANKS-1:0]bank_ready_o,
    input logic[BANKS-1:0][TAG_WIDTH-1:0]bank_tag_i,
    input logic[BANKS-1:0][15:0]bank_sum_i,bank_sumsq_i,
    output logic row_valid_o,input logic row_ready_i,
    output logic row_rms_norm_o,output logic[TAG_WIDTH-1:0]row_tag_o,
    output logic[BANKS-1:0]row_bank_mask_o,
    output logic[BANKS-1:0][15:0]row_partial_sum_o,row_partial_sumsq_o,
    output logic[15:0]row_inv_hidden_o,row_epsilon_o,
    output logic tag_mismatch_error_o,unexpected_bank_error_o,invalid_config_error_o
);
    logic active_q,mode_q;
    logic[TAG_WIDTH-1:0]tag_q;
    logic[BANKS-1:0]mask_q;
    logic[15:0]invh_q,eps_q;
    logic all_present,tags_match,row_fire,config_fire;
    always @* begin
      all_present=active_q;tags_match=1;
      for(integer b=0;b<BANKS;b++)if(mask_q[b])begin
        if(!bank_valid_i[b])all_present=0;
        if(bank_valid_i[b]&&bank_tag_i[b]!=tag_q)tags_match=0;
      end
      row_valid_o=all_present&&tags_match;
      row_fire=row_valid_o&&row_ready_i;
      config_ready_o=!active_q||row_fire;
      config_fire=config_valid_i&&config_ready_o;
      bank_ready_o='0;
      if(row_fire)bank_ready_o=mask_q;
      row_rms_norm_o=mode_q;row_tag_o=tag_q;row_bank_mask_o=mask_q;
      row_partial_sum_o=bank_sum_i;row_partial_sumsq_o=bank_sumsq_i;
      row_inv_hidden_o=invh_q;row_epsilon_o=eps_q;
      tag_mismatch_error_o=active_q&&!tags_match;
      unexpected_bank_error_o=|(bank_valid_i&~mask_q);
    end
    always_ff @(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        active_q<=0;mode_q<=0;tag_q<='0;mask_q<='0;invh_q<=0;eps_q<=0;
        invalid_config_error_o<=0;
      end else begin
        invalid_config_error_o<=0;
        if(row_fire)active_q<=0;
        if(config_fire)begin
          if(config_expected_mask_i=='0)invalid_config_error_o<=1;
          else begin
            active_q<=1;mode_q<=config_rms_norm_i;tag_q<=config_tag_i;
            mask_q<=config_expected_mask_i;invh_q<=config_inv_hidden_i;eps_q<=config_epsilon_i;
          end
        end
      end
    end
endmodule
