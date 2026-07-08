module control_unit (
    input  [6:0] opcode,    
    
    output reg       RegWrite,
    output reg       ALUSrc,
    output reg       MemRead,
    output reg       MemWrite,
    output reg       MemToReg,
    output reg       branch,
    output reg       jump,
    output reg [1:0] ALUOp // 00 - force ADD, 01 - force SUB, 10 - R & I type, 11 - JAL (Jump)
);

    localparam R_AS = 7'b0110011; // ADD, SUB
    localparam ADDI  = 7'b0010011; // ADDI
    localparam LOAD   = 7'b0000011; // LW
    localparam STORE  = 7'b0100011; // SW
    localparam BRANCH = 7'b1100011; // BEQ
    localparam JAL    = 7'b1101111; // JAL

    always @(*) begin
        // defaults
        RegWrite = 1'b0;
        ALUSrc = 1'b0;
        MemRead = 1'b0;
        MemWrite = 1'b0;
        MemToReg = 1'b0;
        branch = 1'b0;
        jump = 1'b0;
        ALUOp = 2'b00;

        case (opcode)
            R_AS : begin
                RegWrite = 1'b1;
                ALUOp = 2'b10;
            end
            ADDI : begin
                RegWrite = 1'b1;
                ALUSrc = 1'b1;
                ALUOp = 2'b10;
            end
            LOAD : begin
                RegWrite = 1'b1;
                ALUSrc = 1'b1;
                MemRead = 1'b1;
                MemToReg = 1'b1;
            end
            STORE : begin
                ALUSrc = 1'b1;
                MemWrite = 1'b1;
            end 
            BRANCH : begin
                branch = 1'b1;
                ALUOp = 2'b01;
            end
            JAL : begin
                jump = 1'b1;
                RegWrite = 1'b1;
                ALUOp = 2'b11;
            end
            default: ;
        endcase
    end

endmodule
