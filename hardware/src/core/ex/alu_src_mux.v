`timescale 1ns / 1ps
module alu_src_mux(
    input ALUSrc,
    input [31:0] rs2_data,
    input [31:0] imm,
    output [31:0] alu_B
);

assign alu_B = ALUSrc ? imm : rs2_data;

endmodule
