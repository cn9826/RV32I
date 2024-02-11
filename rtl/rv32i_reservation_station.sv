//=================================================================================================
// File: rv32i_reservation_station.sv 
//
// Description: RISCV-32I Reservation Station (RS) module. Implemented as a FIFO. Each entry contains
//              SRC1 Phys RF tag  or SRC1 Arch RF value
//              SRC2 Phys RF tag  or SRC2 Arch RF value
//              DST  Phys RF tag (used for WB and for other RS to snoop)
//              When FIFO is empty and there is a push, this pushed entry can be fast-forwarded to pop
//              entry output port without going through FIFO queue.
//              All entries in FIFO need to snoop write back bus   
//
// Date Created: 08/26/2023
//
// Author: Can Ni cni96@outlook.com 
//=================================================================================================
`include "rv32i_pkg.svp"
module rv32i_reservation_station
import rv32i_pkg::*;
#(
  parameter int FIFO_DEPTH = 4
) (
  input  logic                              clk,
  input  logic                              rstn,

  // Pushed to FIFO after dispatcher consults with RF
  input  logic                              i_push,
  // no tag given, Arch RF value already ready; 
  // else still exists as tag
  input  logic                              i_src1_value_vld,
  input  logic [REG_FILE_BW-1:0]            i_src1_value, 
  input  logic [PHYS_REG_FILE_IDX_BW-1:0]   i_src1_phys_rf_tag, 
  input  logic                              i_src2_value_vld,    
  input  logic [REG_FILE_BW-1:0]            i_src2_value, 
  input  logic [PHYS_REG_FILE_IDX_BW-1:0]   i_src2_phys_rf_tag,
  input  logic [PHYS_REG_FILE_IDX_BW-1:0]   i_dst_phys_rf_tag,
  
  // Pushed to FIFO the ROB entry index, aligned with i_push 
  input  logic [$clog2(ROB_DEPTH)-1:0]      i_rob_entry_idx,


  // Snoop broadcast bus
  input  logic                              i_write_back,
  input  logic [PHYS_REG_FILE_IDX_BW-1:0]   i_phys_rf_wr_idx,
  input  logic [REG_FILE_BW-1:0]            i_wdata,

  // PU ready
  input  logic                              i_pu_rdy,

  // FIFO full and empty
  output logic                              o_full,
  output logic                              o_empty,
  
  // Popped entry
  output logic                              o_vld,        // flop out
  output logic [REG_FILE_BW-1:0]            o_src1_value, 
  output logic [REG_FILE_BW-1:0]            o_src2_value, 
  output logic [PHYS_REG_FILE_IDX_BW-1:0]   o_dst_phys_rf_tag, // flop out
  output logic [$clog2(ROB_DEPTH)-1:0]      o_rob_entry_idx
);

localparam int PTR_BW = $clog2(FIFO_DEPTH) + (FIFO_DEPTH==1) + 1;

//=================================================================================================
// Local Declarations 
//=================================================================================================

// FIFO related signals
logic [PTR_BW-1:0]                                rd_ptr, wr_ptr;

logic [PTR_BW-2:0]                                rd_idx, wr_idx;

logic [FIFO_DEPTH-1:0]                            fifo_entry_vld;

logic [FIFO_DEPTH-1:0]                            fifo_src1_value_vld;
logic [FIFO_DEPTH-1:0][REG_FILE_BW-1:0]           fifo_src1_value;
logic [FIFO_DEPTH-1:0][PHYS_REG_FILE_IDX_BW-1:0]  fifo_src1_phys_rf_tag;
logic [FIFO_DEPTH-1:0]                            fifo_src2_value_vld;
logic [FIFO_DEPTH-1:0][REG_FILE_BW-1:0]           fifo_src2_value;
logic [FIFO_DEPTH-1:0][PHYS_REG_FILE_IDX_BW-1:0]  fifo_src2_phys_rf_tag;
logic [FIFO_DEPTH-1:0][PHYS_REG_FILE_IDX_BW-1:0]  fifo_dst_phys_rf_tag;
logic [FIFO_DEPTH-1:0][$clog2(ROB_DEPTH)-1:0]     fifo_rob_entry_idx;

logic                             pop;

logic                             fast_forward_on_empty;

assign rd_idx = rd_ptr[PTR_BW-2:0];
assign wr_idx = wr_ptr[PTR_BW-2:0];
//============================================END==================================================


//=================================================================================================
// FIFO push and pop 
//=================================================================================================
always_comb begin
  pop = 1'b0;
  
  if (
    fifo_entry_vld[rd_idx] &&
    !fifo_src1_value_vld[rd_idx] && fifo_src2_value_vld[rd_idx] && 
    i_write_back && (i_phys_rf_wr_idx == fifo_src1_phys_rf_tag[rd_idx])
  ) begin
    pop = i_pu_rdy; 
  end
  
  if (
    fifo_entry_vld[rd_idx] &&
    !fifo_src2_value_vld[rd_idx] && fifo_src1_value_vld[rd_idx] && 
    i_write_back && (i_phys_rf_wr_idx == fifo_src2_phys_rf_tag[rd_idx])
  ) begin
    pop = i_pu_rdy; 
  end
  
  if (
    fifo_entry_vld[rd_idx] && 
    !fifo_src1_value_vld[rd_idx] && !fifo_src2_value_vld[rd_idx] && 
    i_write_back && (i_phys_rf_wr_idx == fifo_src1_phys_rf_tag[rd_idx]) &&
                    (i_phys_rf_wr_idx == fifo_src2_phys_rf_tag[rd_idx])
  ) begin
    pop = i_pu_rdy; 
  end
  
  if (fifo_src1_value_vld[rd_idx] && fifo_src2_value_vld[rd_idx] && fifo_entry_vld[rd_idx]) begin
    pop = i_pu_rdy;
  end

end

assign fast_forward_on_empty = i_push & o_empty & i_src1_value_vld & i_src2_value_vld;   

assign o_full  = (wr_ptr[PTR_BW-2:0] == rd_ptr[PTR_BW-2:0]) &  (wr_ptr[PTR_BW-1]^rd_ptr[PTR_BW-1]); 
assign o_empty = (wr_ptr[PTR_BW-2:0] == rd_ptr[PTR_BW-2:0]) & ~(wr_ptr[PTR_BW-1]^rd_ptr[PTR_BW-1]);

always_ff @(posedge clk) begin
  if (!rstn) begin
    wr_ptr <= '0;
    rd_ptr <= '0;
  end
  else begin
    if (i_push && !o_full && !fast_forward_on_empty) begin
      wr_ptr <= wr_ptr + 1'b1;
    end
    if (pop && !o_empty) begin
      rd_ptr <= rd_ptr + 1'b1;
    end
  end
end

// Push process AND snoop process: data reg reset is unnecessary
always_ff @(posedge clk) begin
  for (int i=0; i<FIFO_DEPTH; i++) begin
    if ((PTR_BW-1)'(i) == wr_idx) begin
      if (i_push && !o_full && !fast_forward_on_empty) begin

        fifo_src1_value_vld[i] <= i_src1_value_vld;
        if (i_src1_value_vld)
          fifo_src1_value[i] <= i_src1_value;
        if (!i_src1_value_vld)
          fifo_src1_phys_rf_tag[i] <= i_src1_phys_rf_tag;

        fifo_src2_value_vld[i] <= i_src2_value_vld;
        if (i_src2_value_vld)
          fifo_src2_value[i] <= i_src2_value;
        if (!i_src2_value_vld)
          fifo_src2_phys_rf_tag[i] <= i_src2_phys_rf_tag;

        fifo_dst_phys_rf_tag[i] <= i_dst_phys_rf_tag; 
        fifo_rob_entry_idx[i] <= i_rob_entry_idx;  
      end
    end
    else begin
      if (fifo_entry_vld[i]) begin
        if (!fifo_src1_value_vld[i] && i_write_back && i_phys_rf_wr_idx == fifo_src1_phys_rf_tag[i]) begin
          fifo_src1_value_vld[i] <= 1'b1;
          fifo_src1_value    [i] <= i_wdata;
        end
        if (!fifo_src2_value_vld[i] && i_write_back && i_phys_rf_wr_idx == fifo_src2_phys_rf_tag[i]) begin
          fifo_src2_value_vld[i] <= 1'b1;
          fifo_src2_value    [i] <= i_wdata;
        end
      end
    end 
  end
end
//============================================END==================================================



//=================================================================================================
// Validate FIFO entry on push and invalidate on pop 
//=================================================================================================
always_ff @(posedge clk) begin
  if (!rstn) begin
    fifo_entry_vld <= '0;
  end
  else begin
    if (i_push && !o_full && !fast_forward_on_empty) begin
      fifo_entry_vld[wr_idx] <= 1'b1;
    end
    if (pop && !o_empty) begin
      fifo_entry_vld[rd_idx] <= 1'b0;
    end
  end
end
//============================================END==================================================



//=================================================================================================
// Output and qualify output 
//=================================================================================================
always_ff @(posedge clk) begin
  if (!rstn) begin
    o_vld <= 1'b0;
  end
  else if (o_vld != (fast_forward_on_empty | pop)) begin
    o_vld <= (fast_forward_on_empty | pop);
  end
end

always_ff @(posedge clk) begin
  if (pop) begin
    
    if (
      !fifo_src1_value_vld[rd_idx] && fifo_src2_value_vld[rd_idx] && 
      i_write_back && (i_phys_rf_wr_idx == fifo_src1_phys_rf_tag[rd_idx])
    ) begin
      o_src1_value <= i_wdata;
      o_src2_value <= fifo_src2_value[rd_idx];  
    end

    else if (
      !fifo_src2_value_vld[rd_idx] && fifo_src1_value_vld[rd_idx] && 
      i_write_back && (i_phys_rf_wr_idx == fifo_src2_phys_rf_tag[rd_idx])
    ) begin
      o_src1_value <= fifo_src1_value[rd_idx];
      o_src2_value <= i_wdata; 
    end

    else if (
    !fifo_src1_value_vld[rd_idx] && !fifo_src2_value_vld[rd_idx] && 
    i_write_back && (i_phys_rf_wr_idx == fifo_src1_phys_rf_tag[rd_idx]) &&
                    (i_phys_rf_wr_idx == fifo_src2_phys_rf_tag[rd_idx])
    ) begin
      o_src1_value <= i_wdata;
      o_src2_value <= i_wdata;
    end

    else if (fifo_src1_value_vld[rd_idx] && fifo_src2_value_vld[rd_idx]) begin
      o_src1_value <= fifo_src1_value[rd_idx];
      o_src2_value <= fifo_src2_value[rd_idx];
    end
    o_dst_phys_rf_tag <= fifo_dst_phys_rf_tag[rd_idx];
    o_rob_entry_idx   <= fifo_rob_entry_idx[rd_idx];  
  end
  
  else if (fast_forward_on_empty) begin
    o_src1_value <= i_src1_value; 
    o_src2_value <= i_src2_value;
    o_dst_phys_rf_tag <= i_dst_phys_rf_tag;
    o_rob_entry_idx <= i_rob_entry_idx; 
  end
end
//============================================END==================================================

endmodule