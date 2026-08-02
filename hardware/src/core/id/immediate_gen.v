module imm_gen (
    input wire [31:0] instr,
    output reg [31:0] imm
);
    
    wire [6:0] opcode  = instr[6:0];

    localparam ADDI  = 7'b0010011; // ADDI
    localparam LOAD   = 7'b0000011; // LW
    localparam STORE  = 7'b0100011; // SW
    localparam BRANCH = 7'b1100011; // BEQ
    localparam JAL    = 7'b1101111; // JAL

    always @(*) begin
        case (opcode)
            ADDI, LOAD:
                // I-type immediate
                imm  = {{20{instr[31]}}, instr[31:20]};

            STORE:
                // S-type immediate
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            
            BRANCH:
                // SB-type immediate
                imm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
            
            JAL:
                // UJ-type immediate
                imm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
            default:
                imm = 32'b0;
        endcase
    end

endmodule
