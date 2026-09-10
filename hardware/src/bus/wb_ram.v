// wb_ram.v — Wishbone Classic slave RAM
// 32-bit data, 256 words (1 KB), minimal signals (CYC/STB/WE/ACK)
// ACK is combinational (zero wait states)

module wb_ram #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    // Wishbone slave interface
    input  wire                   i_wb_clk,
    input  wire                   i_wb_rst,

    input  wire [ADDR_WIDTH-1:0]  i_wb_adr,   // word address
    input  wire [DATA_WIDTH-1:0]  i_wb_dat,   // write data from master
    input  wire                   i_wb_we,    // 1 = write, 0 = read
    input  wire                   i_wb_stb,   // strobe — valid transfer
    input  wire                   i_wb_cyc,   // bus cycle active

    output wire [DATA_WIDTH-1:0]  o_wb_dat,   // read data to master
    output wire                   o_wb_ack    // acknowledge
);

    // Memory array
    reg [DATA_WIDTH-1:0] mem [0:(2**ADDR_WIDTH)-1];

    integer i;
    initial begin
        for (i = 0; i < 2**ADDR_WIDTH; i = i + 1)
            mem[i] = {DATA_WIDTH{1'b0}};
    end

    // Qualified access: both CYC and STB must be asserted
    wire access = i_wb_cyc & i_wb_stb;

    // Write — synchronous (clocked)
    always @(posedge i_wb_clk) begin
        if (!i_wb_rst && access && i_wb_we)
            mem[i_wb_adr] <= i_wb_dat;
    end

    // Read — combinational (async read, ACK same cycle as STB)
    assign o_wb_dat = (access && !i_wb_we) ? mem[i_wb_adr] : {DATA_WIDTH{1'b0}};

    // ACK — combinational, asserted whenever a valid access is presented
    assign o_wb_ack = access;

endmodule
