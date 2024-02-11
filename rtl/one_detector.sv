//=================================================================================================
// File: one_detector.sv 
//
// Description: Trailing one detector, returns the bit index. If no 1's is detected, o_all_zero
//              will be asserted. 
//
// Date Created: 01/14/2024
//
// Author: Can Ni cni96@outlook.com 
//=================================================================================================

module one_detector
# (
parameter int VEC_LEN = 8
) (
  input  logic  [VEC_LEN-1:0]          i_in_vec,
  output logic  [$clog2(VEC_LEN)-1:0]  o_pos,
  output logic  [VEC_LEN-1:0]          o_pos_mask,
  output logic                         o_all_zero
);

localparam int EXPONENT          = $clog2(VEC_LEN); // also represents levels of 2-entry search tree 
localparam int PADDED_VEC_LEN    = 2**EXPONENT; 

logic [PADDED_VEC_LEN-1:0] padded_in_vec;
logic [EXPONENT-1:0]       idx;
logic [EXPONENT-1:0][PADDED_VEC_LEN-1:0] updated_mask;

assign padded_in_vec = {{(PADDED_VEC_LEN-VEC_LEN){1'b0}}, i_in_vec};

// flag to indicate whether a 2-entry block in this level contains a 1'b1
logic [EXPONENT-1:0][PADDED_VEC_LEN/2-1:0] exists;

// selection pointer to the trailing 1's position within a 2-entry block
logic [EXPONENT-1:0][PADDED_VEC_LEN/2-1:0] sel;

// bit mask to & with lower lvl bit mask to produce final o_pos_mask 
logic [EXPONENT-1:0][PADDED_VEC_LEN/2-1:0][1:0]  mask;


//always_comb begin
  //exists = '0;
  //sel    = '0;
  //for (int lvl_idx = 0; lvl_idx < EXPONENT; lvl_idx++) begin

    //for (int blk_idx = 0; blk_idx < PADDED_VEC_LEN/(2**(lvl_idx+1)); blk_idx++) begin
      //if (lvl_idx == 0) begin
        //exists[lvl_idx][blk_idx] = padded_in_vec[blk_idx*2+1] | padded_in_vec[blk_idx*2];
        //sel   [lvl_idx][blk_idx] = padded_in_vec[blk_idx*2] ? 1'b0 : 1'b1; 
      //end
      //else begin
        //exists[lvl_idx][blk_idx] = exists[lvl_idx-1][blk_idx*2+1] | exists[lvl_idx-1][blk_idx*2+1];
        //case ({exists[lvl_idx-1][blk_idx*2+1], exists[lvl_idx-1][blk_idx*2]})
          //2'b10:   sel[lvl_idx][blk_idx] = 1'b1;
          //2'b01:   sel[lvl_idx][blk_idx] = 1'b0;
          //2'b11:   sel[lvl_idx][blk_idx] = 1'b0;
          //default: sel[lvl_idx][blk_idx] = 1'b1; 
        //endcase 
      //end
    //end // for (blk_idx) 

  //end
//end

generate
  
  for (genvar blk_idx = 0; blk_idx < PADDED_VEC_LEN/2; blk_idx++) begin
    assign exists[0][blk_idx] = padded_in_vec[blk_idx*2+1] | padded_in_vec[blk_idx*2];
    assign sel   [0][blk_idx] = padded_in_vec[blk_idx*2] ? 1'b0 : 1'b1;
    assign mask  [0][blk_idx] = 
      exists[0][blk_idx] ? 
      (sel[0][blk_idx] ? 2'b10 : 2'b01) :
      2'b00                             ;  
  end // for (blk_idx) 
  
  for (genvar lvl_idx = 1; lvl_idx < EXPONENT; lvl_idx++) begin

    for (genvar blk_idx = 0; blk_idx < PADDED_VEC_LEN/(2**(lvl_idx+1)); blk_idx++) begin
      assign exists[lvl_idx][blk_idx] = exists[lvl_idx-1][blk_idx*2+1] | exists[lvl_idx-1][blk_idx*2];
      assign sel[lvl_idx][blk_idx] = exists[lvl_idx-1][blk_idx*2] ? 1'b0 : 1'b1;
      assign mask[lvl_idx][blk_idx] =  
        exists[lvl_idx][blk_idx] ? 
        (sel[lvl_idx][blk_idx] ? 2'b10 : 2'b01) :
        2'b00                                   ;  
    end // for (blk_idx) 

  end

endgenerate



//always_comb begin
//  idx[EXPONENT-1] = sel[EXPONENT-1][0]; 
//  
//  if (EXPONENT > 1) begin
//    for (int bit_idx = EXPONENT-2; bit_idx >=0; bit_idx--) begin 
//      idx[bit_idx] = sel[bit_idx][idx[EXPONENT-1:bit_idx+1]]; 
//    end
//  end 
//  
//end
assign idx[EXPONENT-1] = sel[EXPONENT-1][0];

generate
for (genvar bit_idx=EXPONENT-2; bit_idx >=0; bit_idx--) begin
  assign idx[bit_idx] = sel[bit_idx][idx[EXPONENT-1:bit_idx+1]];
end
endgenerate

assign updated_mask[EXPONENT-1][1:0] = mask[EXPONENT-1][0]; 
generate
for (genvar lvl_idx=EXPONENT-2; lvl_idx>=0; lvl_idx--) begin
  for (genvar blk_idx = 0; blk_idx < PADDED_VEC_LEN/(2**(lvl_idx+1)); blk_idx++) begin
    assign updated_mask[lvl_idx][blk_idx*2+1:blk_idx*2] = 
            {2{updated_mask[lvl_idx+1][blk_idx]}} & mask[lvl_idx][blk_idx];
     
  end
end
endgenerate

assign o_pos = idx[$clog2(VEC_LEN)-1:0];

assign o_pos_mask = updated_mask[0][VEC_LEN-1:0];

assign o_all_zero = ~exists[EXPONENT-1][0];

endmodule