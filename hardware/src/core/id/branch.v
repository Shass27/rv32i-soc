module branch_logic(
    input wire branch,
    input  wire [31:0] pc,
    input  wire [31:0] imm,
    input wire [31:0] ReadData1,
    input wire [31:0] ReadData2,
    input wire [2:0] funct3,
    output wire branch_taken,
    output wire [31:0] target
);
    wire eq, s_lesser, u_lesser;
    assign eq = (ReadData1 == ReadData2) ? 1'b1 : 1'b0;
    assign s_lesser = ($signed(ReadData1) < $signed(ReadData2)) ? 1'b1 : 1'b0;
    assign u_lesser = (ReadData1 < ReadData2) ? 1'b1 : 1'b0;

    
    assign branch_taken = funct3==3'b000 ? eq & branch           // BEQ
                        : funct3==3'b001 ? ~eq & branch          // BNE
                        : funct3==3'b100 ? s_lesser & branch     // BLT
                        : funct3==3'b101 ? ~s_lesser & branch    // BGE
                        : funct3==3'b110 ? u_lesser & branch     // BLTU
                        : funct3==3'b111 ? ~u_lesser & branch    // BGEU
                        : 1'b0;


    assign target = branch_taken ? imm + pc : 32'b0;

endmodule
