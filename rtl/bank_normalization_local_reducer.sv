module bank_normalization_local_reducer #(
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned COUNT_WIDTH = 16,
    parameter int unsigned DATA_FORMAT = 0 // 0=FP16, 1=BF16
) (
    input logic clk_i, input logic rst_ni,
    input logic begin_valid_i, output logic begin_ready_o,
    input logic [TAG_WIDTH-1:0] begin_tag_i,
    input logic [COUNT_WIDTH-1:0] begin_element_count_i,
    input logic element_valid_i, output logic element_ready_o,
    input logic [15:0] element_data_i,
    output logic result_valid_o, input logic result_ready_i,
    output logic [TAG_WIDTH-1:0] result_tag_o,
    output logic [15:0] result_sum_o, result_sumsq_o,
    output logic protocol_error_o
);
    logic active_q;
    logic [TAG_WIDTH-1:0] tag_q;
    logic [COUNT_WIDTH-1:0] remaining_q;
    logic [15:0] sum_q, sumsq_q, square, sum_next, sumsq_next;

    generate
        if (DATA_FORMAT == 0) begin : g_fp16
            fp16_mul u_square(.lhs_i(element_data_i),.rhs_i(element_data_i),.result_o(square));
            fp16_add u_sum(.lhs_i(sum_q),.rhs_i(element_data_i),.result_o(sum_next));
            fp16_add u_sumsq(.lhs_i(sumsq_q),.rhs_i(square),.result_o(sumsq_next));
        end else begin : g_bf16
            bf16_mul u_square(.lhs_i(element_data_i),.rhs_i(element_data_i),.result_o(square));
            bf16_add u_sum(.lhs_i(sum_q),.rhs_i(element_data_i),.result_o(sum_next));
            bf16_add u_sumsq(.lhs_i(sumsq_q),.rhs_i(square),.result_o(sumsq_next));
        end
    endgenerate

    assign begin_ready_o = !active_q && (!result_valid_o || result_ready_i);
    assign element_ready_o = active_q && (!result_valid_o || result_ready_i);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            active_q<=0;tag_q<='0;remaining_q<='0;sum_q<=0;sumsq_q<=0;
            result_valid_o<=0;result_tag_o<='0;result_sum_o<=0;result_sumsq_o<=0;
            protocol_error_o<=0;
        end else begin
            protocol_error_o<=0;
            if(result_valid_o&&result_ready_i)result_valid_o<=0;
            if(begin_valid_i&&begin_ready_o)begin
                if(begin_element_count_i==0)protocol_error_o<=1;
                else begin active_q<=1;tag_q<=begin_tag_i;remaining_q<=begin_element_count_i;
                    sum_q<=0;sumsq_q<=0;end
            end
            if(element_valid_i&&!element_ready_o)protocol_error_o<=1;
            if(element_valid_i&&element_ready_o)begin
                sum_q<=sum_next;sumsq_q<=sumsq_next;remaining_q<=remaining_q-1'b1;
                if(remaining_q==1)begin
                    active_q<=0;result_valid_o<=1;result_tag_o<=tag_q;
                    result_sum_o<=sum_next;result_sumsq_o<=sumsq_next;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial if (DATA_FORMAT > 1) $fatal(1, "DATA_FORMAT must be 0 (FP16) or 1 (BF16)");
`endif
endmodule
