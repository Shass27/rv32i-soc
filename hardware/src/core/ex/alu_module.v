
module alu_module(input [31:0] A,input [31:0] B,input [3:0] ALUControl,input [31:0] pc,output reg [31:0] ALU_result);


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
 localparam AUIPC_OP = 4'b1010;
always @(*)
begin
case(ALUControl)
       ADD:
       begin
      
        ALU_result=A+B;
        end
    
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
        AUIPC_OP:
            ALU_result = pc + B;
 default:
    ALU_result=32'b0;
endcase
    
end
endmodule
