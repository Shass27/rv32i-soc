`timescale 1ns/1ps

module alu_module_tb;

reg [31:0] A;
reg [31:0] B;
reg [3:0] ALUControl;

wire [31:0] ALU_result;
wire ALU_zero;

alu_module dut(
    .A(A),
    .B(B),
    .ALUControl(ALUControl),
    .ALU_result(ALU_result),
    .ALU_zero(ALU_zero)
);

initial begin

    $display("Time\tA\tB\tCtrl\tResult\tZero");
    $monitor("%0t\t%d\t%d\t%b\t%d\t%b",
             $time,A,B,ALUControl,ALU_result,ALU_zero);

    //------------------------------------------------
    // ADD
    //------------------------------------------------
    A = 10;
    B = 5;
    ALUControl = 4'b0000;
    #10;

    //------------------------------------------------
    // SUB (non-zero)
    //------------------------------------------------
    A = 20;
    B = 5;
    ALUControl = 4'b0001;
    #10;

    //------------------------------------------------
    // SUB (zero)
    //------------------------------------------------
    A = 15;
    B = 15;
    ALUControl = 4'b0001;
    #10;

    //------------------------------------------------
    // Default
    //------------------------------------------------
    A = 8;
    B = 3;
    ALUControl = 4'b1111;
    #10;

    $finish;

end

endmodule