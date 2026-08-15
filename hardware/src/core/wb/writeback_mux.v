module writeback_mux(
    input  wire MemToReg,
    input wire jump1,
    input wire jump2,
    input  wire [31:0] alu_result,
    input  wire [31:0] mem_rdata, //Data Read from memory
    input  wire [31:0] jump_ret_addr, 
    output wire [31:0] wb_data
);
 
    assign wb_data = ((jump1) | (jump2)) ? jump_ret_addr :
                     (MemToReg) ? mem_rdata :
                     alu_result;
endmodule 