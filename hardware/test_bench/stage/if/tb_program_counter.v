`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_program_counter
// Description: Testbench for program_counter.v
//              Matches current interface: jump1, jump2 (no single jump port)
//
// NOTE: All register checks use #1 after @(posedge clk) to let non-blocking
//       assignments (pc <= ...) settle before sampling the output.
//////////////////////////////////////////////////////////////////////////////////
module tb_program_counter;
    reg         clk;
    reg         reset;
    reg  [31:0] target;
    reg         stall;
    reg         branch_taken;
    reg         jump1;
    reg         jump2;
    wire [31:0] pc;

    program_counter uut (
        .clk          (clk),
        .reset        (reset),
        .target       (target),
        .stall        (stall),
        .branch_taken (branch_taken),
        .jump1        (jump1),
        .jump2        (jump2),
        .pc           (pc)
    );

    always #5 clk = ~clk;

    initial begin
        clk          = 0;
        reset        = 1;
        target       = 32'h0;
        stall        = 0;
        branch_taken = 0;
        jump1        = 0;
        jump2        = 0;

        // --- Reset: hold for 2 cycles, then sample ---
        @(posedge clk); #1;
        @(posedge clk); #1;
        if (pc !== 32'h0) $display("FAIL reset: pc=%h (expected 00000000)", pc);
        reset = 0;

        // --- Normal increment: 5 cycles from 0x0 → 0x14 ---
        repeat (5) @(posedge clk); #1;
        $display("pc after 5 increments=%h (expected 00000014)", pc);
        if (pc !== 32'h14) $display("FAIL increment: pc=%h (expected 00000014)", pc);

        // --- JAL jump via jump1 ---
        @(negedge clk);
        jump1  = 1;
        target = 32'h0000_1000;
        @(posedge clk); #1;
        if (pc !== 32'h0000_1000) $display("FAIL jump1: pc=%h (expected 00001000)", pc);

        @(negedge clk);
        jump1 = 0;

        // --- 3 normal increments from 0x1000 → 0x100c ---
        repeat (3) @(posedge clk); #1;
        $display("pc after 3 increments from 0x1000=%h (expected 0000100c)", pc);
        if (pc !== 32'h100c) $display("FAIL post-jump1 increment: pc=%h (expected 0000100c)", pc);

        // --- JALR jump via jump2 ---
        @(negedge clk);
        jump2  = 1;
        target = 32'h0000_2000;
        @(posedge clk); #1;
        if (pc !== 32'h0000_2000) $display("FAIL jump2: pc=%h (expected 00002000)", pc);

        @(negedge clk);
        jump2 = 0;

        // --- 2 increments then branch taken ---
        repeat (2) @(posedge clk); #1;  // pc → 0x2008
        @(negedge clk);
        branch_taken = 1;
        target       = 32'h0000_3000;
        @(posedge clk); #1;
        if (pc !== 32'h0000_3000) $display("FAIL branch: pc=%h (expected 00003000)", pc);

        @(negedge clk);
        branch_taken = 0;

        // --- 1 increment then stall ---
        @(posedge clk); #1;  // pc → 0x3004
        @(negedge clk);
        stall = 1;
        @(posedge clk); #1;
        if (pc !== 32'h3004) $display("FAIL stall1: pc=%h (expected 00003004)", pc);
        @(posedge clk); #1;
        if (pc !== 32'h3004) $display("FAIL stall2: pc=%h (expected 00003004)", pc);

        @(negedge clk);
        stall = 0;

        // --- Resume after stall ---
        @(posedge clk); #1;
        if (pc !== 32'h3008) $display("FAIL resume: pc=%h (expected 00003008)", pc);

        // --- Second reset ---
        @(negedge clk);
        reset = 1;
        @(posedge clk); #1;
        if (pc !== 32'h0) $display("FAIL reset2: pc=%h (expected 00000000)", pc);
        reset = 0;

        #20;
        $display("done");
        $finish;
    end
endmodule
