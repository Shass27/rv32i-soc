`timescale 1ns/1ps

// CPU-level test for the integrated Wishbone SEARCH accelerator.
// This is deliberately separate from tb_cpu_top_wb.v and does not edit program.hex.
module tb_cpu_search;
    reg clk = 1'b0;
    reg reset = 1'b1;
    integer i;
    integer errors = 0;
    integer test_key = 12;
    integer test_len = 7;
    integer skip_result_check = 0;
    integer expect_comps_nonzero = 1;
    reg [19:0] len_upper;
    reg [11:0] len_lower;
    reg [31:0] expected_result = 32'd4;
    reg [31:0] expected_status = 32'h00000006;

    cpu_top_wb u_dut (
        .clk   (clk),
        .reset (reset)
    );

    always #5 clk = ~clk;

    localparam [6:0] OP_LOAD   = 7'b0000011;
    localparam [6:0] OP_IMM    = 7'b0010011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [6:0] OP_BRANCH = 7'b1100011;

    function [31:0] enc_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            enc_i = {imm, rs1, funct3, rd, opcode};
        end
    endfunction

    function [31:0] enc_s;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [6:0] opcode;
        begin
            enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
        end
    endfunction

    function [31:0] enc_b;
        input [12:0] off;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [6:0] opcode;
        begin
            enc_b = {off[12], off[10:5], rs2, rs1, funct3,
                     off[4:1], off[11], opcode};
        end
    endfunction

    task put;
        input integer word_index;
        input [31:0] instruction;
        begin
            u_dut.u_imem.mem[word_index] = instruction;
        end
    endtask

    task check32;
        input [255:0] label;
        input [31:0] got;
        input [31:0] expected;
        begin
            if (got !== expected) begin
                $display("FAIL: %0s got=%08h expected=%08h", label, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %08h", label, got);
            end
        end
    endtask

    initial begin
        // Optional runtime parameters allow the same CPU program to test
        // different keys without editing program.hex or this testbench.
        if ($value$plusargs("key=%d", test_key)) begin end
        if ($value$plusargs("len=%d", test_len)) begin end
        if ($value$plusargs("expected=%h", expected_result)) begin end
        if ($value$plusargs("status=%h", expected_status)) begin end
        if ($test$plusargs("invalid")) begin
            skip_result_check = 1;
            expect_comps_nonzero = 0;
        end
        // Supported test lengths here are non-negative values up to 8193.
        len_upper = test_len >> 12;
        len_lower = test_len & 12'hFFF;

        $dumpfile("cpu_search.vcd");
        $dumpvars(0, tb_cpu_search);

        // Let the DUT's $readmemh finish, then replace only its instruction
        // memory contents. The repository's program.hex remains untouched.
        #1;
        for (i = 0; i < 4097; i = i + 1)
            u_dut.u_imem.mem[i] = 32'h00000013; // ADDI x0,x0,0 (NOP)

        // x1 = 0x30000000 (SEARCH array base)
        put(0,  {20'h30000, 5'd1, OP_LUI});
        // x2 = 0x30008000 (SEARCH register page)
        put(1,  {20'h30008, 5'd2, OP_LUI});
        // Sorted signed array: [-8, -3, 2, 7, 12, 19, 25]
        put(2,  enc_i(12'hFF8, 5'd0, 3'b000, 5'd3, OP_IMM)); // addi x3,x0,-8
        put(3,  enc_s(12'd0,  5'd3, 5'd1, 3'b010, OP_STORE));
        put(4,  enc_i(12'hFFD, 5'd0, 3'b000, 5'd3, OP_IMM)); // addi x3,x0,-3
        put(5,  enc_s(12'd4,  5'd3, 5'd1, 3'b010, OP_STORE));
        put(6,  enc_i(12'd2,   5'd0, 3'b000, 5'd3, OP_IMM));
        put(7,  enc_s(12'd8,  5'd3, 5'd1, 3'b010, OP_STORE));
        put(8,  enc_i(12'd7,   5'd0, 3'b000, 5'd3, OP_IMM));
        put(9,  enc_s(12'd12, 5'd3, 5'd1, 3'b010, OP_STORE));
        put(10, enc_i(12'd12,  5'd0, 3'b000, 5'd3, OP_IMM));
        put(11, enc_s(12'd16, 5'd3, 5'd1, 3'b010, OP_STORE));
        put(12, enc_i(12'd19,  5'd0, 3'b000, 5'd3, OP_IMM));
        put(13, enc_s(12'd20, 5'd3, 5'd1, 3'b010, OP_STORE));
        put(14, enc_i(12'd25,  5'd0, 3'b000, 5'd3, OP_IMM));
        put(15, enc_s(12'd24, 5'd3, 5'd1, 3'b010, OP_STORE));

        // Configure length from +len=... (default 7).
        // LUI + ADDI supports both 7 and the invalid test length 8193.
        put(16, {len_upper, 5'd3, OP_LUI});
        put(17, enc_i(len_lower, 5'd3, 3'b000, 5'd3, OP_IMM));
        put(18, enc_s(12'd8, 5'd3, 5'd2, 3'b010, OP_STORE));

        // Configure key, then write CTRL.START=1.
        put(19, enc_i(test_key[11:0], 5'd0, 3'b000, 5'd3, OP_IMM));
        put(20, enc_s(12'd12, 5'd3, 5'd2, 3'b010, OP_STORE));
        put(21, enc_i(12'd1, 5'd0, 3'b000, 5'd3, OP_IMM));
        put(22, enc_s(12'd0, 5'd3, 5'd2, 3'b010, OP_STORE));

        // Poll STATUS.DONE (bit 1). Branch loops to the status load.
        put(23, enc_i(12'd4, 5'd2, 3'b010, 5'd7, OP_LOAD)); // lw x7,4(x2)
        put(24, enc_i(12'd2, 5'd7, 3'b111, 5'd8, OP_IMM));  // andi x8,x7,2
        put(25, enc_b(-13'sd8, 5'd0, 5'd8, 3'b000, OP_BRANCH)); // beq x8,x0,-8

        // Capture result and comparison count, then park at a self-loop.
        put(26, enc_i(12'd16, 5'd2, 3'b010, 5'd9,  OP_LOAD)); // lw x9,16(x2)
        put(27, enc_i(12'd20, 5'd2, 3'b010, 5'd10, OP_LOAD)); // lw x10,20(x2)
        put(28, 32'h0000006F); // jal x0,0

        repeat (3) @(negedge clk);
        reset = 1'b0;

        // The CPU executes the actual bus transactions; no testbench-side
        // writes are made to the SEARCH accelerator.
        // Wait for the CPU to observe STATUS.DONE, not for x9 to equal the
        // expected result (x9 starts at zero, which breaks the index-0 case).
        wait ((u_dut.u_regfile.registers[7] & 32'h00000002) === 32'h00000002);
        repeat (20) @(negedge clk);

        $display("");
        $display("========================================");
        $display(" CPU-LEVEL SEARCH ACCELERATOR TEST");
        $display("========================================");
        $display("Running key=%0d length=%0d expected_result=%08h expected_status=%08h",
                 test_key, test_len, expected_result, expected_status);
        if (!skip_result_check)
            check32("SEARCH result", u_dut.u_regfile.registers[9], expected_result);
        else
            $display("INFO: result check skipped for invalid-length test");

        check32("SEARCH status bits DONE/FOUND/ERROR",
                u_dut.u_regfile.registers[7] & 32'h0000000E, expected_status);

        if (expect_comps_nonzero) begin
            if (u_dut.u_regfile.registers[10] == 0) begin
                $display("FAIL: comparison count is zero");
                errors = errors + 1;
            end else begin
                $display("PASS: comparison count = %0d",
                         u_dut.u_regfile.registers[10]);
            end
        end else begin
            check32("invalid-length comparison count",
                    u_dut.u_regfile.registers[10], 32'd0);
        end

        if (errors == 0)
            $display("ALL CPU-LEVEL SEARCH TESTS PASSED");
        else
            $display("CPU-LEVEL SEARCH TEST FAILED: %0d error(s)", errors);

        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: CPU SEARCH test timed out");
        $finish;
    end
endmodule
