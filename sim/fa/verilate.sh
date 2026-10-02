#!/bin/sh
# usage: verilate.sh <top> <workdir> <files...>
top=$1; work=$2; shift 2
rm -rf "$work"
verilator --binary --timing --timescale 1ns/1ps -Wall \
  -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY \
  -Wno-INITIALDLY -Wno-BLKSEQ -Wno-MULTITOP \
  --Mdir "$work" -I../../rtl/src ../../rtl/src/fa_pkg.sv "$@" --top-module "$top" -o "$top"
