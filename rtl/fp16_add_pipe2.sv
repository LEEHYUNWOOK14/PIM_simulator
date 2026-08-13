// Two-stage FP16 adder candidate for timing closure experiments.
// Stage 1 performs operand ordering/alignment; stage 2 performs add,
// normalization and round-to-nearest-even. II=1, latency=1 cycle.
module fp16_add_pipe2 (
    input logic clk_i, input logic rst_ni,
    input logic valid_i, output logic valid_o,
    input logic [15:0] lhs_i, input logic [15:0] rhs_i,
    output logic [15:0] result_o
);
    function automatic [13:0] shift_right_sticky(input logic [13:0] value, input integer amount);
        logic sticky;
        begin
            if (amount <= 0) shift_right_sticky=value;
            else if (amount >= 14) shift_right_sticky={13'b0,|value};
            else begin
                sticky=|(value & ((14'b1 << amount)-1'b1));
                shift_right_sticky=value >> amount;
                shift_right_sticky[0]=shift_right_sticky[0]|sticky;
            end
        end
    endfunction

    logic [4:0] lhs_exp, rhs_exp, large_exp_d, small_exp_d;
    logic [9:0] lhs_frac, rhs_frac;
    logic [10:0] lhs_sig, rhs_sig, large_sig_d, small_sig_d;
    logic [13:0] large_ext_d, small_ext_d;
    logic large_sign_d, small_sign_d;
    logic lhs_nan_d, rhs_nan_d, lhs_inf_d, rhs_inf_d;
    logic zero_inputs_d;
    logic [13:0] large_ext_q, small_ext_q;
    logic [4:0] large_exp_q;
    logic large_sign_q, small_sign_q;
    logic lhs_nan_q, rhs_nan_q, lhs_inf_q, rhs_inf_q, zero_inputs_q;
    logic [15:0] result_d;
    logic valid_q;
    integer shift_amount_d;

    always @* begin
        lhs_exp=lhs_i[14:10]; rhs_exp=rhs_i[14:10];
        lhs_frac=lhs_i[9:0]; rhs_frac=rhs_i[9:0];
        lhs_sig={lhs_exp!=0,lhs_frac}; rhs_sig={rhs_exp!=0,rhs_frac};
        large_exp_d=(lhs_exp==0)?5'd1:lhs_exp;
        small_exp_d=(rhs_exp==0)?5'd1:rhs_exp;
        large_sig_d=lhs_sig; small_sig_d=rhs_sig;
        large_sign_d=lhs_i[15]; small_sign_d=rhs_i[15];
        if ({((rhs_exp==0)?5'd1:rhs_exp),rhs_sig} >
            {((lhs_exp==0)?5'd1:lhs_exp),lhs_sig}) begin
            large_exp_d=(rhs_exp==0)?5'd1:rhs_exp;
            small_exp_d=(lhs_exp==0)?5'd1:lhs_exp;
            large_sig_d=rhs_sig; small_sig_d=lhs_sig;
            large_sign_d=rhs_i[15]; small_sign_d=lhs_i[15];
        end
        large_ext_d={large_sig_d,3'b000};
        shift_amount_d=large_exp_d-small_exp_d;
        small_ext_d=shift_right_sticky({small_sig_d,3'b000},shift_amount_d);
        lhs_nan_d=(lhs_exp==5'h1f && lhs_frac!=0);
        rhs_nan_d=(rhs_exp==5'h1f && rhs_frac!=0);
        lhs_inf_d=(lhs_exp==5'h1f && lhs_frac==0);
        rhs_inf_d=(rhs_exp==5'h1f && rhs_frac==0);
        zero_inputs_d=(lhs_exp==0 && lhs_frac==0 && rhs_exp==0 && rhs_frac==0);
    end

    integer result_exp, normalize_step;
    logic [14:0] add_ext;
    logic [13:0] magnitude_ext;
    logic [11:0] rounded_sig;
    logic round_up, result_sign;
    always @* begin
        result_sign=large_sign_q; result_exp=large_exp_q; add_ext='0; magnitude_ext='0;
        normalize_step=0;
        if (large_sign_q==small_sign_q) begin
            add_ext={1'b0,large_ext_q}+{1'b0,small_ext_q};
            if (add_ext[14]) begin magnitude_ext=add_ext[14:1]; magnitude_ext[0]=magnitude_ext[0]|add_ext[0]; result_exp=result_exp+1; end
            else magnitude_ext=add_ext[13:0];
        end else begin
            magnitude_ext=large_ext_q-small_ext_q;
            for(normalize_step=0;normalize_step<13;normalize_step=normalize_step+1)
                if(!magnitude_ext[13] && result_exp>1) begin magnitude_ext=magnitude_ext<<1; result_exp=result_exp-1; end
        end
        round_up=magnitude_ext[2] && (magnitude_ext[1]||magnitude_ext[0]||magnitude_ext[3]);
        rounded_sig={1'b0,magnitude_ext[13:3]}+round_up;
        if(rounded_sig[11]) begin rounded_sig=rounded_sig>>1; result_exp=result_exp+1; end
        result_d={result_sign,result_exp[4:0],rounded_sig[9:0]};
        if(lhs_nan_q||rhs_nan_q||(lhs_inf_q&&rhs_inf_q&&large_sign_q!=small_sign_q)) result_d=16'h7e00;
        else if(lhs_inf_q) result_d={large_sign_q,5'h1f,10'b0};
        else if(rhs_inf_q) result_d={large_sign_q,5'h1f,10'b0};
        else if(zero_inputs_q) result_d={large_sign_q&small_sign_q,15'b0};
        else if(magnitude_ext==0) result_d=16'h0000;
        else if(result_exp>=31) result_d={result_sign,5'h1f,10'b0};
        else if(result_exp<=1 && !rounded_sig[10]) result_d={result_sign,5'b0,rounded_sig[9:0]};
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin valid_q<=0; valid_o<=0; result_o<='0; large_ext_q<='0; small_ext_q<='0; large_exp_q<='0;
            large_sign_q<=0; small_sign_q<=0; lhs_nan_q<=0; rhs_nan_q<=0; lhs_inf_q<=0; rhs_inf_q<=0; zero_inputs_q<=0;
        end else begin
            valid_o<=valid_q; valid_q<=valid_i; result_o<=result_d;
            if(valid_i) begin large_ext_q<=large_ext_d; small_ext_q<=small_ext_d; large_exp_q<=large_exp_d;
                large_sign_q<=large_sign_d; small_sign_q<=small_sign_d; lhs_nan_q<=lhs_nan_d; rhs_nan_q<=rhs_nan_d;
                lhs_inf_q<=lhs_inf_d; rhs_inf_q<=rhs_inf_d; zero_inputs_q<=zero_inputs_d; end
        end
    end
endmodule
