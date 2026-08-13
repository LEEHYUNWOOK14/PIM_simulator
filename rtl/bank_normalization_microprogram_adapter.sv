module bank_normalization_microprogram_adapter #(
    parameter int unsigned DATA_WIDTH=256,
    parameter int unsigned TAG_WIDTH=16,
    parameter int unsigned KEY_WIDTH=32
)(
    input logic clk_i,input logic rst_ni,
    input logic scalar_valid_i,output logic scalar_ready_o,
    input logic scalar_rms_norm_i,input logic[TAG_WIDTH-1:0]scalar_tag_i,
    input logic[15:0]scalar_mean_i,scalar_inv_std_i,
    input logic[2:0]gamma_grf_b_index_i,beta_grf_b_index_i,
    output logic srf_write_valid_o,input logic srf_write_ready_i,
    output logic[DATA_WIDTH-1:0]srf_write_data_o,
    output logic command_valid_o,input logic command_ready_i,
    output logic[31:0]command_o,output logic[1:0]precision_o,
    output logic[KEY_WIDTH-1:0]context_key_o,
    output logic transaction_done_o
);
`include "rtl/pim_rtl_constants.svh"
    typedef enum logic[1:0]{IDLE,WRITE_SRF,ISSUE}state_t;state_t state_q;
    logic mode_q;logic[TAG_WIDTH-1:0]tag_q;logic[15:0]mean_q,inv_q;
    logic[2:0]gamma_q,beta_q;logic[2:0]step_q,last_step;
    function automatic[31:0]enc(input logic[3:0]op,input logic[2:0]dst,s0,s1,
      input logic[3:0]di,i0,i1);begin enc='0;enc[31:28]=op;enc[27:25]=dst;
      enc[24:22]=s0;enc[21:19]=s1;enc[11:8]=di;enc[7:4]=i0;enc[3:0]=i1;end endfunction
    assign scalar_ready_o=(state_q==IDLE);
    assign srf_write_valid_o=(state_q==WRITE_SRF);
    assign command_valid_o=(state_q==ISSUE);
    assign precision_o=PIM_PREC_FP16;
    always @* begin
      srf_write_data_o='0;srf_write_data_o[15:0]=mode_q?inv_q:{~mean_q[15],mean_q[14:0]};
      if(!mode_q)srf_write_data_o[31:16]=inv_q;
      context_key_o='0;context_key_o[TAG_WIDTH-1:0]=tag_q;
      last_step=mode_q?3'd1:3'd3;command_o='0;
      if(mode_q)begin
        if(step_q==0)command_o=enc(PIM_OP_MUL,PIM_OPD_GRF_A,PIM_OPD_EVEN_BANK,PIM_OPD_SRF_M,0,0,0);
        else command_o=enc(PIM_OP_MUL,PIM_OPD_M_OUT,PIM_OPD_GRF_A,PIM_OPD_GRF_B,0,0,{1'b0,gamma_q});
      end else begin
        case(step_q)
          0:command_o=enc(PIM_OP_ADD,PIM_OPD_GRF_A,PIM_OPD_EVEN_BANK,PIM_OPD_SRF_M,0,0,0);
          1:command_o=enc(PIM_OP_MUL,PIM_OPD_GRF_A,PIM_OPD_GRF_A,PIM_OPD_SRF_M,1,0,1);
          2:command_o=enc(PIM_OP_MUL,PIM_OPD_GRF_A,PIM_OPD_GRF_A,PIM_OPD_GRF_B,2,1,{1'b0,gamma_q});
          default:command_o=enc(PIM_OP_ADD,PIM_OPD_M_OUT,PIM_OPD_GRF_A,PIM_OPD_GRF_B,0,2,{1'b0,beta_q});
        endcase
      end
    end
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin state_q<=IDLE;mode_q<=0;tag_q<='0;mean_q<=0;inv_q<=0;
        gamma_q<=0;beta_q<=0;step_q<=0;transaction_done_o<=0;end
      else begin
        transaction_done_o<=0;
        case(state_q)
          IDLE:if(scalar_valid_i)begin mode_q<=scalar_rms_norm_i;tag_q<=scalar_tag_i;
            mean_q<=scalar_mean_i;inv_q<=scalar_inv_std_i;gamma_q<=gamma_grf_b_index_i;
            beta_q<=beta_grf_b_index_i;state_q<=WRITE_SRF;end
          WRITE_SRF:if(srf_write_ready_i)begin step_q<=0;state_q<=ISSUE;end
          ISSUE:if(command_ready_i)begin
            if(step_q==last_step)begin state_q<=IDLE;transaction_done_o<=1;end else step_q<=step_q+1'b1;
          end
          default:state_q<=IDLE;
        endcase
      end
    end
endmodule
