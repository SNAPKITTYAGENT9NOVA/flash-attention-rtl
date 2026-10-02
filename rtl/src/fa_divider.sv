// Sequential restoring divider: signed W-bit / signed W-bit, quotient truncated toward zero.
// Latency: W+2 cycles. Division by zero yields 0.

module fa_divider #(
    parameter int W = 64
) (
    input  logic                 clk,
    input  logic                 rst_n,

    input  logic                 start,
    input  logic signed [W-1:0]  num,
    input  logic signed [W-1:0]  den,

    output logic                 done,    // single-cycle pulse; quot valid until next start
    output logic signed [W-1:0]  quot
);

    typedef enum logic [1:0] {IDLE, RUN, FIN} state_t;
    state_t state;

    logic [W-1:0]   dividend, divisor, q;
    logic [W:0]     rem;
    logic           neg;
    logic [$clog2(W+1)-1:0] cnt;

    logic [W:0] rem_sh;
    logic [W:0] rem_sub;

    always_comb begin
        rem_sh  = {rem[W-1:0], dividend[W-1]};
        rem_sub = rem_sh - {1'b0, divisor};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done  <= 1'b0;
            quot  <= '0;
            dividend <= '0; divisor <= '0; q <= '0; rem <= '0; neg <= 1'b0; cnt <= '0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: if (start) begin
                    dividend <= (num < 0) ? W'(-num) : W'(num);
                    divisor  <= (den < 0) ? W'(-den) : W'(den);
                    neg      <= (num < 0) ^ (den < 0);
                    rem      <= '0;
                    q        <= '0;
                    cnt      <= '0;
                    state    <= (den == 0) ? FIN : RUN;
                    if (den == 0) begin q <= '0; neg <= 1'b0; end
                end
                RUN: begin
                    dividend <= {dividend[W-2:0], 1'b0};
                    if (!rem_sub[W]) begin
                        rem <= rem_sub;
                        q   <= {q[W-2:0], 1'b1};
                    end else begin
                        rem <= rem_sh;
                        q   <= {q[W-2:0], 1'b0};
                    end
                    cnt <= cnt + 1'b1;
                    if (cnt == ($bits(cnt))'(W-1)) state <= FIN;
                end
                FIN: begin
                    quot  <= neg ? -$signed(q) : $signed(q);
                    done  <= 1'b1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule : fa_divider
