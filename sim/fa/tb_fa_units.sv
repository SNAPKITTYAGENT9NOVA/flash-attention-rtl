// Unit tests: fa_exp_approx (bit-exact vs Python model), fa_divider (vs SV '/'),
// fa_qk_mac (vs reference sum), fa_row_max.
module tb_fa_units;
    import fa_pkg::*;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    int errors = 0;

    // ---------------- exp approx ----------------
    logic        ex_in_valid = 0;
    logic [31:0] ex_delta = 0;
    logic        ex_out_valid;
    logic [16:0] ex_result;
    fa_exp_approx u_exp (.clk, .rst_n, .in_valid(ex_in_valid), .delta(ex_delta),
                         .out_valid(ex_out_valid), .result(ex_result));

    // ---------------- divider ----------------
    logic               dv_start = 0;
    logic signed [63:0] dv_num = 0, dv_den = 1;
    logic               dv_done;
    logic signed [63:0] dv_quot;
    fa_divider #(.W(64)) u_div (.clk, .rst_n, .start(dv_start), .num(dv_num), .den(dv_den),
                                .done(dv_done), .quot(dv_quot));

    // ---------------- mac ----------------
    logic                  mc_in_valid = 0;
    logic [D_MAX-1:0][7:0] mc_q, mc_k;
    logic [4:0]            mc_d = 1;
    logic                  mc_out_valid;
    logic signed [23:0]    mc_dot;
    fa_qk_mac u_mac (.clk, .rst_n, .in_valid(mc_in_valid), .q_vec(mc_q), .k_vec(mc_k), .d(mc_d),
                     .out_valid(mc_out_valid), .dot(mc_dot));

    // ---------------- row max ----------------
    logic               rm_clear = 0, rm_valid = 0;
    logic signed [31:0] rm_in = 0, rm_max;
    fa_row_max u_rm (.clk, .rst_n, .clear(rm_clear), .in_valid(rm_valid), .in_val(rm_in), .max_val(rm_max));

    task automatic check(input bit cond, input string msg);
        if (!cond) begin errors++; $display("FAIL: %s", msg); end
    endtask

    int vals [5] = '{-50, -20, -90, -21, -70};

    initial begin
        int fd, delta, expv;
        longint num, den;
        int exp_cases = 0;
        int seed = 7;

        mc_q = '0; mc_k = '0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // exp approx: bit-exact vs Python
        fd = $fopen("vectors/exp_vectors.txt", "r");
        if (fd == 0) begin $display("cannot open exp_vectors.txt"); $fatal(1); end
        while ($fscanf(fd, "%d %d\n", delta, expv) == 2) begin
            @(negedge clk); ex_delta = delta; ex_in_valid = 1;
            @(negedge clk); ex_in_valid = 0;
            check(ex_out_valid === 1'b1, "exp out_valid");
            check(int'(ex_result) == expv, $sformatf("exp(%0d): got %0d want %0d", delta, ex_result, expv));
            exp_cases++;
        end
        $fclose(fd);

        // divider: corner cases + random
        for (int t = 0; t < 400; t++) begin
            if (t < 4) begin
                num = (t == 0) ? 0 : (t == 1) ? 1 : (t == 2) ? -7 : 7;
                den = 3;
            end else begin
                num = longint'($random(seed)) <<< (t % 17);
                den = longint'($random(seed)) | 1;
            end
            @(negedge clk); dv_num = num; dv_den = den; dv_start = 1;
            @(negedge clk); dv_start = 0;
            while (!dv_done) @(negedge clk);
            check(dv_quot == num / den, $sformatf("div %0d / %0d = %0d, want %0d", num, den, dv_quot, num / den));
        end
        @(negedge clk); dv_num = 123; dv_den = 0; dv_start = 1;
        @(negedge clk); dv_start = 0;
        while (!dv_done) @(negedge clk);
        check(dv_quot == 0, "div by zero");

        // mac
        for (int t = 0; t < 300; t++) begin
            int ref_sum;
            ref_sum = 0;
            mc_d = 5'(1 + $unsigned($random(seed)) % D_MAX);
            for (int i = 0; i < D_MAX; i++) begin
                mc_q[i] = 8'($random(seed)); mc_k[i] = 8'($random(seed));
                if (i < int'(mc_d)) ref_sum += int'($signed(mc_q[i])) * int'($signed(mc_k[i]));
            end
            @(negedge clk); mc_in_valid = 1;
            @(negedge clk); mc_in_valid = 0;
            @(negedge clk);
            check(mc_out_valid === 1'b1, "mac out_valid");
            check(int'(mc_dot) == ref_sum, $sformatf("mac d=%0d got %0d want %0d", mc_d, mc_dot, ref_sum));
            @(negedge clk);
            check(mc_out_valid === 1'b0, "mac out_valid single pulse");
        end

        // row max (all-negative stream, then clear)
        @(negedge clk); rm_clear = 1;
        @(negedge clk); rm_clear = 0;
        for (int i = 0; i < 5; i++) begin rm_in = vals[i]; rm_valid = 1; @(negedge clk); end
        rm_valid = 0; @(negedge clk);
        check(rm_max == -20, $sformatf("row max got %0d want -20", rm_max));
        rm_clear = 1; @(negedge clk); rm_clear = 0;
        rm_in = 5; rm_valid = 1; @(negedge clk); rm_valid = 0; @(negedge clk);
        check(rm_max == 5, "row max after clear");

        $display("tb_fa_units: %0d exp cases, errors = %0d", exp_cases, errors);
        if (errors == 0) $display("PASS"); else $fatal(1, "FAIL");
        $finish;
    end

    initial begin #200_000_000; $display("timeout"); $fatal(1); end
endmodule
