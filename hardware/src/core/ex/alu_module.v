module alu_module(input [31:0] A,input [31:0] B,input [3:0] ALUControl
,output reg [31:0] ALU_result,
output reg ALU_zero );


localparam ADD = 4'b0000;
localparam SUB = 4'b0001;
always @(*)
begin
case(ALUControl)
    ADD:
   ALU_result=A+B;
    
    SUB:
    ALU_result=A-B;
    default:
    ALU_result=32'b0;
endcase    
ALU_zero=(ALU_result==32'b0);//Zero Flag->mostly for BEQ INS
end
endmodule
