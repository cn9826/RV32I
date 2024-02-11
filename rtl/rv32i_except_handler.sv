//=================================================================================================
// File: rv32i_except_handler.sv 
//
// Description: RISCV-32I Exception handler. Produces in_prog to lower decode_vld input to 
//              dispatch stage and flush the RISCV Core pipeline. 
//
// Author: Can Ni cni96@outlook.com 
//=================================================================================================
`include "rv32i_pkg.svp"
module rv32i_except_handler
import rv32i_pkg::*;
(
  input  logic                    clk,
  input  logic                    rstn,

  input  logic                    i_rob_except_vld,
  input  logic                    i_rf_except_in_prog,
  input  logic                    i_rob_flush,

  input  logic [NUM_PUS-1:0]      i_pu_rdy,
  input  logic [NUM_PUS-1:0]      i_pu_vld, 

  output logic                    o_in_prog,
  output logic                    o_done
);


//=================================================================================================
// Local Declarations 
//=================================================================================================
assign pipeline_flushed = ~((|i_pu_vld) | ~(&i_pu_rdy));
assign o_done = o_in_prog & !(i_rf_except_in_prog || i_rob_flush) & pipeline_flushed;
//=================================================================================================

always_ff @(posedge clk) begin
  if (!rstn) begin
    o_in_prog <= 1'b0;
  end
  else begin
    if (i_rob_except_vld) begin
      o_in_prog <= 1'b1;
    end
    else if (!(i_rf_except_in_prog || i_rob_flush) && pipeline_flushed && o_in_prog) begin
      o_in_prog <= 1'b0;
    end
  end
end

endmodule