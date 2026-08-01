module writeback_mux(
    input  wire        MemToReg,
    input  wire [31:0] alu_result,
    input  wire [31:0] mem_rdata,
    output wire [31:0] wb_data
);

    assign wb_data = (MemToReg) ? mem_rdata : alu_result;

endmodule