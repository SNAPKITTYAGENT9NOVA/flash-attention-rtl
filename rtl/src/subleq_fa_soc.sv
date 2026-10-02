// SUBLEQ CPU + FA_ENGINE + RAM on one memory bus.
//
//   SUBLEQ CPU --(a == -2: FA trap)--> FA_ENGINE --> result in RAM --> SUBLEQ CPU resumes
//
// While the CPU waits on the engine (fa_active) the engine owns the RAM port; otherwise the CPU does.

module subleq_fa_soc #(
    parameter int MEM_WORDS = 4096
) (
    input  logic               clk,
    input  logic               rst_n,

    output logic               io_out_valid,
    output logic signed [31:0] io_out_data,
    input  logic signed [31:0] io_in_data,
    output logic               io_in_pop,

    output logic               halted,
    output logic               fault,       // CPU fault (bad address/opcode, FA error) or RAM out-of-range access
    output logic [31:0]        steps
);

    logic        cpu_req, cpu_we, fa_req, fa_we;
    logic [31:0] cpu_addr, cpu_wdata, fa_addr, fa_wdata;
    logic        fa_start, fa_active, fa_done, fa_err, fa_busy;
    logic [31:0] fa_desc_addr;

    logic        ram_req, ram_we, ram_ready, ram_oob;
    logic [31:0] ram_addr, ram_wdata, ram_rdata;

    logic        cpu_fault;

    assign ram_req   = fa_active ? fa_req   : cpu_req;
    assign ram_we    = fa_active ? fa_we    : cpu_we;
    assign ram_addr  = fa_active ? fa_addr  : cpu_addr;
    assign ram_wdata = fa_active ? fa_wdata : cpu_wdata;
    assign fault     = cpu_fault | ram_oob;

    subleq_cpu #(.MEM_WORDS(MEM_WORDS)) u_cpu (
        .clk, .rst_n,
        .mem_req(cpu_req), .mem_we(cpu_we), .mem_addr(cpu_addr), .mem_wdata(cpu_wdata),
        .mem_rdata(ram_rdata), .mem_ready(ram_ready),
        .io_out_valid, .io_out_data, .io_in_data, .io_in_pop,
        .fa_start, .fa_desc_addr, .fa_active, .fa_done, .fa_err,
        .halted, .fault(cpu_fault), .steps
    );

    fa_engine u_fa (
        .clk, .rst_n,
        .start(fa_start), .desc_addr(fa_desc_addr),
        .busy(fa_busy), .done(fa_done), .err(fa_err),
        .mem_req(fa_req), .mem_we(fa_we), .mem_addr(fa_addr), .mem_wdata(fa_wdata),
        .mem_rdata(ram_rdata), .mem_ready(ram_ready)
    );

    subleq_ram #(.WORDS(MEM_WORDS)) u_ram (
        .clk, .rst_n,
        .req(ram_req), .we(ram_we), .addr(ram_addr), .wdata(ram_wdata),
        .rdata(ram_rdata), .ready(ram_ready), .oob(ram_oob)
    );

endmodule : subleq_fa_soc
