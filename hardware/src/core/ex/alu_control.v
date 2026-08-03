module alu_control(

    input [31:0] instr,
    input [1:0] ALUOp,

    output reg [4:0] rs1,
    output reg [4:0] rs2,
    output reg [4:0] rd,
    output reg [2:0] funct3,
    output reg [6:0] funct7,

    output reg [3:0] ALUControl
);
wire [6:0] opcode;

    localparam R_AS = 7'b0110011; // ADD, SUB
    localparam ADDI  = 7'b0010011; // ADDI
    localparam LOAD   = 7'b0000011; // LW
    localparam STORE  = 7'b0100011; // SW
    localparam BRANCH = 7'b1100011; // BEQ
    localparam JAL    = 7'b1101111; // JAL
    assign opcode = instr[6:0];

always @(*) begin

    rs1    = 5'd0;
    rs2    = 5'd0;
    rd     = 5'd0;
    funct3 = 3'd0;
    funct7 = 7'd0;

    case(opcode)

        R_AS: begin
            rs1    = instr[19:15];
            rs2    = instr[24:20];
            rd     = instr[11:7];
            funct3 = instr[14:12];
            funct7 = instr[31:25];
        end

        ADDI,
        LOAD: begin
            rs1    = instr[19:15];
            rd     = instr[11:7];
            funct3 = instr[14:12];
        end

        STORE,
        BRANCH: begin
            rs1    = instr[19:15];
            rs2    = instr[24:20];
            funct3 = instr[14:12];
        end

        JAL: begin
            rd = instr[11:7];
        end
    endcase
end






// ALUOp Encoding
localparam ALU_ADD    = 2'b00;//Force ADD
localparam ALU_SUB    = 2'b01;// Force SUB
localparam ALU_DECODE = 2'b10;// Should decide the op based on funct3,funct7
localparam ALU_JAL    = 2'b11;//JAL

// ALUControl Encoding ->for the alu module to know what to perform
localparam ADD = 4'b0000;
localparam SUB = 4'b0001;

always @(*) 
begin
    case(ALUOp)

        ALU_ADD:
            ALUControl = ADD; //used for LW,SW

        ALU_SUB:
            ALUControl = SUB;//used for BEQ

    ALU_DECODE: begin
    if (funct3 == 3'b000) begin
        if (funct7 == 7'b0100000)
            ALUControl = SUB;   // SUB
        else
            ALUControl = ADD;   // ADD / ADDI
    end
    else begin
        ALUControl = ADD;       // Safety fallback
    end
end

ALU_JAL:
    ALUControl = ADD;          

        default:
            ALUControl = ADD;// Default to ADD for invalid/unknown ALUOp

    endcase
end
endmodule
