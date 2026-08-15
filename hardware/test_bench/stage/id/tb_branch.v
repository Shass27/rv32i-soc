`timescale 1ns / 1ps

// ============================================================
// Testbench: branch_logic
// Tests: BEQ, BNE, BLT, BGE, BLTU, BGEU
//        - branch taken / not-taken cases
//        - target address calculation
// Waveform: rb_branch.vcd
// ============================================================
module rb_branch;

    // --------------------------------------------------------
    // DUT inputs
    // --------------------------------------------------------
    reg         branch;
    reg  [31:0] pc;
    reg  [31:0] imm;
    reg  [31:0] rd1;
    reg  [31:0] rd2;
    reg  [2:0]  funct3;

    // --------------------------------------------------------
    // DUT outputs
    // --------------------------------------------------------
    wire        branch_taken;
    wire [31:0] target;

    // --------------------------------------------------------
    // Instantiate DUT
    // --------------------------------------------------------
    branch_logic dut (
        .branch     (branch),
        .pc         (pc),
        .imm        (imm),
        .ReadData1  (rd1),
        .ReadData2  (rd2),
        .funct3     (funct3),
        .branch_taken(branch_taken),
        .target     (target)
    );

    // --------------------------------------------------------
    // Helpers
    // --------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task check;
        input [63:0] test_id;
        input [127:0] name;       // not used in display – kept for structure
        input exp_taken;
        input [31:0] exp_target;
        begin
            #5; // let combinational logic settle
            if (branch_taken === exp_taken && target === exp_target) begin
                $display("PASS [%0d] %-30s | taken=%b  target=0x%08h",
                         test_id, name, branch_taken, target);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL [%0d] %-30s | taken=%b(exp %b)  target=0x%08h(exp 0x%08h)",
                         test_id, name, branch_taken, exp_taken, target, exp_target);
                fail_cnt = fail_cnt + 1;
            end
            #5;
        end
    endtask

    // --------------------------------------------------------
    // Waveform dump
    // --------------------------------------------------------
    initial begin
        $dumpfile("rb_branch.vcd");
        $dumpvars(0, rb_branch);
    end

    // --------------------------------------------------------
    // Stimulus
    // --------------------------------------------------------
    initial begin
        $display("========================================");
        $display(" branch_logic testbench");
        $display("========================================");

        // Common base values
        pc     = 32'h0000_1000;
        imm    = 32'h0000_0010;   // +16 offset

        // ------------------------------------------------
        // 1. BEQ  (funct3 = 000)
        // ------------------------------------------------
        funct3 = 3'b000;

        // 1a. BEQ taken  (rd1 == rd2)
        branch = 1; rd1 = 32'd42; rd2 = 32'd42;
        check(1, "BEQ  taken  (rd1==rd2)", 1'b1, pc + imm);

        // 1b. BEQ not-taken  (rd1 != rd2)
        branch = 1; rd1 = 32'd10; rd2 = 32'd20;
        check(2, "BEQ  not-taken(rd1!=rd2)", 1'b0, 32'b0);

        // 1c. branch signal de-asserted
        branch = 0; rd1 = 32'd5;  rd2 = 32'd5;
        check(3, "BEQ  branch=0 (no branch)", 1'b0, 32'b0);

        // ------------------------------------------------
        // 2. BNE  (funct3 = 001)
        // ------------------------------------------------
        funct3 = 3'b001;
        branch = 1;

        // 2a. BNE taken  (rd1 != rd2)
        rd1 = 32'd1; rd2 = 32'd2;
        check(4, "BNE  taken  (rd1!=rd2)", 1'b1, pc + imm);

        // 2b. BNE not-taken  (rd1 == rd2)
        rd1 = 32'd7; rd2 = 32'd7;
        check(5, "BNE  not-taken(rd1==rd2)", 1'b0, 32'b0);

        // ------------------------------------------------
        // 3. BLT  (funct3 = 100) – signed comparison
        // ------------------------------------------------
        funct3 = 3'b100;
        branch = 1;

        // 3a. BLT taken  (rd1 < rd2, signed)
        rd1 = 32'hFFFF_FFFF; rd2 = 32'h0000_0001; // -1 < 1
        check(6, "BLT  taken  (-1 < 1 signed)", 1'b1, pc + imm);

        // 3b. BLT not-taken  (rd1 > rd2, signed)
        rd1 = 32'h0000_0002; rd2 = 32'hFFFF_FFFF; // 2 > -1
        check(7, "BLT  not-taken(2 > -1 signed)", 1'b0, 32'b0);

        // 3c. BLT not-taken  (rd1 == rd2)
        rd1 = 32'd5; rd2 = 32'd5;
        check(8, "BLT  not-taken(rd1==rd2)", 1'b0, 32'b0);

        // ------------------------------------------------
        // 4. BGE  (funct3 = 101) – signed comparison
        // ------------------------------------------------
        funct3 = 3'b101;
        branch = 1;

        // 4a. BGE taken  (rd1 > rd2, signed)
        rd1 = 32'h0000_0001; rd2 = 32'hFFFF_FFFF; // 1 > -1
        check(9, "BGE  taken  (1 >= -1 signed)", 1'b1, pc + imm);

        // 4b. BGE taken  (rd1 == rd2)
        rd1 = 32'd3; rd2 = 32'd3;
        check(10, "BGE  taken  (rd1==rd2)", 1'b1, pc + imm);

        // 4c. BGE not-taken  (rd1 < rd2, signed)
        rd1 = 32'hFFFF_FFFF; rd2 = 32'h0000_0001; // -1 < 1
        check(11, "BGE  not-taken(-1 < 1 signed)", 1'b0, 32'b0);

        // ------------------------------------------------
        // 5. BLTU  (funct3 = 110) – unsigned comparison
        // ------------------------------------------------
        funct3 = 3'b110;
        branch = 1;

        // 5a. BLTU taken  (rd1 < rd2, unsigned)
        rd1 = 32'd3; rd2 = 32'd10;
        check(12, "BLTU taken  (3 < 10 unsigned)", 1'b1, pc + imm);

        // 5b. BLTU taken  (large unsigned rd1 < rd2)
        rd1 = 32'h0000_0001; rd2 = 32'hFFFF_FFFF; // unsigned 1 < 0xFFFF_FFFF
        check(13, "BLTU taken  (1 < 0xFFFFFFFF)", 1'b1, pc + imm);

        // 5c. BLTU not-taken  (rd1 >= rd2, unsigned)
        rd1 = 32'd10; rd2 = 32'd3;
        check(14, "BLTU not-taken(10 >= 3 unsigned)", 1'b0, 32'b0);

        // ------------------------------------------------
        // 6. BGEU  (funct3 = 111) – unsigned comparison
        // ------------------------------------------------
        funct3 = 3'b111;
        branch = 1;

        // 6a. BGEU taken  (rd1 > rd2, unsigned)
        rd1 = 32'd10; rd2 = 32'd3;
        check(15, "BGEU taken  (10 >= 3 unsigned)", 1'b1, pc + imm);

        // 6b. BGEU taken  (rd1 == rd2)
        rd1 = 32'd8; rd2 = 32'd8;
        check(16, "BGEU taken  (rd1==rd2)", 1'b1, pc + imm);

        // 6c. BGEU not-taken  (rd1 < rd2, unsigned)
        rd1 = 32'h0000_0001; rd2 = 32'hFFFF_FFFF;
        check(17, "BGEU not-taken(1 < 0xFFFFFFFF)", 1'b0, 32'b0);

        // ------------------------------------------------
        // Summary
        // ------------------------------------------------
        $display("========================================");
        $display(" Results: %0d PASSED  |  %0d FAILED", pass_cnt, fail_cnt);
        $display("========================================");

        $finish;
    end

endmodule
