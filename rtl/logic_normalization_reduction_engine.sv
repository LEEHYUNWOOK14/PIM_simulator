module logic_normalization_reduction_engine #(
    parameter int unsigned BANKS = 16,
    parameter int unsigned TAG_WIDTH = 16,
    parameter int unsigned BANK_WIDTH = BANKS > 1 ? $clog2(BANKS) : 1
) (
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic                   begin_valid_i,
    output logic                   begin_ready_o,
    input  logic                   begin_rms_norm_i,
    input  logic [TAG_WIDTH-1:0]   begin_tag_i,
    input  logic [BANKS-1:0]       begin_expected_mask_i,
    input  logic [15:0]            begin_inv_hidden_i,
    input  logic [15:0]            begin_epsilon_i,
    input  logic                   partial_valid_i,
    output logic                   partial_ready_o,
    input  logic [BANK_WIDTH-1:0]  partial_bank_i,
    input  logic [TAG_WIDTH-1:0]   partial_tag_i,
    input  logic [15:0]            partial_sum_i,
    input  logic [15:0]            partial_sumsq_i,
    output logic                   response_valid_o,
    input  logic                   response_ready_i,
    output logic                   response_rms_norm_o,
    output logic [TAG_WIDTH-1:0]   response_tag_o,
    output logic [15:0]            response_mean_o,
    output logic [15:0]            response_inv_std_o,
    output logic                   response_variance_clamped_o,
    output logic                   duplicate_error_o,
    output logic                   context_error_o
);
    logic active_q, scalar_pending_q, scalar_inflight_q, mode_q;
    logic [TAG_WIDTH-1:0] tag_q;
    logic [BANKS-1:0] expected_q, received_q, received_next;
    logic [15:0] inv_hidden_q, epsilon_q, sum_q, sumsq_q;
    logic [15:0] sum_next, sumsq_next;
    logic scalar_request_ready;

    fp16_add u_sum_add(.lhs_i(sum_q),.rhs_i(partial_sum_i),.result_o(sum_next));
    fp16_add u_sumsq_add(.lhs_i(sumsq_q),.rhs_i(partial_sumsq_i),.result_o(sumsq_next));
    assign received_next = received_q |
        ({{(BANKS-1){1'b0}},1'b1} << partial_bank_i);

    assign begin_ready_o = !active_q && !scalar_pending_q && !scalar_inflight_q;
    assign partial_ready_o = active_q && partial_tag_i == tag_q &&
                             expected_q[partial_bank_i] && !received_q[partial_bank_i];

    logic_normalization_scalar_engine #(.TAG_WIDTH(TAG_WIDTH)) u_scalar(
        .clk_i,.rst_ni,.request_valid_i(scalar_pending_q),
        .request_ready_o(scalar_request_ready),.rms_norm_i(mode_q),
        .request_tag_i(tag_q),.sum_i(sum_q),.sumsq_i(sumsq_q),
        .inv_hidden_i(inv_hidden_q),.epsilon_i(epsilon_q),
        .response_valid_o(response_valid_o),.response_ready_i(response_ready_i),
        .response_rms_norm_o(response_rms_norm_o),.response_tag_o(response_tag_o),
        .mean_o(response_mean_o),.inv_std_o(response_inv_std_o),
        .variance_clamped_o(response_variance_clamped_o));

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            active_q <= 1'b0;
            scalar_pending_q <= 1'b0;
            scalar_inflight_q <= 1'b0;
            mode_q <= 1'b0;
            tag_q <= '0;
            expected_q <= '0;
            received_q <= '0;
            inv_hidden_q <= '0;
            epsilon_q <= '0;
            sum_q <= '0;
            sumsq_q <= '0;
            duplicate_error_o <= 1'b0;
            context_error_o <= 1'b0;
        end else begin
            duplicate_error_o <= 1'b0;
            context_error_o <= 1'b0;
            if (begin_valid_i && begin_ready_o) begin
                if (begin_expected_mask_i == 0) begin
                    context_error_o <= 1'b1;
                end else begin
                    active_q <= 1'b1;
                    mode_q <= begin_rms_norm_i;
                    tag_q <= begin_tag_i;
                    expected_q <= begin_expected_mask_i;
                    received_q <= '0;
                    inv_hidden_q <= begin_inv_hidden_i;
                    epsilon_q <= begin_epsilon_i;
                    sum_q <= 16'h0000;
                    sumsq_q <= 16'h0000;
                end
            end
            if (partial_valid_i && !partial_ready_o) begin
                if (active_q && partial_tag_i == tag_q &&
                    expected_q[partial_bank_i] && received_q[partial_bank_i])
                    duplicate_error_o <= 1'b1;
                else
                    context_error_o <= 1'b1;
            end
            if (partial_valid_i && partial_ready_o) begin
                sum_q <= sum_next;
                sumsq_q <= sumsq_next;
                received_q <= received_next;
                if (received_next == expected_q) begin
                    active_q <= 1'b0;
                    scalar_pending_q <= 1'b1;
                end
            end
            if (scalar_pending_q && scalar_request_ready) begin
                scalar_pending_q <= 1'b0;
                scalar_inflight_q <= 1'b1;
            end
            if (response_valid_o && response_ready_i)
                scalar_inflight_q <= 1'b0;
        end
    end
endmodule
