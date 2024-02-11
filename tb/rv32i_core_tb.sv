`timescale 1ns/100ps
`include "rv32i_pkg.svp"
module rv32i_core_tb 
import rv32i_pkg::*;
();

logic                                   clk, rstn;
logic                                   i_decode_vld;
logic [PU_ID_BW-1:0]                    i_pu_id; 
logic                                   i_rs1_vld;
logic [ARCH_REG_FILE_IDX_BW-1:0]        i_src1_arch_rf_idx;
logic                                   i_rs2_vld;
logic [ARCH_REG_FILE_IDX_BW-1:0]        i_src2_arch_rf_idx;
logic                                   i_rd_vld;
logic [ARCH_REG_FILE_IDX_BW-1:0]        i_dst_arch_rf_idx;
logic [REG_FILE_BW-1:0]                 i_imm;
logic                                   o_rdy;

always #0.5 clk = ~clk;

initial begin
  clk  = 1'b1;
  rstn = 1'b0;
  i_decode_vld = 1'b0;

  #1.1;
  rstn = 1'b1;

  // 0: R1 = R0 + 7
  @(posedge clk);
  #0.1;
  i_decode_vld = 1'b1;
  i_pu_id = PU_ID_BW'(0);
  i_rs1_vld = 1'b1;
  i_src1_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(0);
  i_rs2_vld = 1'b0;
  i_src2_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(1);
  i_imm = (REG_FILE_BW)'(7);
  i_rd_vld = 1'b1;
  i_dst_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(1);

  // 1: R1 = R1 + R1
  @(posedge clk);
  #0.1;
  i_decode_vld = 1'b1;
  i_pu_id = PU_ID_BW'(0);
  i_rs1_vld = 1'b1;
  i_src1_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(1);
  i_rs2_vld = 1'b1;
  i_src2_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(1);
  i_imm = (REG_FILE_BW)'(0);
  i_rd_vld = 1'b1;
  i_dst_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(1);

  // 2: R2 = R1 * (-3) 
  @(posedge clk);
  #0.1;
  i_decode_vld = 1'b1;
  i_pu_id = PU_ID_BW'(1);
  i_rs1_vld = 1'b1;
  i_src1_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(1);
  i_rs2_vld = 1'b0;
  i_src2_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(0);
  i_imm = $signed((REG_FILE_BW)'(-3));
  i_rd_vld = 1'b1;
  i_dst_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(2);

  // 3: R2 = R1 + 40  
  @(posedge clk);
  #0.1;
  i_decode_vld = 1'b1;
  i_pu_id = PU_ID_BW'(0);
  i_rs1_vld = 1'b1;
  i_src1_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(1);
  i_rs2_vld = 1'b0;
  i_src2_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(0);
  i_imm = (REG_FILE_BW)'(40);
  i_rd_vld = 1'b1;
  i_dst_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(2);

  // 4: R2 = R1 - 100
  @(posedge clk);
  #0.1;
  i_decode_vld = 1'b1;
  i_pu_id = PU_ID_BW'(0);
  i_rs1_vld = 1'b1;
  i_src1_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(1);
  i_rs2_vld = 1'b0;
  i_src2_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(0);
  i_imm = $signed((REG_FILE_BW)'(-100));
  i_rd_vld = 1'b1;
  i_dst_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(2);
  
  
  // 5: R2 = R1 + 100
  @(posedge clk);
  #0.1;
  i_decode_vld = 1'b1;
  i_pu_id = PU_ID_BW'(0);
  i_rs1_vld = 1'b1;
  i_src1_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(1);
  i_rs2_vld = 1'b0;
  i_src2_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(0);
  i_imm = $signed((REG_FILE_BW)'(+100));
  i_rd_vld = 1'b1;
  i_dst_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(2);

  
  // 6: R1 = R1 - 40  
  @(posedge clk);
  #0.1;
  i_decode_vld = 1'b1;
  i_pu_id = PU_ID_BW'(0);
  i_rs1_vld = 1'b1;
  i_src1_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(1);
  i_rs2_vld = 1'b0;
  i_src2_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(0);
  i_imm = $signed((REG_FILE_BW)'(-40));
  i_rd_vld = 1'b1;
  i_dst_arch_rf_idx = ARCH_REG_FILE_IDX_BW'(1);


  @(posedge clk);
  #0.1;
  i_decode_vld = 1'b0;

  repeat(20) @(posedge clk);
  $finish;

end

initial begin
  $dumpfile("dump.vcd");
  $dumpvars;
end

rv32i_core u_rv32i_core (
  .clk,
  .rstn,
  .i_decode_vld,
  .i_pu_id,
  .i_rs1_vld,
  .i_src1_arch_rf_idx,
  .i_rs2_vld,
  .i_src2_arch_rf_idx,
  .i_rd_vld,
  .i_dst_arch_rf_idx,
  .i_imm,
  .o_rdy
);



endmodule