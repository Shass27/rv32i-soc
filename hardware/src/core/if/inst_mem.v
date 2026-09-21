module inst_mem #(
      parameter PROG_FILE = "hardware/src/core/if/program.hex" // override to run another image, e.g. program2.hex
    )(
      input [31:0] i_addr, output [31:0] o_inst
    );
    reg [31:0] mem [0:4096];
    initial begin
    $readmemh(PROG_FILE,mem);
    end
    assign o_inst = mem[i_addr>>2]; // shift 2 bits to the right as we are using word addressing
endmodule
