module mem_stage(
    input  wire        clk,
    input  wire        MemRead,
    input  wire        MemWrite,
    input  wire        MemToReg,

    input  wire [31:0] alu_result,
    input  wire [31:0] rs2_data,

    output wire [31:0] mem_rdata,
    output wire [31:0] wb_data
);

    data_memory dmem (
        .clk(clk),
        .MemWrite(MemWrite),
        .mem_addr(alu_result),
        .rs2_data(rs2_data),
        .mem_rdata(mem_rdata)
    );

    writeback_mux wb_mux (
        .MemToReg(MemToReg),
        .alu_result(alu_result),
        .mem_rdata(mem_rdata),
        .wb_data(wb_data)
    );

endmodule