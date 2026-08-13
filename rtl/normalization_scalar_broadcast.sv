module normalization_scalar_broadcast #(
    parameter int unsigned BANKS=16,
    parameter int unsigned TAG_WIDTH=16
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic input_valid_i,
    output logic input_ready_o,
    input  logic [BANKS-1:0] target_mask_i,
    input  logic rms_norm_i,
    input  logic [TAG_WIDTH-1:0] tag_i,
    input  logic [15:0] mean_i,
    input  logic [15:0] inv_std_i,
    output logic [BANKS-1:0] bank_valid_o,
    input  logic [BANKS-1:0] bank_ready_i,
    output logic [BANKS-1:0] bank_rms_norm_o,
    output logic [BANKS-1:0][TAG_WIDTH-1:0] bank_tag_o,
    output logic [BANKS-1:0][15:0] bank_mean_o,
    output logic [BANKS-1:0][15:0] bank_inv_std_o,
    output logic zero_target_error_o
);
    logic [BANKS-1:0] pending_q;
    logic rms_norm_q;
    logic [TAG_WIDTH-1:0] tag_q;
    logic [15:0] mean_q,inv_std_q;

    assign input_ready_o=(pending_q=='0);
    assign bank_valid_o=pending_q;

    always_comb begin
      for(integer b=0;b<BANKS;b++)begin
        bank_rms_norm_o[b]=rms_norm_q;
        bank_tag_o[b]=tag_q;
        bank_mean_o[b]=mean_q;
        bank_inv_std_o[b]=inv_std_q;
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        pending_q<='0;rms_norm_q<=1'b0;tag_q<='0;mean_q<='0;inv_std_q<='0;
        zero_target_error_o<=1'b0;
      end else begin
        pending_q<=pending_q&~(bank_valid_o&bank_ready_i);
        if(input_valid_i&&input_ready_o)begin
          if(target_mask_i=='0)zero_target_error_o<=1'b1;
          else begin
            pending_q<=target_mask_i;
            rms_norm_q<=rms_norm_i;tag_q<=tag_i;mean_q<=mean_i;inv_std_q<=inv_std_i;
          end
        end
      end
    end
endmodule
