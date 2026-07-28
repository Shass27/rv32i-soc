
module data_memory #(
    parameter MEM_SIZE = 1024
) (
    input wire clk,
    input wire i_we,
    input wire [31:0] i_data,
    input wire [$clog2(MEM_SIZE)-1:0] i_addr,
    output wire [31:0] o_data
);
    
    reg [31:0] memory [0:MEM_SIZE-1];

    initial begin
       $readmemh("data.hex",memory);
    end

  assign o_data = memory[i_addr>>2]; //asynchronous read
  always @ (posedge clk) begin       //synchronous write
    if(i_we) begin
      memory[i_addr>>2] <= i_data;
    end
  end
    

endmodule