module logic_normalization_dispatcher_top #(
    parameter int unsigned ENGINES=4,
    parameter int unsigned BANKS=16,
    parameter int unsigned TAG_WIDTH=16,
    parameter int unsigned ENGINE_ID_WIDTH=ENGINES>1?$clog2(ENGINES):1,
    parameter int unsigned BANK_ID_WIDTH=BANKS>1?$clog2(BANKS):1
)(
    input logic clk_i,input logic rst_ni,
    input logic begin_valid_i,output logic begin_ready_o,
    input logic begin_rms_norm_i,input logic[TAG_WIDTH-1:0]begin_tag_i,
    input logic[BANKS-1:0]begin_expected_mask_i,
    input logic[15:0]begin_inv_hidden_i,begin_epsilon_i,
    input logic partial_valid_i,output logic partial_ready_o,
    input logic[TAG_WIDTH-1:0]partial_tag_i,
    input logic[BANK_ID_WIDTH-1:0]partial_bank_i,
    input logic[15:0]partial_sum_i,partial_sumsq_i,
    output logic response_valid_o,input logic response_ready_i,
    output logic response_rms_norm_o,output logic[TAG_WIDTH-1:0]response_tag_o,
    output logic[15:0]response_mean_o,response_inv_std_o,
    output logic response_variance_clamped_o,
    output logic duplicate_begin_error_o,unmatched_partial_error_o,
    output logic engine_protocol_error_o
);
    logic[ENGINES-1:0]active_q;
    logic[ENGINES-1:0][TAG_WIDTH-1:0]active_tag_q;
    logic[ENGINE_ID_WIDTH-1:0]begin_rr_q,response_rr_q;
    logic begin_found,begin_duplicate,partial_found,response_found;
    logic[ENGINE_ID_WIDTH-1:0]begin_sel,partial_sel,response_sel;
    logic[ENGINES-1:0]e_bv,e_br,e_mode,e_pv,e_pr,e_rv,e_rr,e_rmode,e_clamp,e_dup,e_ctx;
    logic[ENGINES-1:0][TAG_WIDTH-1:0]e_btag,e_ptag,e_rtag;
    logic[ENGINES-1:0][BANKS-1:0]e_mask;
    logic[ENGINES-1:0][15:0]e_invh,e_eps,e_psum,e_psq,e_mean,e_inv;
    logic[ENGINES-1:0][BANK_ID_WIDTH-1:0]e_pbank;

    always @* begin
        begin_found=0;begin_duplicate=0;begin_sel='0;
        for(integer e=0;e<ENGINES;e++)if(active_q[e]&&active_tag_q[e]==begin_tag_i)
            begin_duplicate=1;
        for(integer offset=0;offset<ENGINES;offset++)begin
            integer index;
            index=(begin_rr_q+offset)%ENGINES;
            if(!begin_found&&!active_q[index]&&e_br[index])begin
                begin_found=1;begin_sel=index[ENGINE_ID_WIDTH-1:0];
            end
        end
        begin_ready_o=begin_found&&!begin_duplicate;
        e_bv='0;e_mode={ENGINES{begin_rms_norm_i}};e_btag={ENGINES{begin_tag_i}};
        e_mask={ENGINES{begin_expected_mask_i}};e_invh={ENGINES{begin_inv_hidden_i}};
        e_eps={ENGINES{begin_epsilon_i}};
        if(begin_valid_i&&begin_ready_o)e_bv[begin_sel]=1;

        partial_found=0;partial_sel='0;
        for(integer e=0;e<ENGINES;e++)
            if(!partial_found&&active_q[e]&&active_tag_q[e]==partial_tag_i)begin
                partial_found=1;partial_sel=e[ENGINE_ID_WIDTH-1:0];
            end
        e_pv='0;e_ptag={ENGINES{partial_tag_i}};e_pbank={ENGINES{partial_bank_i}};
        e_psum={ENGINES{partial_sum_i}};e_psq={ENGINES{partial_sumsq_i}};
        partial_ready_o=partial_found&&e_pr[partial_sel];
        if(partial_valid_i&&partial_ready_o)e_pv[partial_sel]=1;

        response_found=0;response_sel='0;
        for(integer offset=0;offset<ENGINES;offset++)begin
            integer index;
            index=(response_rr_q+offset)%ENGINES;
            if(!response_found&&e_rv[index])begin
                response_found=1;response_sel=index[ENGINE_ID_WIDTH-1:0];
            end
        end
        response_valid_o=response_found;e_rr='0;
        response_rms_norm_o=response_found?e_rmode[response_sel]:0;
        response_tag_o=response_found?e_rtag[response_sel]:'0;
        response_mean_o=response_found?e_mean[response_sel]:'0;
        response_inv_std_o=response_found?e_inv[response_sel]:'0;
        response_variance_clamped_o=response_found?e_clamp[response_sel]:0;
        if(response_found)e_rr[response_sel]=response_ready_i;
    end

    assign engine_protocol_error_o=|e_dup|| |e_ctx;
    always_ff @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin
            active_q<='0;active_tag_q<='0;begin_rr_q<='0;response_rr_q<='0;
            duplicate_begin_error_o<=0;unmatched_partial_error_o<=0;
        end else begin
            duplicate_begin_error_o<=begin_valid_i&&begin_duplicate;
            unmatched_partial_error_o<=partial_valid_i&&!partial_found;
            if(begin_valid_i&&begin_ready_o)begin
                active_q[begin_sel]<=1;active_tag_q[begin_sel]<=begin_tag_i;
                begin_rr_q<=begin_sel+1'b1;
            end
            if(response_valid_o&&response_ready_i)begin
                active_q[response_sel]<=0;response_rr_q<=response_sel+1'b1;
            end
        end
    end

    logic_normalization_engine_array #(.ENGINES(ENGINES),.BANKS(BANKS),.TAG_WIDTH(TAG_WIDTH))u_array(
      .clk_i(clk_i),.rst_ni(rst_ni),.begin_valid_i(e_bv),.begin_ready_o(e_br),
      .begin_rms_norm_i(e_mode),.begin_tag_i(e_btag),.begin_expected_bank_mask_i(e_mask),
      .begin_inv_hidden_i(e_invh),.begin_epsilon_i(e_eps),.partial_valid_i(e_pv),
      .partial_ready_o(e_pr),.partial_tag_i(e_ptag),.partial_bank_i(e_pbank),
      .partial_sum_i(e_psum),.partial_sumsq_i(e_psq),.response_valid_o(e_rv),
      .response_ready_i(e_rr),.response_rms_norm_o(e_rmode),.response_tag_o(e_rtag),
      .response_mean_o(e_mean),.response_inv_std_o(e_inv),
      .response_variance_clamped_o(e_clamp),.duplicate_error_o(e_dup),.context_error_o(e_ctx));
`ifndef SYNTHESIS
    initial if(ENGINES==0||(ENGINES&(ENGINES-1))!=0)$fatal(1,"ENGINES must be power of two");
`endif
endmodule
