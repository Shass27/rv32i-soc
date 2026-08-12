module alu_module(input [31:0] A,input [31:0] B,input [3:0] ALUControl
,output reg [31:0] ALU_result,
output reg ALU_zero );


localparam ADD = 4'b0000;
localparam SUB = 4'b0001;
localparam AND  = 4'b0010;
localparam OR   = 4'b0011;
localparam XOR  = 4'b0100;
localparam SLL  = 4'b0101;
localparam SRL  = 4'b0110;
localparam SRA  = 4'b0111;
localparam SLT  = 4'b1000;
localparam SLTU = 4'b1001;
always @(*)
begin
case(ALUControl)
       ADD:
        ALU_result=A+B;
    
       SUB:
          ALU_result=A-B;
    
        AND:
            ALU_result = A & B;

        OR:
            ALU_result = A | B;

        XOR:
            ALU_result = A ^ B;

        SLL:
            ALU_result = A << B[4:0];

        SRL:
            ALU_result = A >> B[4:0];

        SRA:
            ALU_result = $signed(A) >>> B[4:0];

        SLT:
            ALU_result = ($signed(A) < $signed(B)) ? 32'd1 : 32'd0;

        SLTU:
            ALU_result = (A < B) ? 32'd1 : 32'd0;
 default:
    ALU_result=32'b0;
endcase
if(ALUControl==SUB)    
    ALU_zero=(ALU_result==32'b0);//Zero Flag->mostly for BEQ INS
else
   ALU_zero=1'b0;
    
end
endmodule
