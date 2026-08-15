module program_counter (
    input wire        clk,
    input wire        reset,
    input wire        branch_taken,
    input wire        jump1,
    input wire        jump2,       
    input wire [31:0] target,   // the branch/jump target address
    output reg  [31:0] pc
);
    wire pc_sel;
    assign pc_sel = branch_taken | jump1 | jump2;
    always @(posedge clk or posedge reset) begin
        if (reset)
            pc <= 32'b0;
        else if (pc_sel)
            pc <= target;
        else
            pc <= pc + 4;
    end

endmodule
