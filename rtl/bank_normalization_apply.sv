module bank_normalization_apply #(
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned DATA_FORMAT = 0 // 0=FP16, 1=BF16
) (
    input logic clk_i, input logic rst_ni,
    input logic config_valid_i, output logic config_ready_o,
    input logic config_rms_norm_i,
    input logic [TAG_WIDTH-1:0] config_tag_i,
    input logic [15:0] config_mean_i, config_inv_std_i,
    input logic element_valid_i, output logic element_ready_o,
    input logic [TAG_WIDTH-1:0] element_tag_i,
    input logic [15:0] element_x_i, element_gamma_i, element_beta_i,
    input logic element_last_i,
    output logic result_valid_o, input logic result_ready_i,
    output logic [TAG_WIDTH-1:0] result_tag_o,
    output logic [15:0] result_data_o,
    output logic result_last_o,
    output logic context_error_o
);
    logic config_active_q, mode_q;
    logic [TAG_WIDTH-1:0] tag_q;
    logic [15:0] mean_q, inv_q, negative_mean, centered, normalized, scaled, shifted;
    assign negative_mean={~mean_q[15],mean_q[14:0]};
    generate
        if (DATA_FORMAT == 0) begin : g_fp16
            fp16_add u_center(.lhs_i(element_x_i),.rhs_i(negative_mean),.result_o(centered));
            fp16_mul u_normalize(.lhs_i(mode_q?element_x_i:centered),.rhs_i(inv_q),
                                 .result_o(normalized));
            fp16_mul u_gamma(.lhs_i(normalized),.rhs_i(element_gamma_i),.result_o(scaled));
            fp16_add u_beta(.lhs_i(scaled),.rhs_i(mode_q?16'h0000:element_beta_i),
                            .result_o(shifted));
        end else begin : g_bf16
            bf16_add u_center(.lhs_i(element_x_i),.rhs_i(negative_mean),.result_o(centered));
            bf16_mul u_normalize(.lhs_i(mode_q?element_x_i:centered),.rhs_i(inv_q),
                                 .result_o(normalized));
            bf16_mul u_gamma(.lhs_i(normalized),.rhs_i(element_gamma_i),.result_o(scaled));
            bf16_add u_beta(.lhs_i(scaled),.rhs_i(mode_q?16'h0000:element_beta_i),
                            .result_o(shifted));
        end
    endgenerate
    assign config_ready_o=!config_active_q&&(!result_valid_o||result_ready_i);
    assign element_ready_o=config_active_q&&element_tag_i==tag_q&&
                           (!result_valid_o||result_ready_i);
    always_ff @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin
            config_active_q<=0;mode_q<=0;tag_q<='0;mean_q<=0;inv_q<=0;
            result_valid_o<=0;result_tag_o<='0;result_data_o<=0;result_last_o<=0;
            context_error_o<=0;
        end else begin
            context_error_o<=0;
            if(result_valid_o&&result_ready_i)result_valid_o<=0;
            if(config_valid_i&&config_ready_o)begin
                config_active_q<=1;mode_q<=config_rms_norm_i;tag_q<=config_tag_i;
                mean_q<=config_mean_i;inv_q<=config_inv_std_i;
            end
            // Holding valid while ready is low is legal ready/valid behaviour.
            // Report only a missing context or a tag mismatch; downstream
            // backpressure must not be mistaken for a protocol violation.
            if(element_valid_i&&(!config_active_q||element_tag_i!=tag_q))
                context_error_o<=1;
            if(element_valid_i&&element_ready_o)begin
                result_valid_o<=1;result_tag_o<=tag_q;result_data_o<=shifted;
                result_last_o<=element_last_i;
                if(element_last_i)config_active_q<=0;
            end
        end
    end

`ifndef SYNTHESIS
    initial if (DATA_FORMAT > 1) $fatal(1, "DATA_FORMAT must be 0 (FP16) or 1 (BF16)");
`endif
endmodule
