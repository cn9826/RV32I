#!/bin/zsh
iverilog -g2012 -I ../include \
  -o rv32i_core_tb.vvp \
  ../rtl/rv32i_adder.sv \
  ../rtl/rv32i_multiplier_pipelined.sv \
  ../rtl/rv32i_reservation_station.sv \
  ../rtl/rv32i_register_file.sv \
  ../rtl/rv32i_reorder_buffer.sv \
  ../rtl/rv32i_dispatch.sv \
  ../rtl/round_robin_arbiter.sv \
  ../rtl/rv32i_core.sv \
  ./rv32i_core_tb.sv \

vvp rv32i_core_tb.vvp
