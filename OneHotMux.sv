//OneHotMux.sv
//Nov 12, 2015
//This is derived from:

//http://stackoverflow.com/questions/19875899/how-to-define-a-parameterized-multiplexer-using-systemverilog

//This module is used to route the 'hot' set to the output of the Cache module

module OneHotMux #( parameter int unsigned databusWidth = 8,
                    parameter int unsigned numInputs = 4 )
(
      input logic [0:numInputs-1] sel,
      input [databusWidth-1:0] in[numInputs],
      output wire [databusWidth-1:0] out
);
wire [databusWidth-1:0] preOut;
for(genvar i=0;i<numInputs;i++) begin
   assign preOut = sel[i] ? in[i] : 'z;
end
//output defaults to in[0] if sel is no-hot
assign out = ~(| sel) ? in[0] : preOut;
endmodule