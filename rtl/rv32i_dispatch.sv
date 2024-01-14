//=================================================================================================
// File: rv32i_dispatch.sv 
//
// Description: RISCV-32I Dispatcher Pipeline Stage. This stage internally is a 2-cycle pipeline.
//              Cycle 0 : rs1 & rs2 & dst request to RF, if any
//              Cycle 1 : Cycle 0 RF response return 
//              Cycle 2 : flop cycle 1's RF response and assert final o_dispatch
//              The Dispatch requests to PUs' reservation stations occur on Cycle 3. 
//              Dispatch can be stalled by the following conditions (encapsulated in i_rdy):
//                RF runs out of DST tags on Cycle 1
//                targeted PU's reservation station is full
//                ROB is full
//              At Dispatch Cycle 2, also consult with ROB to push ROB entry index to reservation
//              stations.  
// Date Created: 09/04/2023
//
// Author: Can Ni cni96@outlook.com 
//=================================================================================================
`include "rv32i_pkg.svp" 
module rv32i_dispatch
import rv32i_pkg::*;
(
  input  logic                              clk,
  input  logic                              rstn,

  // Upstream I/F from Decode Stage
  input  logic                              i_decode_vld,
  input  logic [PU_ID_BW-1:0]               i_pu_id,                              
  input  logic                              i_rs1_vld,
  input  logic [ARCH_REG_FILE_IDX_BW-1:0]   i_src1_arch_rf_idx,
  // There is an immediate when ~i_rs2_vld (I-type) | ~i_rd_vld (S-type) 
  input  logic                              i_rs2_vld, 
  input  logic [ARCH_REG_FILE_IDX_BW-1:0]   i_src2_arch_rf_idx,
  input  logic                              i_rd_vld,
  input  logic [ARCH_REG_FILE_IDX_BW-1:0]   i_dst_arch_rf_idx,
  input  logic [REG_FILE_BW-1:0]            i_imm,

  // Response I/F from RF
  input  logic                              i_src1_phys_rf_tag_vld,
  input  logic [PHYS_REG_FILE_IDX_BW-1:0]   i_src1_phys_rf_tag_idx, 
  input  logic                              i_src1_rdata_vld,
  input  logic [REG_FILE_BW-1:0]            i_src1_rdata,
  input  logic                              i_src2_phys_rf_tag_vld,
  input  logic [PHYS_REG_FILE_IDX_BW-1:0]   i_src2_phys_rf_tag_idx, 
  input  logic                              i_src2_rdata_vld,
  input  logic [REG_FILE_BW-1:0]            i_src2_rdata,
  input  logic                              i_dst_phys_rf_tag_vld,
  input  logic [PHYS_REG_FILE_IDX_BW-1:0]   i_dst_phys_rf_tag, 

  // Write Back snoop I/F
  input  logic                              i_write_back,
  input  logic [PHYS_REG_FILE_IDX_BW-1:0]   i_phys_rf_wr_idx,
  input  logic [REG_FILE_BW-1:0]            i_wdata,

  // Stall related signals coming from RF, PU's reservation station, and ROB 
  input  logic                              i_rf_phys_rf_tag_avail,
  input  logic [NUM_PUS-1:0]                i_rsrv_sttn_full,
  input  logic                              i_rob_full, 

  // Output I/F to RF
  output logic                              o_pre_dispatch, // Asserted on Cycle 0
  output logic                              o_ren_src1,     // indicates SRC RF request is valid
  output logic                              o_ren_src2,     // indicates SRC RF request is valid
  output logic [ARCH_REG_FILE_IDX_BW-1:0]   o_src1_arch_rf_idx,
  output logic [ARCH_REG_FILE_IDX_BW-1:0]   o_src2_arch_rf_idx,
  output logic                              o_dst_arch_rf_vld,
  output logic [ARCH_REG_FILE_IDX_BW-1:0]   o_dst_arch_rf_idx,

  // Output I/F to PUs' reservation stations
  output logic                              o_dispatch,
  output logic [PU_ID_BW-1:0]               o_pu_id,
  output logic                              o_src1_value_vld,
  output logic [REG_FILE_BW-1:0]            o_src1_value,
  output logic                              o_src1_phys_rf_vld, 
  output logic [PHYS_REG_FILE_IDX_BW-1:0]   o_src1_phys_rf_tag,    
  output logic                              o_src2_value_vld, 
  output logic [REG_FILE_BW-1:0]            o_src2_value,
  output logic                              o_src2_phys_rf_vld, 
  output logic [PHYS_REG_FILE_IDX_BW-1:0]   o_src2_phys_rf_tag,
  output logic                              o_dst_phys_rf_vld,
  output logic [PHYS_REG_FILE_IDX_BW-1:0]   o_dst_phys_rf_tag,
  output logic [ARCH_REG_FILE_IDX_BW-1:0]   o_dispatch_dst_arch_rf_idx,
  output logic [REG_FILE_BW-1:0]            o_imm,

  // Output to Decode stage
  output logic                              o_rdy
);


//=================================================================================================
// Local Declarations 
//=================================================================================================
logic [2:0] stg_vld;
logic [2:0] stg_rdy;
logic [2:0] stg_pu_id;

logic [REG_FILE_BW-1:0] imm_S0;

logic                             dispatch_S1;
logic                             src1_vld_S1, src2_vld_S1;
logic                             dst_vld_S1;
logic                             src1_value_vld_on_wb_S1;
logic                             src2_value_vld_on_wb_S1;
logic [ARCH_REG_FILE_IDX_BW-1:0]  dst_arch_rf_idx_S1;
logic [REG_FILE_BW-1:0]           imm_S1;

logic                             src1_value_vld_S2;
logic                             src2_value_vld_S2;
logic [REG_FILE_BW-1:0]           src1_value_S2;
logic [REG_FILE_BW-1:0]           src2_value_S2;
//============================================END==================================================


//=================================================================================================
// Stage valid and ready 
//=================================================================================================
assign stg_rdy[0] = ~(i_decode_vld & ~stg_rdy[1]) & i_rf_phys_rf_tag_avail;
assign stg_rdy[1] = ~(stg_vld[0] & ~stg_rdy[2]);
assign stg_rdy[2] = ~(stg_vld[2] & (i_rsrv_sttn_full[stg_pu_id[2]] || i_rob_full));  

assign o_rdy = stg_rdy[0]; 

always_ff @(posedge clk) begin
  if(!rstn) begin
    stg_vld <= '0;
  end
  else begin
    if (i_decode_vld && stg_rdy[0]) begin
      stg_vld[0] <= 1'b1;
    end
    else if (!i_decode_vld && stg_vld[0] && stg_rdy[1]) begin
      stg_vld[0] <= 1'b0;
    end

    if (stg_vld[0] && stg_rdy[1]) begin
      stg_vld[1] <= 1'b1;
    end
    else if (!stg_vld[0] && stg_vld[1] && stg_rdy[2]) begin
      stg_vld[1] <= 1'b0;
    end

    if (stg_vld[1] && stg_rdy[2]) begin
      stg_vld[2] <= 1'b1;
    end
    else if ( !stg_vld[1] && stg_vld[2] && !(i_rsrv_sttn_full[stg_pu_id[2]] || i_rob_full) ) begin
      stg_vld[2] <= 1'b0;
    end 
  end
end

always_ff @(posedge clk) begin
  if (!rstn) begin
    stg_pu_id <= '0;
  end
  else begin
    if (i_decode_vld && stg_rdy[0]) begin
      stg_pu_id[0] <= i_pu_id; 
    end
    for (int i=1; i<3; i++) begin
      if (stg_vld[i-1] && stg_rdy[i]) begin
        stg_pu_id[i] <= stg_pu_id[i-1]; 
      end
    end 
  end
end

//============================================END==================================================


//=================================================================================================
// Stage 0: RF request  
//=================================================================================================
assign o_pre_dispatch = stg_vld[0];
always_ff @(posedge clk) begin
  if (!rstn) begin
    o_ren_src1         <= 1'b0;
    o_ren_src2         <= 1'b0;
    o_src1_arch_rf_idx <= '0;
    o_src2_arch_rf_idx <= '0;
    o_dst_arch_rf_vld  <= 1'b0;
    o_dst_arch_rf_idx  <= '0;  
  end
  else begin
    if (i_decode_vld && stg_rdy[0]) begin
      o_ren_src1          <= i_rs1_vld;  
      o_ren_src2          <= i_rs2_vld;
      if (!i_rs2_vld || !i_rd_vld) begin
        imm_S0 <= i_imm;
      end
      o_src1_arch_rf_idx  <= i_src1_arch_rf_idx;
      o_src2_arch_rf_idx  <= i_src2_arch_rf_idx;
      o_dst_arch_rf_vld   <= i_rd_vld;
      o_dst_arch_rf_idx   <= i_dst_arch_rf_idx; 
    end
  end
end

//============================================END==================================================


//=================================================================================================
// Stage 1: flop 
//=================================================================================================
always_ff @(posedge clk) begin
  if (stg_vld[0] && stg_rdy[1]) begin
    dispatch_S1        <= o_pre_dispatch;
    src1_vld_S1        <= o_ren_src1;
    src2_vld_S1        <= o_ren_src2;
    dst_vld_S1         <= o_dst_arch_rf_vld;
    dst_arch_rf_idx_S1 <= o_dst_arch_rf_idx; 
    if (!o_ren_src2 || !o_dst_arch_rf_vld) begin
      imm_S1 <= imm_S0;
    end 
  end
  else if (!stg_vld[0] && stg_vld[1] && stg_rdy[2]) begin
    dispatch_S1 <= 1'b0;
  end
end

assign src1_value_vld_on_wb_S1 = 
  ~i_src1_rdata_vld & src1_vld_S1 & i_write_back & i_phys_rf_wr_idx == i_src1_phys_rf_tag_idx; 

assign src2_value_vld_on_wb_S1 = 
  ~i_src2_rdata_vld & src2_vld_S1 & i_write_back & i_phys_rf_wr_idx == i_src2_phys_rf_tag_idx; 
//============================================END==================================================


//=================================================================================================
// Stage 2: flop RF response return and snoop    
//=================================================================================================
assign o_dispatch       = stg_vld[2];
assign o_pu_id          = stg_pu_id[2];

// on dispatch cycle, if SRC1/SRC2 sees a matching write back and the target reservation station
// is ready to accept on this cycle, then validate 
assign o_src1_value_vld = 
  src1_value_vld_S2 | 
  ( ~src1_value_vld_S2 & o_src1_phys_rf_vld & i_write_back & i_phys_rf_wr_idx == o_src1_phys_rf_tag & 
    ~(i_rsrv_sttn_full[stg_pu_id[2]] || i_rob_full) );
assign o_src1_value = 
  src1_value_vld_S2 ? 
  src1_value_S2 :
  ( ~src1_value_vld_S2 & o_src1_phys_rf_vld & i_write_back & i_phys_rf_wr_idx == o_src1_phys_rf_tag & 
    ~(i_rsrv_sttn_full[stg_pu_id[2]] || i_rob_full) ) ? i_wdata : src1_value_S2; 

assign o_src2_value_vld = 
  src2_value_vld_S2 | 
  ( ~src2_value_vld_S2 & o_src2_phys_rf_vld & i_write_back & i_phys_rf_wr_idx == o_src2_phys_rf_tag & 
    ~(i_rsrv_sttn_full[stg_pu_id[2]] || i_rob_full) );
assign o_src2_value = 
  src2_value_vld_S2 ? 
  src2_value_S2 :
  ( ~src2_value_vld_S2 & o_src2_phys_rf_vld & i_write_back & i_phys_rf_wr_idx == o_src2_phys_rf_tag & 
    ~(i_rsrv_sttn_full[stg_pu_id[2]] || i_rob_full) ) ? i_wdata : src2_value_S2; 


always_ff @(posedge clk) begin
  if (stg_vld[1] && stg_rdy[2]) begin
    o_dst_phys_rf_vld <= i_dst_phys_rf_tag_vld;
    o_dispatch_dst_arch_rf_idx <= dst_arch_rf_idx_S1;
    o_src1_phys_rf_vld  <= i_src1_phys_rf_tag_vld & ~src1_value_vld_on_wb_S1;
    o_src2_phys_rf_vld  <= i_src2_phys_rf_tag_vld & ~src2_value_vld_on_wb_S1;
    o_src1_phys_rf_tag <= i_src1_phys_rf_tag_idx;
    o_src2_phys_rf_tag <= i_src2_phys_rf_tag_idx;
    
    src1_value_vld_S2  <= i_src1_rdata_vld | src1_value_vld_on_wb_S1;
    if (i_src1_rdata_vld) begin
      src1_value_S2 <= i_src1_rdata; 
    end
    else if (src1_value_vld_on_wb_S1) begin
      src1_value_S2 <= i_wdata; 
    end
   
    src2_value_vld_S2 <= i_src2_rdata_vld | src2_value_vld_on_wb_S1 | (~src2_vld_S1 & src1_vld_S1);
    if (i_src2_rdata_vld) begin
      src2_value_S2 <= i_src2_rdata;
    end
    else if (~src2_vld_S1 & src1_vld_S1) begin
      src2_value_S2 <= imm_S1; 
    end
    else if (src2_value_vld_on_wb_S1) begin
      src2_value_S2 <= i_wdata;
    end

    if (i_dst_phys_rf_tag_vld) begin
      o_dst_phys_rf_tag <= i_dst_phys_rf_tag; 
    end

    if (!src2_vld_S1 || !dst_vld_S1) begin
      o_imm <= imm_S1; 
    end
  end

  // For snoopoing WB bus but target reservation station not ready to accept 
  else if ( stg_vld[2] && (i_rsrv_sttn_full[stg_pu_id[2]] || i_rob_full) ) begin
    if (!src1_value_vld_S2 && o_src1_phys_rf_vld && i_write_back && i_phys_rf_wr_idx == o_src1_phys_rf_tag) begin
      src1_value_vld_S2 <= 1'b1;
      src1_value_S2 <= i_wdata; 
    end
    
    if (!src2_value_vld_S2 && o_src2_phys_rf_vld && i_write_back && i_phys_rf_wr_idx == o_src2_phys_rf_tag) begin
      src2_value_vld_S2 <= 1'b1;
      src2_value_S2 <= i_wdata;
    end
  end
end
//============================================END==================================================



endmodule