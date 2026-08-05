module bank_local_reduction_buffer #(
    parameter int unsigned BANKS = 8,
    parameter int unsigned ENTRIES_PER_BANK = 16,
    parameter int unsigned KEY_WIDTH = 64,
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned SLOT_WIDTH = $clog2(ENTRIES_PER_BANK)
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [BANKS-1:0] update_valid_i,
    output logic [BANKS-1:0] update_ready_o,
    input  logic [BANKS-1:0][KEY_WIDTH-1:0] update_key_i,
    input  logic [BANKS-1:0][SLOT_WIDTH-1:0] update_slot_i,
    input  logic [BANKS-1:0][DATA_WIDTH-1:0] update_partial_i,
    input  logic [BANKS-1:0] update_first_i,
    input  logic [BANKS-1:0] update_last_i,

    output logic [BANKS-1:0][DATA_WIDTH-1:0] add_lhs_o,
    output logic [BANKS-1:0][DATA_WIDTH-1:0] add_rhs_o,
    input  logic [BANKS-1:0][DATA_WIDTH-1:0] add_result_i,

    output logic [BANKS-1:0] final_valid_o,
    input  logic [BANKS-1:0] final_ready_i,
    output logic [BANKS-1:0][KEY_WIDTH-1:0] final_key_o,
    output logic [BANKS-1:0][DATA_WIDTH-1:0] final_data_o,

    output logic [BANKS-1:0] protocol_error_o
);
    logic [BANKS-1:0][ENTRIES_PER_BANK-1:0] entry_valid_q;
    logic [BANKS-1:0][ENTRIES_PER_BANK-1:0][KEY_WIDTH-1:0] entry_key_q;
    logic [BANKS-1:0][ENTRIES_PER_BANK-1:0][DATA_WIDTH-1:0] entry_data_q;

    logic [BANKS-1:0] final_valid_q;
    logic [BANKS-1:0][KEY_WIDTH-1:0] final_key_q;
    logic [BANKS-1:0][DATA_WIDTH-1:0] final_data_q;

    for (genvar bank = 0; bank < BANKS; bank++) begin : g_accumulator_bank
        always @* begin
            update_ready_o[bank] =
                (update_first_i[bank]
                     ? !entry_valid_q[bank][update_slot_i[bank]]
                     : entry_valid_q[bank][update_slot_i[bank]] &&
                           entry_key_q[bank][update_slot_i[bank]] == update_key_i[bank]) &&
                                   (!update_last_i[bank] || !final_valid_q[bank] ||
                                    final_ready_i[bank]);
            add_lhs_o[bank] = update_first_i[bank]
                                  ? '0
                                  : entry_data_q[bank][update_slot_i[bank]];
            add_rhs_o[bank] = update_partial_i[bank];
            protocol_error_o[bank] =
                update_valid_i[bank] &&
                !(update_first_i[bank]
                      ? !entry_valid_q[bank][update_slot_i[bank]]
                      : entry_valid_q[bank][update_slot_i[bank]] &&
                            entry_key_q[bank][update_slot_i[bank]] == update_key_i[bank]);
        end

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                entry_valid_q[bank] <= '0;
                entry_key_q[bank] <= '0;
                entry_data_q[bank] <= '0;
                final_valid_q[bank] <= 1'b0;
                final_key_q[bank] <= '0;
                final_data_q[bank] <= '0;
            end else begin
                if (final_valid_q[bank] && final_ready_i[bank])
                    final_valid_q[bank] <= 1'b0;

                if (update_valid_i[bank] && update_ready_o[bank]) begin
                    if (update_last_i[bank]) begin
                        final_valid_q[bank] <= 1'b1;
                        final_key_q[bank] <= update_key_i[bank];
                        final_data_q[bank] <= add_result_i[bank];
                        entry_valid_q[bank][update_slot_i[bank]] <= 1'b0;
                    end else begin
                        entry_valid_q[bank][update_slot_i[bank]] <= 1'b1;
                        entry_key_q[bank][update_slot_i[bank]] <= update_key_i[bank];
                        entry_data_q[bank][update_slot_i[bank]] <= add_result_i[bank];
                    end
                end
            end
        end
    end

    assign final_valid_o = final_valid_q;
    assign final_key_o = final_key_q;
    assign final_data_o = final_data_q;

`ifndef SYNTHESIS
    initial begin
        if (BANKS == 0) $fatal(1, "BANKS must be non-zero");
        if (ENTRIES_PER_BANK < 2 || 2**SLOT_WIDTH < ENTRIES_PER_BANK)
            $fatal(1, "SLOT_WIDTH cannot address ENTRIES_PER_BANK");
    end
`endif
endmodule
