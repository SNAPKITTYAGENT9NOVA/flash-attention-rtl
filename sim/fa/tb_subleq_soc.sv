// SoC testbench: loads a memory image, runs the SUBLEQ CPU (+ FA engine) until it halts and
// compares the emitted output words with an expected list.
//
//   +img=<file>   memory image, one decimal word per line (word i = line i)
//   +exp=<file>   expected output words, one decimal per line
//   +in=<file>    optional input words, one decimal per line
//   +maxcycles=N  optional cycle limit (default 50,000,000)
module tb_subleq_soc;
    localparam int WORDS = 16384;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic               io_out_valid, io_in_pop, halted, fault;
    logic signed [31:0] io_out_data, io_in_data;
    logic [31:0]        steps;

    subleq_fa_soc #(.MEM_WORDS(WORDS)) dut (.clk, .rst_n, .io_out_valid, .io_out_data,
                                            .io_in_data, .io_in_pop, .halted, .fault, .steps);

    int out_words [$];
    int in_words  [$];
    int in_idx = 0;

    assign io_in_data = (in_idx < in_words.size()) ? in_words[in_idx] : 0;
    always @(posedge clk) begin
        if (io_in_pop) in_idx <= in_idx + 1;
        if (io_out_valid) out_words.push_back(io_out_data);
    end

    string img, expf, inf;
    int fd, v, n, errors, cycles, maxcycles;
    int exp_words [$];

    initial begin
        errors = 0;
        maxcycles = 50_000_000;
        if (!$value$plusargs("img=%s", img)) begin $display("missing +img="); $fatal(1); end
        if (!$value$plusargs("exp=%s", expf)) begin $display("missing +exp="); $fatal(1); end
        void'($value$plusargs("maxcycles=%d", maxcycles));

        for (int i = 0; i < WORDS; i++) dut.u_ram.mem[i] = 0;
        fd = $fopen(img, "r");
        if (fd == 0) begin $display("cannot open %s", img); $fatal(1); end
        n = 0;
        while ($fscanf(fd, "%d\n", v) == 1) begin
            if (n >= WORDS) begin $display("image larger than RAM"); $fatal(1); end
            dut.u_ram.mem[n] = v; n++;
        end
        $fclose(fd);

        if ($value$plusargs("in=%s", inf)) begin
            fd = $fopen(inf, "r");
            while ($fscanf(fd, "%d\n", v) == 1) in_words.push_back(v);
            $fclose(fd);
        end

        fd = $fopen(expf, "r");
        if (fd == 0) begin $display("cannot open %s", expf); $fatal(1); end
        while ($fscanf(fd, "%d\n", v) == 1) exp_words.push_back(v);
        $fclose(fd);

        repeat (3) @(posedge clk);
        rst_n = 1;

        cycles = 0;
        while (!halted && !fault && cycles < maxcycles) begin @(posedge clk); cycles++; end
        repeat (3) @(posedge clk);

        if (fault) begin errors++; $display("FAIL: CPU/RAM fault after %0d instructions", steps); end
        else if (!halted) begin errors++; $display("FAIL: did not halt within %0d cycles", maxcycles); end

        if (out_words.size() != exp_words.size()) begin
            errors++;
            $display("FAIL: %0d output words, expected %0d", out_words.size(), exp_words.size());
        end
        for (int i = 0; i < out_words.size() && i < exp_words.size(); i++)
            if (out_words[i] != exp_words[i]) begin
                errors++;
                if (errors < 10) $display("FAIL: out[%0d] = %0d, expected %0d", i, out_words[i], exp_words[i]);
            end

        $display("%s: %0d instructions, %0d cycles, %0d output words, errors = %0d",
                 img, steps, cycles, out_words.size(), errors);
        if (errors == 0) $display("PASS"); else $fatal(1, "FAIL");
        $finish;
    end
endmodule
