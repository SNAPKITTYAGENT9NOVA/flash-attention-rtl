// PV_ACCUMULATOR: o[row][c] for BR rows x D_MAX lanes (64-bit signed).
//   rescale: o <= (o * alpha) >>> 16            (alpha in Q0.16)
//   acc    : o += p * v[c]   for c < d          (p in Q0.16, v signed 8-bit)
// op_done pulses the cycle after rescale_en / acc_en.

module fa_pv_accum
    import fa_pkg::*;
(
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic                       init,

    input  logic                       rescale_en,
    input  logic [$clog2(BR)-1:0]      row,
    input  logic [16:0]                alpha,

    input  logic                       acc_en,
    input  logic [16:0]                p,
    input  logic [D_MAX-1:0][7:0]      v_vec,
    input  logic [4:0]                 d,

    output logic                       op_done,

    input  logic [$clog2(BR)-1:0]      rd_row,
    input  logic [$clog2(D_MAX)-1:0]   rd_col,
    output logic signed [63:0]         o_out
);

    logic signed [63:0] o [BR][D_MAX];
    logic signed [63:0] p64;
    assign p64 = {47'b0, p};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < BR; i++)
                for (int c = 0; c < D_MAX; c++) o[i][c] <= '0;
            op_done <= 1'b0;
        end else begin
            op_done <= rescale_en | acc_en;
            if (init) begin
                for (int i = 0; i < BR; i++)
                    for (int c = 0; c < D_MAX; c++) o[i][c] <= '0;
            end else if (rescale_en) begin
                for (int c = 0; c < D_MAX; c++)
                    o[row][c] <= 64'((128'(o[row][c]) * $signed({111'b0, alpha})) >>> 16);
            end else if (acc_en) begin
                for (int c = 0; c < D_MAX; c++)
                    if (c < int'(d))
                        o[row][c] <= o[row][c] + p64 * 64'($signed(v_vec[c]));
            end
        end
    end

    assign o_out = o[rd_row][rd_col];

endmodule : fa_pv_accum
