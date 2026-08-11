module shared_fp16_pipeline_fabric #(
    parameter int unsigned SOURCES = 8,
    parameter int unsigned PIPELINES = 1,
    parameter int unsigned LANES = 16,
    parameter int unsigned DATA_WIDTH = LANES * 16,
    parameter int unsigned SOURCE_WIDTH = SOURCES > 1 ? $clog2(SOURCES) : 1
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [SOURCES-1:0] request_valid_i,
    output logic [SOURCES-1:0] request_grant_o,
    input  logic [SOURCES-1:0][DATA_WIDTH-1:0] lhs_i,
    input  logic [SOURCES-1:0][DATA_WIDTH-1:0] rhs_i,
    output logic [SOURCES-1:0][DATA_WIDTH-1:0] result_o
);
    logic [SOURCE_WIDTH-1:0] round_robin_q;
    logic [PIPELINES-1:0] grant_valid;
    logic [PIPELINES-1:0][SOURCE_WIDTH-1:0] grant_source;
    logic [PIPELINES-1:0][DATA_WIDTH-1:0] pipeline_lhs, pipeline_rhs;
    logic [PIPELINES-1:0][DATA_WIDTH-1:0] pipeline_result;

    always @* begin
        logic [SOURCES-1:0] selected;
        logic found;
        integer candidate;
        selected = '0;
        request_grant_o = '0;
        grant_valid = '0;
        grant_source = '0;
        for (integer pipeline = 0; pipeline < PIPELINES; pipeline = pipeline + 1) begin
            found = 1'b0;
            for (integer offset = 0; offset < SOURCES; offset = offset + 1) begin
                candidate = (round_robin_q + offset) % SOURCES;
                if (!found && !selected[candidate] && request_valid_i[candidate]) begin
                    found = 1'b1;
                    selected[candidate] = 1'b1;
                    grant_valid[pipeline] = 1'b1;
                    grant_source[pipeline] = candidate[SOURCE_WIDTH-1:0];
                    request_grant_o[candidate] = 1'b1;
                end
            end
        end
    end

    always @* begin
        result_o = '0;
        pipeline_lhs = '0;
        pipeline_rhs = '0;
        for (integer pipeline = 0; pipeline < PIPELINES; pipeline = pipeline + 1)
            if (grant_valid[pipeline]) begin
                pipeline_lhs[pipeline] = lhs_i[grant_source[pipeline]];
                pipeline_rhs[pipeline] = rhs_i[grant_source[pipeline]];
                result_o[grant_source[pipeline]] = pipeline_result[pipeline];
            end
    end

    for (genvar pipeline = 0; pipeline < PIPELINES; pipeline++) begin : g_pipeline
        fp16_vector_add #(.LANES(LANES)) adder (
            .lhs_i(pipeline_lhs[pipeline]), .rhs_i(pipeline_rhs[pipeline]),
            .result_o(pipeline_result[pipeline])
        );
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) round_robin_q <= '0;
        else
            for (integer pipeline = 0; pipeline < PIPELINES; pipeline = pipeline + 1)
                if (grant_valid[pipeline]) round_robin_q <= grant_source[pipeline] + 1'b1;
    end

`ifndef SYNTHESIS
    initial begin
        if (SOURCES < 2 || (SOURCES & (SOURCES - 1)) != 0)
            $fatal(1, "SOURCES must be a power of two");
        if (PIPELINES == 0 || PIPELINES > SOURCES)
            $fatal(1, "PIPELINES must be in [1, SOURCES]");
    end
`endif
endmodule
