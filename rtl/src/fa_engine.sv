// FA_ENGINE: tiled FlashAttention with online softmax, driven by an in-memory descriptor.
//
//   FA_BEGIN descriptor (6 consecutive words at desc_addr):
//     [0] Q_ptr  [1] K_ptr  [2] V_ptr  [3] O_ptr  [4] sequence_length N  [5] head_dimension d
//   Q, K, V, O are N x d row-major word arrays. Q/K/V elements are Q4.4 int8 (low 8 bits of the
//   word); O elements are signed integers with 8 fractional bits.
//
//   FA_ENGINE
//   |-- Q_TILE_SRAM / K_TILE_SRAM / V_TILE_SRAM
//   |-- QK_DOT_PRODUCT (fa_qk_mac)  -> ROW_MAX (fa_row_max)
//   |-- ONLINE_SOFTMAX (m, l) with EXP_APPROX
//   |-- PV_ACCUMULATOR
//   |-- OUTPUT_NORMALIZER
//   `-- DMA / MEMORY_INTERFACE
//
// start/desc_addr are sampled while idle. done pulses when finished; err is set (until the next
// start) if the descriptor is invalid, in which case memory is not written.

module fa_engine
    import fa_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        start,
    input  logic [31:0] desc_addr,
    output logic        busy,
    output logic        done,
    output logic        err,

    output logic        mem_req,
    output logic        mem_we,
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    input  logic [31:0] mem_rdata,
    input  logic        mem_ready
);

    localparam int RW = $clog2(BR);
    localparam int CW = $clog2(D_MAX);
    localparam logic [31:0] MAX_N = 32'd1_048_576;

    localparam logic [1:0] OP_LOAD = 2'd0, OP_RD = 2'd1, OP_WR = 2'd2;
    localparam logic [1:0] TGT_Q = 2'd0, TGT_K = 2'd1, TGT_V = 2'd2;

    typedef enum logic [5:0] {
        S_IDLE, S_DESC_REQ, S_DESC_WAIT, S_CHECK,
        S_Q_REQ, S_Q_WAIT, S_INIT,
        S_K_REQ, S_K_WAIT, S_V_REQ, S_V_WAIT,
        S_SC_CLR, S_SC_RD, S_SC_FEED, S_SC_WAIT,
        S_TILE_ST, S_ALPHA_WAIT, S_RESC, S_RESC_WAIT,
        S_PR_RD, S_PR_WAIT, S_PR_ACC, S_PR_ACCW,
        S_NRM_START, S_NRM_WAIT, S_NRM_STORE, S_NRM_STWAIT,
        S_FIN, S_ERR
    } state_t;
    state_t state;

    // descriptor
    logic [31:0] desc_base;
    logic [2:0]  dcnt;
    logic [31:0] q_ptr, k_ptr, v_ptr, o_ptr, seq_n, hd;

    // loop state
    logic [31:0] i0, j0, rows_q, keys_k, r, jj, nr, nc;
    logic [1:0]  tgt;
    logic signed [31:0] score_buf [BC];
    logic signed [31:0] nrm_out_q;
    logic err_q;

    assign busy = (state != S_IDLE);
    assign err  = err_q;

    function automatic logic [31:0] min32(input logic [31:0] a, input logic [31:0] b);
        return (a < b) ? a : b;
    endfunction

    // ------------------------------------------------------------------ DMA
    logic        dma_cmd_valid;
    logic [1:0]  dma_op;
    logic [31:0] dma_addr, dma_wdata;
    logic [3:0]  dma_rows;
    logic [4:0]  dma_cols;
    logic        dma_done;
    logic [31:0] dma_rd_data;
    logic        sram_we;
    logic [1:0]  sram_row;
    logic [3:0]  sram_col;
    logic [7:0]  sram_data;

    fa_dma u_dma (
        .clk, .rst_n,
        .cmd_valid(dma_cmd_valid), .cmd_op(dma_op), .cmd_addr(dma_addr),
        .cmd_rows(dma_rows), .cmd_cols(dma_cols), .cmd_wdata(dma_wdata),
        .cmd_done(dma_done), .rd_data(dma_rd_data),
        .sram_we, .sram_row, .sram_col, .sram_data,
        .mem_req, .mem_we, .mem_addr, .mem_wdata, .mem_rdata, .mem_ready
    );

    // ------------------------------------------------------------------ tile SRAMs
    logic [D_MAX-1:0][7:0] q_rd, k_rd, v_rd;

    fa_tile_sram #(.ROWS(BR), .COLS(D_MAX), .W(8)) u_q_sram (
        .clk, .wr_en(sram_we && tgt == TGT_Q), .wr_row(sram_row[RW-1:0]), .wr_col(sram_col[CW-1:0]),
        .wr_data(sram_data), .rd_row(r[RW-1:0]), .rd_data(q_rd));
    fa_tile_sram #(.ROWS(BC), .COLS(D_MAX), .W(8)) u_k_sram (
        .clk, .wr_en(sram_we && tgt == TGT_K), .wr_row(sram_row[$clog2(BC)-1:0]), .wr_col(sram_col[CW-1:0]),
        .wr_data(sram_data), .rd_row(jj[$clog2(BC)-1:0]), .rd_data(k_rd));
    fa_tile_sram #(.ROWS(BC), .COLS(D_MAX), .W(8)) u_v_sram (
        .clk, .wr_en(sram_we && tgt == TGT_V), .wr_row(sram_row[$clog2(BC)-1:0]), .wr_col(sram_col[CW-1:0]),
        .wr_data(sram_data), .rd_row(jj[$clog2(BC)-1:0]), .rd_data(v_rd));

    // ------------------------------------------------------------------ QK MAC + ROW_MAX
    logic               mac_in_valid, mac_out_valid;
    logic signed [23:0] mac_dot;
    fa_qk_mac u_mac (
        .clk, .rst_n, .in_valid(mac_in_valid), .q_vec(q_rd), .k_vec(k_rd), .d(hd[4:0]),
        .out_valid(mac_out_valid), .dot(mac_dot));

    logic signed [47:0] logit_wide;
    logic signed [31:0] logit_val;
    always_comb begin
        logit_wide = 48'(mac_dot) * $signed({39'b0, scale_q(hd[4:0])});
        logit_val  = 32'(logit_wide >>> 8);
    end

    logic               rm_clear, rm_valid;
    logic signed [31:0] rm_max;
    fa_row_max u_rowmax (
        .clk, .rst_n, .clear(rm_clear), .in_valid(rm_valid), .in_val(logit_val), .max_val(rm_max));

    // ------------------------------------------------------------------ online softmax + PV
    logic        sm_init, sm_tile_start, sm_alpha_valid, sm_p_start, sm_p_valid;
    logic [16:0] sm_alpha, sm_p;
    logic signed [63:0] sm_l;
    fa_online_softmax u_softmax (
        .clk, .rst_n, .init(sm_init),
        .tile_start(sm_tile_start), .row(r[RW-1:0]), .tile_max(rm_max),
        .alpha_valid(sm_alpha_valid), .alpha(sm_alpha),
        .p_start(sm_p_start), .logit(score_buf[jj[$clog2(BC)-1:0]]),
        .p_valid(sm_p_valid), .p(sm_p),
        .l_rd_row(nr[RW-1:0]), .l_out(sm_l));

    logic        pv_rescale, pv_acc, pv_done;
    logic signed [63:0] pv_o;
    fa_pv_accum u_pv (
        .clk, .rst_n, .init(sm_init),
        .rescale_en(pv_rescale), .row(r[RW-1:0]), .alpha(sm_alpha),
        .acc_en(pv_acc), .p(sm_p), .v_vec(v_rd), .d(hd[4:0]),
        .op_done(pv_done),
        .rd_row(nr[RW-1:0]), .rd_col(nc[CW-1:0]), .o_out(pv_o));

    // ------------------------------------------------------------------ normalizer
    logic               nrm_start, nrm_done;
    logic signed [31:0] nrm_out;
    fa_output_normalizer u_norm (
        .clk, .rst_n, .start(nrm_start), .o(pv_o), .l(sm_l), .done(nrm_done), .out(nrm_out));

    // ------------------------------------------------------------------ control outputs
    always_comb begin
        dma_cmd_valid = 1'b0; dma_op = OP_RD; dma_addr = '0; dma_wdata = '0;
        dma_rows = '0; dma_cols = hd[4:0];
        mac_in_valid = 1'b0; rm_clear = 1'b0;
        rm_valid = 1'b0;
        sm_init = 1'b0; sm_tile_start = 1'b0; sm_p_start = 1'b0;
        pv_rescale = 1'b0; pv_acc = 1'b0; nrm_start = 1'b0;

        case (state)
            S_DESC_REQ: begin
                dma_cmd_valid = 1'b1; dma_op = OP_RD; dma_addr = desc_base + 32'(dcnt);
            end
            S_Q_REQ: begin
                dma_cmd_valid = 1'b1; dma_op = OP_LOAD; dma_addr = q_ptr + i0 * hd;
                dma_rows = rows_q[3:0];
            end
            S_K_REQ: begin
                dma_cmd_valid = 1'b1; dma_op = OP_LOAD; dma_addr = k_ptr + j0 * hd;
                dma_rows = keys_k[3:0];
            end
            S_V_REQ: begin
                dma_cmd_valid = 1'b1; dma_op = OP_LOAD; dma_addr = v_ptr + j0 * hd;
                dma_rows = keys_k[3:0];
            end
            S_NRM_STORE: begin
                dma_cmd_valid = 1'b1; dma_op = OP_WR;
                dma_addr  = o_ptr + (i0 + nr) * hd + nc;
                dma_wdata = nrm_out_q;
            end
            S_INIT:      sm_init = 1'b1;
            S_SC_CLR:    rm_clear = 1'b1;
            S_SC_FEED:   mac_in_valid = 1'b1;
            S_SC_WAIT:   rm_valid = mac_out_valid;
            S_TILE_ST:   sm_tile_start = 1'b1;
            S_RESC:      pv_rescale = 1'b1;
            S_PR_RD:     sm_p_start = 1'b1;
            S_PR_ACC:    pv_acc = 1'b1;
            S_NRM_START: nrm_start = 1'b1;
            default: ;
        endcase
    end

    // ------------------------------------------------------------------ FSM
    logic [31:0] i0_next, j0_next;
    always_comb begin
        i0_next = i0 + 32'(BR);
        j0_next = j0 + 32'(BC);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; done <= 1'b0; err_q <= 1'b0; tgt <= TGT_Q;
            desc_base <= '0; dcnt <= '0;
            q_ptr <= '0; k_ptr <= '0; v_ptr <= '0; o_ptr <= '0; seq_n <= '0; hd <= '0;
            i0 <= '0; j0 <= '0; rows_q <= '0; keys_k <= '0; r <= '0; jj <= '0; nr <= '0; nc <= '0;
            nrm_out_q <= '0;
            for (int i = 0; i < BC; i++) score_buf[i] <= '0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: if (start) begin
                    desc_base <= desc_addr; dcnt <= '0; err_q <= 1'b0; state <= S_DESC_REQ;
                end

                S_DESC_REQ: state <= S_DESC_WAIT;
                S_DESC_WAIT: if (dma_done) begin
                    case (dcnt)
                        3'd0: q_ptr <= dma_rd_data;
                        3'd1: k_ptr <= dma_rd_data;
                        3'd2: v_ptr <= dma_rd_data;
                        3'd3: o_ptr <= dma_rd_data;
                        3'd4: seq_n <= dma_rd_data;
                        default: hd <= dma_rd_data;
                    endcase
                    if (dcnt == 3'd5) state <= S_CHECK;
                    else begin dcnt <= dcnt + 3'd1; state <= S_DESC_REQ; end
                end

                S_CHECK: begin
                    if (seq_n == 0 || seq_n > MAX_N || hd == 0 || hd > 32'(D_MAX)) state <= S_ERR;
                    else begin
                        i0 <= '0; rows_q <= min32(32'(BR), seq_n); tgt <= TGT_Q; state <= S_Q_REQ;
                    end
                end

                S_Q_REQ:  state <= S_Q_WAIT;
                S_Q_WAIT: if (dma_done) state <= S_INIT;
                S_INIT: begin
                    j0 <= '0; keys_k <= min32(32'(BC), seq_n); tgt <= TGT_K; state <= S_K_REQ;
                end

                S_K_REQ:  state <= S_K_WAIT;
                S_K_WAIT: if (dma_done) begin tgt <= TGT_V; state <= S_V_REQ; end
                S_V_REQ:  state <= S_V_WAIT;
                S_V_WAIT: if (dma_done) begin r <= '0; state <= S_SC_CLR; end

                S_SC_CLR:  begin jj <= '0; state <= S_SC_RD; end
                S_SC_RD:   state <= S_SC_FEED;
                S_SC_FEED: state <= S_SC_WAIT;
                S_SC_WAIT: if (mac_out_valid) begin
                    score_buf[jj[$clog2(BC)-1:0]] <= logit_val;
                    if (jj + 32'd1 == keys_k) state <= S_TILE_ST;
                    else begin jj <= jj + 32'd1; state <= S_SC_RD; end
                end

                S_TILE_ST:    state <= S_ALPHA_WAIT;
                S_ALPHA_WAIT: if (sm_alpha_valid) state <= S_RESC;
                S_RESC:       state <= S_RESC_WAIT;
                S_RESC_WAIT:  if (pv_done) begin jj <= '0; state <= S_PR_RD; end

                S_PR_RD:   state <= S_PR_WAIT;
                S_PR_WAIT: if (sm_p_valid) state <= S_PR_ACC;
                S_PR_ACC:  state <= S_PR_ACCW;
                S_PR_ACCW: if (pv_done) begin
                    if (jj + 32'd1 != keys_k) begin
                        jj <= jj + 32'd1; state <= S_PR_RD;
                    end else if (r + 32'd1 != rows_q) begin
                        r <= r + 32'd1; state <= S_SC_CLR;
                    end else if (j0_next < seq_n) begin
                        j0 <= j0_next; keys_k <= min32(32'(BC), seq_n - j0_next);
                        tgt <= TGT_K; state <= S_K_REQ;
                    end else begin
                        nr <= '0; nc <= '0; state <= S_NRM_START;
                    end
                end

                S_NRM_START: state <= S_NRM_WAIT;
                S_NRM_WAIT:  if (nrm_done) begin nrm_out_q <= nrm_out; state <= S_NRM_STORE; end
                S_NRM_STORE: state <= S_NRM_STWAIT;
                S_NRM_STWAIT: if (dma_done) begin
                    if (nc + 32'd1 != hd) begin
                        nc <= nc + 32'd1; state <= S_NRM_START;
                    end else if (nr + 32'd1 != rows_q) begin
                        nc <= '0; nr <= nr + 32'd1; state <= S_NRM_START;
                    end else if (i0_next < seq_n) begin
                        i0 <= i0_next; rows_q <= min32(32'(BR), seq_n - i0_next);
                        tgt <= TGT_Q; state <= S_Q_REQ;
                    end else begin
                        state <= S_FIN;
                    end
                end

                S_FIN: begin done <= 1'b1; state <= S_IDLE; end
                S_ERR: begin err_q <= 1'b1; done <= 1'b1; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule : fa_engine
