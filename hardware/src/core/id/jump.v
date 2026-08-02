module jump_logic (
    input  wire        jump,
    input  wire [31:0] pc,
    input  wire [31:0] imm,

<<<<<<< HEAD
    output wire [31:0]target
=======
    output wire [31:0] target,
    output wire [31:0] jump_ret_addr
>>>>>>> origin/main
);
    wire [31:0] jump_target;
    assign jump_target = jump ? (pc + imm) : 32'b0;
    assign target = jump_target;

<<<<<<< HEAD
=======
    assign jump_ret_addr = pc + 4;

>>>>>>> origin/main
endmodule
