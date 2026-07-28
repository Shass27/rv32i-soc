
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
    
    
endmodule
