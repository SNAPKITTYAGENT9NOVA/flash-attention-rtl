// SUBLEQ CPU with a FlashAttention trap.
//
// Instruction = triad (a, b, c) of 32-bit words fetched from pc, pc+1, pc+2:
//   a == -2        FA trap: b = address of the 6-word FA_BEGIN descriptor, c = continuation.
//                  The FA engine takes the memory bus, writes O to memory, then execution
//                  resumes at c (pc <- c; negative c halts).
//   a == -1        input:  mem[b] <- next input word, pc <- pc + 3
//   a <  -2        fault
//   b <  0         output: emit mem[a], pc <- pc + 3
//   otherwise      mem[b] <- mem[b] - mem[a];  pc <- (mem[b] <= 0) ? c : pc + 3
// pc < 0 halts. Any address outside [0, MEM_WORDS) faults.
//
// This is the same instruction semantics as runSubleq() in subleq_bf.nim (32-bit words here).

module subleq_cpu
    import fa_pkg::*;
#(
    parameter int MEM_WORDS = 4096
) (
    input  logic               clk,
    input  logic               rst_n,

    // memory master (request held until ready)
    output logic               mem_req,
    output logic               mem_we,
    output logic [31:0]        mem_addr,
    output logic [31:0]        mem_wdata,
    input  logic [31:0]        mem_rdata,
    input  logic               mem_ready,

    // word I/O
    output logic               io_out_valid,   // 1-cycle pulse
    output logic signed [31:0] io_out_data,
    input  logic signed [31:0] io_in_data,     // current input word
    output logic               io_in_pop,      // 1-cycle pulse: input word consumed

    // FA engine
    output logic               fa_start,       // 1-cycle pulse
    output logic [31:0]        fa_desc_addr,
    output logic               fa_active,      // CPU is waiting on the engine (it owns the bus)
    input  logic               fa_done,
    input  logic               fa_err,

    output logic               halted,
    output logic               fault,
    output logic [31:0]        steps
);

    typedef enum logic [3:0] {
        C_FETCH_A, C_FETCH_B, C_FETCH_C, C_DECODE,
        C_RD_A, C_RD_B, C_WR_B, C_OUT, C_IN_WR,
        C_FA_START, C_FA_WAIT, C_NEXT, C_HALT, C_FAULT
    } state_t;
    state_t state;

    logic signed [31:0] pc, a, b, c, ma, mb, res, npc;
    localparam logic signed [31:0] LIM = 32'(MEM_WORDS);

    function automatic logic in_mem(input logic signed [31:0] x);
        return (x >= 0) && (x < LIM);
    endfunction

    assign halted = (state == C_HALT);
    assign fault  = (state == C_FAULT);
    assign fa_active    = (state == C_FA_START) || (state == C_FA_WAIT);
    assign fa_start     = (state == C_FA_START);
    assign fa_desc_addr = b;
    assign io_out_valid = (state == C_OUT);
    assign io_out_data  = ma;
    assign io_in_pop    = (state == C_IN_WR) && mem_ready;

    always_comb begin
        mem_req   = 1'b0;
        mem_we    = 1'b0;
        mem_addr  = '0;
        mem_wdata = '0;
        case (state)
            C_FETCH_A: begin mem_req = 1'b1; mem_addr = 32'(pc); end
            C_FETCH_B: begin mem_req = 1'b1; mem_addr = 32'(pc + 32'sd1); end
            C_FETCH_C: begin mem_req = 1'b1; mem_addr = 32'(pc + 32'sd2); end
            C_RD_A:    begin mem_req = 1'b1; mem_addr = 32'(a); end
            C_RD_B:    begin mem_req = 1'b1; mem_addr = 32'(b); end
            C_WR_B:    begin mem_req = 1'b1; mem_we = 1'b1; mem_addr = 32'(b); mem_wdata = 32'(res); end
            C_IN_WR:   begin mem_req = 1'b1; mem_we = 1'b1; mem_addr = 32'(b); mem_wdata = 32'(io_in_data); end
            default: ;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= C_FETCH_A;
            pc <= '0; a <= '0; b <= '0; c <= '0; ma <= '0; mb <= '0; res <= '0; npc <= '0;
            steps <= '0;
        end else begin
            case (state)
                C_FETCH_A: begin
                    if (!in_mem(pc) || !in_mem(pc + 32'sd2)) state <= C_FAULT;
                    else if (mem_ready) begin a <= mem_rdata; state <= C_FETCH_B; end
                end
                C_FETCH_B: if (mem_ready) begin b <= mem_rdata; state <= C_FETCH_C; end
                C_FETCH_C: if (mem_ready) begin c <= mem_rdata; state <= C_DECODE; end

                C_DECODE: begin
                    if (a == -32'sd1) begin
                        state <= in_mem(b) ? C_IN_WR : C_FAULT;
                    end else if (a == 32'(FA_TRAP)) begin
                        state <= (in_mem(b) && in_mem(b + 32'sd5)) ? C_FA_START : C_FAULT;
                    end else if (a < 0) begin
                        state <= C_FAULT;
                    end else if (b < 0) begin
                        state <= in_mem(a) ? C_RD_A : C_FAULT;
                    end else begin
                        state <= (in_mem(a) && in_mem(b)) ? C_RD_A : C_FAULT;
                    end
                end

                C_RD_A: if (mem_ready) begin
                    ma <= mem_rdata;
                    state <= (b < 0) ? C_OUT : C_RD_B;
                end
                C_RD_B: if (mem_ready) begin mb <= mem_rdata; res <= $signed(mem_rdata) - ma; state <= C_WR_B; end
                C_WR_B: if (mem_ready) begin
                    npc   <= (res <= 0) ? c : pc + 32'sd3;
                    state <= C_NEXT;
                end
                C_OUT: begin npc <= pc + 32'sd3; state <= C_NEXT; end
                C_IN_WR: if (mem_ready) begin npc <= pc + 32'sd3; state <= C_NEXT; end

                C_FA_START: state <= C_FA_WAIT;
                C_FA_WAIT: if (fa_done) begin
                    npc   <= c;
                    state <= fa_err ? C_FAULT : C_NEXT;
                end

                C_NEXT: begin
                    pc    <= npc;
                    steps <= steps + 32'd1;
                    state <= (npc < 0) ? C_HALT : C_FETCH_A;
                end

                default: ;   // C_HALT, C_FAULT are terminal
            endcase
        end
    end

endmodule : subleq_cpu
