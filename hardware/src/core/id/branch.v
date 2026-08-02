module branch_logic(
    input wire branch,
    input wire alu_zero,
    input  wire [31:0] pc,
<<<<<<< HEAD
=======
    input  wire [31:0] imm,
>>>>>>> origin/main
    output wire branch_taken,
    output wire [31:0] target
);
    assign branch_taken = alu_zero & branch;
<<<<<<< HEAD
    assign target = branch_taken ? branch_taken + pc : 32'b0;
=======
    assign target = branch_taken ? imm + pc : 32'b0;
>>>>>>> origin/main

endmodule
