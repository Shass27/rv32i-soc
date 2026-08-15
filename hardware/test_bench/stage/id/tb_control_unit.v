`timescale 1ns/1ps

module tb_control_unit;

    reg  [31:0] instr;

    wire       RegWrite;
    wire       ALUSrc;
    wire       ALUSrcA;
    wire       MemRead;
    wire       MemWrite;
    wire       MemToReg;
    wire       branch;
    wire       jump1;
    wire       jump2;
    wire [1:0] ALUOp;

    control_unit dut (
        .instr    (instr),
        .RegWrite (RegWrite),
        .ALUSrc   (ALUSrc),
        .ALUSrcA  (ALUSrcA),
        .MemRead  (MemRead),
        .MemWrite (MemWrite),
        .MemToReg (MemToReg),
        .branch   (branch),
        .jump1    (jump1),
        .jump2    (jump2),
        .ALUOp    (ALUOp)
    );

    task check;
        input [31:0] op_instr;
        input        exp_RegWrite, exp_ALUSrc, exp_ALUSrcA, exp_MemRead;
        input        exp_MemWrite, exp_MemToReg, exp_branch, exp_jump1, exp_jump2;
        input [1:0]  exp_ALUOp;
        input [63:0] label;
        begin
            instr = op_instr;
            #10;

            if (RegWrite !== exp_RegWrite) $error("%s: RegWrite got %b, want %b", label, RegWrite, exp_RegWrite);
            if (ALUSrc   !== exp_ALUSrc)   $error("%s: ALUSrc   got %b, want %b", label, ALUSrc,   exp_ALUSrc);
            if (ALUSrcA  !== exp_ALUSrcA)  $error("%s: ALUSrcA  got %b, want %b", label, ALUSrcA,  exp_ALUSrcA);
            if (MemRead  !== exp_MemRead)  $error("%s: MemRead  got %b, want %b", label, MemRead,  exp_MemRead);
            if (MemWrite !== exp_MemWrite) $error("%s: MemWrite got %b, want %b", label, MemWrite, exp_MemWrite);
            if (MemToReg !== exp_MemToReg) $error("%s: MemToReg got %b, want %b", label, MemToReg, exp_MemToReg);
            if (branch   !== exp_branch)   $error("%s: branch   got %b, want %b", label, branch,   exp_branch);
            if (jump1    !== exp_jump1)    $error("%s: jump1    got %b, want %b", label, jump1,    exp_jump1);
            if (jump2    !== exp_jump2)    $error("%s: jump2    got %b, want %b", label, jump2,    exp_jump2);
            if (ALUOp    !== exp_ALUOp)    $error("%s: ALUOp    got %b, want %b", label, ALUOp,    exp_ALUOp);

            $display("PASS: %s", label);
        end
    endtask

    initial begin
        $dumpfile("tb_control_unit.vcd");
        $dumpvars(0, tb_control_unit);

        check({25'd0, 7'b0110011}, 1, 0, 0, 0, 0, 0, 0, 0, 0, 2'b10, "R-type");
        check({25'd0, 7'b0010011}, 1, 1, 0, 0, 0, 0, 0, 0, 0, 2'b10, "ADDI   ");
        check({25'd0, 7'b0000011}, 1, 1, 0, 1, 0, 1, 0, 0, 0, 2'b00, "LW     ");
        check({25'd0, 7'b0100011}, 0, 1, 0, 0, 1, 0, 0, 0, 0, 2'b00, "SW     ");
        check({25'd0, 7'b1100011}, 0, 0, 0, 0, 0, 0, 1, 0, 0, 2'b01, "BEQ    ");
        check({25'd0, 7'b1101111}, 1, 0, 0, 0, 0, 0, 0, 1, 0, 2'b00, "JAL    ");
        check({25'd0, 7'b1100111}, 1, 0, 0, 0, 0, 0, 0, 0, 1, 2'b00, "JALR   ");
        check({25'd0, 7'b0110111}, 1, 1, 0, 0, 0, 0, 0, 0, 0, 2'b00, "LUI    ");
        check({25'd0, 7'b0010111}, 1, 1, 1, 0, 0, 0, 0, 0, 0, 2'b00, "AUIPC  ");

        $display("── all tests done ──");
        $finish;
    end

endmodule
