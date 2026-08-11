module fp16_mul (
    input  logic [15:0] lhs_i,
    input  logic [15:0] rhs_i,
    output logic [15:0] result_o
);
    logic sign;
    logic [4:0] lhs_exp, rhs_exp;
    logic [9:0] lhs_frac, rhs_frac;
    logic [10:0] lhs_sig, rhs_sig;
    logic [21:0] product;
    logic [63:0] magnitude, rounded_wide, low_mask;
    logic [4:0] result_exp_field;
    integer lhs_unbiased, rhs_unbiased, exponent, msb_index, shift_amount;
    logic round_up;

    always @* begin
        sign = lhs_i[15] ^ rhs_i[15];
        lhs_exp = lhs_i[14:10]; rhs_exp = rhs_i[14:10];
        lhs_frac = lhs_i[9:0]; rhs_frac = rhs_i[9:0];
        lhs_sig = {lhs_exp != 0, lhs_frac};
        rhs_sig = {rhs_exp != 0, rhs_frac};
        product = lhs_sig * rhs_sig;
        magnitude = product;
        lhs_unbiased = lhs_exp == 0 ? -14 : lhs_exp - 15;
        rhs_unbiased = rhs_exp == 0 ? -14 : rhs_exp - 15;
        msb_index = 0;
        for (integer bit_index = 0; bit_index < 22; bit_index = bit_index + 1)
            if (product[bit_index]) msb_index = bit_index;
        exponent = lhs_unbiased + rhs_unbiased - 20 + msb_index;
        rounded_wide = '0;
        low_mask = '0;
        round_up = 1'b0;
        result_exp_field = '0;
        if ((lhs_exp == 5'h1f && lhs_frac != 0) ||
                 (rhs_exp == 5'h1f && rhs_frac != 0) ||
                 ((lhs_exp == 5'h1f || rhs_exp == 5'h1f) &&
                  ((lhs_exp == 0 && lhs_frac == 0) || (rhs_exp == 0 && rhs_frac == 0))))
            result_o = 16'h7e00;
        else if (lhs_exp == 5'h1f || rhs_exp == 5'h1f)
            result_o = {sign, 5'h1f, 10'b0};
        else if ((lhs_exp == 0 && lhs_frac == 0) || (rhs_exp == 0 && rhs_frac == 0))
            result_o = {sign, 15'b0};
        else if (exponent >= 31) result_o = {sign, 5'h1f, 10'b0};
        else if (exponent >= -14) begin
            shift_amount = msb_index - 10;
            if (shift_amount > 0) begin
                rounded_wide = magnitude >> shift_amount;
                low_mask = (64'd1 << (shift_amount-1)) - 1'b1;
                round_up = magnitude[shift_amount-1] &&
                           ((|(magnitude & low_mask)) || rounded_wide[0]);
                rounded_wide = rounded_wide + round_up;
            end else rounded_wide = magnitude << (-shift_amount);
            if (rounded_wide >= 2048) begin
                rounded_wide = rounded_wide >> 1;
                exponent = exponent + 1;
            end
            if (exponent >= 16) result_o = {sign, 5'h1f, 10'b0};
            else begin
                result_exp_field = exponent + 15;
                result_o = {sign, result_exp_field, rounded_wide[9:0]};
            end
        end else begin
            // A half subnormal stores round(value / 2^-24).
            shift_amount = -(lhs_unbiased + rhs_unbiased + 4);
            if (shift_amount > 0) begin
                rounded_wide = magnitude >> shift_amount;
                low_mask = (64'd1 << (shift_amount-1)) - 1'b1;
                round_up = magnitude[shift_amount-1] &&
                           ((|(magnitude & low_mask)) || rounded_wide[0]);
                rounded_wide = rounded_wide + round_up;
            end else rounded_wide = magnitude << (-shift_amount);
            if (rounded_wide >= 1024) result_o = {sign, 5'd1, 10'd0};
            else result_o = {sign, 5'd0, rounded_wide[9:0]};
        end
    end
endmodule
