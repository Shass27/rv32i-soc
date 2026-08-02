`timescale 1ns/1ps

module alu_control_tb;

reg [1:0] ALUOp;
reg [2:0] funct3;
reg [6:0] funct7;

wire [3:0] ALUControl;

localparam ADD = 4'b0000;
localparam SUB = 4'b0001;

alu_control uut (
    .ALUOp(ALUOp),
    .funct3(funct3),
    .funct7(funct7),
    .ALUControl(ALUControl)
);

task check;
    input [127:0] test_name;
    input [3:0] expected;
begin
    #5;

    $display("-------------------------------------------------------------");
    $display("Test        : %s", test_name);
    $display("ALUOp       : %02b", ALUOp);
    $display("funct3      : %03b", funct3);
    $display("funct7      : %07b", funct7);
    $display("ALUControl  : %04b", ALUControl);

    if(ALUControl == expected)
        $display("Result      : PASS\n");
    else begin
        $display("Expected    : %04b", expected);
        $display("Result      : FAIL\n");
    end
end
endtask

initial begin

// LW / SW
ALUOp  = 2'b00;
funct3 = 3'b000;
funct7 = 7'b0000000;
check("LW / SW", ADD);

// BEQ
ALUOp  = 2'b01;
check("BEQ", SUB);

// ADD
ALUOp  = 2'b10;
funct3 = 3'b000;
funct7 = 7'b0000000;
check("ADD", ADD);

// SUB
ALUOp  = 2'b10;
funct3 = 3'b000;
funct7 = 7'b0100000;
check("SUB", SUB);

// ADDI
ALUOp  = 2'b10;
funct3 = 3'b000;
funct7 = 7'b0000000;
check("ADDI", ADD);

// JAL
ALUOp  = 2'b11;
funct3 = 3'b000;
funct7 = 7'b0000000;
check("JAL", ADD);

// Invalid funct3
ALUOp  = 2'b10;
funct3 = 3'b111;
funct7 = 7'b0000000;
check("Invalid funct3", ADD);

$finish;

end

endmodule