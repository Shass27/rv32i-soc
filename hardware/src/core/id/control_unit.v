module control_unit (
    input wire [31:0] instr,

    output reg       RegWrite,
    output reg       ALUSrc,
    output reg       MemRead,
    output reg       MemWrite,
    output reg       MemToReg,
    output reg       branch,
    output reg       jump1,
    output reg       jump2,
    output reg [1:0] ALUOp // 00 - force ADD, 01 - force SUB, 10 - R & I type, 11 - JAL (Jump)
);

    wire [6:0] opcode  = instr[6:0];

    localparam OP_REG  = 7'b0110011; // R-type : AND OR XOR SLL SRL SRA SLT SLTU (+ ADD SUB)
    localparam IMM  = 7'b0010011; // I-type : ANDI ORI XORI SLLI SRLI SRAI SLTI SLTIU (+ ADDI)
    localparam LOAD    = 7'b0000011; // I-type : LB LH LW LBU LHU
    localparam STORE   = 7'b0100011; // S-type : SB SH SW
    localparam BRANCH  = 7'b1100011; // B-type : BEQ BNE BLT BGE BLTU BGEU
    localparam JAL     = 7'b1101111; // J-type : JAL
    localparam JALR    = 7'b1100111; // I-type : JALR

    always @(*) begin
        // defaults
        RegWrite = 1'b0;
        ALUSrc = 1'b0;
        MemRead = 1'b0;
        MemWrite = 1'b0;
        MemToReg = 1'b0;
        branch = 1'b0;
        jump1 = 1'b0;
        jump2 = 1'b0;
        ALUOp = 2'b00;

        case (opcode)
            OP_REG : begin
                RegWrite = 1'b1;
                ALUOp    = 2'b10;
            end
            IMM : begin
                RegWrite = 1'b1;
                ALUSrc   = 1'b1;
                ALUOp    = 2'b10;
            end
            LOAD : begin
                RegWrite = 1'b1;
                ALUSrc   = 1'b1;
                MemRead  = 1'b1;
                MemToReg = 1'b1;
            end
            STORE : begin
                ALUSrc   = 1'b1;
                MemWrite = 1'b1;
            end
            BRANCH : begin
                branch = 1'b1;
                ALUOp  = 2'b01; // force SUB for comparison
            end
            JAL : begin
                jump1 = 1'b1;
                RegWrite = 1'b1;
            end
            JALR : begin
                RegWrite = 1'b1;
                jump2 = 1'b1;
            end
            default: ;
        endcase
    end

endmodule
