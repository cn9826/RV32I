//=================================================================================================
// File: rv32i_multiplier_pipelined.sv 
//
// Description: RISCV-32I 32b Multiplier PU. Products are formed in 4 stages. Each stage 
//              sums up 8 lines of partial product. 
//
// Date Created: 08/28/2023
//
// Author: Can Ni cni96@outlook.com 
//=================================================================================================
`include "rv32i_pkg.svp"
module rv32i_multiplier_pipelined
import rv32i_pkg::*;
(
  input  logic                                clk,
  input  logic                                rstn,

  input  logic                                i_vld,
  input  logic [31:0]                         i_multiplicand,
  input  logic [31:0]                         i_multiplier,
  input  logic [PHYS_REG_FILE_IDX_BW-1:0]     i_dst_phys_rf_tag,
  input  logic [$clog2(ROB_DEPTH)-1:0]        i_rob_entry_idx,
  input  logic                                i_rdy,

  output logic                                o_rdy,
  output logic                                o_vld,
  output logic [PHYS_REG_FILE_IDX_BW-1:0]     o_dst_phys_rf_tag,
  output logic [$clog2(ROB_DEPTH)-1:0]        o_rob_entry_idx,
  output logic [31:0]                         o_product 
);


//=================================================================================================
// Local Declarations 
//=================================================================================================

logic [2:0]                         stage_cnt;
logic [7:0][63:0]                   partial_product_s; 
logic [7:0][63:0]                   partial_product_r;
logic [63:0]                        partial_sum_s;
logic [63:0]                        partial_sum_r;
logic [31:0]                        multiplicand_r; 
logic [31:0]                        multiplier_r;

//============================================END==================================================


//=================================================================================================
// Incrementing stage count and o_rdy o_vld logic that depend on it 
//=================================================================================================
always_ff @(posedge clk) begin
  if (!rstn) begin
    stage_cnt         <= '0;
    o_dst_phys_rf_tag <= '0;
    o_rob_entry_idx   <= '0;
  end
  else if (i_vld && o_rdy) begin
    stage_cnt <= 1'b1;
    o_dst_phys_rf_tag <= i_dst_phys_rf_tag;
    o_rob_entry_idx   <= i_rob_entry_idx;
  end
  else if (stage_cnt >= 3'd1) begin
    if (stage_cnt != 3'd4)
      stage_cnt <= stage_cnt + 1'b1;
    else
      stage_cnt <= '0; 
  end
end

assign o_rdy = o_vld ? i_rdy : stage_cnt == '0;

always_ff @(posedge clk) begin
  if (!rstn) begin
    o_vld <= 1'b0;
  end
  else if (i_vld && o_rdy) begin
    o_vld <= 1'b0;
  end
  else if (stage_cnt == 3'd3) begin
    o_vld <= 1'b1;
  end
  else if (o_vld && i_rdy) begin
    o_vld <= 1'b0;
  end
end
//============================================END==================================================


//=================================================================================================
// Datapath combinational and feedback flop 
//=================================================================================================

always_ff @(posedge clk) begin
  if (i_vld && o_rdy) begin
    multiplicand_r <= i_multiplicand;
    multiplier_r   <= i_multiplier;
  end
end

always_comb begin
  partial_product_s = partial_product_r;
  if (i_vld && o_rdy) begin
    partial_sum_s = '0;
    for (int i=0; i<8; i++) begin
      partial_product_s[i] = (i_multiplicand << i);
      if (i_multiplier[i]) begin
        partial_sum_s += partial_product_s[i];
      end 
    end
  end
  else if (stage_cnt >= 3'd1 && stage_cnt <= 3'd3) begin
    for (int i=0; i<8; i++) begin
      partial_product_s[i] = ( multiplicand_r << (stage_cnt*8+i) );
      if (multiplier_r[stage_cnt*8+i]) begin
        partial_sum_s += partial_product_s[i]; 
      end
    end
  end
end

always_ff @(posedge clk) begin
  if (!rstn) begin
    partial_product_r <= '0;
    partial_sum_r     <= '0;
  end
  else if ((i_vld && o_rdy) || (stage_cnt >= 3'd1 && stage_cnt <= 3'd3)) begin
    partial_product_r <= partial_product_s;
    partial_sum_r     <= partial_sum_s;
  end
end

assign o_product = partial_sum_r[31:0]; 
//============================================END==================================================


endmodule