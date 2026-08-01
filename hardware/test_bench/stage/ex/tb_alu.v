`timescale 1ns / 1ps

module alu_tb;

    reg [31:0] A;
    reg [31:0] B;
    reg [3:0] ALUControl;

    wire [31:0] result;
    wire zero;

    // Instantiate ALU
    alu_module uut (
        .A(A),
        .B(B),
        .ALUControl(ALUControl),
        .result(result),
        .zero(zero)
    );

    initial begin

        $display("Time\tA\tB\tALUCtrl\tResult\tZero");
        $monitor("%0t\t%d\t%d\t%b\t%d\t%b",
                 $time, A, B, ALUControl, result, zero);

        // Test 1 : ADD
        A = 10;
        B = 5;
        ALUControl = 4'b0000;
        #10;

        // Test 2 : ADD resulting in zero
        A = 8;
        B = -8;
        ALUControl = 4'b0000;
        #10;

        // Test 3 : SUB
        A = 15;
        B = 5;
        ALUControl = 4'b0001;
        #10;

        // Test 4 : SUB resulting in zero
        A = 20;
        B = 20;
        ALUControl = 4'b0001;
        #10;

        // Test 5 : Invalid ALU Control
        A = 10;
        B = 5;
        ALUControl = 4'b1111;
        #10;

        $finish;

    end

endmodule
