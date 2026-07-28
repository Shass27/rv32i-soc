`timescale 1ns/1ps

module tb_immediate_gen;

    reg  [31:0] instruction;
    wire [31:0] imm_out;

    imm_gen dut (
        .instruction (instruction),
        .imm_out     (imm_out)
    );

    localparam [31:0] INST_ADDI    = 32'b00000000010100000000000010010011;
    localparam [31:0] INST_LW      = 32'b11111111110000011010000100000011;
    localparam [31:0] INST_SW      = 32'b00000000010100011010010000100011;
    localparam [31:0] INST_BEQ     = 32'b00000000010100011000100001100011;
    localparam [31:0] INST_JAL     = 32'b00000000100000000000000011101111;
    localparam [31:0] INST_DEFAULT = 32'b00000000000000000000000001111111;

    task check;
        input [31:0] instr;
        input [31:0] expected_imm;
        input [63:0] label;
        begin
            instruction = instr;
            #10;

            if (imm_out !== expected_imm) begin
                $error("%s: imm_out got %h, want %h", label, imm_out, expected_imm);
            end else begin
                $display("PASS: %s -> imm_out=%h", label, imm_out);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_immediate_gen.vcd");
        $dumpvars(0, tb_immediate_gen);

        check(INST_ADDI,    32'h0000_0005, "ADDI  +5");
        check(INST_LW,      32'hffff_fffc, "LW    -4");
        check(INST_SW,      32'h0000_0008, "SW    +8");
        check(INST_BEQ,     32'h0000_0010, "BEQ   +16");
        check(INST_JAL,     32'h0000_0008, "JAL   +8");
        check(INST_DEFAULT, 32'h0000_0000, "DEFAULT");

        $display("── all immediate_gen tests done ──");
        $finish;
    end

endmodule