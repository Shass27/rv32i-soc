`timescale 1ns / 1ps
module alu_control(

    input  [1:0] ALUOp,
    input  [2:0] funct3,
    input  [6:0] funct7,

    output reg [3:0] ALUControl
);

// ALUOp Encoding
localparam ALU_ADD    = 2'b00;//Force ADD
localparam ALU_SUB    = 2'b01;// Force SUB
localparam ALU_DECODE = 2'b10;// Should decide the op based on funct3,funct7
localparam ALU_JAL    = 2'b11;//JAL

// ALUControl Encoding ->for the alu module to know what to perform
localparam ADD = 4'b0000;
localparam SUB = 4'b0001;

always @(*) 
begin
    case(ALUOp)

        ALU_ADD:
            ALUControl = ADD; //used for LW,SW

        ALU_SUB:
            ALUControl = SUB;//used for BEQ

    ALU_DECODE: begin
    if (funct3 == 3'b000) begin
        if (funct7 == 7'b0100000)
            ALUControl = SUB;   // SUB
        else
            ALUControl = ADD;   // ADD / ADDI
    end
    else begin
        ALUControl = ADD;       // Safety fallback
    end
end

ALU_JAL:
    ALUControl = ADD;           // Compute PC + immediate // Safety fallback   


        default:
            ALUControl = ADD;// Default to ADD for invalid/unknown ALUOp

    endcase
end
endmodule