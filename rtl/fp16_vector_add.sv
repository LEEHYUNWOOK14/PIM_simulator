module fp16_vector_add #(
    parameter int unsigned LANES = 16
) (
    input  logic [LANES*16-1:0] lhs_i,
    input  logic [LANES*16-1:0] rhs_i,
    output logic [LANES*16-1:0] result_o
);
    for (genvar lane = 0; lane < LANES; lane++) begin : g_lane
        fp16_add adder (
            .lhs_i(lhs_i[lane * 16 +: 16]),
            .rhs_i(rhs_i[lane * 16 +: 16]),
            .result_o(result_o[lane * 16 +: 16])
        );
    end
endmodule
