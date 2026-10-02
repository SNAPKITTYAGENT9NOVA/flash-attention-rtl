// Tile SRAM: ROWS x COLS words of W bits.
// Word-granular write port; whole-row read port with 1-cycle latency.

module fa_tile_sram #(
    parameter int ROWS = 4,
    parameter int COLS = 16,
    parameter int W    = 8
) (
    input  logic                       clk,

    input  logic                       wr_en,
    input  logic [$clog2(ROWS)-1:0]    wr_row,
    input  logic [$clog2(COLS)-1:0]    wr_col,
    input  logic [W-1:0]               wr_data,

    input  logic [$clog2(ROWS)-1:0]    rd_row,
    output logic [COLS-1:0][W-1:0]     rd_data   // valid the cycle after rd_row is presented
);

    logic [COLS-1:0][W-1:0] mem [ROWS];

    always_ff @(posedge clk) begin
        if (wr_en) mem[wr_row][wr_col] <= wr_data;
        rd_data <= mem[rd_row];
    end

endmodule : fa_tile_sram
