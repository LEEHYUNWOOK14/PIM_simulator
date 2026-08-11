module logic_normalization_scalar_engine #(
    parameter int unsigned TAG_WIDTH = 16
) (
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic                 request_valid_i,
    output logic                 request_ready_o,
    input  logic                 rms_norm_i,
    input  logic [TAG_WIDTH-1:0] request_tag_i,
    input  logic [15:0]          sum_i,
    input  logic [15:0]          sumsq_i,
    input  logic [15:0]          inv_hidden_i,
    input  logic [15:0]          epsilon_i,
    output logic                 response_valid_o,
    input  logic                 response_ready_i,
    output logic                 response_rms_norm_o,
    output logic [TAG_WIDTH-1:0] response_tag_o,
    output logic [15:0]          mean_o,
    output logic [15:0]          inv_std_o,
    output logic                 variance_clamped_o
);
    typedef enum logic [2:0] {IDLE, VARIANCE, EPSILON, RSQRT_SEND, RSQRT_WAIT} state_t;
    state_t state_q;
    logic mode_q, clamped_q;
    logic [TAG_WIDTH-1:0] tag_q;
    logic [15:0] epsilon_q, mean_q, mean_square_q, variance_q, argument_q;
    logic [15:0] input_mean, input_mean_square, mean_squared, negative_mean_squared;
    logic [15:0] variance_raw, variance_nonnegative, epsilon_result;
    logic rsqrt_input_valid, rsqrt_input_ready, rsqrt_output_valid, rsqrt_output_ready;
    logic [15:0] rsqrt_output_data;

    fp16_mul u_mean_mul(.lhs_i(sum_i),.rhs_i(inv_hidden_i),.result_o(input_mean));
    fp16_mul u_mean_square_mul(.lhs_i(sumsq_i),.rhs_i(inv_hidden_i),
                               .result_o(input_mean_square));
    fp16_mul u_square_mean(.lhs_i(mean_q),.rhs_i(mean_q),.result_o(mean_squared));
    assign negative_mean_squared = {~mean_squared[15],mean_squared[14:0]};
    fp16_add u_variance_sub(.lhs_i(mean_square_q),.rhs_i(negative_mean_squared),
                            .result_o(variance_raw));
    assign variance_nonnegative = !mode_q && variance_raw[15] && |variance_raw[14:0] ?
                                  16'h0000 : variance_raw;
    fp16_add u_epsilon_add(.lhs_i(variance_q),.rhs_i(epsilon_q),.result_o(epsilon_result));

    assign rsqrt_input_valid = state_q == RSQRT_SEND;
    assign rsqrt_output_ready = state_q == RSQRT_WAIT &&
                                (!response_valid_o || response_ready_i);
    fp16_rsqrt_lut256 u_rsqrt(
        .clk_i,.rst_ni,.input_valid_i(rsqrt_input_valid),
        .input_ready_o(rsqrt_input_ready),.input_data_i(argument_q),
        .output_valid_o(rsqrt_output_valid),.output_ready_i(rsqrt_output_ready),
        .output_data_o(rsqrt_output_data));

    assign request_ready_o = state_q == IDLE &&
                             (!response_valid_o || response_ready_i);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            mode_q <= 1'b0;
            tag_q <= '0;
            epsilon_q <= '0;
            mean_q <= '0;
            mean_square_q <= '0;
            variance_q <= '0;
            argument_q <= '0;
            clamped_q <= 1'b0;
            response_valid_o <= 1'b0;
            response_rms_norm_o <= 1'b0;
            response_tag_o <= '0;
            mean_o <= '0;
            inv_std_o <= '0;
            variance_clamped_o <= 1'b0;
        end else begin
            if (response_valid_o && response_ready_i) response_valid_o <= 1'b0;
            case (state_q)
                IDLE: if (request_valid_i && request_ready_o) begin
                    mode_q <= rms_norm_i;
                    tag_q <= request_tag_i;
                    epsilon_q <= epsilon_i;
                    mean_q <= rms_norm_i ? 16'h0000 : input_mean;
                    mean_square_q <= input_mean_square;
                    clamped_q <= 1'b0;
                    state_q <= VARIANCE;
                end
                VARIANCE: begin
                    variance_q <= mode_q ? mean_square_q : variance_nonnegative;
                    clamped_q <= !mode_q && variance_raw[15] && |variance_raw[14:0];
                    state_q <= EPSILON;
                end
                EPSILON: begin
                    argument_q <= epsilon_result;
                    state_q <= RSQRT_SEND;
                end
                RSQRT_SEND: if (rsqrt_input_ready) state_q <= RSQRT_WAIT;
                RSQRT_WAIT: if (rsqrt_output_valid && rsqrt_output_ready) begin
                    response_valid_o <= 1'b1;
                    response_rms_norm_o <= mode_q;
                    response_tag_o <= tag_q;
                    mean_o <= mean_q;
                    inv_std_o <= rsqrt_output_data;
                    variance_clamped_o <= clamped_q;
                    state_q <= IDLE;
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
