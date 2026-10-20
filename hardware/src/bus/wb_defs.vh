// wb_defs.vh — Wishbone address map
// Include with `include "wb_defs.vh" in any bus module or testbench.
//
// Region layout (top byte of 32-bit address):
//   0x00xx_xxxx   Data RAM        (256 words, 1 KB)
//   0x10xx_xxxx   MAC Accelerator (64 KB slot)
//   0x2000_xxxx   DMA Controller  (64 KB slot, register page aliased every 32 B)
//   0x3000_xxxx   Sort Accelerator (64 KB slot, registers on adr[5:2])
//   0x5000_xxxx   Search Accelerator (64 KB slot)
//   0xFFxx_xxxx   Error slave     (catch-all for unmapped addresses)

// ── Data RAM (wb_ram) ────────────────────────────────────────────────────────
`define WB_RAM_BASE     32'h0000_0000
`define WB_RAM_SIZE     32'h0000_0400   // 1 KB  (256 words × 4 bytes)
`define WB_RAM_END      32'h0000_03FF

// ── Matrix MAC Accelerator (wb_mac_accel, 4x4 systolic C = A*B) ─────────────
`define WB_MAC_BASE     32'h1000_0000
`define WB_MAC_SIZE     32'h0001_0000   // 64 KB slot
`define WB_MAC_END      32'h1000_FFFF

// Result window (read-only C[r][c], 64-bit as low word then high word)
`define WB_MAC_RES_OFF  16'h0000        // 0x0000–0x007C  16 x 64-bit = 32 words
`define WB_MAC_REG_OFF  16'h8000        // 0x8000–0x800C  control registers

// Control register absolute addresses
`define WB_MAC_DATA_BASE 32'h1000_8000  // byte address of tile 0 (low 5 bits forced to 0)
`define WB_MAC_K        32'h1000_8004   // inner dimension 1..K_MAX (larger values clamp)
`define WB_MAC_CTRL     32'h1000_8008   // [0]=START  [1]=CLEAR_RESULTS (also clears DONE)
`define WB_MAC_STATUS   32'h1000_800C   // [0]=BUSY   [1]=DONE (write 1 to clear DONE)

// CTRL bit positions
`define WB_MAC_START    0
`define WB_MAC_CLR      1

// STATUS bit positions
`define WB_MAC_BUSY     0
`define WB_MAC_DONE     1

// ── Matrix scratch window (matrix_mem, not a Wishbone slave) ────────────────
// Core-local, write-only, sw only; 32*K_MAX bytes (8 KB for K_MAX = 256)
`define WB_MAT_BASE     32'h4000_0000   // cpu_top_wb parameter MAT_BASE

// ── DMA Controller (wb_dma) ─────────────────────────────────────────────────
`define WB_DMA_BASE     32'h2000_0000
`define WB_DMA_END      32'h2000_FFFF   // 64 KB slot; registers alias every 32 bytes
`define WB_DMA_SRC      32'h2000_0000
`define WB_DMA_DST      32'h2000_0004
`define WB_DMA_LEN      32'h2000_0008
`define WB_DMA_CTRL     32'h2000_000C
`define WB_DMA_STATUS   32'h2000_0010

// ── Sort Accelerator (wb_sort) ──────────────────────────────────────────────
`define WB_SORT_BASE    32'h3000_0000
`define WB_SORT_END     32'h3000_FFFF   // 64 KB slot; registers decoded on adr[5:2]
`define WB_SORT_SRC     32'h3000_0000
`define WB_SORT_DST     32'h3000_0004
`define WB_SORT_LEN     32'h3000_0008
`define WB_SORT_CTRL    32'h3000_000C
`define WB_SORT_STATUS  32'h3000_0010

// ── Search Accelerator (wb_search_accel) ────────────────────────────────────
`define WB_SEARCH_BASE    32'h5000_0000
`define WB_SEARCH_END     32'h5000_FFFF // 64 KB slot; array 0x0000–0x7FFF, registers 0x8000+
`define WB_SEARCH_CTRL    32'h5000_8000 // [0]=START  [1]=CLEAR (done/error)
`define WB_SEARCH_STATUS  32'h5000_8004 // [0]=BUSY [1]=DONE [2]=FOUND [3]=ERROR
`define WB_SEARCH_LEN     32'h5000_8008
`define WB_SEARCH_KEY     32'h5000_800C
`define WB_SEARCH_RESULT  32'h5000_8010
`define WB_SEARCH_COMPS   32'h5000_8014

// ── Error slave (wb_err) — catch-all ────────────────────────────────────────
`define WB_ERR_BASE     32'hFFFF_0000
`define WB_ERR_END      32'hFFFF_FFFF
