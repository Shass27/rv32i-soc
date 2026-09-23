// rv32i_asm.vh — RV32I instruction encoders for testbenches.
// Include inside a module. Pure functions, no hierarchical references.
//
// Argument order follows the assembly text, except stores and branches
// where the register reading order is (base/rs1, src/rs2, imm):
//   ADDI(rd, rs1, imm)     LW(rd, rs1, imm)     LUI(rd, imm20)
//   SW(rs1, rs2, imm)      BNE(rs1, rs2, off)   JAL(rd, off)
// Branch/jump offsets are in bytes, relative to the instruction itself.

// ---- register names ----
localparam [4:0] x0  = 5'd0,  x1  = 5'd1,  x2  = 5'd2,  x3  = 5'd3,
                 x4  = 5'd4,  x5  = 5'd5,  x6  = 5'd6,  x7  = 5'd7,
                 x8  = 5'd8,  x9  = 5'd9,  x10 = 5'd10, x11 = 5'd11,
                 x12 = 5'd12, x13 = 5'd13, x14 = 5'd14, x15 = 5'd15,
                 x16 = 5'd16, x17 = 5'd17, x18 = 5'd18, x19 = 5'd19,
                 x20 = 5'd20, x21 = 5'd21, x22 = 5'd22, x23 = 5'd23,
                 x24 = 5'd24, x25 = 5'd25, x26 = 5'd26, x27 = 5'd27,
                 x28 = 5'd28, x29 = 5'd29, x30 = 5'd30, x31 = 5'd31;

// ---- opcodes ----
localparam [6:0] OPC_LOAD   = 7'b0000011,
                 OPC_IMM    = 7'b0010011,
                 OPC_STORE  = 7'b0100011,
                 OPC_LUI    = 7'b0110111,
                 OPC_BRANCH = 7'b1100011,
                 OPC_JAL    = 7'b1101111;

// ---- format encoders ----
function [31:0] enc_i (input [11:0] imm, input [4:0] rs1, input [2:0] f3, input [4:0] rd, input [6:0] op);
    enc_i = {imm, rs1, f3, rd, op};
endfunction

function [31:0] enc_s (input [11:0] imm, input [4:0] rs2, input [4:0] rs1, input [2:0] f3, input [6:0] op);
    enc_s = {imm[11:5], rs2, rs1, f3, imm[4:0], op};
endfunction

function [31:0] enc_b (input [12:0] off, input [4:0] rs2, input [4:0] rs1, input [2:0] f3, input [6:0] op);
    enc_b = {off[12], off[10:5], rs2, rs1, f3, off[4:1], off[11], op};
endfunction

function [31:0] enc_u (input [19:0] imm, input [4:0] rd, input [6:0] op);
    enc_u = {imm, rd, op};
endfunction

function [31:0] enc_j (input [20:0] off, input [4:0] rd, input [6:0] op);
    enc_j = {off[20], off[10:1], off[11], off[19:12], rd, op};
endfunction

// ---- mnemonics used by the drivers ----
function [31:0] LUI  (input [4:0] rd, input [19:0] imm);            LUI  = enc_u(imm, rd, OPC_LUI);                  endfunction
function [31:0] ADDI (input [4:0] rd, input [4:0] rs1, input [11:0] imm); ADDI = enc_i(imm, rs1, 3'b000, rd, OPC_IMM);  endfunction
function [31:0] ANDI (input [4:0] rd, input [4:0] rs1, input [11:0] imm); ANDI = enc_i(imm, rs1, 3'b111, rd, OPC_IMM);  endfunction
function [31:0] LW   (input [4:0] rd, input [4:0] rs1, input [11:0] imm); LW   = enc_i(imm, rs1, 3'b010, rd, OPC_LOAD); endfunction
function [31:0] SW   (input [4:0] rs1, input [4:0] rs2, input [11:0] imm); SW  = enc_s(imm, rs2, rs1, 3'b010, OPC_STORE); endfunction
function [31:0] BEQ  (input [4:0] rs1, input [4:0] rs2, input [12:0] off); BEQ  = enc_b(off, rs2, rs1, 3'b000, OPC_BRANCH); endfunction
function [31:0] BNE  (input [4:0] rs1, input [4:0] rs2, input [12:0] off); BNE  = enc_b(off, rs2, rs1, 3'b001, OPC_BRANCH); endfunction
function [31:0] JAL  (input [4:0] rd, input [20:0] off);            JAL  = enc_j(off, rd, OPC_JAL);                  endfunction
