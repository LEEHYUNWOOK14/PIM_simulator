module fp16_add_random_tb;
    logic [15:0] lhs, rhs, result;
    logic [15:0] expected;
    integer vectors, status, count;
    string vector_path;
    fp16_add dut(.lhs_i(lhs), .rhs_i(rhs), .result_o(result));

    initial begin
        if (!$value$plusargs("VECTORS=%s", vector_path))
            $fatal(1, "missing +VECTORS=path");
        vectors = $fopen(vector_path, "r");
        if (!vectors) $fatal(1, "cannot open %s", vector_path);
        count = 0;
        while (!$feof(vectors)) begin
            status = $fscanf(vectors, "%h %h %h\n", lhs, rhs, expected);
            if (status == 3) begin
                #1;
                if (result !== expected)
                    $fatal(1, "vector %0d lhs=%h rhs=%h got=%h expected=%h",
                           count, lhs, rhs, result, expected);
                count = count + 1;
            end
        end
        $fclose(vectors);
        if (count != 4096) $fatal(1, "expected 4096 vectors, read %0d", count);
        $display("FP16_ADD_RANDOM_TB PASS vectors[%0d] reference[C++ half.h]", count);
        $finish;
    end
endmodule
