// Behavioral word RAM (simulation / FPGA block-RAM style) with a 2-cycle request/ready protocol.
//   Master holds req (+we/addr/wdata) until ready; rdata is valid while ready is high.
//   Accesses outside [0, WORDS) are ignored (reads return 0) and set the sticky 'oob' flag.

module subleq_ram #(
    parameter int WORDS = 4096
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        req,
    input  logic        we,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,
    output logic        ready,
    output logic        oob
);

    logic [31:0] mem [WORDS];
    logic        in_range;
    assign in_range = (addr < 32'(WORDS));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready <= 1'b0;
            rdata <= '0;
            oob   <= 1'b0;
        end else begin
            ready <= req && !ready;
            if (req && !ready) begin
                if (!in_range) begin
                    oob   <= 1'b1;
                    rdata <= '0;
                end else begin
                    if (we) mem[addr[$clog2(WORDS)-1:0]] <= wdata;
                    rdata <= mem[addr[$clog2(WORDS)-1:0]];
                end
            end
        end
    end

endmodule : subleq_ram
