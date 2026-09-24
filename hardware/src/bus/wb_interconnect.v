// wb_interconnect.v — Wishbone Classic address decoder + response mux
// One master, four slaves: wb_ram / wb_mac_accel / wb_dma / wb_err (catch-all)
//
// Address map (from wb_defs.vh):
//   0x0000_0000 – 0x0000_03FF   wb_ram       (1 KB)
//   0x1000_0000 – 0x1000_FFFF   wb_mac_accel (64 KB)
//   0x2000_0000 – 0x2000_00FF   wb_dma       (register page)
//   everything else              wb_err       (catch-all → ERR)
//
// WE / ADR / DAT (master→slave) are broadcast to all slaves.
// Only the selected slave receives CYC & STB, so only it will drive ACK/ERR.

`include "wb_defs.vh"

module wb_interconnect #(
    parameter DATA_WIDTH = 32
)(
    // ── Master-facing interface ──────────────────────────────────────────────
    input  wire                  i_wb_cyc,
    input  wire                  i_wb_stb,
    input  wire                  i_wb_we,
    input  wire [31:0]           i_wb_adr,
    input  wire [DATA_WIDTH-1:0] i_wb_dat_ms,  // master → slave write data

    output wire [DATA_WIDTH-1:0] o_wb_dat_sm,  // slave  → master read data
    output wire                  o_wb_ack,
    output wire                  o_wb_err,

    // ── Slave 0: wb_ram ──────────────────────────────────────────────────────
    output wire                  o_ram_cyc,
    output wire                  o_ram_stb,
    // WE / ADR / DAT_MS wired directly to slave in parent
    input  wire [DATA_WIDTH-1:0] i_ram_dat,
    input  wire                  i_ram_ack,
    // wb_ram has no ERR port (pre-ERR design)

    // ── Slave 1: wb_mac_accel ────────────────────────────────────────────────
    output wire                  o_mac_cyc,
    output wire                  o_mac_stb,
    input  wire [DATA_WIDTH-1:0] i_mac_dat,
    input  wire                  i_mac_ack,
    input  wire                  i_mac_err,

    // ── Slave 2: wb_err (catch-all) ──────────────────────────────────────────
    output wire                  o_err_cyc,
    output wire                  o_err_stb,
    input  wire [DATA_WIDTH-1:0] i_err_dat,
    input  wire                  i_err_ack,   // always 0 from wb_err
    input  wire                  i_err_err,   // always 1 on access from wb_err

    // ── Slave 3: wb_dma register page ────────────────────────────────────────
    output wire                  o_dma_cyc,
    output wire                  o_dma_stb,
    input  wire [DATA_WIDTH-1:0] i_dma_dat,
    input  wire                  i_dma_ack,
    input  wire                  i_dma_err
);

    // ── Address decode ───────────────────────────────────────────────────────
    // RAM:  0x0000_0000 – 0x0000_03FF  → addr[31:10] == 0
    // MAC:  0x1000_0000 – 0x1000_FFFF  → addr[31:16] == 16'h1000
    // DMA:  0x2000_0000 – 0x2000_00FF  → addr[31:16] == 16'h2000
    // ERR:  everything else
    wire sel_ram = (i_wb_adr[31:10] == 22'd0);
    wire sel_mac = (i_wb_adr[31:16] == 16'h1000);
    wire sel_dma = (i_wb_adr[31:16] == 16'h2000);
    wire sel_err = ~sel_ram & ~sel_mac & ~sel_dma;

    // ── CYC / STB routing ────────────────────────────────────────────────────
    assign o_ram_cyc = i_wb_cyc & sel_ram;
    assign o_ram_stb = i_wb_stb & sel_ram;

    assign o_mac_cyc = i_wb_cyc & sel_mac;
    assign o_mac_stb = i_wb_stb & sel_mac;

    assign o_dma_cyc = i_wb_cyc & sel_dma;
    assign o_dma_stb = i_wb_stb & sel_dma;

    assign o_err_cyc = i_wb_cyc & sel_err;
    assign o_err_stb = i_wb_stb & sel_err;

    // ── Response mux (only one sel_* is high per cycle) ──────────────────────
    assign o_wb_ack = (sel_ram ? i_ram_ack : 1'b0)
                    | (sel_mac ? i_mac_ack : 1'b0)
                    | (sel_dma ? i_dma_ack : 1'b0);
                    // wb_err never ACKs — i_err_ack omitted intentionally

    assign o_wb_err = (sel_mac ? i_mac_err : 1'b0)
                    | (sel_dma ? i_dma_err : 1'b0)
                    | (sel_err ? i_err_err : 1'b0);

    assign o_wb_dat_sm = sel_ram ? i_ram_dat :
                         sel_mac ? i_mac_dat :
                         sel_dma ? i_dma_dat :
                                   i_err_dat;

endmodule
