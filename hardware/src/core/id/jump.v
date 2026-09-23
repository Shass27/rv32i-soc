module jump_logic (
    input  wire        jump1,
    input  wire        jump2,
    input  wire [31:0] pc,
    input  wire [31:0] imm,
    input  wire [31:0] ReadData1,

    output wire [31:0] target,
    output wire [31:0] jump_ret_addr
);
    wire [31:0] jump_target;
    assign jump_target = jump1 ? (pc + imm) : (jump2 ? ReadData1 + imm : 32'b0);
    assign target = jump_target;

    assign jump_ret_addr = pc + 4;

endmodule
