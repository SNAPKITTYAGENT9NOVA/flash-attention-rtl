#!/bin/sh
# Build all FA testbenches with Verilator (run from sim/fa).
set -e
R=../../rtl/src
ENGINE="$R/fa_tile_sram.sv $R/fa_qk_mac.sv $R/fa_row_max.sv $R/fa_exp_approx.sv $R/fa_divider.sv \
$R/fa_online_softmax.sv $R/fa_pv_accum.sv $R/fa_output_normalizer.sv $R/fa_dma.sv $R/fa_engine.sv"
./verilate.sh tb_fa_units  work_units  $R/fa_exp_approx.sv $R/fa_divider.sv $R/fa_qk_mac.sv $R/fa_row_max.sv tb_fa_units.sv >/dev/null
./verilate.sh tb_fa_engine work_engine $R/subleq_ram.sv $ENGINE tb_fa_engine.sv >/dev/null
./verilate.sh tb_subleq_soc work_soc   $R/subleq_ram.sv $ENGINE $R/subleq_cpu.sv $R/subleq_fa_soc.sv tb_subleq_soc.sv >/dev/null
