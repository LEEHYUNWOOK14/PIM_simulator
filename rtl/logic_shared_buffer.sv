module logic_shared_buffer #(
    parameter int unsigned DATA_WIDTH = 256,
    parameter int unsigned BYTES = 65536,
    parameter int unsigned DEPTH = BYTES / (DATA_WIDTH/8),
    parameter int unsigned ADDR_WIDTH = DEPTH > 1 ? $clog2(DEPTH) : 1
) (
    input logic clk_i, input logic rst_ni,
    input logic write_valid_i, output logic write_ready_o,
    input logic [ADDR_WIDTH-1:0] write_addr_i,
    input logic [DATA_WIDTH-1:0] write_data_i,
    input logic [DATA_WIDTH/8-1:0] write_mask_i,
    input logic read_valid_i, output logic read_ready_o,
    input logic [ADDR_WIDTH-1:0] read_addr_i,
    output logic response_valid_o, input logic response_ready_i,
    output logic [DATA_WIDTH-1:0] response_data_o,
    input logic context_commit_i,
    input logic [15:0] context_id_i,
    output logic context_valid_o,
    output logic [15:0] resident_context_o
);
    logic [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    logic resident_valid_q;
    assign write_ready_o = 1'b1;
    assign read_ready_o = !response_valid_o || response_ready_i;
    assign context_valid_o = resident_valid_q && resident_context_o == context_id_i;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            response_valid_o <= 1'b0;
            response_data_o <= '0;
            resident_context_o <= '0;
            resident_valid_q <= 1'b0;
        end else begin
            if (response_valid_o && response_ready_i) response_valid_o <= 1'b0;
            if (write_valid_i && write_ready_o)
                for (integer byte_idx = 0; byte_idx < DATA_WIDTH/8; byte_idx = byte_idx + 1)
                    if (write_mask_i[byte_idx])
                        memory[write_addr_i][byte_idx*8 +: 8] <= write_data_i[byte_idx*8 +: 8];
            if (read_valid_i && read_ready_o) begin
                response_valid_o <= 1'b1;
                response_data_o <= memory[read_addr_i];
            end
            if (context_commit_i) begin
                resident_context_o <= context_id_i;
                resident_valid_q <= 1'b1;
            end
        end
    end
endmodule
