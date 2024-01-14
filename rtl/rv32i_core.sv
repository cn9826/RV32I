//=================================================================================================
// File: rv32i_dispatch.sv 
//
// Description: RISCV-32I Core module. Instantiates:
//              Dispatch stage
//              Execute Stage including Reservation Stations and their serviced PUs.
//              Write Back stage that arbitrates among PUs' WB requests.
//              ROB
//              The assumption is Decode stage never passes a valid Arch RF dst as 0
// Date Created: 09/24/2023
//
// Author: Can Ni cni96@outlook.com 
//=================================================================================================
`include "rv32i_pkg.svp"
module rv32i_core
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

  // Output to Decode stage
  output logic                              o_rdy
);


//=================================================================================================
// Local Declarations 
//=================================================================================================

// Dispatch Stage output to RF
logic                              pre_dispatch; 
logic                              ren_src1;
logic                              ren_src2;
logic [ARCH_REG_FILE_IDX_BW-1:0]   src1_arch_rf_idx;
logic [ARCH_REG_FILE_IDX_BW-1:0]   src2_arch_rf_idx;
logic                              dst_arch_rf_vld;
logic [ARCH_REG_FILE_IDX_BW-1:0]   dst_arch_rf_idx;


// RF to Dispatch Stage responses
logic                              src1_phys_rf_tag_vld;
logic [PHYS_REG_FILE_IDX_BW-1:0]   src1_phys_rf_tag_idx;
logic                              src1_rdata_vld;
logic [REG_FILE_BW-1:0]            src1_rdata;
logic                              src2_phys_rf_tag_vld;
logic [PHYS_REG_FILE_IDX_BW-1:0]   src2_phys_rf_tag_idx;
logic                              src2_rdata_vld;
logic [REG_FILE_BW-1:0]            src2_rdata;
logic                              dst_phys_rf_tag_vld;
logic [PHYS_REG_FILE_IDX_BW-1:0]   dst_phys_rf_tag;

// Dispatch to PUs' reservation station
logic                              dispatch;
logic [PU_ID_BW-1:0]               dispatch_pu_id;
logic                              dispatch_src1_value_vld;
logic [REG_FILE_BW-1:0]            dispatch_src1_value;
logic                              dispatch_src1_phys_rf_vld; 
logic [PHYS_REG_FILE_IDX_BW-1:0]   dispatch_src1_phys_rf_tag;    
logic                              dispatch_src2_value_vld; 
logic [REG_FILE_BW-1:0]            dispatch_src2_value;
logic                              dispatch_src2_phys_rf_vld; 
logic [PHYS_REG_FILE_IDX_BW-1:0]   dispatch_src2_phys_rf_tag;
logic                              dispatch_dst_phys_rf_vld;
logic [PHYS_REG_FILE_IDX_BW-1:0]   dispatch_dst_phys_rf_tag;
logic [ARCH_REG_FILE_IDX_BW-1:0]   dispatch_dst_arch_rf_idx;
logic [REG_FILE_BW-1:0]            dispatch_imm;

logic [$clog2(ROB_DEPTH)-1:0]      dispatch_rob_entry_idx;


// WriteBack signals
logic                              write_back;
logic [PHYS_REG_FILE_IDX_BW-1:0]   wb_phys_rf_wr_idx;
logic [$clog2(ROB_DEPTH)-1:0]      wb_rob_entry_idx;
logic [REG_FILE_BW-1:0]            wb_data;
logic [NUM_PUS-1:0]                wb_rdy; // write back arbiter is ready to grant to a specific PU
logic [NUM_PUS-1:0]                               wb_req;
logic [NUM_PUS-1:0][PHYS_REG_FILE_IDX_BW-1:0]     wb_req_dst_phys_rf_tag;
logic [NUM_PUS-1:0][$clog2(ROB_DEPTH)-1:0]        wb_req_rob_entry_idx;
logic [NUM_PUS-1:0][REG_FILE_BW-1:0]              wb_req_data;
logic [NUM_PUS-1:0]                               wb_grant;


// ROB signals
logic                              rob_full;
logic                              rob_empty;
logic                              retire;
logic                              retire_dst_vld;
logic [PHYS_REG_FILE_IDX_BW-1:0]   retire_dst_phys_rf_tag;
logic [ARCH_REG_FILE_IDX_BW-1:0]   retire_dst_arch_rf_idx;

// Reservation Stations signals
logic [NUM_PUS-1:0]                rsrv_sttn_full;
logic [NUM_PUS-1:0]                rsrv_sttn_empty;

logic [NUM_PUS-1:0]                rsrv_sttn_pop_vld;

logic [REG_FILE_BW-1:0]            add_rsrv_sttn_src1_value;
logic [REG_FILE_BW-1:0]            add_rsrv_sttn_src2_value;
logic [PHYS_REG_FILE_IDX_BW-1:0]   add_rsrv_sttn_dst_phys_rf_tag;
logic [$clog2(ROB_DEPTH)-1:0]      add_rsrv_sttn_rob_entry_idx;

logic [REG_FILE_BW-1:0]            mult_rsrv_sttn_src1_value;
logic [REG_FILE_BW-1:0]            mult_rsrv_sttn_src2_value;
logic [PHYS_REG_FILE_IDX_BW-1:0]   mult_rsrv_sttn_dst_phys_rf_tag;
logic [$clog2(ROB_DEPTH)-1:0]      mult_rsrv_sttn_rob_entry_idx;


// PU signals
logic [NUM_PUS-1:0]                pu_rdy;
logic [NUM_PUS-1:0]                pu_vld;
logic [PHYS_REG_FILE_IDX_BW-1:0]   add_dst_phys_rf_tag;
logic [$clog2(ROB_DEPTH)-1:0]      add_rob_entry_idx;
logic [REG_FILE_BW-1:0]            add_result;
logic [PHYS_REG_FILE_IDX_BW-1:0]   mult_dst_phys_rf_tag;
logic [$clog2(ROB_DEPTH)-1:0]      mult_rob_entry_idx;
logic [REG_FILE_BW-1:0]            mult_result;

// RF signals
logic                              rf_phys_rf_tag_avail;
//============================================END==================================================


//=================================================================================================
// Instantiate Dispatch Stage 
//=================================================================================================
rv32i_dispatch u_dispatch (
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

  // RF to dispatch responses
  .i_src1_phys_rf_tag_vld         (src1_phys_rf_tag_vld),
  .i_src1_phys_rf_tag_idx         (src1_phys_rf_tag_idx),
  .i_src1_rdata_vld               (src1_rdata_vld),
  .i_src1_rdata                   (src1_rdata),
  .i_src2_phys_rf_tag_vld         (src2_phys_rf_tag_vld),
  .i_src2_phys_rf_tag_idx         (src2_phys_rf_tag_idx),
  .i_src2_rdata_vld               (src2_rdata_vld),
  .i_src2_rdata                   (src2_rdata),
  .i_dst_phys_rf_tag_vld          (dst_phys_rf_tag_vld),
  .i_dst_phys_rf_tag              (dst_phys_rf_tag),

  // Write Back snoop I/F
  .i_write_back                   (write_back),
  .i_phys_rf_wr_idx               (wb_phys_rf_wr_idx),
  .i_wdata                        (wb_data),

  // Stall related signals coming from RF, PU's reservation station, and ROB
  .i_rf_phys_rf_tag_avail         (rf_phys_rf_tag_avail),
  .i_rsrv_sttn_full               (rsrv_sttn_full),
  .i_rob_full                     (rob_full),

  // Output I/F to RF
  .o_pre_dispatch                 (pre_dispatch),
  .o_ren_src1                     (ren_src1),
  .o_ren_src2                     (ren_src2),
  .o_src1_arch_rf_idx             (src1_arch_rf_idx),
  .o_src2_arch_rf_idx             (src2_arch_rf_idx),
  .o_dst_arch_rf_vld              (dst_arch_rf_vld),
  .o_dst_arch_rf_idx              (dst_arch_rf_idx),

  // Output I/F to PUs' reservation stations
  .o_dispatch                     (dispatch),
  .o_pu_id                        (dispatch_pu_id),
  .o_src1_value_vld               (dispatch_src1_value_vld),
  .o_src1_value                   (dispatch_src1_value),
  .o_src1_phys_rf_vld             (dispatch_src1_phys_rf_vld), 
  .o_src1_phys_rf_tag             (dispatch_src1_phys_rf_tag),    
  .o_src2_value_vld               (dispatch_src2_value_vld), 
  .o_src2_value                   (dispatch_src2_value),
  .o_src2_phys_rf_vld             (dispatch_src2_phys_rf_vld), 
  .o_src2_phys_rf_tag             (dispatch_src2_phys_rf_tag),
  .o_dst_phys_rf_vld              (dispatch_dst_phys_rf_vld),
  .o_dst_phys_rf_tag              (dispatch_dst_phys_rf_tag),
  .o_dispatch_dst_arch_rf_idx     (dispatch_dst_arch_rf_idx),
  .o_imm                          (dispatch_imm),

  // Output to Decode stage
  .o_rdy 
);

//============================================END==================================================


//=================================================================================================
// Instantiate Reservation Stations and their serviced PUs 
//=================================================================================================

//-------------------------------------------------------------------------------------------------
// PU ID = 0 ADD
//-------------------------------------------------------------------------------------------------
rv32i_reservation_station #(
  .FIFO_DEPTH       (2)
) u_add_rsrv_sttn (
  .clk,
  .rstn,

  .i_push                         (dispatch & dispatch_pu_id==PU_ID_BW'(0)),

  .i_src1_value_vld               (dispatch_src1_value_vld),
  .i_src1_value                   (dispatch_src1_value),
  .i_src1_phys_rf_tag             (dispatch_src1_phys_rf_tag),
  .i_src2_value_vld               (dispatch_src2_value_vld),
  .i_src2_value                   (dispatch_src2_value),
  .i_src2_phys_rf_tag             (dispatch_src2_phys_rf_tag),
  .i_dst_phys_rf_tag              (dispatch_dst_phys_rf_tag),

  .i_rob_entry_idx                (dispatch_rob_entry_idx),

  .i_write_back                   (write_back),
  .i_phys_rf_wr_idx               (wb_phys_rf_wr_idx),
  .i_wdata                        (wb_data),

  .i_pu_rdy                       (pu_rdy[0]),

  .o_full                         (rsrv_sttn_full[0]),
  .o_empty                        (rsrv_sttn_empty[0]),

  .o_vld                          (rsrv_sttn_pop_vld[0]),
  .o_src1_value                   (add_rsrv_sttn_src1_value),
  .o_src2_value                   (add_rsrv_sttn_src2_value),
  .o_dst_phys_rf_tag              (add_rsrv_sttn_dst_phys_rf_tag),
  .o_rob_entry_idx                (add_rsrv_sttn_rob_entry_idx)
);

rv32i_adder u_adder_pu (
  .clk,
  .rstn,
  .i_vld                          (rsrv_sttn_pop_vld[0]),
  .i_sub_flag                     (1'b0),
  .i_a                            (add_rsrv_sttn_src1_value),
  .i_b                            (add_rsrv_sttn_src2_value),
  .i_dst_phys_rf_tag              (add_rsrv_sttn_dst_phys_rf_tag),
  .i_rob_entry_idx                (add_rsrv_sttn_rob_entry_idx),
  .i_rdy                          (wb_rdy[0]),

  .o_rdy                          (pu_rdy[0]),
  .o_vld                          (pu_vld[0]),
  .o_dst_phys_rf_tag              (add_dst_phys_rf_tag),
  .o_rob_entry_idx                (add_rob_entry_idx),
  .o_sum                          (add_result)
);

//--------------------------------------------END--------------------------------------------------


//-------------------------------------------------------------------------------------------------
// PU ID = 1 MULT 
//-------------------------------------------------------------------------------------------------
rv32i_reservation_station #(
  .FIFO_DEPTH       (2)
) u_mult_rsrv_sttn (
  .clk,
  .rstn,

  .i_push                         (dispatch & dispatch_pu_id==PU_ID_BW'(1)),

  .i_src1_value_vld               (dispatch_src1_value_vld),
  .i_src1_value                   (dispatch_src1_value),
  .i_src1_phys_rf_tag             (dispatch_src1_phys_rf_tag),
  .i_src2_value_vld               (dispatch_src2_value_vld),
  .i_src2_value                   (dispatch_src2_value),
  .i_src2_phys_rf_tag             (dispatch_src2_phys_rf_tag),
  .i_dst_phys_rf_tag              (dispatch_dst_phys_rf_tag),

  .i_rob_entry_idx                (dispatch_rob_entry_idx),

  .i_write_back                   (write_back),
  .i_phys_rf_wr_idx               (wb_phys_rf_wr_idx),
  .i_wdata                        (wb_data),

  .i_pu_rdy                       (pu_rdy[1]),

  .o_full                         (rsrv_sttn_full[1]),
  .o_empty                        (rsrv_sttn_empty[1]),

  .o_vld                          (rsrv_sttn_pop_vld[1]),
  .o_src1_value                   (mult_rsrv_sttn_src1_value),
  .o_src2_value                   (mult_rsrv_sttn_src2_value),
  .o_dst_phys_rf_tag              (mult_rsrv_sttn_dst_phys_rf_tag),
  .o_rob_entry_idx                (mult_rsrv_sttn_rob_entry_idx)
);

rv32i_multiplier_pipelined u_mltplr_pu (
  .clk,
  .rstn,
  
  .i_vld                          (rsrv_sttn_pop_vld[1]),
  .i_multiplicand                 (mult_rsrv_sttn_src1_value),
  .i_multiplier                   (mult_rsrv_sttn_src2_value),
  .i_dst_phys_rf_tag              (mult_rsrv_sttn_dst_phys_rf_tag),
  .i_rob_entry_idx                (mult_rsrv_sttn_rob_entry_idx),
  .i_rdy                          (wb_rdy[1]),
  
  .o_rdy                          (pu_rdy[1]),
  .o_vld                          (pu_vld[1]),
  .o_dst_phys_rf_tag              (mult_dst_phys_rf_tag),
  .o_rob_entry_idx                (mult_rob_entry_idx),
  .o_product                      (mult_result)
);

//============================================END==================================================


//=================================================================================================
// Write Back Stage 
//=================================================================================================
assign wb_req = pu_vld; 
assign wb_rdy = ~(wb_req & ~wb_grant); 
round_robin_arbiter #(
  .N (NUM_PUS)
) u_wb_arbiter (
  .clk,
  .rstn,
  .i_req    (wb_req),
  .o_grant  (wb_grant) 
);

assign wb_req_dst_phys_rf_tag[0] = add_dst_phys_rf_tag;
assign wb_req_dst_phys_rf_tag[1] = mult_dst_phys_rf_tag;
assign wb_req_rob_entry_idx[0] = add_rob_entry_idx; 
assign wb_req_rob_entry_idx[1] = mult_rob_entry_idx;
assign wb_req_data[0] = add_result;
assign wb_req_data[1] = mult_result;

assign write_back = |wb_grant;
always_comb begin
  wb_phys_rf_wr_idx = '0;
  wb_rob_entry_idx  = '0;
  wb_data       = '0;
  for (int i=0; i<NUM_PUS; i++) begin
    wb_phys_rf_wr_idx = wb_phys_rf_wr_idx | ({PHYS_REG_FILE_IDX_BW{wb_grant[i]}} & wb_req_dst_phys_rf_tag[i]);
    wb_rob_entry_idx  = wb_rob_entry_idx  | ({$clog2(ROB_DEPTH){wb_grant[i]}} & wb_req_rob_entry_idx[i]);
    wb_data           = wb_data           | ({REG_FILE_BW{wb_grant[i]}} & wb_req_data[i]); 
  end
end
//============================================END==================================================


//=================================================================================================
// Instantiate Register File 
//=================================================================================================
rv32i_register_file u_register_file
(
  .clk,
  .rstn,
  .i_wen                    (write_back),
  .i_phys_rf_wr_idx         (wb_phys_rf_wr_idx),
  .i_wdata                  (wb_data),
  
  .i_pre_dispatch           (pre_dispatch),
  .i_ren_src1               (ren_src1),
  .i_ren_src2               (ren_src2),
  .i_src1_arch_rf_idx       (src1_arch_rf_idx),
  .i_src2_arch_rf_idx       (src2_arch_rf_idx),
  .i_dst_arch_rf_vld        (dst_arch_rf_vld),
  .i_dst_arch_rf_idx        (dst_arch_rf_idx),

  .i_retire                 (retire),
  .i_retire_dst_vld         (retire_dst_vld),
  .i_retire_arch_rf_idx     (retire_dst_arch_rf_idx),
  .i_retire_phys_rf_idx     (retire_dst_phys_rf_tag),

  .o_src1_phys_rf_tag_vld   (src1_phys_rf_tag_vld),
  .o_src1_phys_rf_tag_idx   (src1_phys_rf_tag_idx),
  .o_src1_rdata_vld         (src1_rdata_vld),
  .o_src1_rdata             (src1_rdata),
  .o_src2_phys_rf_tag_vld   (src2_phys_rf_tag_vld),
  .o_src2_phys_rf_tag_idx   (src2_phys_rf_tag_idx),
  .o_src2_rdata_vld         (src2_rdata_vld),
  .o_src2_rdata             (src2_rdata),

  .o_dst_phys_rf_tag_vld    (dst_phys_rf_tag_vld),
  .o_dst_phys_rf_tag_idx    (dst_phys_rf_tag),

  .o_phys_rf_tag_avail      (rf_phys_rf_tag_avail)
);
//============================================END==================================================


//=================================================================================================
// Instantiate Re-order buffer 
//=================================================================================================
rv32i_reorder_buffer u_rob (
  .clk,
  .rstn,

  .i_dispatch                     (dispatch),
  .i_dst_vld                      (dispatch_dst_phys_rf_vld),
  .i_dst_phys_rf_tag              (dispatch_dst_phys_rf_tag),
  .i_dst_arch_rf_idx              (dispatch_dst_arch_rf_idx),

  .i_write_back                   (write_back),
  .i_write_back_rob_entry_idx     (wb_rob_entry_idx),

  .o_rob_entry_idx                (dispatch_rob_entry_idx),
  .o_full                         (rob_full),
  .o_empty                        (rob_empty),

  .o_retire                       (retire),
  .o_dst_vld                      (retire_dst_vld),
  .o_retire_dst_phys_rf_tag       (retire_dst_phys_rf_tag),
  .o_retire_dst_arch_rf_idx       (retire_dst_arch_rf_idx)
);

//============================================END==================================================




endmodule