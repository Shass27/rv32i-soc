`timescale 1ns/1ps

module tb_cpu_top;

    // ---------------------------------------------------------
    // Clock / reset
    // ---------------------------------------------------------
    reg clk;
    reg reset;

    integer cycle;
    integer errors;

    // DUT: top-level CPU
    cpu_top u_dut (
        .clk   (clk),
        .reset (reset)
    );

    // ---------------------------------------------------------
    // Test program in program.hex  (31 instructions)
    //
    // Addr  Encoding    Instruction
    // 0x00: 06400093    addi  x1,  x0,  100       // x1  = 100
    // 0x04: 02a00113    addi  x2,  x0,  42        // x2  = 42
    // 0x08: 002081b3    add   x3,  x1,  x2        // x3  = 142
    // 0x0C: 40218233    sub   x4,  x3,  x2        // x4  = 100
    // 0x10: 0021f2b3    and   x5,  x3,  x2        // x5  = 142 & 42  = 10
    // 0x14: 0021e333    or    x6,  x3,  x2        // x6  = 142 | 42  = 174
    // 0x18: 0021c3b3    xor   x7,  x3,  x2        // x7  = 142 ^ 42  = 164
    // 0x1C: 00211433    sll   x8,  x2,  x2        // x8  = 42 << 42  (42<<10 = 43008)
    // 0x20: 002454b3    srl   x9,  x8,  x2        // x9  = x8 >> 42  (>> 10) = 42
    // 0x24: 40245533    sra   x10, x8,  x2        // x10 = x8 >>> 42 (>>> 10) = 42
    // 0x28: 002225b3    slt   x11, x4,  x2        // x11 = (100 < 42) = 0
    // 0x2C: 00223633    sltu  x12, x4,  x2        // x12 = (100 < 42)u= 0
    // 0x30: 00f1f693    andi  x13, x3,  15        // x13 = 142 & 15  = 14
    // 0x34: 05506713    ori   x14, x0,  85        // x14 = 85
    // 0x38: 0ff74793    xori  x15, x14, 255       // x15 = 85 ^ 255  = 170
    // 0x3C: 00211813    slli  x16, x2,  2         // x16 = 42 << 2   = 168
    // 0x40: 00285893    srli  x17, x16, 2         // x17 = 168 >> 2  = 42
    // 0x44: ff000913    addi  x18, x0,  -16       // x18 = -16
    // 0x48: 40295993    srai  x19, x18, 2         // x19 = -16 >>> 2 = -4
    // 0x4C: 00092a13    slti  x20, x18, 0         // x20 = (-16 < 0) = 1
    // 0x50: 00093a93    sltiu x21, x18, 0         // x21 = (0xFFFFFFF0 < 0)u= 0
    // 0x54: 0020a023    sw    x2,  0(x1)          // mem[100] = 42
    // 0x58: 0000ab03    lw    x22, 0(x1)          // x22 = mem[100] = 42
    // 0x5C: 00208463    beq   x1,  x2,  +8        // 100!=42, NOT taken -> 0x60
    // 0x60: 06f00b93    addi  x23, x0,  111       // x23 = 111 (executed)
    // 0x64: 002b0463    beq   x22, x2,  +8        // 42==42, TAKEN -> 0x6C
    // 0x68: 0de00c93    addi  x25, x0,  222       // SKIPPED
    // 0x6C: 00800c6f    jal   x24, +8             // x24=0x70, jump -> 0x74
    // 0x70: 14d00c93    addi  x25, x0,  333       // SKIPPED
    // 0x74: 1bc00d13    addi  x26, x0,  444       // x26 = 444
    // 0x78: 0000006f    jal   x0,  +0             // infinite self-loop
    //
    // Expected register values at end (after self-loop):
    //   x1=100, x2=42, x3=142, x4=100, x5=10, x6=174, x7=164
    //   x8=43008, x9=42, x10=42, x11=0, x12=0, x13=14, x14=85
    //   x15=170, x16=168, x17=42, x18=-16, x19=-4, x20=1, x21=0
    //   x22=42, x23=111, x24=0x70, x25=<skipped, unchanged>, x26=444
    // ---------------------------------------------------------

    // ---------------------------------------------------------
    // Waveform dump
    // This recreates cpu_top.vcd on each simulation run.
    // ---------------------------------------------------------
    initial begin
        $dumpfile("cpu_top.vcd");
        $dumpvars(0, tb_cpu_top);
    end

    // Clock: 10 ns period
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Reset: hold high for a few cycles, then release
    initial begin
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
    end

    // ---------------------------------------------------------
    // Simple helper for checks
    // ---------------------------------------------------------
    task automatic check_eq32;
        input [255:0] label;
        input [31:0] got;
        input [31:0] exp;
        begin
            if (got !== exp) begin
                $display("FAIL: %0s got=%08h exp=%08h @%0t", label, got, exp, $time);
                errors = errors + 1;
            end
        end
    endtask

    task automatic check_eq1;
        input [255:0] label;
        input got;
        input exp;
        begin
            if (got !== exp) begin
                $display("FAIL: %0s got=%b exp=%b @%0t", label, got, exp, $time);
                errors = errors + 1;
            end
        end
    endtask

    // ---------------------------------------------------------
    // Main self-checking monitor
    //
    // Single-cycle CPU: one instruction per clock after reset.
    // Cycle numbers below correspond to instructions in order,
    // with branches/jumps adjusting the PC accordingly.
    //
    // Cycle  PC      Instr        Note
    //   0    0x00    addi x1,x0,100
    //   1    0x04    addi x2,x0,42
    //   2    0x08    add  x3,x1,x2
    //   3    0x0C    sub  x4,x3,x2
    //   4    0x10    and  x5,x3,x2
    //   5    0x14    or   x6,x3,x2
    //   6    0x18    xor  x7,x3,x2
    //   7    0x1C    sll  x8,x2,x2
    //   8    0x20    srl  x9,x8,x2
    //   9    0x24    sra  x10,x8,x2
    //  10    0x28    slt  x11,x4,x2
    //  11    0x2C    sltu x12,x4,x2
    //  12    0x30    andi x13,x3,15
    //  13    0x34    ori  x14,x0,85
    //  14    0x38    xori x15,x14,255
    //  15    0x3C    slli x16,x2,2
    //  16    0x40    srli x17,x16,2
    //  17    0x44    addi x18,x0,-16
    //  18    0x48    srai x19,x18,2
    //  19    0x4C    slti x20,x18,0
    //  20    0x50    sltiu x21,x18,0
    //  21    0x54    sw   x2,0(x1)
    //  22    0x58    lw   x22,0(x1)
    //  23    0x5C    beq  x1,x2,+8   NOT taken -> 0x60
    //  24    0x60    addi x23,x0,111 (executed)
    //  25    0x64    beq  x22,x2,+8  TAKEN -> 0x6C
    //  26    0x6C    jal  x24,+8     -> 0x74
    //  27    0x74    addi x26,x0,444
    //  28    0x78    jal  x0,+0      self-loop
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            cycle  <= 0;
            errors <= 0;
        end else begin
            case (cycle)
                // ---- ALU register instructions ----
                0: begin
                    check_eq32("pc[0]",    u_dut.pc,    32'h00000000);
                    check_eq32("instr[0]", u_dut.instr, 32'h06400093);
                end
                1: begin
                    check_eq32("pc[1]",    u_dut.pc,    32'h00000004);
                    check_eq32("instr[1]", u_dut.instr, 32'h02a00113);
                end
                2: begin
                    check_eq32("pc[2]",    u_dut.pc,    32'h00000008);
                    check_eq32("instr[2]", u_dut.instr, 32'h002081b3);
                end
                3: begin
                    check_eq32("pc[3]",    u_dut.pc,    32'h0000000C);
                    check_eq32("instr[3]", u_dut.instr, 32'h40218233);
                end
                4: begin
                    check_eq32("pc[4]",    u_dut.pc,    32'h00000010);
                    check_eq32("instr[4]", u_dut.instr, 32'h0021f2b3);
                end
                5: begin
                    check_eq32("pc[5]",    u_dut.pc,    32'h00000014);
                    check_eq32("instr[5]", u_dut.instr, 32'h0021e333);
                end
                6: begin
                    check_eq32("pc[6]",    u_dut.pc,    32'h00000018);
                    check_eq32("instr[6]", u_dut.instr, 32'h0021c3b3);
                end
                7: begin
                    check_eq32("pc[7]",    u_dut.pc,    32'h0000001C);
                    check_eq32("instr[7]", u_dut.instr, 32'h00211433);
                end
                8: begin
                    check_eq32("pc[8]",    u_dut.pc,    32'h00000020);
                    check_eq32("instr[8]", u_dut.instr, 32'h002454b3);
                end
                9: begin
                    check_eq32("pc[9]",    u_dut.pc,    32'h00000024);
                    check_eq32("instr[9]", u_dut.instr, 32'h40245533);
                end
                10: begin
                    check_eq32("pc[10]",    u_dut.pc,    32'h00000028);
                    check_eq32("instr[10]", u_dut.instr, 32'h002225b3);
                end
                11: begin
                    check_eq32("pc[11]",    u_dut.pc,    32'h0000002C);
                    check_eq32("instr[11]", u_dut.instr, 32'h00223633);
                end
                // ---- ALU immediate instructions ----
                12: begin
                    check_eq32("pc[12]",    u_dut.pc,    32'h00000030);
                    check_eq32("instr[12]", u_dut.instr, 32'h00f1f693);
                end
                13: begin
                    check_eq32("pc[13]",    u_dut.pc,    32'h00000034);
                    check_eq32("instr[13]", u_dut.instr, 32'h05506713);
                end
                14: begin
                    check_eq32("pc[14]",    u_dut.pc,    32'h00000038);
                    check_eq32("instr[14]", u_dut.instr, 32'h0ff74793);
                end
                15: begin
                    check_eq32("pc[15]",    u_dut.pc,    32'h0000003C);
                    check_eq32("instr[15]", u_dut.instr, 32'h00211813);
                end
                16: begin
                    check_eq32("pc[16]",    u_dut.pc,    32'h00000040);
                    check_eq32("instr[16]", u_dut.instr, 32'h00285893);
                end
                17: begin
                    check_eq32("pc[17]",    u_dut.pc,    32'h00000044);
                    check_eq32("instr[17]", u_dut.instr, 32'hff000913);
                end
                18: begin
                    check_eq32("pc[18]",    u_dut.pc,    32'h00000048);
                    check_eq32("instr[18]", u_dut.instr, 32'h40295993);
                end
                19: begin
                    check_eq32("pc[19]",    u_dut.pc,    32'h0000004C);
                    check_eq32("instr[19]", u_dut.instr, 32'h00092a13);
                end
                20: begin
                    check_eq32("pc[20]",    u_dut.pc,    32'h00000050);
                    check_eq32("instr[20]", u_dut.instr, 32'h00093a93);
                end
                // ---- Memory: sw / lw ----
                21: begin
                    check_eq32("pc[21]",    u_dut.pc,    32'h00000054);
                    check_eq32("instr[21]", u_dut.instr, 32'h0020a023);
                end
                22: begin
                    check_eq32("pc[22]",    u_dut.pc,    32'h00000058);
                    check_eq32("instr[22]", u_dut.instr, 32'h0000ab03);
                    // lw should load 42 from mem[100]
                    check_eq32("load-data", u_dut.mem_rdata,     32'h0000002a);
                    check_eq32("wb-data",   u_dut.final_wb_data, 32'h0000002a);
                end
                // ---- Branch: beq x1,x2 NOT taken ----
                23: begin
                    check_eq32("pc[23]",      u_dut.pc,    32'h0000005C);
                    check_eq32("instr[23]",   u_dut.instr, 32'h00208463);
                    check_eq1 ("branch-not-taken", u_dut.branch_taken, 1'b0);
                end
                // ---- addi x23 is executed because branch was NOT taken ----
                24: begin
                    check_eq32("pc[24]",    u_dut.pc,    32'h00000060);
                    check_eq32("instr[24]", u_dut.instr, 32'h06f00b93);
                end
                // ---- Branch: beq x22,x2 TAKEN -> 0x6C ----
                25: begin
                    check_eq32("pc[25]",      u_dut.pc,    32'h00000064);
                    check_eq32("instr[25]",   u_dut.instr, 32'h002b0463);
                    check_eq1 ("branch-taken", u_dut.branch_taken, 1'b1);
                end
                // ---- JAL x24,+8 -> 0x74  (0x68 skipped) ----
                26: begin
                    check_eq32("pc[26]",    u_dut.pc,    32'h0000006C);
                    check_eq32("instr[26]", u_dut.instr, 32'h00800c6f);
                    check_eq1 ("jump", u_dut.jump, 1'b1);
                end
                // ---- addi x26,x0,444  (0x70 skipped by JAL) ----
                27: begin
                    check_eq32("pc[27]",    u_dut.pc,    32'h00000074);
                    check_eq32("instr[27]", u_dut.instr, 32'h1bc00d13);
                end
                // ---- infinite self-loop ----
                28: begin
                    check_eq32("pc[28]",    u_dut.pc,    32'h00000078);
                    check_eq32("instr[28]", u_dut.instr, 32'h0000006f);
                    check_eq1 ("loop-jump", u_dut.jump, 1'b1);
                end
                default: begin
                    // CPU must stay in the self-loop at 0x78
                    check_eq32("pc-loop",    u_dut.pc,    32'h00000078);
                    check_eq32("instr-loop", u_dut.instr, 32'h0000006f);
                end
            endcase

            cycle <= cycle + 1;
        end
    end

    // ---------------------------------------------------------
    // Stop after enough cycles and report result
    // ---------------------------------------------------------
    initial begin
        cycle  = 0;
        errors = 0;

        // 3 reset cycles + 29 instruction cycles + margin
        repeat (50) @(posedge clk);

        if (errors == 0) begin
            $display("PASS: all checks passed");
        end else begin
            $display("FAIL: %0d check(s) failed", errors);
        end

        $finish;
    end

endmodule