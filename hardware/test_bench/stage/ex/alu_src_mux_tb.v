`timescale 1ns/1ps

module alu_src_mux_tb;

reg ALUSrc;
reg [31:0] rs2_data;
reg [31:0] imm;

wire [31:0] alu_B;

alu_src_mux uut(

.ALUSrc(ALUSrc),
.rs2_data(rs2_data),
.imm(imm),
.alu_B(alu_B)

);

initial begin

rs2_data=32'd20;
imm=32'd100;

ALUSrc=0;
#5;

if(alu_B==20)
$display("PASS rs2");

else
$display("FAIL");

ALUSrc=1;
#5;

if(alu_B==100)
$display("PASS imm");

else
$display("FAIL");

$finish;

end

endmodule
