// wb_defs.vh — Wishbone address map
// Include with `include "wb_defs.vh" in any bus module or testbench.
//
// Region layout (top byte of 32-bit address):
//   0x00xx_xxxx   Data RAM        (256 words, 1 KB)
//   0x10xx_xxxx   MAC Accelerator (64 KB slot)
//   0xFFxx_xxxx   Error slave     (catch-all for unmapped addresses)

// ── Data RAM (wb_ram) ────────────────────────────────────────────────────────
`define WB_RAM_BASE     32'h0000_0000
`define WB_RAM_SIZE     32'h0000_0400   // 1 KB  (256 words × 4 bytes)
`define WB_RAM_END      32'h0000_03FF

// ── MAC Accelerator (wb_mac_accel) ──────────────────────────────────────────
`define WB_MAC_BASE     32'h1000_0000
`define WB_MAC_SIZE     32'h0001_0000   // 64 KB slot
`define WB_MAC_END      32'h1000_FFFF

// Buffer sub-regions (offsets from WB_MAC_BASE)
`define WB_MAC_BUFA_OFF 16'h0000        // 0x0000–0x3FFF  BUF_A (16 KB, 4096 words)
`define WB_MAC_BUFB_OFF 16'h4000        // 0x4000–0x7FFF  BUF_B (16 KB, 4096 words)
`define WB_MAC_REG_OFF  16'h8000        // 0x8000–0xFFFF  control registers

// Control register absolute addresses
`define WB_MAC_CTRL     32'h1000_8000   // [0]=START  [1]=CLR_ACC  (self-clearing)
`define WB_MAC_STATUS   32'h1000_8004   // [0]=BUSY   [1]=DONE     (write-1-to-clear DONE)
`define WB_MAC_LEN      32'h1000_8008   // element count 0..4096
`define WB_MAC_ACC_LO   32'h1000_800C   // accumulator[31:0]
`define WB_MAC_ACC_HI   32'h1000_8010   // accumulator[63:32]

// CTRL bit positions
`define WB_MAC_START    0
`define WB_MAC_CLR_ACC  1

// STATUS bit positions
`define WB_MAC_BUSY     0
`define WB_MAC_DONE     1

// ── Error slave (wb_err) — catch-all ────────────────────────────────────────
`define WB_ERR_BASE     32'hFFFF_0000
`define WB_ERR_END      32'hFFFF_FFFF
