// OUTPUT_NORMALIZER: out = (o * 16) / l, truncated toward zero.
// o is the PV accumulator (sum p*v), l the softmax denominator (sum p).
// The result has 8 fractional bits (V is Q4.4).

module fa_output_normalizer (
    input  logic               clk,
    input  logic               rst_n,

    input  logic               start,
    input  logic signed [63:0] o,
    input  logic signed [63:0] l,

    output logic               done,     // pulse; out valid until next start
    output logic signed [31:0] out
);

    logic signed [63:0] quot;

    fa_divider #(.W(64)) u_div (
        .clk, .rst_n,
        .start,
        .num(o <<< 4),
        .den(l),
        .done,
        .quot
    );

    assign out = quot[31:0];

endmodule : fa_output_normalizer
