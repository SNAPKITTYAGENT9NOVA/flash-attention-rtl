#!/bin/sh
# Full FA verification flow. Run from anywhere; requires python3+numpy, nim, verilator.
#   1. Python integer model -> test vectors (and float-accuracy check)
#   2. Nim: FA opcode in the SUBLEQ interpreter vs the vectors; writes memory images
#   3. Verilator: unit tests, FA_ENGINE vs vectors, SUBLEQ CPU + FA_ENGINE SoC vs the same outputs
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
python3 software/gen_fa_vectors.py
nim c -d:release --hints:off test_fa_opcode.nim
./test_fa_opcode
cd sim/fa
./build.sh
./work_units/tb_fa_units | grep -E "PASS|FAIL|errors"
./work_engine/tb_fa_engine | grep -E "PASS|FAIL|ran |errors"
pass=0
for img in work_img/*.img; do
  base=${img%.img}
  inarg=""
  [ -f "$base.in" ] && [ -s "$base.in" ] && inarg="+in=$base.in"
  if ./work_soc/tb_subleq_soc +img=$img +exp=$base.exp $inarg > "$base.log" 2>&1; then
    pass=$((pass + 1))
  else
    echo "SoC FAIL: $img"; cat "$base.log" | head -20; exit 1
  fi
done
echo "SoC: $pass programs passed (CPU + FA engine vs reference outputs)"
