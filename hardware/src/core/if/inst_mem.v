module inst_mem(
      input [31:0] pc, output [31:0] instr
    );
    reg [31:0] mem [0:1023];
    initial begin
    $readmemh("program.hex",mem);
    end
    assign instr = mem[pc>>2]; // shift 2 bits to the right as we are using word addressing
endmodule