`timescale 1ns/1ps

module alu_tb;

reg [31:0] A;
reg [31:0] B;
reg [3:0] ALUControl;

wire [31:0] result;
wire ALU_zero;

localparam ADD = 4'b0000;
localparam SUB = 4'b0001;

alu_module uut(
    .A(A),
    .B(B),
    .ALUControl(ALUControl),
    .result(result),
    .ALU_zero(ALU_zero)
);

task check;
input [31:0] exp_result;
input exp_zero;
begin
    #5;
    if(result==exp_result && ALU_zero==exp_zero)
        $display("PASS");
    else
        $display("FAIL Expected=%d Zero=%b Got=%d Zero=%b",
                exp_result,exp_zero,result,ALU_zero);
end
endtask

initial begin

A=10; B=20; ALUControl=ADD;
check(30,0);

A=20; B=20; ALUControl=ADD;
check(40,0);

A=10; B=10; ALUControl=SUB;
check(0,1);

A=100; B=40; ALUControl=SUB;
check(60,0);

A=20; B=50; ALUControl=SUB;
check(-30,0);

ALUControl=4'b1111;
check(0,1);

$finish;

end

endmodule