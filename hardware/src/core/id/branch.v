module branch_logic(
    input wire branch,
    input wire alu_zero,
    input  wire [31:0] pc,
    output wire branch_taken,
    output wire [31:0] target
);
    assign branch_taken = alu_zero & branch;
    assign target = branch_taken ? branch_taken + pc : 32'b0;

endmodule
