module data_memory #(
    parameter MEM_SIZE = 1024
)(
    input  wire        clk,
    input  wire        MemWrite,
    input  wire [31:0] mem_addr,
    input  wire [31:0] rs2_data,
    output wire [31:0] mem_rdata
);

    reg [31:0] memory [0:MEM_SIZE-1];

    initial begin
        $readmemh("data.hex", memory);
    end

    // Asynchronous Read
    assign mem_rdata = memory[mem_addr >> 2];

    // Synchronous Write
    always @(posedge clk) begin
        if (MemWrite)
            memory[mem_addr >> 2] <= rs2_data;
    end

endmodule