// ROW_MAX: streaming maximum of signed 32-bit values. 'clear' restarts the scan.

module fa_row_max (
    input  logic               clk,
    input  logic               rst_n,

    input  logic               clear,
    input  logic               in_valid,
    input  logic signed [31:0] in_val,

    output logic signed [31:0] max_val
);

    logic has;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            has     <= 1'b0;
            max_val <= '0;
        end else if (clear) begin
            has     <= 1'b0;
            max_val <= '0;
        end else if (in_valid) begin
            if (!has || in_val > max_val) max_val <= in_val;
            has <= 1'b1;
        end
    end

endmodule : fa_row_max
