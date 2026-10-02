// QK_DOT_PRODUCT: D_MAX-lane MAC array.
// dot = sum_{i < d} q[i] * k[i]   (signed 8-bit operands, lanes >= d ignored)
// Two pipeline stages: lane products, then adder tree. out_valid trails in_valid by 2 cycles.

module fa_qk_mac
    import fa_pkg::*;
(
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         in_valid,
    input  logic [D_MAX-1:0][7:0]        q_vec,
    input  logic [D_MAX-1:0][7:0]        k_vec,
    input  logic [4:0]                   d,

    output logic                         out_valid,
    output logic signed [23:0]           dot
);

    logic signed [15:0] prod [D_MAX];
    logic               v1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1 <= 1'b0;
            for (int i = 0; i < D_MAX; i++) prod[i] <= '0;
        end else begin
            v1 <= in_valid;
            for (int i = 0; i < D_MAX; i++)
                prod[i] <= (i < int'(d)) ? 16'($signed(q_vec[i]) * $signed(k_vec[i])) : 16'sd0;
        end
    end

    logic signed [23:0] sum_c;
    always_comb begin
        sum_c = '0;
        for (int i = 0; i < D_MAX; i++) sum_c = sum_c + 24'(prod[i]);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            dot       <= '0;
        end else begin
            out_valid <= v1;
            dot       <= sum_c;
        end
    end

endmodule : fa_qk_mac
