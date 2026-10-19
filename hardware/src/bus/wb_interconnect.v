
`include "wb_defs.vh"

// Wishbone address decoder and response mux
// Supports RAM, MAC, DMA, SEARCH, and ERR slaves.

module wb_interconnect #(
    parameter DATA_WIDTH = 32
)(
    // Master interface
    input  wire                  i_wb_cyc,
    input  wire                  i_wb_stb,
    input  wire                  i_wb_we,
    input  wire [31:0]           i_wb_adr,
    input  wire [DATA_WIDTH-1:0] i_wb_dat_ms,

    output wire [DATA_WIDTH-1:0] o_wb_dat_sm,
    output wire                  o_wb_ack,
    output wire                  o_wb_err,

    // Slave 0: RAM
    output wire                  o_ram_cyc,
    output wire                  o_ram_stb,
    input  wire [DATA_WIDTH-1:0] i_ram_dat,
    input  wire                  i_ram_ack,

    // Slave 1: MAC
    output wire                  o_mac_cyc,
    output wire                  o_mac_stb,
    input  wire [DATA_WIDTH-1:0] i_mac_dat,
    input  wire                  i_mac_ack,
    input  wire                  i_mac_err,

    // Slave 2: ERR
    output wire                  o_err_cyc,
    output wire                  o_err_stb,
    input  wire [DATA_WIDTH-1:0] i_err_dat,
    input  wire                  i_err_ack,
    input  wire                  i_err_err,

    // Slave 3: DMA
    output wire                  o_dma_cyc,
    output wire                  o_dma_stb,
    input  wire [DATA_WIDTH-1:0] i_dma_dat,
    input  wire                  i_dma_ack,
    input  wire                  i_dma_err,

    // Slave 4: SEARCH
    output wire                  o_search_cyc,
    output wire                  o_search_stb,
    input  wire [DATA_WIDTH-1:0] i_search_dat,
    input  wire                  i_search_ack,
    input  wire                  i_search_err
);

    // Address decoding
    wire sel_ram    = (i_wb_adr[31:10] == 22'd0);
    wire sel_mac    = (i_wb_adr[31:16] == 16'h1000);
    wire sel_dma    = (i_wb_adr[31:16] == 16'h2000);
    wire sel_search = (i_wb_adr[31:16] == 16'h3000);

    // Any address not assigned above selects the error slave.
    wire sel_err = ~(sel_ram | sel_mac | sel_dma | sel_search);

    // Route the master's CYC and STB to the selected slave.
        // ── Slave 4: wb_sort register page ──────────────────────────────────────
    output wire                  o_sort_cyc,       // NEW
    output wire                  o_sort_stb,       // NEW
    input wire [DATA_WIDTH-1:0]  i_sort_dat,       // NEW
    input wire                   i_sort_ack,       // NEW
    input wire                   i_sort_err        // NEW
);

    // ── Address decode ───────────────────────────────────────────────────────
    // RAM:  0x0000_0000 – 0x0000_03FF  → addr[31:10] == 0
    // MAC:  0x1000_0000 – 0x1000_FFFF  → addr[31:16] == 16'h1000
    // DMA:  0x2000_0000 – 0x2000_FFFF  → addr[31:16] == 16'h2000
    // ERR:  everything else
    wire sel_ram = (i_wb_adr[31:10] == 22'd0);
    wire sel_mac = (i_wb_adr[31:16] == 16'h1000);
    wire sel_dma = (i_wb_adr[31:16] == 16'h2000);
    wire sel_sort = (i_wb_adr[31:16] == 16'h3000); 
wire sel_err  = ~sel_ram & ~sel_mac & ~sel_dma & ~sel_sort; 

    // ── CYC / STB routing ────────────────────────────────────────────────────
    assign o_ram_cyc = i_wb_cyc & sel_ram;
    assign o_ram_stb = i_wb_stb & sel_ram;

    assign o_mac_cyc = i_wb_cyc & sel_mac;
    assign o_mac_stb = i_wb_stb & sel_mac;

    assign o_dma_cyc = i_wb_cyc & sel_dma;
    assign o_dma_stb = i_wb_stb & sel_dma;
    assign o_sort_cyc = i_wb_cyc & sel_sort;  
    assign o_sort_stb = i_wb_stb & sel_sort;  

    assign o_search_cyc = i_wb_cyc & sel_search;
    assign o_search_stb = i_wb_stb & sel_search;

    assign o_err_cyc = i_wb_cyc & sel_err;
    assign o_err_stb = i_wb_stb & sel_err;

    // Return ACK from the selected slave.
    assign o_wb_ack =
        (sel_ram    & i_ram_ack)    |
        (sel_mac    & i_mac_ack)    |
        (sel_dma    & i_dma_ack)    |
        (sel_search & i_search_ack);

    // Return ERR from the selected slave.
    assign o_wb_err =
        (sel_mac    & i_mac_err)    |
        (sel_dma    & i_dma_err)    |
        (sel_search & i_search_err) |
        (sel_err    & i_err_err);

    // Return read data from the selected slave.
    assign o_wb_dat_sm =
        sel_ram    ? i_ram_dat    :
        sel_mac    ? i_mac_dat    :
        sel_dma    ? i_dma_dat    :
        sel_search ? i_search_dat :
                     i_err_dat;
    // ── Response mux (only one sel_* is high per cycle) ──────────────────────
    assign o_wb_ack = (sel_ram  ? i_ram_ack  : 1'b0)
                | (sel_mac  ? i_mac_ack  : 1'b0)
                | (sel_dma  ? i_dma_ack  : 1'b0)
                | (sel_sort ? i_sort_ack : 1'b0);
                    // wb_err never ACKs — i_err_ack omitted intentionally

    assign o_wb_err = (sel_mac  ? i_mac_err  : 1'b0)
                | (sel_dma  ? i_dma_err  : 1'b0)
                | (sel_sort ? i_sort_err : 1'b0)  // NEW
                | (sel_err  ? i_err_err  : 1'b0);
   assign o_wb_dat_sm = sel_ram  ? i_ram_dat  :
                     sel_mac  ? i_mac_dat  :
                     sel_dma  ? i_dma_dat  :
                     sel_sort ? i_sort_dat :  // NEW
                                i_err_dat;

endmodule
