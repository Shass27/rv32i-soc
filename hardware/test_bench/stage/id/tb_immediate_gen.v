`timescale 1ns/1ps

module tb_immediate_gen;

    reg  [31:0] instruction;
    wire [31:0] imm;

    imm_gen dut (
        .instr (instruction),
        .imm   (imm)
    );

    // I-type ALU (opcode=0010011): ADDI x1, x0, +5
    localparam [31:0] INST_ADDI    = 32'b0000_0000_0101_0000_0000_0000_1001_0011;
    // I-type ALU: SLTI x2, x0, -1  (sign-extension check)
    localparam [31:0] INST_SLTI    = 32'b1111_1111_1111_0000_0010_0001_0001_0011;
    // I-type LOAD (opcode=0000011): LW x2, -4(x3)
    localparam [31:0] INST_LW      = 32'b1111_1111_1100_0001_1010_0001_0000_0011;
    // S-type STORE (opcode=0100011): SW x5, 8(x3)
    localparam [31:0] INST_SW      = 32'b0000_0000_0101_0001_1010_0100_0010_0011;
    // B-type BRANCH (opcode=1100011): BEQ x3, x5, +16
    localparam [31:0] INST_BEQ     = 32'b0000_0000_0101_0001_1000_1000_0110_0011;
    // J-type JAL (opcode=1101111): JAL x0, +8
    localparam [31:0] INST_JAL     = 32'b0000_0000_1000_0000_0000_0000_0110_1111;
    // U-type LUI (opcode=0110111): LUI x1, 0x12345
    localparam [31:0] INST_LUI     = 32'b0001_0010_0011_0100_0101_0000_0011_0111;
    // U-type AUIPC (opcode=0010111): AUIPC x2, 0xABCDE
    localparam [31:0] INST_AUIPC   = 32'b1010_1011_1100_1101_1110_0001_0001_0111;
    // Unknown opcode -> imm = 0
    localparam [31:0] INST_DEFAULT = 32'b0000_0000_0000_0000_0000_0000_0111_1111;

    task check;
        input [31:0]  instr;
        input [31:0]  expected_imm;
        input [127:0] label;
        begin
            instruction = instr;
            #10;
            if (imm !== expected_imm)
                $error("%s: got imm=%h, want %h", label, imm, expected_imm);
            else
                $display("PASS: %s", label);
        end
    endtask

    initial begin
        $dumpfile("tb_immediate_gen.vcd");
        $dumpvars(0, tb_immediate_gen);

        check(INST_ADDI,    32'h0000_0005, "ADDI   +5    ");
        check(INST_SLTI,    32'hffff_ffff, "SLTI   -1    ");
        check(INST_LW,      32'hffff_fffc, "LW     -4    ");
        check(INST_SW,      32'h0000_0008, "SW     +8    ");
        check(INST_BEQ,     32'h0000_0010, "BEQ    +16   ");
        check(INST_JAL,     32'h0000_0008, "JAL    +8    ");
        check(INST_LUI,     32'h1234_5000, "LUI  0x12345 ");
        check(INST_AUIPC,   32'hABCD_E000, "AUIPC 0xABCDE");
        check(INST_DEFAULT, 32'h0000_0000, "DEFAULT      ");

        $display("── all immediate_gen tests done ──");
        $finish;
    end

endmodule