//BinaryEncoder.sv

//Nov 12, 2015

//This module takes a 2^n bit one-hot input
// to the log-base-2 of the one-hot value.
// for example 0100 -> 2, aka 10

// In the Cache module, it is used to translate 
// which of the four sets is 'hot' to the index of 
// that set, so if for example the hit occurs in
// the third set, the one hot encoded value will
// be 1000, which results in an index of 3, and tells
// the controller that writes will go into set 3, aka 2'b11

module BinaryEncoder #(parameter int unsigned n)(
    input [2**n - 1:0] in,
    output [n - 1:0] out        
);

//the below would be a better parametrized RTL implementation,
//but it doesnt work because verilog doesnt support
//conditionally incrementing genvars

//for (genvar j = 0; j < n; j++) begin
//  wire [(2**(n-1))-1:0] wires;
//  or U0(out[j], wires);
  
  
//    for (genvar k = 0; k < 2**(n-1); k += 0) begin
//      for (genvar i = 0; i < 2**n; i++) begin
//        if (i[j]) begin          
//          assign wires[k] = in[i];
//          k += 1;
//        end
//      end
//    end  
  
//end

for (genvar i = 0; i < 2**n; i++) begin
    assign out = in[i] ? i : 'z;
end

endmodule
