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

localparam R_TYPE      = 7'b0110011; // R-type ALU
localparam I_TYPE      = 7'b0010011; // I-type ALU
localparam LOAD        = 7'b0000011; // I-type Load (LW)
localparam STORE       = 7'b0100011; // S-type Store (SW)
localparam BRANCH      = 7'b1100011; // B-type Branch (BEQ)
localparam JAL         = 7'b1101111; // J-type Jump
localparam LUI   = 7'b0110111; // U-type
localparam AUIPC = 7'b0010111; // U-type
 assign opcode = instr[6:0];

always @(*) begin

    rs1    = 5'd0;
    rs2    = 5'd0;
    rd     = 5'd0;
    funct3 = 3'd0;
    funct7 = 7'd0;

 case(opcode)
 R_TYPE: begin
      rs1    = instr[19:15];
      rs2    = instr[24:20];
      rd     = instr[11:7];
      funct3 = instr[14:12];
      funct7 = instr[31:25];
     end 

I_TYPE: begin
    rs1    = instr[19:15];
    rd     = instr[11:7];
    funct3 = instr[14:12];
    
end

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
LUI,
 AUIPC: begin
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
localparam AND = 4'b0010;
localparam OR  = 4'b0011;
localparam XOR = 4'b0100;
localparam SLL = 4'b0101;
localparam SRL = 4'b0110;
localparam SRA = 4'b0111;
localparam SLT = 4'b1000;
localparam SLTU =4'b1001;
localparam AUIPC_OP = 4'b1010;
always @(*) 
begin
    case(ALUOp)

       
        ALU_ADD: begin
            if (opcode == 7'b0010111)   // AUIPC
                ALUControl = AUIPC_OP;
            else
                ALUControl = ADD;
        end

        ALU_SUB:
            ALUControl = SUB;//used for BEQ

ALU_DECODE: begin

    case(funct3)

        3'b000: begin
     
           if ((opcode == R_TYPE) && (funct7 == 7'b0100000))
              ALUControl = SUB;
           else
             ALUControl = ADD;
        end

        3'b001: begin
            // SLL
            ALUControl = SLL;
        end

        3'b010: begin
            // SLT
            ALUControl = SLT;
        end

        3'b011: begin
            // SLTU
            ALUControl = SLTU;
        end

        3'b100: begin
            // XOR
            ALUControl = XOR;
        end

      3'b101: begin
    // SRL/SRA and SRLI/SRAI
    if (instr[31:25] == 7'b0100000)
        ALUControl = SRA;
    else
        ALUControl = SRL;
    end

        3'b110: begin
            // OR
            ALUControl = OR;
        end

        3'b111: begin
            // AND
            ALUControl = AND;
        end

        default: begin
            ALUControl = ADD;
        end

    endcase

end

ALU_JAL:
    ALUControl = ADD;  // Compute PC + immediate // Safety fallback   


  default:
  ALUControl = ADD;// Default to ADD for invalid/unknown ALUOp

  endcase
end
endmodule
