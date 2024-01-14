`timescale 1ns/100ps
`include "rv32i_pkg.svp"
module reservation_station_tb
import rv32i_pkg::*;
();

localparam int FIFO_DEPTH = 4;

logic clk, rstn;

logic i_push;

logic                              i_src1_value_vld;
logic [REG_FILE_BW-1:0]            i_src1_value; 
logic [PHYS_REG_FILE_IDX_BW-1:0]   i_src1_phys_rf_tag;
logic                              i_src2_value_vld;  
logic [REG_FILE_BW-1:0]            i_src2_value; 
logic [PHYS_REG_FILE_IDX_BW-1:0]   i_src2_phys_rf_tag;
logic [PHYS_REG_FILE_IDX_BW-1:0]   i_dst_phys_rf_tag;

logic                              i_write_back;
logic [PHYS_REG_FILE_IDX_BW-1:0]   i_phys_rf_wr_idx;
logic [REG_FILE_BW-1:0]            i_wdata;

logic                              i_pu_rdy;
logic                              o_full;
logic                              o_empty;

logic                              o_vld; 
logic [REG_FILE_BW-1:0]            o_src1_value; 
logic [REG_FILE_BW-1:0]            o_src2_value; 
logic [PHYS_REG_FILE_IDX_BW-1:0]   o_dst_phys_rf_tag;

always #0.5 clk = ~clk;

initial begin
  clk = 1'b1;
  rstn = 1'b0;
  i_push = 1'b0;
  i_pu_rdy = 1'b1;
  i_write_back = 1'b0;

  #1.1;
  rstn = 1'b1;
  // Entry 0: both SRCs are valid, fast forward
  @(posedge clk);
  #0.1;
  i_push = 1'b1;
  i_src1_value_vld = 1'b1;
  i_src1_value     = 'hbbbbaaaa; 
  i_src2_value_vld = 1'b1;
  i_src2_value     = 'hcacacaca; 
  i_dst_phys_rf_tag  = 'h0c;

  // Entry 1: both SRCs are invalid, same SRC tag
  @(posedge clk);
  #0.1;
  i_push = 1'b1;
  i_src1_value_vld = 1'b0;
  i_src1_phys_rf_tag = 'h00;
  i_src2_value_vld = 1'b0;
  i_src2_phys_rf_tag = 'h00;
  i_dst_phys_rf_tag  = 'h0a;
  @(posedge clk);
  #0.1;
  i_push = 1'b0;


  // Entry 2: SRC1 valid, SRC2 invalid at the same time of push, initiate WB on Entry 1
  @(posedge clk);
  #0.1;
  i_push = 1'b1;
  i_src1_value_vld = 1'b1;
  i_src1_value     = 'hbeefbeef; 
  i_src2_value_vld = 1'b0;
  i_src2_phys_rf_tag = 'h02;
  i_dst_phys_rf_tag  = 'h1f;
  
  i_write_back = 1'b1;
  i_phys_rf_wr_idx = 'h00;
  i_wdata = 'hdaddad00;  
  
  // Entry 3: both valid 
  @(posedge clk);
  #0.1;
  i_write_back = 1'b0;
  i_push = 1'b1;
  i_src1_value_vld = 1'b1;
  i_src1_value     = 'hfeedfeed; 
  i_src2_value_vld = 1'b1;
  i_src2_value     = 'hdeafdeaf;
  i_dst_phys_rf_tag  = 'h0b;

  // Entry 4: SRC2 valid, SRC1 invalid at time of push
  @(posedge clk);
  #0.1;
  i_push = 1'b1;
  i_src1_value_vld = 1'b0;
  i_src1_phys_rf_tag = 'h02;
  i_src2_value_vld = 1'b1;
  i_src2_value     = 'hedfafeda; 
  i_dst_phys_rf_tag  = 'h1f;

  // Write back on Entry 2 and 4
  @(posedge clk);
  #0.1;
  i_push = 1'b0;
  i_write_back = 1'b1;
  i_phys_rf_wr_idx = 'h02;
  i_wdata = 'hfadecafe; 
  @(posedge clk);
  #0.1;
  i_write_back = 1'b0;

  repeat (5) @(posedge clk);
  $finish;
end

initial begin
  $dumpfile("dump.vcd");
  $dumpvars;
end

rv32i_reservation_station #(
  .FIFO_DEPTH (FIFO_DEPTH)
) u_reservation_stateion (
  .clk,
  .rstn,
  .i_push,
  .i_src1_value_vld,
  .i_src1_value,
  .i_src1_phys_rf_tag,
  .i_src2_value_vld,
  .i_src2_value,
  .i_src2_phys_rf_tag,
  .i_dst_phys_rf_tag,
  .i_rob_entry_idx ('0),

  .i_write_back,
  .i_phys_rf_wr_idx,
  .i_wdata,
  
  .i_pu_rdy,
  
  .o_full,
  .o_empty,
  .o_vld,
  .o_src1_value,
  .o_src2_value,
  .o_dst_phys_rf_tag,
  .o_rob_entry_idx ()
);


endmodule