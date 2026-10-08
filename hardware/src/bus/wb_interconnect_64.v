// wb_interconnect_64.v — 64-bit Wishbone Classic Address Decoder + Arbitration
// Three masters: CPU Port A (high priority), CPU Port B, DMA (low priority)
// Four slaves:   RAM (32-bit), MAC (64-bit), DMA registers (32-bit), Error (32-bit)
//
// Key feature: When Port A and Port B both target MAC with adjacent writes,
// data is combined: {port_b_dat | port_a_dat} → 64-bit MAC write
//
// Arbitration priority: A > B > DMA
// Port B is blocked if Port A has active transaction to same slave

module wb_interconnect_64 (
    // ───────────────────────────────────────────────────────────────────── Master A (CPU primary)
    input  wire                  i_a_cyc,
    input  wire                  i_a_stb,
    input  wire                  i_a_we,
    input  wire [31:0]           i_a_adr,
    input  wire [63:0]           i_a_dat_ms,    // 64-bit from Port A master
    output wire [63:0]           o_a_dat_sm,    // 64-bit to Port A master
    output wire                  o_a_ack,
    output wire                  o_a_err,

    // ───────────────────────────────────────────────────────────────────── Master B (CPU auxiliary)
    input  wire                  i_b_cyc,
    input  wire                  i_b_stb,
    input  wire                  i_b_we,
    input  wire [31:0]           i_b_adr,
    input  wire [63:0]           i_b_dat_ms,    // 64-bit from Port B master
    output wire [63:0]           o_b_dat_sm,    // 64-bit to Port B master
    output wire                  o_b_ack,
    output wire                  o_b_err,

    // ───────────────────────────────────────────────────────────────────── Master DMA (32-bit)
    input  wire                  i_dma_cyc,
    input  wire                  i_dma_stb,
    input  wire                  i_dma_we,
    input  wire [31:0]           i_dma_adr,
    input  wire [31:0]           i_dma_dat_ms,  // 32-bit from DMA
    output wire [31:0]           o_dma_dat_sm,  // 32-bit to DMA
    output wire                  o_dma_ack,
    output wire                  o_dma_err,
    
    // ───────────────────────────────────────────────────────────────────── Slave: MAC (64-bit)
    output wire                  o_mac_cyc,
    output wire                  o_mac_stb,
    output wire                  o_mac_we,
    output wire [31:0]           o_mac_adr,
    output wire [63:0]           o_mac_dat,
    input  wire [63:0]           i_mac_dat,
    input  wire                  i_mac_ack,
    input  wire                  i_mac_err,
    
    // ───────────────────────────────────────────────────────────────────── Slave: DMA registers (32-bit)
    output wire                  o_dma_s_cyc,
    output wire                  o_dma_s_stb,
    output wire                  o_dma_s_we,
    output wire [31:0]           o_dma_s_adr,
    output wire [31:0]           o_dma_s_dat,
    input  wire [31:0]           i_dma_s_dat,
    input  wire                  i_dma_s_ack
);

    // ───────────────────────────────────────────────────────────────────── Address Decode (all masters same map)
    // RAM:  0x0000_0000 – 0x0000_03FF  → addr[31:10] == 0
    // MAC:  0x1000_0000 – 0x1000_FFFF  → addr[31:16] == 16'h1000
    // DMA:  0x2000_0000 – 0x2000_FFFF  → addr[31:16] == 16'h2000
    // ERR:  everything else

    wire sel_mac_a  = (i_a_adr[31:16] == 16'h1000);
    wire sel_dma_a  = (i_a_adr[31:16] == 16'h2000);
    wire sel_err_a  = ~sel_mac_a & ~sel_dma_a;

    wire sel_mac_b  = (i_b_adr[31:16] == 16'h1000);
    wire sel_dma_b  = (i_b_adr[31:16] == 16'h2000);
    wire sel_err_b  = ~sel_mac_b & ~sel_dma_b;

    wire sel_mac_dma  = (i_dma_adr[31:16] == 16'h1000);
    wire sel_dma_dma  = (i_dma_adr[31:16] == 16'h2000);
    wire sel_err_dma  = ~sel_mac_dma & ~sel_dma_dma;

    // ───────────────────────────────────────────────────────────────────── Arbitration
    wire a_active = i_a_cyc & i_a_stb;
    wire b_active = i_b_cyc & i_b_stb & ~a_active;   // B blocked if A active
    wire dma_active = i_dma_cyc & i_dma_stb & ~a_active & ~b_active;

    // ───────────────────────────────────────────────────────────────────── Slave: MAC (64-bit)
    wire mac_sel = sel_mac_a | sel_mac_b | sel_mac_dma;
    wire mac_cyc = mac_sel & (a_active | b_active | dma_active);
    wire mac_we = a_active ? i_a_we : (b_active ? i_b_we : i_dma_we);
    wire [31:0] mac_adr = a_active ? i_a_adr : (b_active ? i_b_adr : i_dma_adr);

    // MAC 64-bit data routing:
    // If both A and B active to MAC: combine as {B | A}
    // Otherwise: use active master (replicate 32-bit for DMA)
    wire [63:0] mac_dat;
    assign mac_dat = ((sel_mac_a & a_active) & (sel_mac_b & b_active)) ?
                     {i_b_dat_ms[31:0], i_a_dat_ms[31:0]} :  // Both active: combine
                     (sel_mac_a & a_active) ?
                     i_a_dat_ms :  // A only
                     (sel_mac_b & b_active) ?
                     i_b_dat_ms :  // B only
                     {i_dma_dat_ms, i_dma_dat_ms};  // DMA: replicate

    assign o_mac_cyc = mac_cyc;
    assign o_mac_stb = mac_cyc;
    assign o_mac_we  = mac_we;
    assign o_mac_adr = mac_adr;
    assign o_mac_dat = mac_dat;

    // ───────────────────────────────────────────────────────────────────── Slave: DMA Register Page (32-bit)
    wire dma_sel = sel_dma_a | sel_dma_b | sel_dma_dma;
    wire dma_cyc = dma_sel & (a_active | b_active | dma_active);
    wire dma_we = a_active ? i_a_we : (b_active ? i_b_we : i_dma_we);
    wire [31:0] dma_adr = a_active ? i_a_adr : (b_active ? i_b_adr : i_dma_adr);
    wire [31:0] dma_dat = a_active ? i_a_dat_ms[31:0] : (b_active ? i_b_dat_ms[31:0] : i_dma_dat_ms);

    assign o_dma_s_cyc = dma_cyc;
    assign o_dma_s_stb = dma_cyc;
    assign o_dma_s_we  = dma_we;
    assign o_dma_s_adr = dma_adr;
    assign o_dma_s_dat = dma_dat;

    // ───────────────────────────────────────────────────────────────────── Response Routing: ACK/ERR/DAT
    wire slave_ack = (sel_mac_a | sel_mac_b | sel_mac_dma) ? i_mac_ack :
                     (sel_dma_a | sel_dma_b | sel_dma_dma) ? i_dma_s_ack :
                     1'b0;

    wire slave_err = (sel_mac_a | sel_mac_b | sel_mac_dma) ? i_mac_err :
                     (sel_err_a | sel_err_b | sel_err_dma) ? 1'b1 :
                     1'b0;

    wire [63:0] slave_dat_64 = (sel_mac_a | sel_mac_b | sel_mac_dma) ? i_mac_dat :
                               {32'b0, i_dma_s_dat};
    
    wire [31:0] slave_dat_32 = (sel_dma_a | sel_dma_b | sel_dma_dma) ? i_dma_s_dat :
                               32'b0;

    // Port A response (64-bit)
    assign o_a_ack = a_active ? slave_ack : 1'b0;
    assign o_a_err = a_active ? slave_err : 1'b0;
    assign o_a_dat_sm = a_active ? slave_dat_64 : 64'b0;

    // Port B response (64-bit)
    assign o_b_ack = b_active ? slave_ack : 1'b0;
    assign o_b_err = b_active ? slave_err : 1'b0;
    assign o_b_dat_sm = b_active ? slave_dat_64 : 64'b0;

    // DMA response (32-bit)
    assign o_dma_ack = dma_active ? slave_ack : 1'b0;
    assign o_dma_err = dma_active ? slave_err : 1'b0;
    assign o_dma_dat_sm = dma_active ? slave_dat_32 : 32'b0;

endmodule
