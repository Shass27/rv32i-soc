module branch_logic(
    input wire branch,
    input wire alu_zero,
    output wire target
);
    wire branch_target;
    assign branch_target = alu_zero & branch;
    assign target = branch_target;

endmodule
