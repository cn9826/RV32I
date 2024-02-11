//=================================================================================================
// File: rv32i_adder.sv 
//
// Description: RISCV-32I 32b adder functional unit. Inputs are considered signed numbers. Takes one
//              to return sum or difference.
//
// Date Created: 09/03/2023
//
// Author: Can Ni cni96@outlook.com 
//=================================================================================================
`include "rv32i_pkg.svp"
module rv32i_adder
import rv32i_pkg::*;
(
  input  logic                                clk,
  input  logic                                rstn,

  input  logic                                i_vld,
  input  logic                                i_sub_flag,
  input  logic signed [31:0]                  i_a,
  input  logic signed [31:0]                  i_b,
  input  logic [PHYS_REG_FILE_IDX_BW-1:0]     i_dst_phys_rf_tag,
  input  logic [$clog2(ROB_DEPTH)-1:0]        i_rob_entry_idx,
  input  logic                                i_rdy,

  output logic                                o_rdy,
  output logic                                o_vld,
  output logic [PHYS_REG_FILE_IDX_BW-1:0]     o_dst_phys_rf_tag,
  output logic [$clog2(ROB_DEPTH)-1:0]        o_rob_entry_idx,
  output logic signed [31:0]                  o_sum,
  output logic                                o_overflow
);

logic signed [32:0] sum;
logic signed [31:0] b; 
assign o_rdy = ~(o_vld & ~i_rdy);
assign b = i_sub_flag ? -i_b : i_b;

always_ff @(posedge clk) begin
  if (!rstn) begin
    o_vld <= 1'b0;
  end
  else if (o_rdy && i_vld) begin
    o_vld <= 1'b1;
  end
  else if (o_vld && i_rdy) begin
    o_vld <= 1'b0;
  end
end

always_ff @(posedge clk) begin
  if (!rstn) begin
    sum               <= '0;
    o_dst_phys_rf_tag <= '0;
    o_rob_entry_idx   <= '0;
  end
  else if (i_vld && o_rdy) begin
    sum               <= i_a + b;
    o_dst_phys_rf_tag <= i_dst_phys_rf_tag;
    o_rob_entry_idx   <= i_rob_entry_idx;
  end
end

assign o_sum = sum[31:0];
assign o_overflow = 
  ~i_a[31] & ~b[31] & sum[31] | i_a[31] & b[31] & ~sum[31]; 

endmodule