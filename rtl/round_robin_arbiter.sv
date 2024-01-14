//=================================================================================================
// File: round_robin_arbiter.sv 
//
// Description: Parameterized higher_priority_req & masked implementation of Round-Robin Arbiter.
//              higher_priority_req[n] means at current cycle, relative to port n, whether there is a
//              higher-piriority request. Only if ~higher_priority_req[n] & req[n] will port n gets a 
//              grant.
//              Mask is used to filter out the requests on ports that got a grant in the previous cycle. 
//
// Date Created: 10/08/2023
//
// Author: Can Ni cni96@outlook.com 
//=================================================================================================
module round_robin_arbiter #(
  parameter int N = 2
) (
  input  logic                            clk,
  input  logic                            rstn,
  input  logic [N-1:0]                    i_req,
  output logic [N-1:0]                    o_grant
);


//=================================================================================================
// Local Declarations 
//=================================================================================================
logic [N-1:0] mask;
logic [N-1:0] masked_req;
logic [N-1:0] masked_higher_prior_req;
logic [N-1:0] unmasked_higher_prior_req;
logic no_masked_req;
logic [N-1:0] masked_grant;
logic [N-1:0] unmasked_grant; 
//============================================END==================================================


//=================================================================================================
// Masked higher priority request logic 
//=================================================================================================
assign masked_req = mask & i_req;
assign masked_higher_prior_req[0] = 1'b0;
assign masked_higher_prior_req[N-1:1] = masked_higher_prior_req[N-2:0] | masked_req[N-2:0];
assign masked_grant = ~masked_higher_prior_req & masked_req;

assign no_masked_req = ~(|masked_req); 
//============================================END==================================================

//=================================================================================================
// UnMasked higher priority request logic 
//=================================================================================================
assign unmasked_higher_prior_req[0] = 1'b0;
assign unmasked_higher_prior_req[N-1:1] = unmasked_higher_prior_req[N-2:0] | i_req[N-2:0];
assign unmasked_grant = ~unmasked_higher_prior_req & i_req;
//============================================END==================================================

assign o_grant = {N{no_masked_req}} & unmasked_grant | masked_grant; 

//=================================================================================================
// Update mask 
//=================================================================================================
always_ff @(posedge clk) begin
  if (!rstn) mask <= '1;
  else if (|i_req) begin
    if (no_masked_req) begin
      mask <= unmasked_higher_prior_req; 
    end
    else begin
      mask <= masked_higher_prior_req;
    end
  end
end
//============================================END==================================================

endmodule