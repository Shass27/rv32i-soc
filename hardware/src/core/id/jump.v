module jump_logic (
    input  wire        jump,
    input  wire [31:0] pc,
    input  wire [31:0] imm,

    output wire [31:0]target
);
    wire [31:0] jump_target;
    assign jump_target = jump ? (pc + imm) : 32'b0;
    assign target = jump_target;

endmodule
