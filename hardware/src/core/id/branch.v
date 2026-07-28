module branch_logic(
    input wire branch,
    input wire alu_zero,
    output wire branch_taken
);

    assign branch_taken = alu_zero & branch;

endmodule
