module logic_result_router #(
    parameter int unsigned KEY_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 256
) (
    input logic result_valid_i, output logic result_ready_o,
    input logic destination_bank_i,
    input logic [KEY_WIDTH-1:0] result_key_i,
    input logic [DATA_WIDTH-1:0] result_data_i,
    output logic bank_valid_o, input logic bank_ready_i,
    output logic [KEY_WIDTH-1:0] bank_key_o,
    output logic [DATA_WIDTH-1:0] bank_data_o,
    output logic host_valid_o, input logic host_ready_i,
    output logic [KEY_WIDTH-1:0] host_key_o,
    output logic [DATA_WIDTH-1:0] host_data_o
);
    always @* begin
        bank_valid_o = result_valid_i && destination_bank_i;
        host_valid_o = result_valid_i && !destination_bank_i;
        result_ready_o = destination_bank_i ? bank_ready_i : host_ready_i;
        bank_key_o = result_key_i; host_key_o = result_key_i;
        bank_data_o = result_data_i; host_data_o = result_data_i;
    end
endmodule
