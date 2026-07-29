`timescale 1ns/1ps

module tb_control_unit;

    reg  [6:0] opcode;

    wire       RegWrite;
    wire       ALUSrc;
    wire       MemRead;
    wire       MemWrite;
    wire       MemToReg;
    wire       branch;
    wire       jump;
    wire [1:0] ALUOp;

    control_unit dut (
        .opcode   (opcode),
        .RegWrite (RegWrite),
        .ALUSrc   (ALUSrc),
        .MemRead  (MemRead),
        .MemWrite (MemWrite),
        .MemToReg (MemToReg),
        .branch   (branch),
        .jump     (jump),
        .ALUOp    (ALUOp)
    );

    task check;
        input [6:0]  op;
        input        exp_RegWrite, exp_ALUSrc, exp_MemRead;
        input        exp_MemWrite, exp_MemToReg, exp_branch, exp_jump;
        input [1:0]  exp_ALUOp;
        input [63:0] label;   // for printing string
        begin
            opcode = op;
            #10;

            if (RegWrite !== exp_RegWrite) $error("%s: RegWrite  got %b, want %b", label, RegWrite,  exp_RegWrite);
            if (ALUSrc   !== exp_ALUSrc)   $error("%s: ALUSrc    got %b, want %b", label, ALUSrc,    exp_ALUSrc);
            if (MemRead  !== exp_MemRead)  $error("%s: MemRead   got %b, want %b", label, MemRead,   exp_MemRead);
            if (MemWrite !== exp_MemWrite) $error("%s: MemWrite  got %b, want %b", label, MemWrite,  exp_MemWrite);
            if (MemToReg !== exp_MemToReg) $error("%s: MemToReg  got %b, want %b", label, MemToReg,  exp_MemToReg);
            if (branch   !== exp_branch)   $error("%s: branch    got %b, want %b", label, branch,    exp_branch);
            if (jump     !== exp_jump)     $error("%s: jump      got %b, want %b", label, jump,      exp_jump);
            if (ALUOp    !== exp_ALUOp)    $error("%s: ALUOp     got %b, want %b", label, ALUOp,     exp_ALUOp);

            $display("PASS: %s", label);
        end
    endtask

    initial begin
        $dumpfile("tb_control_unit.vcd");  // for waveform viewer
        $dumpvars(0, tb_control_unit);

        check(7'b0110011,        1,  0,  0,  0,  0,   0,  0,  2'b10,  "R-type");
        check(7'b0010011,        1,  1,  0,  0,  0,   0,  0,  2'b10,  "ADDI  ");
        check(7'b0000011,        1,  1,  1,  0,  1,   0,  0,  2'b00,  "LW    ");
        check(7'b0100011,        0,  1,  0,  1,  0,   0,  0,  2'b00,  "SW    ");
        check(7'b1100011,        0,  0,  0,  0,  0,   1,  0,  2'b01,  "BEQ   ");
        check(7'b1101111,        1,  0,  0,  0,  0,   0,  1,  2'b11,  "JAL   ");

        $display("── all tests done ──");
        $finish;
    end

endmodule
