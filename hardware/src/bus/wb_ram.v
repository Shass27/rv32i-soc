// wb_ram.v — Wishbone Classic slave RAM
// 32-bit data, 256 words (1 KB), minimal signals (CYC/STB/WE/ACK)
// ACK is combinational (zero wait states)

module wb_ram #(
    parameter ADDR_WIDTH = 8,                                    // 2^8 = 256 word-addressed locations
    parameter DATA_WIDTH = 32,
    parameter MEM_FILE   = "hardware/src/core/mem/data.hex"     // initial memory image
)(
    input  wire                  i_wb_clk,
    input  wire                  i_wb_rst,

    input  wire [31:0]           i_wb_adr,   // full 32-bit byte address from master
    input  wire [DATA_WIDTH-1:0] i_wb_dat,   // write data from master
    input  wire                  i_wb_we,    // 1 = write, 0 = read
    input  wire                  i_wb_stb,   // strobe — valid transfer
    input  wire                  i_wb_cyc,   // bus cycle active

    output wire [DATA_WIDTH-1:0] o_wb_dat,   // read data to master
    output wire                  o_wb_ack    // acknowledge
);

    // Memory array — word addressed
    reg [DATA_WIDTH-1:0] mem [0:(2**ADDR_WIDTH)-1];

    integer i;
    initial begin
        for (i = 0; i < 2**ADDR_WIDTH; i = i + 1)
            mem[i] = {DATA_WIDTH{1'b0}};          // zero-init first so unloaded words are safe
        if (MEM_FILE != "") $readmemh(MEM_FILE, mem);
    end

    wire [ADDR_WIDTH-1:0] word_addr = i_wb_adr[ADDR_WIDTH+1:2];

    wire access = i_wb_cyc & i_wb_stb;

    // Write — synchronous, gated by access + WE
    always @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            // RAM content does not need reset
        end else if (access && i_wb_we) begin
            mem[word_addr] <= i_wb_dat;
        end
    end

    // Read — combinational, always drives from memory
    // Master ignores this on writes, so no ternary needed
    assign o_wb_dat = mem[word_addr];

    // ACK — combinational, same cycle as STB (zero wait states)
    assign o_wb_ack = access;

endmodule
