`timescale 1ns/1ps

module reg_file_tb;

reg clk;
reg reset;

reg RegWrite;

reg [4:0] ReadReg1;
reg [4:0] ReadReg2;

reg [4:0] WriteReg;
reg [31:0] WriteData;

wire [31:0] ReadData1;
wire [31:0] ReadData2;

reg_file uut(

.clk(clk),
.reset(reset),

.RegWrite(RegWrite),

.ReadReg1(ReadReg1),
.ReadReg2(ReadReg2),

.WriteReg(WriteReg),
.WriteData(WriteData),

.ReadData1(ReadData1),
.ReadData2(ReadData2)

);

always #5 clk=~clk;

task check1;
input [31:0] expected;
begin
#1;
if(ReadData1==expected)
$display("PASS");
else
$display("FAIL Expected=%d Got=%d",expected,ReadData1);
end
endtask

initial begin

clk=0;


// RESET
reset=1;
RegWrite=0;
#10;
reset=0;


// Write x5

RegWrite=1;
WriteReg=5;
WriteData=123;
#10;

ReadReg1=5;
check1(123);


// Write x10


WriteReg=10;
WriteData=500;
#10;

ReadReg1=10;
check1(500);

// Overwrite

WriteReg=5;
WriteData=777;
#10;

ReadReg1=5;
check1(777);


// Disable Write


RegWrite=0;
WriteReg=5;
WriteData=9999;
#10;

ReadReg1=5;
check1(777);


// x0
RegWrite=1;
WriteReg=0;
WriteData=5555;
#10;

ReadReg1=0;
check1(0);


// Dual Read


ReadReg1=5;
ReadReg2=10;
#5;

if(ReadData1==777 && ReadData2==500)
$display("PASS Dual Read");
else
$display("FAIL Dual Read");

$finish;

end

endmodule