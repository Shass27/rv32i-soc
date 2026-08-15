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
    // Test program in program.hex  (56 instructions)
    //
    // ===== R-type ALU instructions =====
    // Addr  Encoding    Instruction                     Result
    // 0x00: 00a00093    addi  x1,  x0,  10            // x1  = 10
    // 0x04: 00300113    addi  x2,  x0,  3             // x2  = 3
    // 0x08: 002081b3    add   x3,  x1,  x2            // x3  = 13
    // 0x0C: 40208233    sub   x4,  x1,  x2            // x4  = 7
    // 0x10: 0020f2b3    and   x5,  x1,  x2            // x5  = 10 & 3  = 2
    // 0x14: 0020e333    or    x6,  x1,  x2            // x6  = 10 | 3  = 11
    // 0x18: 0020c3b3    xor   x7,  x1,  x2            // x7  = 10 ^ 3  = 9
    // 0x1C: 00211433    sll   x8,  x2,  x2            // x8  = 3 << 3  = 24
    // 0x20: 0020d4b3    srl   x9,  x1,  x2            // x9  = 10 >> 3 = 1
    // 0x24: ff000593    addi  x11, x0,  -16           // x11 = -16 (0xFFFFFFF0)
    // 0x28: 4025d633    sra   x12, x11, x2            // x12 = -16 >>> 3 = -2 (0xFFFFFFFE)
    // 0x2C: 0020a6b3    slt   x13, x1,  x2            // x13 = (10 < 3) = 0
    // 0x30: 0020b733    sltu  x14, x1,  x2            // x14 = (10 < 3)u = 0
    //
    // ===== I-type ALU instructions =====
    // 0x34: 0060f793    andi  x15, x1,  6             // x15 = 10 & 6  = 2
    // 0x38: 0050e813    ori   x16, x1,  5             // x16 = 10 | 5  = 15
    // 0x3C: 0070c893    xori  x17, x1,  7             // x17 = 10 ^ 7  = 13
    // 0x40: 00211913    slli  x18, x2,  2             // x18 = 3 << 2  = 12
    // 0x44: 0020d993    srli  x19, x1,  2             // x19 = 10 >> 2 = 2
    // 0x48: 4025da13    srai  x20, x11, 2             // x20 = -16 >>> 2 = -4 (0xFFFFFFFC)
    // 0x4C: 00a12a93    slti  x21, x2,  10            // x21 = (3 < 10) = 1
    // 0x50: 00a13b13    sltiu x22, x2,  10            // x22 = (3 < 10)u = 1
    //
    // ===== Memory: SW + LW/LB/LH/LBU/LHU =====
    // 0x54: 00b02023    sw    x11, 0(x0)              // mem[0] = 0xFFFFFFF0
    // 0x58: 00002b83    lw    x23, 0(x0)              // x23 = 0xFFFFFFF0
    // 0x5C: 00000c03    lb    x24, 0(x0)              // x24 = sign_ext(0xF0) = 0xFFFFFFF0
    // 0x60: 00001c83    lh    x25, 0(x0)              // x25 = sign_ext(0xFFF0) = 0xFFFFFFF0
    // 0x64: 00004d03    lbu   x26, 0(x0)              // x26 = zero_ext(0xF0) = 0x000000F0
    // 0x68: 00005d83    lhu   x27, 0(x0)              // x27 = zero_ext(0xFFF0) = 0x0000FFF0
    //
    // ===== Memory: SB + SH + sub-word loads =====
    // 0x6C: 001000a3    sb    x1,  1(x0)              // mem[0] byte1 = 0x0A -> word = 0xFFFF0AF0
    // 0x70: 00201123    sh    x2,  2(x0)              // mem[0] half1 = 0x0003 -> word = 0x00030AF0
    // 0x74: 00100e03    lb    x28, 1(x0)              // x28 = sign_ext(0x0A) = 0x0000000A
    // 0x78: 00304e83    lbu   x29, 3(x0)              // x29 = zero_ext(0x00) = 0x00000000
    // 0x7C: 00205f03    lhu   x30, 2(x0)              // x30 = zero_ext(0x0003) = 0x00000003
    //
    // ===== Branch instructions (all TAKEN, skip addi x31,x0,99) =====
    // 0x80: 00209463    bne   x1, x2, +8  -> 0x88     // 10!=3, TAKEN
    // 0x84: 06300f93    addi  x31, x0, 99             // SKIPPED
    // 0x88: 00100f93    addi  x31, x0, 1              // x31 = 1
    // 0x8C: 00114463    blt   x2, x1, +8  -> 0x94     // 3<10, TAKEN
    // 0x90: 06300f93    addi  x31, x0, 99             // SKIPPED
    // 0x94: 00200f93    addi  x31, x0, 2              // x31 = 2
    // 0x98: 0020d463    bge   x1, x2, +8  -> 0xA0     // 10>=3, TAKEN
    // 0x9C: 06300f93    addi  x31, x0, 99             // SKIPPED
    // 0xA0: 00300f93    addi  x31, x0, 3              // x31 = 3
    // 0xA4: 00116463    bltu  x2, x1, +8  -> 0xAC     // 3<10u, TAKEN
    // 0xA8: 06300f93    addi  x31, x0, 99             // SKIPPED
    // 0xAC: 00400f93    addi  x31, x0, 4              // x31 = 4
    // 0xB0: 0020f463    bgeu  x1, x2, +8  -> 0xB8     // 10>=3u, TAKEN
    // 0xB4: 06300f93    addi  x31, x0, 99             // SKIPPED
    // 0xB8: 00500f93    addi  x31, x0, 5              // x31 = 5
    //
    // ===== JAL =====
    // 0xBC: 008002ef    jal   x5, +8  -> 0xC4         // x5 = 0xC0 (ret addr), jump to 0xC4
    // 0xC0: 06300213    addi  x4, x0, 99              // SKIPPED
    // 0xC4: 03700213    addi  x4, x0, 55              // x4 = 55
    //
    // ===== JALR =====
    // 0xC8: 0d400513    addi  x10, x0, 212            // x10 = 212 = 0xD4
    // 0xCC: 00050367    jalr  x6,  x10, 0             // x6 = 0xD0 (ret addr), jump to 0xD4
    // 0xD0: 06300213    addi  x4, x0, 99              // SKIPPED
    // 0xD4: 04200213    addi  x4, x0, 66              // x4 = 66
    //
    // ===== LUI + AUIPC =====
    // 0xD8: 123453b7    lui   x7,  0x12345            // x7 = 0x12345000
    // 0xDC: 00001417    auipc x8,  0x1                // x8 = 0xDC + 0x1000 = 0x10DC
    //
    // ===== Final register state =====
    //   x1=10, x2=3, x3=13, x4=66, x5=0xC0, x6=0xD0
    //   x7=0x12345000, x8=0x10DC, x9=1, x10=212
    //   x11=0xFFFFFFF0, x12=0xFFFFFFFE, x13=0, x14=0
    //   x15=2, x16=15, x17=13, x18=12, x19=2
    //   x20=0xFFFFFFFC, x21=1, x22=1
    //   x23=0xFFFFFFF0, x24=0xFFFFFFF0, x25=0xFFFFFFF0
    //   x26=0xF0, x27=0xFFF0
    //   x28=0x0A, x29=0, x30=3, x31=5
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
    // Cycle  PC      Instr                Note
    //   0    0x00    addi x1,x0,10
    //   1    0x04    addi x2,x0,3
    //   2    0x08    add  x3,x1,x2
    //   3    0x0C    sub  x4,x1,x2
    //   4    0x10    and  x5,x1,x2
    //   5    0x14    or   x6,x1,x2
    //   6    0x18    xor  x7,x1,x2
    //   7    0x1C    sll  x8,x2,x2
    //   8    0x20    srl  x9,x1,x2
    //   9    0x24    addi x11,x0,-16
    //  10    0x28    sra  x12,x11,x2
    //  11    0x2C    slt  x13,x1,x2
    //  12    0x30    sltu x14,x1,x2
    //  13    0x34    andi x15,x1,6
    //  14    0x38    ori  x16,x1,5
    //  15    0x3C    xori x17,x1,7
    //  16    0x40    slli x18,x2,2
    //  17    0x44    srli x19,x1,2
    //  18    0x48    srai x20,x11,2
    //  19    0x4C    slti x21,x2,10
    //  20    0x50    sltiu x22,x2,10
    //  21    0x54    sw   x11,0(x0)
    //  22    0x58    lw   x23,0(x0)
    //  23    0x5C    lb   x24,0(x0)
    //  24    0x60    lh   x25,0(x0)
    //  25    0x64    lbu  x26,0(x0)
    //  26    0x68    lhu  x27,0(x0)
    //  27    0x6C    sb   x1,1(x0)
    //  28    0x70    sh   x2,2(x0)
    //  29    0x74    lb   x28,1(x0)
    //  30    0x78    lbu  x29,3(x0)
    //  31    0x7C    lhu  x30,2(x0)
    //  32    0x80    bne  x1,x2,+8     TAKEN -> 0x88
    //  33    0x88    addi x31,x0,1
    //  34    0x8C    blt  x2,x1,+8     TAKEN -> 0x94
    //  35    0x94    addi x31,x0,2
    //  36    0x98    bge  x1,x2,+8     TAKEN -> 0xA0
    //  37    0xA0    addi x31,x0,3
    //  38    0xA4    bltu x2,x1,+8     TAKEN -> 0xAC
    //  39    0xAC    addi x31,x0,4
    //  40    0xB0    bgeu x1,x2,+8     TAKEN -> 0xB8
    //  41    0xB8    addi x31,x0,5
    //  42    0xBC    jal  x5,+8        -> 0xC4
    //  43    0xC4    addi x4,x0,55
    //  44    0xC8    addi x10,x0,212
    //  45    0xCC    jalr x6,x10,0     -> 0xD4
    //  46    0xD4    addi x4,x0,66
    //  47    0xD8    lui  x7,0x12345
    //  48    0xDC    auipc x8,0x1
    //  49    0xE0    <past program end, no more instructions>
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            cycle  <= 0;
            errors <= 0;
        end else begin
            case (cycle)
                // ============================================
                //  R-type ALU instructions
                // ============================================
                0: begin
                    check_eq32("pc[0]",    u_dut.pc,    32'h00000000);
                    check_eq32("instr[0]", u_dut.instr, 32'h00a00093);
                end
                1: begin
                    check_eq32("pc[1]",    u_dut.pc,    32'h00000004);
                    check_eq32("instr[1]", u_dut.instr, 32'h00300113);
                end
                2: begin
                    check_eq32("pc[2]",    u_dut.pc,    32'h00000008);
                    check_eq32("instr[2]", u_dut.instr, 32'h002081b3);
                end
                3: begin
                    check_eq32("pc[3]",    u_dut.pc,    32'h0000000C);
                    check_eq32("instr[3]", u_dut.instr, 32'h40208233);
                end
                4: begin
                    check_eq32("pc[4]",    u_dut.pc,    32'h00000010);
                    check_eq32("instr[4]", u_dut.instr, 32'h0020f2b3);
                end
                5: begin
                    check_eq32("pc[5]",    u_dut.pc,    32'h00000014);
                    check_eq32("instr[5]", u_dut.instr, 32'h0020e333);
                end
                6: begin
                    check_eq32("pc[6]",    u_dut.pc,    32'h00000018);
                    check_eq32("instr[6]", u_dut.instr, 32'h0020c3b3);
                end
                7: begin
                    check_eq32("pc[7]",    u_dut.pc,    32'h0000001C);
                    check_eq32("instr[7]", u_dut.instr, 32'h00211433);
                end
                8: begin
                    check_eq32("pc[8]",    u_dut.pc,    32'h00000020);
                    check_eq32("instr[8]", u_dut.instr, 32'h0020d4b3);
                end
                9: begin
                    check_eq32("pc[9]",    u_dut.pc,    32'h00000024);
                    check_eq32("instr[9]", u_dut.instr, 32'hff000593);
                end
                10: begin
                    check_eq32("pc[10]",    u_dut.pc,    32'h00000028);
                    check_eq32("instr[10]", u_dut.instr, 32'h4025d633);
                end
                11: begin
                    check_eq32("pc[11]",    u_dut.pc,    32'h0000002C);
                    check_eq32("instr[11]", u_dut.instr, 32'h0020a6b3);
                end
                12: begin
                    check_eq32("pc[12]",    u_dut.pc,    32'h00000030);
                    check_eq32("instr[12]", u_dut.instr, 32'h0020b733);
                end
                // ============================================
                //  I-type ALU instructions
                // ============================================
                13: begin
                    check_eq32("pc[13]",    u_dut.pc,    32'h00000034);
                    check_eq32("instr[13]", u_dut.instr, 32'h0060f793);
                end
                14: begin
                    check_eq32("pc[14]",    u_dut.pc,    32'h00000038);
                    check_eq32("instr[14]", u_dut.instr, 32'h0050e813);
                end
                15: begin
                    check_eq32("pc[15]",    u_dut.pc,    32'h0000003C);
                    check_eq32("instr[15]", u_dut.instr, 32'h0070c893);
                end
                16: begin
                    check_eq32("pc[16]",    u_dut.pc,    32'h00000040);
                    check_eq32("instr[16]", u_dut.instr, 32'h00211913);
                end
                17: begin
                    check_eq32("pc[17]",    u_dut.pc,    32'h00000044);
                    check_eq32("instr[17]", u_dut.instr, 32'h0020d993);
                end
                18: begin
                    check_eq32("pc[18]",    u_dut.pc,    32'h00000048);
                    check_eq32("instr[18]", u_dut.instr, 32'h4025da13);
                end
                19: begin
                    check_eq32("pc[19]",    u_dut.pc,    32'h0000004C);
                    check_eq32("instr[19]", u_dut.instr, 32'h00a12a93);
                end
                20: begin
                    check_eq32("pc[20]",    u_dut.pc,    32'h00000050);
                    check_eq32("instr[20]", u_dut.instr, 32'h00a13b13);
                end
                // ============================================
                //  Memory: SW then LW/LB/LH/LBU/LHU
                // ============================================
                21: begin
                    check_eq32("pc[21]",    u_dut.pc,    32'h00000054);
                    check_eq32("instr[21]", u_dut.instr, 32'h00b02023);
                end
                22: begin
                    check_eq32("pc[22]",    u_dut.pc,    32'h00000058);
                    check_eq32("instr[22]", u_dut.instr, 32'h00002b83);
                    // lw should load 0xFFFFFFF0 from mem[0]
                    check_eq32("lw-data",   u_dut.mem_rdata, 32'hFFFFFFF0);
                    check_eq32("lw-wb",     u_dut.wb_data,   32'hFFFFFFF0);
                end
                23: begin
                    check_eq32("pc[23]",    u_dut.pc,    32'h0000005C);
                    check_eq32("instr[23]", u_dut.instr, 32'h00000c03);
                    // lb byte0 = 0xF0, sign-extended = 0xFFFFFFF0
                    check_eq32("lb-data",   u_dut.mem_rdata, 32'hFFFFFFF0);
                end
                24: begin
                    check_eq32("pc[24]",    u_dut.pc,    32'h00000060);
                    check_eq32("instr[24]", u_dut.instr, 32'h00001c83);
                    // lh halfword0 = 0xFFF0, sign-extended = 0xFFFFFFF0
                    check_eq32("lh-data",   u_dut.mem_rdata, 32'hFFFFFFF0);
                end
                25: begin
                    check_eq32("pc[25]",    u_dut.pc,    32'h00000064);
                    check_eq32("instr[25]", u_dut.instr, 32'h00004d03);
                    // lbu byte0 = 0xF0, zero-extended = 0x000000F0
                    check_eq32("lbu-data",  u_dut.mem_rdata, 32'h000000F0);
                end
                26: begin
                    check_eq32("pc[26]",    u_dut.pc,    32'h00000068);
                    check_eq32("instr[26]", u_dut.instr, 32'h00005d83);
                    // lhu halfword0 = 0xFFF0, zero-extended = 0x0000FFF0
                    check_eq32("lhu-data",  u_dut.mem_rdata, 32'h0000FFF0);
                end
                // ============================================
                //  Memory: SB + SH then sub-word loads
                // ============================================
                27: begin
                    check_eq32("pc[27]",    u_dut.pc,    32'h0000006C);
                    check_eq32("instr[27]", u_dut.instr, 32'h001000a3);
                end
                28: begin
                    check_eq32("pc[28]",    u_dut.pc,    32'h00000070);
                    check_eq32("instr[28]", u_dut.instr, 32'h00201123);
                end
                29: begin
                    check_eq32("pc[29]",    u_dut.pc,    32'h00000074);
                    check_eq32("instr[29]", u_dut.instr, 32'h00100e03);
                    // lb byte1 of word[0] = 0x0A, sign-extended = 0x0000000A
                    check_eq32("lb-byte1",  u_dut.mem_rdata, 32'h0000000A);
                end
                30: begin
                    check_eq32("pc[30]",    u_dut.pc,    32'h00000078);
                    check_eq32("instr[30]", u_dut.instr, 32'h00304e83);
                    // lbu byte3 of word[0] = 0x00
                    check_eq32("lbu-byte3", u_dut.mem_rdata, 32'h00000000);
                end
                31: begin
                    check_eq32("pc[31]",    u_dut.pc,    32'h0000007C);
                    check_eq32("instr[31]", u_dut.instr, 32'h00205f03);
                    // lhu halfword1 of word[0] = 0x0003
                    check_eq32("lhu-half1", u_dut.mem_rdata, 32'h00000003);
                end
                // ============================================
                //  Branch: BNE x1,x2 (10!=3) TAKEN -> 0x88
                // ============================================
                32: begin
                    check_eq32("pc[32]",    u_dut.pc,    32'h00000080);
                    check_eq32("instr[32]", u_dut.instr, 32'h00209463);
                    check_eq1 ("bne-taken", u_dut.branch_taken, 1'b1);
                end
                33: begin
                    check_eq32("pc[33]",    u_dut.pc,    32'h00000088);
                    check_eq32("instr[33]", u_dut.instr, 32'h00100f93);
                end
                // ============================================
                //  Branch: BLT x2,x1 (3<10) TAKEN -> 0x94
                // ============================================
                34: begin
                    check_eq32("pc[34]",    u_dut.pc,    32'h0000008C);
                    check_eq32("instr[34]", u_dut.instr, 32'h00114463);
                    check_eq1 ("blt-taken", u_dut.branch_taken, 1'b1);
                end
                35: begin
                    check_eq32("pc[35]",    u_dut.pc,    32'h00000094);
                    check_eq32("instr[35]", u_dut.instr, 32'h00200f93);
                end
                // ============================================
                //  Branch: BGE x1,x2 (10>=3) TAKEN -> 0xA0
                // ============================================
                36: begin
                    check_eq32("pc[36]",    u_dut.pc,    32'h00000098);
                    check_eq32("instr[36]", u_dut.instr, 32'h0020d463);
                    check_eq1 ("bge-taken", u_dut.branch_taken, 1'b1);
                end
                37: begin
                    check_eq32("pc[37]",    u_dut.pc,    32'h000000A0);
                    check_eq32("instr[37]", u_dut.instr, 32'h00300f93);
                end
                // ============================================
                //  Branch: BLTU x2,x1 (3<10u) TAKEN -> 0xAC
                // ============================================
                38: begin
                    check_eq32("pc[38]",    u_dut.pc,    32'h000000A4);
                    check_eq32("instr[38]", u_dut.instr, 32'h00116463);
                    check_eq1 ("bltu-taken",u_dut.branch_taken, 1'b1);
                end
                39: begin
                    check_eq32("pc[39]",    u_dut.pc,    32'h000000AC);
                    check_eq32("instr[39]", u_dut.instr, 32'h00400f93);
                end
                // ============================================
                //  Branch: BGEU x1,x2 (10>=3u) TAKEN -> 0xB8
                // ============================================
                40: begin
                    check_eq32("pc[40]",    u_dut.pc,    32'h000000B0);
                    check_eq32("instr[40]", u_dut.instr, 32'h0020f463);
                    check_eq1 ("bgeu-taken",u_dut.branch_taken, 1'b1);
                end
                41: begin
                    check_eq32("pc[41]",    u_dut.pc,    32'h000000B8);
                    check_eq32("instr[41]", u_dut.instr, 32'h00500f93);
                end
                // ============================================
                //  JAL x5, +8 -> 0xC4 (skip 0xC0)
                // ============================================
                42: begin
                    check_eq32("pc[42]",    u_dut.pc,    32'h000000BC);
                    check_eq32("instr[42]", u_dut.instr, 32'h008002ef);
                    check_eq1 ("jal-jump1", u_dut.jump1, 1'b1);
                end
                43: begin
                    check_eq32("pc[43]",    u_dut.pc,    32'h000000C4);
                    check_eq32("instr[43]", u_dut.instr, 32'h03700213);
                end
                // ============================================
                //  JALR setup + execute
                // ============================================
                44: begin
                    check_eq32("pc[44]",    u_dut.pc,    32'h000000C8);
                    check_eq32("instr[44]", u_dut.instr, 32'h0d400513);
                end
                45: begin
                    check_eq32("pc[45]",    u_dut.pc,    32'h000000CC);
                    check_eq32("instr[45]", u_dut.instr, 32'h00050367);
                    check_eq1 ("jalr-jump2",u_dut.jump2, 1'b1);
                end
                46: begin
                    check_eq32("pc[46]",    u_dut.pc,    32'h000000D4);
                    check_eq32("instr[46]", u_dut.instr, 32'h04200213);
                end
                // ============================================
                //  LUI + AUIPC
                // ============================================
                47: begin
                    check_eq32("pc[47]",    u_dut.pc,    32'h000000D8);
                    check_eq32("instr[47]", u_dut.instr, 32'h123453b7);
                end
                48: begin
                    check_eq32("pc[48]",    u_dut.pc,    32'h000000DC);
                    check_eq32("instr[48]", u_dut.instr, 32'h00001417);
                end
                // ============================================
                //  Final register check (after all instructions)
                // ============================================
                49: begin
                    check_eq32("x1",  u_dut.u_regfile.registers[1],  32'd10);
                    check_eq32("x2",  u_dut.u_regfile.registers[2],  32'd3);
                    check_eq32("x3",  u_dut.u_regfile.registers[3],  32'd13);
                    check_eq32("x4",  u_dut.u_regfile.registers[4],  32'd66);
                    check_eq32("x5",  u_dut.u_regfile.registers[5],  32'h000000C0);
                    check_eq32("x6",  u_dut.u_regfile.registers[6],  32'h000000D0);
                    check_eq32("x7",  u_dut.u_regfile.registers[7],  32'h12345000);
                    check_eq32("x8",  u_dut.u_regfile.registers[8],  32'h000010DC);
                    check_eq32("x9",  u_dut.u_regfile.registers[9],  32'd1);
                    check_eq32("x10", u_dut.u_regfile.registers[10], 32'd212);
                    check_eq32("x11", u_dut.u_regfile.registers[11], 32'hFFFFFFF0);
                    check_eq32("x12", u_dut.u_regfile.registers[12], 32'hFFFFFFFE);
                    check_eq32("x13", u_dut.u_regfile.registers[13], 32'd0);
                    check_eq32("x14", u_dut.u_regfile.registers[14], 32'd0);
                    check_eq32("x15", u_dut.u_regfile.registers[15], 32'd2);
                    check_eq32("x16", u_dut.u_regfile.registers[16], 32'd15);
                    check_eq32("x17", u_dut.u_regfile.registers[17], 32'd13);
                    check_eq32("x18", u_dut.u_regfile.registers[18], 32'd12);
                    check_eq32("x19", u_dut.u_regfile.registers[19], 32'd2);
                    check_eq32("x20", u_dut.u_regfile.registers[20], 32'hFFFFFFFC);
                    check_eq32("x21", u_dut.u_regfile.registers[21], 32'd1);
                    check_eq32("x22", u_dut.u_regfile.registers[22], 32'd1);
                    check_eq32("x23", u_dut.u_regfile.registers[23], 32'hFFFFFFF0);
                    check_eq32("x24", u_dut.u_regfile.registers[24], 32'hFFFFFFF0);
                    check_eq32("x25", u_dut.u_regfile.registers[25], 32'hFFFFFFF0);
                    check_eq32("x26", u_dut.u_regfile.registers[26], 32'h000000F0);
                    check_eq32("x27", u_dut.u_regfile.registers[27], 32'h0000FFF0);
                    check_eq32("x28", u_dut.u_regfile.registers[28], 32'h0000000A);
                    check_eq32("x29", u_dut.u_regfile.registers[29], 32'h00000000);
                    check_eq32("x30", u_dut.u_regfile.registers[30], 32'h00000003);
                    check_eq32("x31", u_dut.u_regfile.registers[31], 32'd5);
                end
                default: ;
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

        // 3 reset cycles + 50 instruction cycles + margin
        repeat (70) @(posedge clk);

        if (errors == 0) begin
            $display("PASS: all checks passed");
        end else begin
            $display("FAIL: %0d check(s) failed", errors);
        end

        $finish;
    end

endmodule