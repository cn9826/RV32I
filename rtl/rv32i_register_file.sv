//=================================================================================================
// File: rv32i_register_file.sv 
//
// Description: RISCV-32I Register File module. 1-cycle WR latency and 1-cycle RD latency. Uses 
//              SV register to emulate SRAM behavior. There are 2 read ports and 1 write ports
//
// Date Created: 08/13/2023
//
// Author: Can Ni cni96@outlook.com 
//=================================================================================================
`include "rv32i_pkg.svp"
module rv32i_register_file 
import rv32i_pkg::*;
(
  input  logic                              clk,
  input  logic                              rstn,
  input  logic                              i_wen,
  input  logic [PHYS_REG_FILE_IDX_BW-1:0]   i_phys_rf_wr_idx,  // Physical RF address
  input  logic [REG_FILE_BW-1:0]            i_wdata,

  // dispatcher checks with RF prior to dispatch, giving RF the Arch RF it wants to read,
  // and its DST Arch RF (if any), for RF to update RAT on this Arch RF with a new tag 
  input  logic                              i_pre_dispatch,
  input  logic                              i_ren_src1,
  input  logic                              i_ren_src2,
  input  logic [ARCH_REG_FILE_IDX_BW-1:0]   i_src1_arch_rf_idx,  // Architectural RF address
  input  logic [ARCH_REG_FILE_IDX_BW-1:0]   i_src2_arch_rf_idx,  // Architectural RF address
  input  logic                              i_dst_arch_rf_vld,
  input  logic [ARCH_REG_FILE_IDX_BW-1:0]   i_dst_arch_rf_idx, 

  // Inputs from ROB to update RAT
  // A tag is freed to use when in the RAT, Arch RF - Phys RF entry indicates committed
  // And then a new instruction with the same Arch RF comes 
  input  logic                              i_retire,
  input  logic                              i_retire_dst_vld,
  input  logic [ARCH_REG_FILE_IDX_BW-1:0]   i_retire_arch_rf_idx,
  input  logic [PHYS_REG_FILE_IDX_BW-1:0]   i_retire_phys_rf_idx,

  // returns a Physical RF tag to dispatcher if SRC Arch RF's corresponding Phys RF tag says
  // !valid 
  output logic                              o_src1_phys_rf_tag_vld, 
  output logic [PHYS_REG_FILE_IDX_BW-1:0]   o_src1_phys_rf_tag_idx,
  output logic                              o_src1_rdata_vld,
  output logic [REG_FILE_BW-1:0]            o_src1_rdata,
  output logic                              o_src2_phys_rf_tag_vld, 
  output logic [PHYS_REG_FILE_IDX_BW-1:0]   o_src2_phys_rf_tag_idx,
  output logic                              o_src2_rdata_vld,
  output logic [REG_FILE_BW-1:0]            o_src2_rdata,

  // returned DST Alias
  output logic                              o_dst_phys_rf_tag_vld,
  output logic [PHYS_REG_FILE_IDX_BW-1:0]   o_dst_phys_rf_tag_idx,

  output logic                              o_phys_rf_tag_avail
);

localparam int TAG_STACK_DEPTH = NUM_PHYS_REG_FILES;
localparam int TAG_STACK_PTR_BW = $clog2(TAG_STACK_DEPTH); 

//=================================================================================================
// Local Declarations 
//=================================================================================================

// Register Alias Table Tag field
logic [NUM_ARCH_REG_FILES-1:0][PHYS_REG_FILE_IDX_BW-1:0]  rat_tag_r;

// Register Alias Table Committed field
logic [NUM_ARCH_REG_FILES-1:0]                            rat_committed_r;

// Tag stack
logic [TAG_STACK_DEPTH-1:0][PHYS_REG_FILE_IDX_BW-1:0]     tag_stack_r;
logic [TAG_STACK_PTR_BW-1:0]                              tag_stack_ptr; // the last valid entry position
logic [TAG_STACK_PTR_BW-1:0]                              tag_stack_ptr_m1;
logic                                                     tag_stack_pop;
logic                                                     tag_stack_push;
logic [PHYS_REG_FILE_IDX_BW-1:0]                          tag_to_free;
logic [PHYS_REG_FILE_IDX_BW-1:0]                          popped_tag;
logic                                                     tag_stack_empty, tag_stack_full;
logic                                                     tag_stack_pop_data_vld;

// Physical Register File valid field; asserted as valid after WB
logic [NUM_PHYS_REG_FILES-1:0]                            phys_rf_vld_r;

// Instantiation of Physical RF array
logic [NUM_PHYS_REG_FILES-1:0][REG_FILE_BW-1:0]           phys_rf_array; 

//============================================END==================================================



//=================================================================================================
// Ready logic of RF. Stall if no RF tag is available    
//=================================================================================================
assign tag_stack_empty = (tag_stack_ptr == TAG_STACK_PTR_BW'(TAG_STACK_DEPTH-1));
assign tag_stack_full  = (tag_stack_ptr == '0);
assign o_phys_rf_tag_avail = ~tag_stack_empty;
// Could overflow but the overflown value should never be flopped to _r
assign tag_stack_ptr_m1 = tag_stack_ptr - 1'b1; 

// LIFO Pop on Dispatcher DST consultation; 
// LIFO Push to reclaim a previously committed Phys Tag when ROB retires a DST with a Phys Tag that is not the most up-to-date, i.e.,
// ROB retires an old Phys Tag != most up-to-date Phys Tag, then this old Phys Tag can be reclaimed  
assign tag_stack_pop  = o_phys_rf_tag_avail & i_pre_dispatch & i_dst_arch_rf_vld;
//assign tag_stack_push = i_pre_dispatch & i_dst_arch_rf_vld & rat_committed_r[i_dst_arch_rf_idx];
//assign tag_to_free    = tag_stack_push ? rat_tag_r[i_dst_arch_rf_idx] : '0; 
assign tag_stack_push = i_retire & i_retire_dst_vld & (i_retire_phys_rf_idx != rat_tag_r[i_retire_arch_rf_idx]);
assign tag_to_free    = tag_stack_push ? i_retire_phys_rf_idx : '0;
always_ff @(posedge clk) begin
  if (!rstn) begin
    for (int i=0; i<TAG_STACK_DEPTH; i++) begin
      tag_stack_r[i] = PHYS_REG_FILE_IDX_BW'(i);
    end
    tag_stack_ptr <= '0;
  end

  else if (tag_stack_pop) begin
    // simultaneous push: don't decrement wptr, pop and push
    if (tag_stack_push) begin
      tag_stack_r[tag_stack_ptr] <= tag_to_free; 
    end
    // if purely pop
    else begin
      tag_stack_ptr <= tag_stack_ptr + 1'b1;
    end
  end

  // stack push should not respond to o_phys_rf_tag_avail and can occur alone 
  else if (tag_stack_push) begin
    tag_stack_r[tag_stack_ptr_m1] <= tag_to_free;
    tag_stack_ptr <= tag_stack_ptr_m1;
  end

end

//============================================END==================================================




//=================================================================================================
// Dispatcher concsulting logic: returns a Phys RF tag if Arch RF is uncommitted; else returns
// the Phys RF content (SRC Part).
// With DST Arch RF, find itself a tag.
// These output returns 1 cycle after i_pre_dispatch 
//=================================================================================================
//---------------------------------------------------------------------
// SRC logic part
//---------------------------------------------------------------------

always_ff @(posedge clk) begin
  if (!rstn) begin
    o_src1_phys_rf_tag_vld <= 1'b0;
    o_src1_phys_rf_tag_idx <= '0;
    o_src1_rdata_vld       <= 1'b0;
    o_src2_phys_rf_tag_vld <= 1'b0;
    o_src2_phys_rf_tag_idx <= '0;
    o_src2_rdata_vld       <= 1'b0;
  end

  else if (o_phys_rf_tag_avail) begin
    
    if (i_pre_dispatch && i_ren_src1) begin
      if (i_src1_arch_rf_idx != '0) begin
        if (phys_rf_vld_r[rat_tag_r[i_src1_arch_rf_idx]]) begin
          o_src1_rdata_vld       <= 1'b1;
          o_src1_rdata           <= phys_rf_array[rat_tag_r[i_src1_arch_rf_idx]];
          o_src1_phys_rf_tag_vld <= 1'b0;
        end
        else if (i_wen && i_phys_rf_wr_idx == rat_tag_r[i_src1_arch_rf_idx]) begin
          o_src1_rdata_vld       <= 1'b1;
          o_src1_rdata           <= i_wdata;
          o_src1_phys_rf_tag_vld <= 1'b0; 
        end
        else begin
          o_src1_rdata_vld       <= 1'b0;
          o_src1_phys_rf_tag_vld <= 1'b1;
          o_src1_phys_rf_tag_idx <= rat_tag_r[i_src1_arch_rf_idx]; 
        end
      end // if (i_src1_arch_rf_idx != '0)
      else begin
        o_src1_rdata_vld       <= 1'b1;
        o_src1_rdata           <= '0;
        o_src1_phys_rf_tag_vld <= 1'b0; 
      end // else if (i_src1_arch_rf_idx == '0)
    end
    else begin
      if (o_src1_rdata_vld) begin
        o_src1_rdata_vld <= 1'b0;
      end
      if (o_src1_phys_rf_tag_vld) begin
        o_src1_phys_rf_tag_vld <= 1'b0;
      end
    end
    
    if (i_pre_dispatch && i_ren_src2) begin
      if (i_src2_arch_rf_idx != '0) begin
        if (phys_rf_vld_r[rat_tag_r[i_src2_arch_rf_idx]]) begin
          o_src2_rdata_vld       <= 1'b1;
          o_src2_rdata           <= phys_rf_array[rat_tag_r[i_src2_arch_rf_idx]];
          o_src2_phys_rf_tag_vld <= 1'b0;
        end
        else if (i_wen && i_phys_rf_wr_idx == rat_tag_r[i_src2_arch_rf_idx]) begin
          o_src2_rdata_vld       <= 1'b1;
          o_src2_rdata           <= i_wdata;
          o_src2_phys_rf_tag_vld <= 1'b0; 
        end
        else begin
          o_src2_rdata_vld       <= 1'b0;
          o_src2_phys_rf_tag_vld <= 1'b1;
          o_src2_phys_rf_tag_idx <= rat_tag_r[i_src2_arch_rf_idx]; 
        end
      end // if (i_src2_arch_rf_idx != '0)
      else begin 
        o_src2_rdata_vld        <= 1'b1;
        o_src2_rdata            <= '0;
        o_src2_phys_rf_tag_vld  <= 1'b0; 
      end // else if (i_src2_arch_rf_idx == '0)
    end
    else begin
      if (o_src2_rdata_vld) begin
        o_src2_rdata_vld <= 1'b0;
      end
      if (o_src2_phys_rf_tag_vld) begin
        o_src2_phys_rf_tag_vld <= 1'b0;
      end
    end
  
  end

  else begin
    if (o_src1_phys_rf_tag_vld)
      o_src1_phys_rf_tag_vld <= 1'b0;
    if (o_src1_rdata_vld)
      o_src1_rdata_vld <= 1'b0;
    if (o_src2_phys_rf_tag_vld)
      o_src2_phys_rf_tag_vld <= 1'b0;
    if (o_src2_rdata_vld)
      o_src2_rdata_vld <= 1'b0;
  end
end

//------------------------------END------------------------------------



//---------------------------------------------------------------------
// DST logic part
//---------------------------------------------------------------------
always_ff @(posedge clk) begin
  if (!rstn) begin
    o_dst_phys_rf_tag_vld <= 1'b0;
  end
  else begin
    if (tag_stack_pop) begin
      o_dst_phys_rf_tag_vld <= 1'b1;
      o_dst_phys_rf_tag_idx <= tag_stack_r[tag_stack_ptr]; 
    end
    else if (!tag_stack_pop && o_dst_phys_rf_tag_vld) begin
      o_dst_phys_rf_tag_vld <= 1'b0;
    end
  end
end
//------------------------------END------------------------------------

//============================================END==================================================



//=================================================================================================
// RAT table assignemnt logic
// Retire logic from ROB: if retire phys_rf_idx == rat_tag_r, mark as committed
// Tag assignment is done upon tag_stack_pop 
//=================================================================================================
always_ff @(posedge clk) begin
  if (!rstn) begin
    rat_committed_r <= '0;
  end
  else if (tag_stack_pop) begin
    rat_committed_r[i_dst_arch_rf_idx] <= 1'b0;
    rat_tag_r[i_dst_arch_rf_idx] <= tag_stack_r[tag_stack_ptr];
  end
  else if (i_retire & i_retire_dst_vld) begin
    rat_committed_r[i_dst_arch_rf_idx] <= (i_retire_phys_rf_idx == rat_tag_r[i_retire_arch_rf_idx]);
  end
end
//============================================END==================================================




//=================================================================================================
// Write back logic 
//=================================================================================================
always_ff @(posedge clk) begin
  if (!rstn) begin
    phys_rf_vld_r <= '0;
    phys_rf_array <= '0;
  end
  else if (tag_stack_pop) begin
    if (i_wen) begin
      phys_rf_vld_r[i_phys_rf_wr_idx] <= 1'b1;
      phys_rf_array[i_phys_rf_wr_idx] <= i_wdata;
    end
    phys_rf_vld_r[tag_stack_r[tag_stack_ptr]] <= 1'b0; 
  end
  else if (i_wen) begin
    phys_rf_vld_r[i_phys_rf_wr_idx] <= 1'b1;
    phys_rf_array[i_phys_rf_wr_idx] <= i_wdata;
  end
end
//============================================END==================================================




endmodule