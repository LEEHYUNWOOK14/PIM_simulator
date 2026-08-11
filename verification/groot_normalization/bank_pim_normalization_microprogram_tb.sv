module bank_pim_normalization_microprogram_tb;
    localparam int DATA_WIDTH = 256;
    localparam int LANES = DATA_WIDTH / 16;
`include "rtl/pim_rtl_constants.svh"

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic command_valid, command_ready;
    logic [31:0] command;
    logic [1:0] precision;
    logic [31:0] context_key;
    logic [DATA_WIDTH-1:0] even_data, odd_data;
    logic even_valid, odd_valid;
    logic register_write_valid, register_write_bank;
    logic [2:0] register_write_index;
    logic [DATA_WIDTH-1:0] register_write_data;
    logic srf_write_valid;
    logic [DATA_WIDTH-1:0] srf_write_data;
    logic result_valid, result_ready;
    logic [31:0] result_key;
    logic [2:0] result_destination;
    logic [3:0] result_index;
    logic [DATA_WIDTH-1:0] result_data;
    logic command_error;
    integer command_count, cycle_count;

    always #5 clk = ~clk;
    always @(posedge clk) if (rst_n) cycle_count <= cycle_count + 1;

    bank_pim_core #(.DATA_WIDTH(DATA_WIDTH), .KEY_WIDTH(32)) dut (
        .clk_i(clk), .rst_ni(rst_n),
        .command_valid_i(command_valid), .command_ready_o(command_ready),
        .command_i(command), .precision_i(precision), .context_key_i(context_key),
        .even_bank_data_i(even_data), .odd_bank_data_i(odd_data),
        .even_bank_valid_i(even_valid), .odd_bank_valid_i(odd_valid),
        .register_write_valid_i(register_write_valid),
        .register_write_bank_i(register_write_bank),
        .register_write_index_i(register_write_index),
        .register_write_data_i(register_write_data),
        .srf_write_valid_i(srf_write_valid), .srf_write_data_i(srf_write_data),
        .result_valid_o(result_valid), .result_ready_i(result_ready),
        .result_key_o(result_key), .result_destination_o(result_destination),
        .result_index_o(result_index), .result_data_o(result_data),
        .command_error_o(command_error));

    function automatic [31:0] encode_command(
        input logic [3:0] opcode,
        input logic [2:0] dst, src0, src1,
        input logic [3:0] dst_idx, src0_idx, src1_idx);
        begin
            encode_command = '0;
            encode_command[31:28] = opcode;
            encode_command[27:25] = dst;
            encode_command[24:22] = src0;
            encode_command[21:19] = src1;
            encode_command[11:8] = dst_idx;
            encode_command[7:4] = src0_idx;
            encode_command[3:0] = src1_idx;
        end
    endfunction

    task automatic write_srf(input logic [DATA_WIDTH-1:0] value);
        begin
            @(negedge clk);
            srf_write_data = value;
            srf_write_valid = 1'b1;
            @(negedge clk);
            srf_write_valid = 1'b0;
        end
    endtask

    task automatic write_grf_b(
        input logic [2:0] index,
        input logic [DATA_WIDTH-1:0] value);
        begin
            @(negedge clk);
            register_write_bank = 1'b1;
            register_write_index = index;
            register_write_data = value;
            register_write_valid = 1'b1;
            @(negedge clk);
            register_write_valid = 1'b0;
        end
    endtask

    task automatic issue_and_expect(
        input logic [31:0] cmd,
        input logic [DATA_WIDTH-1:0] expected,
        input logic [2:0] expected_dst,
        input logic [3:0] expected_idx,
        input string label_name);
        begin
            @(negedge clk);
            command = cmd;
            command_valid = 1'b1;
            while (!command_ready) @(negedge clk);
            @(negedge clk);
            command_valid = 1'b0;
            command_count = command_count + 1;
            if (!result_valid) $fatal(1, "%s: result_valid missing", label_name);
            if (result_data !== expected)
                $fatal(1, "%s: result mismatch got=%h expected=%h",
                       label_name, result_data, expected);
            if (result_destination !== expected_dst || result_index !== expected_idx)
                $fatal(1, "%s: result destination mismatch", label_name);
            if (result_key !== context_key) $fatal(1, "%s: context key mismatch", label_name);
            if (command_error) $fatal(1, "%s: legal command flagged", label_name);
        end
    endtask

    logic [DATA_WIDTH-1:0] rms_scalar, layer_scalars, gamma_vector, beta_vector;
    logic [DATA_WIDTH-1:0] rms_normalized, rms_affine_expected;
    logic [DATA_WIDTH-1:0] centered_expected, layer_normalized;
    logic [DATA_WIDTH-1:0] layer_scaled, layer_affine_expected;
    logic [15:0] x_lane;
    initial begin
        command_valid = 0; command = 0; precision = PIM_PREC_FP16;
        context_key = 32'h4e4f524d;
        even_data = '0; odd_data = '0; even_valid = 1; odd_valid = 0;
        register_write_valid = 0; register_write_bank = 0;
        register_write_index = 0; register_write_data = 0;
        srf_write_valid = 0; srf_write_data = 0;
        result_ready = 1; command_count = 0; cycle_count = 0;
        rms_scalar = '0; layer_scalars = '0; gamma_vector = '0; beta_vector = '0;
        rms_normalized = '0; rms_affine_expected = '0;
        centered_expected = '0; layer_normalized = '0;
        layer_scaled = '0; layer_affine_expected = '0;

        // Repeated exact FP16 inputs: 2, 3, 4, 1.
        for (integer lane = 0; lane < LANES; lane++) begin
            case (lane % 4)
                0: begin x_lane = 16'h4000; rms_normalized[lane*16 +: 16] = 16'h3c00;
                         rms_affine_expected[lane*16 +: 16] = 16'h4000;
                         centered_expected[lane*16 +: 16] = 16'h3c00;
                         layer_normalized[lane*16 +: 16] = 16'h3800;
                         layer_scaled[lane*16 +: 16] = 16'h3c00;
                         layer_affine_expected[lane*16 +: 16] = 16'h3e00; end
                1: begin x_lane = 16'h4200; rms_normalized[lane*16 +: 16] = 16'h3e00;
                         rms_affine_expected[lane*16 +: 16] = 16'h4200;
                         centered_expected[lane*16 +: 16] = 16'h4000;
                         layer_normalized[lane*16 +: 16] = 16'h3c00;
                         layer_scaled[lane*16 +: 16] = 16'h4000;
                         layer_affine_expected[lane*16 +: 16] = 16'h4100; end
                2: begin x_lane = 16'h4400; rms_normalized[lane*16 +: 16] = 16'h4000;
                         rms_affine_expected[lane*16 +: 16] = 16'h4400;
                         centered_expected[lane*16 +: 16] = 16'h4200;
                         layer_normalized[lane*16 +: 16] = 16'h3e00;
                         layer_scaled[lane*16 +: 16] = 16'h4200;
                         layer_affine_expected[lane*16 +: 16] = 16'h4300; end
                default: begin x_lane = 16'h3c00; rms_normalized[lane*16 +: 16] = 16'h3800;
                         rms_affine_expected[lane*16 +: 16] = 16'h3c00;
                         centered_expected[lane*16 +: 16] = 16'h0000;
                         layer_normalized[lane*16 +: 16] = 16'h0000;
                         layer_scaled[lane*16 +: 16] = 16'h0000;
                         layer_affine_expected[lane*16 +: 16] = 16'h3800; end
            endcase
            even_data[lane*16 +: 16] = x_lane;
            gamma_vector[lane*16 +: 16] = 16'h4000; // gamma = 2.0
            beta_vector[lane*16 +: 16] = 16'h3800;  // beta = 0.5
        end
        rms_scalar[15:0] = 16'h3800;       // inv_rms = 0.5
        layer_scalars[15:0] = 16'hbc00;    // -mean = -1.0
        layer_scalars[31:16] = 16'h3800;   // inv_std = 0.5

        repeat (3) @(negedge clk);
        rst_n = 1;

        // Affine RMSNorm: scalar and gamma loads, normalize, then scale.
        write_srf(rms_scalar);
        write_grf_b(0, gamma_vector);
        issue_and_expect(
            encode_command(PIM_OP_MUL, PIM_OPD_GRF_A, PIM_OPD_EVEN_BANK,
                           PIM_OPD_SRF_M, 0, 0, 0),
            rms_normalized, PIM_OPD_GRF_A, 0, "rmsnorm_normalize");
        issue_and_expect(
            encode_command(PIM_OP_MUL, PIM_OPD_M_OUT, PIM_OPD_GRF_A,
                           PIM_OPD_GRF_B, 0, 0, 0),
            rms_affine_expected, PIM_OPD_M_OUT, 0, "rmsnorm_gamma");

        // Affine LayerNorm: center, normalize, gamma scale, beta shift.
        write_srf(layer_scalars);
        write_grf_b(1, beta_vector);
        issue_and_expect(
            encode_command(PIM_OP_ADD, PIM_OPD_GRF_A, PIM_OPD_EVEN_BANK,
                           PIM_OPD_SRF_M, 1, 0, 0),
            centered_expected, PIM_OPD_GRF_A, 1, "layernorm_center");
        issue_and_expect(
            encode_command(PIM_OP_MUL, PIM_OPD_GRF_A, PIM_OPD_GRF_A,
                           PIM_OPD_SRF_M, 2, 1, 1),
            layer_normalized, PIM_OPD_GRF_A, 2, "layernorm_normalize");
        issue_and_expect(
            encode_command(PIM_OP_MUL, PIM_OPD_GRF_A, PIM_OPD_GRF_A,
                           PIM_OPD_GRF_B, 3, 2, 0),
            layer_scaled, PIM_OPD_GRF_A, 3, "layernorm_gamma");
        issue_and_expect(
            encode_command(PIM_OP_ADD, PIM_OPD_M_OUT, PIM_OPD_GRF_A,
                           PIM_OPD_GRF_B, 0, 3, 1),
            layer_affine_expected, PIM_OPD_M_OUT, 0, "layernorm_beta");

        $display("BANK_PIM_NORMALIZATION_MICROPROGRAM_TB PASS commands=%0d cycles=%0d lanes=%0d",
                 command_count, cycle_count, LANES);
        $finish;
    end
endmodule
