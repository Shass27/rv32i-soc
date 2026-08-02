`timescale 1ns / 1ps
module alu_module(input [31:0] A,input [31:0] B,input [3:0] ALUControl
,output reg [31:0] result,
<<<<<<< HEAD
output reg ALU_zero );
=======
output reg zero );
>>>>>>> 67c45e14c1987f2fcb1dfa84bfe05d54cf8170b5


localparam ADD = 4'b0000;
localparam SUB = 4'b0001;
always @(*)
begin
case(ALUControl)
    ADD:
    result=A+B;
    
    SUB:
    result=A-B;
    default:
    result=32'b0;
endcase    
<<<<<<< HEAD
ALU_zero=(result==32'b0);//Zero Flag->mostly for BEQ INS
=======
zero=(result==32'b0);//Zero Flag->mostly for BEQ INS
>>>>>>> 67c45e14c1987f2fcb1dfa84bfe05d54cf8170b5
end
endmodule
