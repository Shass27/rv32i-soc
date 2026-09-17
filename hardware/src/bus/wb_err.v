// Dummy slave that immediately terminates invalid accesses with an error.
// Uses strict Wishbone B4 standard (ACK and ERR are mutually exclusive).
module wb_err #(
    parameter DATA_WIDTH = 32
)(
    input  wire                  i_wb_clk,
    input  wire                  i_wb_rst,

    input  wire [31:0]           i_wb_adr,
    input  wire [DATA_WIDTH-1:0] i_wb_dat,
    input  wire                  i_wb_we,
    input  wire                  i_wb_stb,
    input  wire                  i_wb_cyc,

    output wire [DATA_WIDTH-1:0] o_wb_dat,
    output wire                  o_wb_ack,
    output wire                  o_wb_err
);

    wire access = i_wb_cyc & i_wb_stb;

    assign o_wb_dat = {DATA_WIDTH{1'b0}}; // Reads return zero
    assign o_wb_err = access;             // Always assert ERR on access
    assign o_wb_ack = 1'b0;               // Never assert ACK

endmodule