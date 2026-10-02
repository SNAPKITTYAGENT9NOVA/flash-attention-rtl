// DMA / MEMORY_INTERFACE: single-word-at-a-time bus master.
//   OP_LOAD : stream cmd_rows x cmd_cols consecutive words (row-major) from cmd_addr into a
//             tile SRAM write port (low 8 bits of each word)
//   OP_RD   : read one word  -> rd_data
//   OP_WR   : write one word (cmd_wdata)
// Memory protocol: hold mem_req (+we/addr/wdata) until mem_ready; rdata is valid while mem_ready.

module fa_dma (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        cmd_valid,
    input  logic [1:0]  cmd_op,
    input  logic [31:0] cmd_addr,
    input  logic [3:0]  cmd_rows,
    input  logic [4:0]  cmd_cols,
    input  logic [31:0] cmd_wdata,
    output logic        cmd_done,       // pulse
    output logic [31:0] rd_data,

    output logic        sram_we,
    output logic [1:0]  sram_row,
    output logic [3:0]  sram_col,
    output logic [7:0]  sram_data,

    output logic        mem_req,
    output logic        mem_we,
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    input  logic [31:0] mem_rdata,
    input  logic        mem_ready
);

    localparam logic [1:0] OP_LOAD = 2'd0, OP_RD = 2'd1, OP_WR = 2'd2;

    logic        busy;
    logic [1:0]  op_q;
    logic [31:0] addr_q, wdata_q;
    logic [3:0]  rows_q, r_q;
    logic [4:0]  cols_q, c_q;

    assign mem_req   = busy;
    assign mem_we    = (op_q == OP_WR);
    assign mem_addr  = addr_q;
    assign mem_wdata = wdata_q;

    assign sram_we   = busy && mem_ready && (op_q == OP_LOAD);
    assign sram_row  = r_q[1:0];
    assign sram_col  = c_q[3:0];
    assign sram_data = mem_rdata[7:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; cmd_done <= 1'b0; rd_data <= '0;
            op_q <= '0; addr_q <= '0; wdata_q <= '0; rows_q <= '0; cols_q <= '0; r_q <= '0; c_q <= '0;
        end else begin
            cmd_done <= 1'b0;
            if (!busy) begin
                if (cmd_valid) begin
                    busy    <= 1'b1;
                    op_q    <= cmd_op;
                    addr_q  <= cmd_addr;
                    wdata_q <= cmd_wdata;
                    rows_q  <= cmd_rows;
                    cols_q  <= cmd_cols;
                    r_q     <= '0;
                    c_q     <= '0;
                end
            end else if (mem_ready) begin
                case (op_q)
                    OP_LOAD: begin
                        addr_q <= addr_q + 32'd1;
                        if (c_q + 5'd1 == cols_q) begin
                            c_q <= '0;
                            if (r_q + 4'd1 == rows_q) begin
                                busy <= 1'b0; cmd_done <= 1'b1;
                            end else begin
                                r_q <= r_q + 4'd1;
                            end
                        end else begin
                            c_q <= c_q + 5'd1;
                        end
                    end
                    OP_RD: begin
                        rd_data <= mem_rdata; busy <= 1'b0; cmd_done <= 1'b1;
                    end
                    default: begin
                        busy <= 1'b0; cmd_done <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule : fa_dma
