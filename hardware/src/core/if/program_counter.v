<<<<<<< HEAD
module program_counter (
    input wire        clk,
    input wire        reset,
    input wire        stall,
    input wire        branch_taken,
    input wire        jump,       
    input wire [31:0] target,   // the branch/jump target address
    output reg  [31:0] pc
);
    wire pc_sel;
    assign pc_sel = branch_taken | jump;
    always @(posedge clk or posedge reset) begin
        if (reset)
            pc <= 32'b0;
        else if (stall)
            pc <= pc;
        else if (pc_sel)
            pc <= target;
        else
            pc <= pc + 4;
    end

=======

module program_counter(
       input clk, input pc_src, input reset_high, input [31:0] target, input stall, output reg [31:0] pc
    );
    always @(posedge clk or posedge reset_high) begin
    if(reset_high) begin
    pc <= 32'b0;
    end
    else begin
    if(stall) begin
    pc <= pc;
    end
    else begin
    pc <=  (pc_src) ? target : pc+4;  //pc_src-program counter source-decides if branch/jump has to happen
    end
    end
    end
    
    
>>>>>>> 67c45e14c1987f2fcb1dfa84bfe05d54cf8170b5
endmodule
