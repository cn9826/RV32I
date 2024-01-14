//=================================================================================================
// File: rv32i_reorder_buffer.sv 
//
// Description: RISCV-32I Reorder Buffer (ROB). Implemented as a FIFO. Two pointers, 
//              one points to the oldest (rd_ptr) waiting to be committed, one points to the youngest
//              (wr_ptr).
//              Each entrty has the following field:
//                vld, dst_vld, done, Arch RF Index, Phys RF Index
//              FIFO gets written upon i_dispatch (when all SRCS and DST VR have been consulted) and
//              targed PU reservation station is not full. At the cycle when i_dispatch is asserted,
//              ROB is responsible for returning a comb out of wr_ptr to reflect the instruction entry
//              index for PUs to flop, and use this index to update the done field when PUs finish.
//              
//              An entry is read / retired, when the entry pointed to by rd_ptr's done field is already, 
//              or about to get updated to 1.    
//
// Date Created: 09/03/2023
//
// Author: Can Ni cni96@outlook.com 
//=================================================================================================
`include "rv32i_pkg.svp"
module rv32i_reorder_buffer
import rv32i_pkg::*; 
(
  input  logic                                    clk,
  input  logic                                    rstn,

  // Dispatcher side input I/F
  input  logic                                    i_dispatch,
  input  logic                                    i_dst_vld,
  input  logic [PHYS_REG_FILE_IDX_BW-1:0]         i_dst_phys_rf_tag,
  input  logic [ARCH_REG_FILE_IDX_BW-1:0]         i_dst_arch_rf_idx,

  // PUs'  Write Back I/F to update done field
  input  logic                                    i_write_back,
  input  logic [$clog2(ROB_DEPTH)-1:0]            i_write_back_rob_entry_idx,

  // Upon i_dispatch, return the write index of the entry to be written
  output logic [$clog2(ROB_DEPTH)-1:0]            o_rob_entry_idx,  // aligned and qualified with i_dispatch
  output logic                                    o_full,  
  output logic                                    o_empty,
  
  // Retire output I/F to Register File
  output logic                                    o_retire,
  output logic                                    o_dst_vld,
  output logic [PHYS_REG_FILE_IDX_BW-1:0]         o_retire_dst_phys_rf_tag,
  output logic [ARCH_REG_FILE_IDX_BW-1:0]         o_retire_dst_arch_rf_idx 
);

localparam int ROB_PTR_BW = $clog2(ROB_DEPTH) + (ROB_DEPTH==1) + 1;  


//=================================================================================================
// Local Declarations 
//=================================================================================================
logic [ROB_PTR_BW-1:0]                                wr_ptr, rd_ptr;
logic [ROB_PTR_BW-2:0]                                wr_idx, rd_idx;
logic [ROB_DEPTH-1:0]                                 fifo_vld;
logic [ROB_DEPTH-1:0]                                 fifo_done; // fifo_done somewhat useless
logic [ROB_DEPTH-1:0]                                 fifo_dst_vld;
logic [ROB_DEPTH-1:0][PHYS_REG_FILE_IDX_BW-1:0]       fifo_dst_phys_rf_tag;
logic [ROB_DEPTH-1:0][ARCH_REG_FILE_IDX_BW-1:0]       fifo_dst_arch_rf_idx;
logic                                                 retire_pre; // pop signal, 1 cycle early than o_retire

assign wr_idx = wr_ptr[ROB_PTR_BW-2:0];
assign rd_idx = rd_ptr[ROB_PTR_BW-2:0];
assign o_rob_entry_idx = wr_idx; 
//============================================END==================================================


//=================================================================================================
// FIFO Pointer processes 
//=================================================================================================
assign retire_pre = 
  (fifo_done[rd_ptr]) | 
  (~fifo_done[rd_ptr] & i_write_back & i_write_back_rob_entry_idx == rd_idx); 

assign o_full  = (wr_idx == rd_idx) & (wr_ptr[ROB_PTR_BW-1] ^ rd_ptr[ROB_PTR_BW-1]); 
assign o_empty =  wr_ptr == rd_ptr; 

always_ff @(posedge clk) begin
  if (!rstn) begin
    wr_ptr <= '0;
    rd_ptr <= '0;
  end
  else begin
    if (i_dispatch && !o_full) begin
      wr_ptr <= wr_ptr + 1'b1;
    end
    if (retire_pre) begin
      rd_ptr <= rd_ptr + 1'b1;
    end
  end
end
//============================================END==================================================



//=================================================================================================
// FIFO Push and Pop processes 
//=================================================================================================

//-------------------------------------------------------------------------------------
// Push process
//-------------------------------------------------------------------------------------
always_ff @(posedge clk) begin
  if (!rstn) begin
    fifo_vld                 <= 1'b0;
    //fifo_done                <= '0;
    fifo_dst_vld             <= '0;
    fifo_dst_phys_rf_tag     <= '0;
    fifo_dst_arch_rf_idx     <= '0;  
  end
  else if (i_dispatch && !o_full) begin
    fifo_vld                [wr_idx] <= 1'b1;
    //fifo_done               [wr_idx] <= 1'b0;
    fifo_dst_vld            [wr_idx] <= i_dst_vld; 
    fifo_dst_phys_rf_tag    [wr_idx] <= i_dst_phys_rf_tag;
    fifo_dst_arch_rf_idx    [wr_idx] <= i_dst_arch_rf_idx;
  end
end
//---------------------------------------END-------------------------------------------


//-------------------------------------------------------------------------------------
// Pop process
//-------------------------------------------------------------------------------------
always_ff @(posedge clk) begin
  if (!rstn) begin
    o_retire <= 1'b0;
  end
  else if (o_retire != retire_pre) begin
    o_retire <= retire_pre;
  end
end

always_ff @(posedge clk) begin
  if (retire_pre) begin
    o_dst_vld                <= fifo_dst_vld        [rd_idx];
    o_retire_dst_phys_rf_tag <= fifo_dst_phys_rf_tag[rd_idx];
    o_retire_dst_arch_rf_idx <= fifo_dst_arch_rf_idx[rd_idx]; 
  end
end

//---------------------------------------END-------------------------------------------

//============================================END==================================================


//=================================================================================================
// Update fifo_done on Write Back 
//=================================================================================================
always_ff @(posedge clk) begin
  if (!rstn) begin
    fifo_done <= '0;
  end
  else begin
    if (i_dispatch && !o_full) begin
      
      if (i_write_back) begin
        fifo_done[i_write_back_rob_entry_idx] <= 1'b1;
      end
      
      fifo_done[wr_idx] <= 1'b0;
    end

    else if (i_write_back) begin
      fifo_done[i_write_back_rob_entry_idx] <= 1'b1;
    end
  end
end

//============================================END==================================================



endmodule