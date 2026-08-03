`timescale 1ns/1ps

module alu_control_tb;

reg  [31:0] instr;
reg  [1:0]  ALUOp;

wire [4:0] rs1;
wire [4:0] rs2;
wire [4:0] rd;
wire [2:0] funct3;
wire [6:0] funct7;
wire [3:0] ALUControl;

localparam ADD = 4'b0000;
localparam SUB = 4'b0001;

alu_control dut(
    .instr(instr),
    .ALUOp(ALUOp),
    .rs1(rs1),
    .rs2(rs2),
    .rd(rd),
    .funct3(funct3),
    .funct7(funct7),
    .ALUControl(ALUControl)
);

integer errors;
integer prev_errors;

task check;

input [4:0] exp_rs1;
input [4:0] exp_rs2;
input [4:0] exp_rd;
input [2:0] exp_funct3;
input [6:0] exp_funct7;
input [3:0] exp_ALUControl;
input [127:0] test_name;

begin

prev_errors = errors;

if(rs1 !== exp_rs1) begin
    $display("%s FAILED : rs1 Expected=%b Got=%b",
              test_name,exp_rs1,rs1);
    errors = errors + 1;
end

if(rs2 !== exp_rs2) begin
    $display("%s FAILED : rs2 Expected=%b Got=%b",
              test_name,exp_rs2,rs2);
    errors = errors + 1;
end

if(rd !== exp_rd) begin
    $display("%s FAILED : rd Expected=%b Got=%b",
              test_name,exp_rd,rd);
    errors = errors + 1;
end

if(funct3 !== exp_funct3) begin
    $display("%s FAILED : funct3 Expected=%b Got=%b",
              test_name,exp_funct3,funct3);
    errors = errors + 1;
end

if(funct7 !== exp_funct7) begin
    $display("%s FAILED : funct7 Expected=%b Got=%b",
              test_name,exp_funct7,funct7);
    errors = errors + 1;
end

if(ALUControl !== exp_ALUControl) begin
    $display("%s FAILED : ALUControl Expected=%b Got=%b",
              test_name,exp_ALUControl,ALUControl);
    errors = errors + 1;
end

if(errors == prev_errors)
    $display("%s PASSED",test_name);

end
endtask

initial begin

errors = 0;

//--------------------------------------------------
// ADD x5,x1,x2
//--------------------------------------------------
ALUOp = 2'b10;
instr = 32'b0000000_00010_00001_000_00101_0110011;
#10;

check(
5'b00001,
5'b00010,
5'b00101,
3'b000,
7'b0000000,
4'b0000,
"ADD");

//--------------------------------------------------
// SUB x5,x1,x2
//--------------------------------------------------
ALUOp = 2'b10;
instr = 32'b0100000_00010_00001_000_00101_0110011;
#10;

check(
5'b00001,
5'b00010,
5'b00101,
3'b000,
7'b0100000,
4'b0001,
"SUB");

//--------------------------------------------------
// ADDI x5,x1,10
//--------------------------------------------------
ALUOp = 2'b10;
instr = 32'b000000001010_00001_000_00101_0010011;
#10;

check(
5'b00001,
5'b00000,
5'b00101,
3'b000,
7'b0000000,
4'b0000,
"ADDI");

//--------------------------------------------------
// LW x5,8(x1)
//--------------------------------------------------
ALUOp = 2'b00;
instr = 32'b000000001000_00001_010_00101_0000011;
#10;

check(
5'b00001,
5'b00000,
5'b00101,
3'b010,
7'b0000000,
4'b0000,
"LW");

//--------------------------------------------------
// SW x2,8(x1)
//--------------------------------------------------
ALUOp = 2'b00;
instr = 32'b0000000_00010_00001_010_01000_0100011;
#10;

check(
5'b00001,
5'b00010,
5'b00000,
3'b010,
7'b0000000,
4'b0000,
"SW");

//--------------------------------------------------
// BEQ x1,x2,label
//--------------------------------------------------
ALUOp = 2'b01;
instr = 32'b0000000_00010_00001_000_00000_1100011;
#10;

check(
5'b00001,
5'b00010,
5'b00000,
3'b000,
7'b0000000,
4'b0001,
"BEQ");

//--------------------------------------------------
// JAL x1,label
//--------------------------------------------------
ALUOp = 2'b11;
instr = 32'b00000000000100000000_00001_1101111;
#10;

check(
5'b00000,
5'b00000,
5'b00001,
3'b000,
7'b0000000,
4'b0000,
"JAL");

$display("-----------------------------------");

if(errors==0)
    $display("ALL TESTS PASSED");

else
    $display("TOTAL FAILURES = %0d",errors);

$display("-----------------------------------");

$finish;

end

endmodule