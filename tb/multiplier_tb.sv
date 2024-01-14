`timescale 1ns/100ps
module multiplier_tb ();

logic clk, rstn;

logic i_vld, i_rdy;

logic [31:0] i_multiplicand, i_multiplier;

logic o_rdy, o_vld;

logic [31:0]  o_product;

always #0.5 clk = ~clk;

initial begin
  clk = 1'b1;
  rstn = 1'b0;
  i_vld = 1'b0;
  i_rdy = 1'b1;

;
  rstn = 1'b1;

  // First set of input
  @(posedge clk);
  #0.1;
  i_vld = 1'b1;
  i_multiplicand = 'h0000BEEF; 
  i_multiplier   = 'h000000CA;

  // Second set of input; multiplier should not accept it
  @(posedge clk);
  #0.1;
  i_vld = 1'b1;
  i_multiplicand = 'h0000FEED; 
  i_multiplier   = 'h000000AC;

  // posedge of o_vld; should be deasserted after one cycle and accept the second
  // set of input
  @(posedge o_vld);

  repeat(2) @(posedge clk);
  #0.1;
  i_rdy = 1'b0;
  #2.0;
  i_rdy = 1'b1;

  // Third set of input
  i_vld = 1'b1;
  i_multiplicand = 'h0000ACBD; 
  i_multiplier   = 'h0000CAFE;
  
  @(posedge o_vld); 
  #0.1;
  i_rdy = 1'b0;
  #2.0;
  i_rdy = 1'b1;

  repeat(5) @(posedge clk);
  $finish;
end

initial begin
  $dumpfile("dump.vcd");
  $dumpvars;
end

rv32i_multiplier_pipelined u_dut (
  .clk,
  .rstn,
  .i_vld,
  .i_multiplicand,
  .i_multiplier,
  .i_rdy,
  .o_rdy,
  .o_vld,
  .o_product
);


endmodule