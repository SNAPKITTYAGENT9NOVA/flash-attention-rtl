// FA_ENGINE testbench: runs every case in vectors/fa_vectors.txt and compares the output
// bit-exactly with the Python integer model. Also checks that inputs and the memory around
// the output are untouched, that invalid descriptors are rejected without writing, and that
// out-of-range memory accesses are flagged.
module tb_fa_engine;
    import fa_pkg::*;

    localparam int WORDS = 8192;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic        start = 0;
    logic [31:0] desc_addr = 0;
    logic        busy, done, err;
    logic        mem_req, mem_we, mem_ready, oob;
    logic [31:0] mem_addr, mem_wdata, mem_rdata;

    fa_engine dut (.clk, .rst_n, .start, .desc_addr, .busy, .done, .err,
                   .mem_req, .mem_we, .mem_addr, .mem_wdata, .mem_rdata, .mem_ready);
    subleq_ram #(.WORDS(WORDS)) u_ram (.clk, .rst_n, .req(mem_req), .we(mem_we), .addr(mem_addr),
                                       .wdata(mem_wdata), .rdata(mem_rdata), .ready(mem_ready), .oob(oob));

    int errors = 0;
    localparam int SENT = 32'h7EADBEEF;

    task automatic fail(input string msg);
        errors++;
        $display("FAIL: %s", msg);
    endtask

    task automatic run_engine(input int daddr, output int cycles, output bit timed_out);
        cycles = 0; timed_out = 0;
        @(negedge clk); desc_addr = daddr; start = 1;
        @(negedge clk); start = 0;
        while (!done && cycles < 2_000_000) begin @(negedge clk); cycles++; end
        if (!done) timed_out = 1;
        @(negedge clk);
    endtask

    int q [], k [], v [], o [];

    initial begin
        int fd, ncases, n, d, cyc, total_cycles, qa, ka, va, oa, guard_hi, tmp;
        bit to;
        total_cycles = 0;

        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        fd = $fopen("vectors/fa_vectors.txt", "r");
        if (fd == 0) begin $display("cannot open fa_vectors.txt"); $fatal(1); end
        void'($fscanf(fd, "%d", ncases));

        for (int cs = 0; cs < ncases; cs++) begin
            void'($fscanf(fd, "%d %d", n, d));
            q = new[n*d]; k = new[n*d]; v = new[n*d]; o = new[n*d];
            foreach (q[i]) void'($fscanf(fd, "%d", q[i]));
            foreach (k[i]) void'($fscanf(fd, "%d", k[i]));
            foreach (v[i]) void'($fscanf(fd, "%d", v[i]));
            foreach (o[i]) void'($fscanf(fd, "%d", o[i]));

            qa = 64;
            ka = qa + n*d + 3;
            va = ka + n*d + 3;
            oa = va + n*d + 3;
            guard_hi = oa + n*d;

            // poison everything first
            for (int a = 0; a < 64 + 4*(n*d + 3) + 16; a++) u_ram.mem[a] = SENT;
            u_ram.mem[0] = qa; u_ram.mem[1] = ka; u_ram.mem[2] = va; u_ram.mem[3] = oa;
            u_ram.mem[4] = n;  u_ram.mem[5] = d;
            for (int i = 0; i < n*d; i++) begin
                u_ram.mem[qa+i] = q[i]; u_ram.mem[ka+i] = k[i]; u_ram.mem[va+i] = v[i];
            end

            run_engine(0, cyc, to);
            total_cycles += cyc;
            if (to) fail($sformatf("case %0d (N=%0d d=%0d) timed out", cs, n, d));
            else if (err) fail($sformatf("case %0d unexpected err", cs));
            else begin
                for (int i = 0; i < n*d; i++)
                    if (int'(u_ram.mem[oa+i]) !== o[i])
                        fail($sformatf("case %0d (N=%0d d=%0d) O[%0d][%0d] = %0d, want %0d",
                                       cs, n, d, i / d, i % d, int'(u_ram.mem[oa+i]), o[i]));
                // inputs untouched, guard words around O untouched
                for (int i = 0; i < n*d; i++) begin
                    if (int'(u_ram.mem[qa+i]) !== q[i]) fail("Q modified");
                    if (int'(u_ram.mem[ka+i]) !== k[i]) fail("K modified");
                    if (int'(u_ram.mem[va+i]) !== v[i]) fail("V modified");
                end
                for (int g = 0; g < 3; g++) begin
                    if (int'(u_ram.mem[oa+n*d+g]) !== SENT) fail("write past end of O");
                    if (int'(u_ram.mem[oa-3+g]) !== SENT)  fail("write before O");
                end
            end
        end
        $fclose(fd);
        $display("ran %0d cases, %0d total cycles", ncases, total_cycles);

        // invalid descriptors: (N, d) = (0, 4), (4, 0), (4, 17); no write to O
        for (int t = 0; t < 3; t++) begin
            for (int a = 0; a < 200; a++) u_ram.mem[a] = SENT;
            u_ram.mem[0] = 100; u_ram.mem[1] = 100; u_ram.mem[2] = 100; u_ram.mem[3] = 150;
            u_ram.mem[4] = (t == 0) ? 0 : 4;
            u_ram.mem[5] = (t == 0) ? 4 : (t == 1) ? 0 : 17;
            run_engine(0, cyc, to);
            if (to) fail("invalid descriptor: timeout");
            else if (!err) fail($sformatf("invalid descriptor %0d not flagged", t));
            for (int a = 100; a < 200; a++) if (int'(u_ram.mem[a]) !== SENT) fail("invalid descriptor wrote memory");
        end

        // a valid run after errors clears err
        for (int a = 0; a < 200; a++) u_ram.mem[a] = SENT;
        u_ram.mem[0] = 100; u_ram.mem[1] = 110; u_ram.mem[2] = 120; u_ram.mem[3] = 130;
        u_ram.mem[4] = 1; u_ram.mem[5] = 2;
        u_ram.mem[100] = 16; u_ram.mem[101] = 32; u_ram.mem[110] = 16; u_ram.mem[111] = 16;
        u_ram.mem[120] = 48; u_ram.mem[121] = -48;
        run_engine(0, cyc, to);
        // N=1: attention weight is exactly 1, so O == V * 16 (Q4.4 -> 8 fractional bits)
        if (to || err) fail("valid run after errors");
        else if (int'(u_ram.mem[130]) !== 48*16 || int'(u_ram.mem[131]) !== -48*16)
            fail($sformatf("N=1 output %0d %0d, want %0d %0d", int'(u_ram.mem[130]), int'(u_ram.mem[131]), 48*16, -48*16));

        // out-of-range pointer: flagged by the RAM, engine still terminates
        for (int a = 0; a < 200; a++) u_ram.mem[a] = SENT;
        u_ram.mem[0] = WORDS - 2; u_ram.mem[1] = 110; u_ram.mem[2] = 120; u_ram.mem[3] = 130;
        u_ram.mem[4] = 4; u_ram.mem[5] = 4;
        run_engine(0, cyc, to);
        if (to) fail("oob run timed out");
        if (!oob) fail("out-of-range access not flagged");

        $display("tb_fa_engine: errors = %0d", errors);
        if (errors == 0) $display("PASS"); else $fatal(1, "FAIL");
        $finish;
    end

    initial begin #2_000_000_000; $display("global timeout"); $fatal(1); end
endmodule
