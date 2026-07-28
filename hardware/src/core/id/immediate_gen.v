module imm_gen (
    input wire [31:0] instruction,
    output reg [31:0] imm_out
);
    
    wire [6:0] opcode  = instruction[6:0];

    localparam ADDI  = 7'b0010011; // ADDI
    localparam LOAD   = 7'b0000011; // LW
    localparam STORE  = 7'b0100011; // SW
    localparam BRANCH = 7'b1100011; // BEQ
    localparam JAL    = 7'b1101111; // JAL

    always @(*) begin
        case (opcode)
            ADDI, LOAD:
                // I-type immediate
                imm_out  = {{20{instruction[31]}}, instruction[31:20]};

            STORE:
                // S-type immediate
                imm_out = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            
            BRANCH:
                // SB-type immediate
                imm_out = {{20{instruction[31]}}, instruction[7], instruction[30:25], instruction[11:8], 1'b0};
            
            JAL:
                // UJ-type immediate
                imm_out = {{12{instruction[31]}}, instruction[19:12], instruction[20], instruction[30:21], 1'b0};
            default:
                imm_out = 32'b0;
        endcase
    end

endmodule
