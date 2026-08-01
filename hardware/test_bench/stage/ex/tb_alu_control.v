`timescale 1ns / 1ps


module alu_control_tb;

    reg [1:0] ALUOp;
    reg [2:0] funct3;
    reg [6:0] funct7;

    wire [3:0] ALUControl;

    // Instantiate ALU Control
    alu_control uut (
        .ALUOp(ALUOp),
        .funct3(funct3),
        .funct7(funct7),
        .ALUControl(ALUControl)
    );

    initial begin

        $display("Time\tALUOp\tfunct3\tfunct7\t\tALUControl");
        $monitor("%0t\t%b\t%b\t%b\t%b",
                 $time, ALUOp, funct3, funct7, ALUControl);

        // Test 1 : LW
        ALUOp = 2'b00;
        funct3 = 3'b000;
        funct7 = 7'b0000000;
        #10;

        // Test 2 : SW
        ALUOp = 2'b00;
        #10;

        // Test 3 : BEQ
        ALUOp = 2'b01;
        #10;

        // Test 4 : ADD
        ALUOp = 2'b10;
        funct3 = 3'b000;
        funct7 = 7'b0000000;
        #10;

        // Test 5 : SUB
        ALUOp = 2'b10;
        funct3 = 3'b000;
        funct7 = 7'b0100000;
        #10;

        // Test 6 : ADDI
        ALUOp = 2'b10;
        funct3 = 3'b000;
        funct7 = 7'b0000001;
        #10;

        // Test 7 : JAL
        ALUOp = 2'b11;
        #10;

        // Test 8 : Invalid funct3
        ALUOp = 2'b10;
        funct3 = 3'b111;
        funct7 = 7'b0000000;
        #10;

        $finish;

    end

endmodule
