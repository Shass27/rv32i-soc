`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/01/2026 04:50:12 PM
// Design Name: 
// Module Name: tb_program_counter
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
module tb_program_counter;
    reg         clk;
    reg         reset;
    reg  [31:0] target;
    reg         stall;
    reg         branch_taken;
    reg         jump;
    wire [31:0] pc;

    program_counter uut (
        .clk          (clk),
        .reset        (reset),
        .target       (target),
        .stall        (stall),
        .branch_taken (branch_taken),
        .jump         (jump),
        .pc           (pc)
    );

    always #5 clk = ~clk;

    initial begin
        clk          = 0;
        reset        = 1;
        target       = 32'h0;
        stall        = 0;
        branch_taken = 0;
        jump         = 0;

        @(posedge clk);
        @(posedge clk);
        if (pc !== 32'h0) $display("FAIL reset: pc=%h", pc);
        reset = 0;

        repeat (5) @(posedge clk);
        $display("pc=%h", pc);

        @(negedge clk);
        jump   = 1;
        target = 32'h0000_1000;
        @(posedge clk);
        if (pc !== target) $display("FAIL jump: pc=%h", pc);

        @(negedge clk);
        jump = 0;

        repeat (3) @(posedge clk);
        $display("pc=%h", pc);

        @(negedge clk);
        stall = 1;
        @(posedge clk);
        if (pc !== 32'h1010) $display("FAIL stall1: pc=%h", pc);
        @(posedge clk);
        if (pc !== 32'h1010) $display("FAIL stall2: pc=%h", pc);

        @(negedge clk);
        stall = 0;

        @(posedge clk);
        if (pc !== 32'h1014) $display("FAIL resume: pc=%h", pc);

        @(negedge clk);
        reset = 1;
        @(posedge clk);
        if (pc !== 32'h0) $display("FAIL reset2: pc=%h", pc);
        reset = 0;

        #20;
        $display("done");
        $finish;
    end
endmodule