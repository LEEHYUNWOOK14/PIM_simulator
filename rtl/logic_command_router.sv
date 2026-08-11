module logic_command_router #(
    parameter int unsigned PACKET_WIDTH = 512
) (
    input logic request_valid_i,
    output logic request_ready_o,
    input logic target_logic_i,
    input logic [PACKET_WIDTH-1:0] request_packet_i,
    output logic bank_valid_o,
    input logic bank_ready_i,
    output logic [PACKET_WIDTH-1:0] bank_packet_o,
    output logic logic_valid_o,
    input logic logic_ready_i,
    output logic [PACKET_WIDTH-1:0] logic_packet_o
);
    always @* begin
        bank_valid_o = request_valid_i && !target_logic_i;
        logic_valid_o = request_valid_i && target_logic_i;
        request_ready_o = target_logic_i ? logic_ready_i : bank_ready_i;
        bank_packet_o = request_packet_i;
        logic_packet_o = request_packet_i;
    end
endmodule
