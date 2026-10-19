// matrix_mem.v -- dedicated matrix scratch memory for wb_mac_accel
//
// Software writes the matrices with ordinary 32-bit stores (sw) into an
// 8*K_MAX-word window, laid out exactly like these C arrays:
//
//     int32_t A[4][K_MAX];     // word offset 0            (row pitch = K_MAX)
//     int32_t B[K_MAX][4];     // word offset 4*K_MAX      (normal row-major)
//
// Only the first K columns of A / first K rows of B need to be filled.
// Internally the window is split into 8 single-word banks (4 for the rows of
// A, 4 for the columns of B) so the accelerator can read A[0..3][k] and
// B[k][0..3] -- one 256-bit tile -- from ONE index k in a single cycle.
// No interleaved/"paired" layout is needed in software.
//
// Accelerator side: tile address is the byte address from wb_mac_accel;
// set the accelerator's DATA_BASE to this window's base address, which must
// be aligned to 32*K_MAX bytes (8 KB for K_MAX=256). Tile index
// k = tile_addr[5 +: LOGK].
//
// MEM_LAT = 0 : combinational read (LUT RAM). MEM_LAT = 1 : registered read
// (block RAM friendly). Must match wb_mac_accel's MEM_LAT.
// K_MAX must be a power of two and match wb_mac_accel's K_MAX.

module matrix_mem #(
    parameter K_MAX   = 256,
    parameter MEM_LAT = 0
)(
    input  wire         clk,

    // word write port (CPU store decoded to this window, or DMA)
    input  wire         we,
    input  wire [31:0]  waddr,      // byte address; only bits inside the window are used
    input  wire [31:0]  wdata,

    // accelerator tile port
    input  wire [31:0]  tile_addr,  // byte address from o_mem_tile_addr
    output wire [255:0] tile        // {B[k][3..0], A[3..0][k]}
);

    localparam LOGK = $clog2(K_MAX);

    wire [31:0]     wi    = waddr >> 2;      // word index inside window
    wire            is_b  = wi[LOGK+2];      // A region is 4*K_MAX words
    wire [LOGK-1:0] kidx  = tile_addr[5 +: LOGK];

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : GEN_BANK
            // banks 0..3 hold A row i; banks 4..7 hold B column (i-4)
            reg [31:0] mem [0:K_MAX-1];

            wire            hit_a = !is_b && (wi[LOGK+1:LOGK] == (i % 4));
            wire            hit_b =  is_b && (wi[1:0]         == (i % 4));
            wire            hit   = (i < 4) ? hit_a : hit_b;
            wire [LOGK-1:0] widx  = (i < 4) ? wi[LOGK-1:0] : wi[LOGK+1:2];

            always @(posedge clk)
                if (we && hit) mem[widx] <= wdata;

            if (MEM_LAT == 0) begin : GEN_ASYNC
                assign tile[32*i +: 32] = mem[kidx];
            end else begin : GEN_SYNC
                reg [31:0] rd;
                always @(posedge clk) rd <= mem[kidx];
                assign tile[32*i +: 32] = rd;
            end
        end
    endgenerate

endmodule
