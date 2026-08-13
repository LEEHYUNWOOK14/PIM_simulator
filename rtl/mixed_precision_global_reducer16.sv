module mixed_precision_global_reducer16 #(
    parameter int unsigned TAG_WIDTH=16
)(
    input logic clk_i,input logic rst_ni,
    input logic input_valid_i,output logic input_ready_o,
    input logic[TAG_WIDTH-1:0]input_tag_i,
    input logic[15:0][31:0]partial_sum_i,partial_sumsq_i,
    output logic output_valid_o,input logic output_ready_i,
    output logic[TAG_WIDTH-1:0]output_tag_o,
    output logic[31:0]sum_o,sumsq_o
);
    logic advance;
    logic[3:0]valid_q;
    logic[3:0][TAG_WIDTH-1:0]tag_q;
    logic[7:0][31:0]sum_l0_d,sumsq_l0_d,sum_l0_q,sumsq_l0_q;
    logic[3:0][31:0]sum_l1_d,sumsq_l1_d,sum_l1_q,sumsq_l1_q;
    logic[1:0][31:0]sum_l2_d,sumsq_l2_d,sum_l2_q,sumsq_l2_q;
    logic[31:0]sum_l3_d,sumsq_l3_d,sum_l3_q,sumsq_l3_q;
    assign advance=!valid_q[3]||output_ready_i;
    assign input_ready_o=advance;
    assign output_valid_o=valid_q[3];assign output_tag_o=tag_q[3];
    assign sum_o=sum_l3_q;assign sumsq_o=sumsq_l3_q;
    for(genvar n=0;n<8;n++)begin:g_l0
      fp32_add u_sum(.lhs_i(partial_sum_i[n*2]),.rhs_i(partial_sum_i[n*2+1]),.result_o(sum_l0_d[n]));
      fp32_add u_sumsq(.lhs_i(partial_sumsq_i[n*2]),.rhs_i(partial_sumsq_i[n*2+1]),.result_o(sumsq_l0_d[n]));
    end
    for(genvar n=0;n<4;n++)begin:g_l1
      fp32_add u_sum(.lhs_i(sum_l0_q[n*2]),.rhs_i(sum_l0_q[n*2+1]),.result_o(sum_l1_d[n]));
      fp32_add u_sumsq(.lhs_i(sumsq_l0_q[n*2]),.rhs_i(sumsq_l0_q[n*2+1]),.result_o(sumsq_l1_d[n]));
    end
    for(genvar n=0;n<2;n++)begin:g_l2
      fp32_add u_sum(.lhs_i(sum_l1_q[n*2]),.rhs_i(sum_l1_q[n*2+1]),.result_o(sum_l2_d[n]));
      fp32_add u_sumsq(.lhs_i(sumsq_l1_q[n*2]),.rhs_i(sumsq_l1_q[n*2+1]),.result_o(sumsq_l2_d[n]));
    end
    fp32_add u_sum_l3(.lhs_i(sum_l2_q[0]),.rhs_i(sum_l2_q[1]),.result_o(sum_l3_d));
    fp32_add u_sumsq_l3(.lhs_i(sumsq_l2_q[0]),.rhs_i(sumsq_l2_q[1]),.result_o(sumsq_l3_d));
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin valid_q<=0;tag_q<=0;sum_l0_q<=0;sumsq_l0_q<=0;sum_l1_q<=0;sumsq_l1_q<=0;sum_l2_q<=0;sumsq_l2_q<=0;sum_l3_q<=0;sumsq_l3_q<=0;end
      else if(advance)begin
        valid_q[0]<=input_valid_i;valid_q[1]<=valid_q[0];valid_q[2]<=valid_q[1];valid_q[3]<=valid_q[2];
        tag_q[0]<=input_tag_i;tag_q[1]<=tag_q[0];tag_q[2]<=tag_q[1];tag_q[3]<=tag_q[2];
        if(input_valid_i)begin sum_l0_q<=sum_l0_d;sumsq_l0_q<=sumsq_l0_d;end
        if(valid_q[0])begin sum_l1_q<=sum_l1_d;sumsq_l1_q<=sumsq_l1_d;end
        if(valid_q[1])begin sum_l2_q<=sum_l2_d;sumsq_l2_q<=sumsq_l2_d;end
        if(valid_q[2])begin sum_l3_q<=sum_l3_d;sumsq_l3_q<=sumsq_l3_d;end
      end
    end
endmodule

