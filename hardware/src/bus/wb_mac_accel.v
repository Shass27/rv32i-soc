// wb_mac_accel.v -- 4x4 output-stationary systolic matrix multiplier (optimized)
//
// Computes C = A(4xK) * B(Kx4), signed 32-bit inputs, signed 64-bit outputs.
//
// Memory interface (direct, no Wishbone):
//   * ONE 256-bit tile (8 x 32-bit words) is fetched per cycle, one K index
//     per tile. Tile k occupies 32 bytes, word 0 at tile[31:0]:
//         words 0..3 : A[0][k] A[1][k] A[2][k] A[3][k]   (column k of A)
//         words 4..7 : B[k][0] B[k][1] B[k][2] B[k][3]   (row    k of B)
//   * DATA_BASE is the byte address of tile 0 (32-byte aligned, low 5 bits
//     forced to 0). Tile k is at DATA_BASE + 32*k.
//   * MEM_LAT = 0 : i_mem_tile is a combinational function of o_mem_tile_addr.
//     MEM_LAT = 1 : synchronous memory, i_mem_tile valid one cycle after the
//                   address (best for timing, costs 1 cycle of latency).
//
// Why 256 bits is the minimum for one K step per cycle: a 4x4 outer product
// needs 4 A + 4 B operands = 8 words per cycle. (The old 512-bit tile moved
// the same 8 words/cycle on average, but only every 2nd cycle.)
//
// Skew: row r of A and column c of B are delayed r / c cycles by small shift
// registers at the array edge (6 words each), so PE(r,c) sees A[r][k] and
// B[k][c] together at cycle k+r+c. This replaces the two 512-bit history
// registers and all per-lane tile/word muxes of the previous version.
//
// Wishbone register map (offset = low 16 address bits):
//   0x0000..0x007C : C[0][0]..C[3][3], signed 64-bit, low word then high word
//   0x8000         : DATA_BASE
//   0x8004         : K (1..K_MAX, larger values are clamped)
//   0x8008 CTRL    : bit 0 START, bit 1 CLEAR_RESULTS (also clears DONE)
//   0x800C STATUS  : bit 0 BUSY, bit 1 DONE (write bit 1 to clear DONE)
//
// Timing (RUN cycles): K + 6 + MEM_LAT + MULT_PIPE. There is one extra
// BUSY cycle before RUN in which the accumulators are cleared from a
// registered (low fan-out) strobe instead of the Wishbone decode.
// Defaults (MEM_LAT=0, MULT_PIPE=0) keep the original K+6 RUN cycles.

module wb_mac_accel #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter K_MAX      = 256,
    parameter MEM_LAT    = 0,   // 0: combinational memory read, 1: synchronous (1-cycle) read
    parameter MULT_PIPE  = 0    // 1: register the 32x32 product (higher Fmax, +1 cycle)
)(
    input  wire                       i_wb_clk,
    input  wire                       i_wb_rst,

    input  wire [31:0]                i_wb_adr,
    input  wire [DATA_WIDTH-1:0]      i_wb_dat,
    input  wire                       i_wb_we,
    input  wire                       i_wb_stb,
    input  wire                       i_wb_cyc,

    output wire [DATA_WIDTH-1:0]      o_wb_dat,
    output wire                       o_wb_ack,
    output wire                       o_wb_err,
    output wire                       o_irq,

    // Byte address of the tile to read, aligned to 32 bytes, driven from a
    // register. i_mem_tile[31:0] is the lowest-addressed word.
    output wire [31:0]                o_mem_tile_addr,
    input  wire [(8*DATA_WIDTH)-1:0]  i_mem_tile
);

    localparam DW        = DATA_WIDTH;
    localparam ACC_WIDTH = 2 * DW;
    localparam LAT       = MEM_LAT + MULT_PIPE;
    localparam CNT_W     = $clog2(K_MAX + 8);

    localparam [CNT_W-1:0] TAIL           = 5 + LAT;  // cnt = K + TAIL at RUN cycle 0
    localparam [CNT_W-1:0] LAST_ISSUE_CNT = 6 + LAT;  // cnt value in the cycle of the last tile address

    localparam REG_DATA_BASE = 3'd0;
    localparam REG_K         = 3'd1;
    localparam REG_CTRL      = 3'd2;
    localparam REG_STATUS    = 3'd3;

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_CLR  = 2'd1;   // 1 cycle: clear accumulators, load counters
    localparam [1:0] S_RUN  = 2'd2;

    // ------------------------------------------------------------------
    // Wishbone decode
    // ------------------------------------------------------------------
    wire                  access     = i_wb_cyc & i_wb_stb;
    wire                  write      = access & i_wb_we;
    wire [ADDR_WIDTH-1:0] offset     = i_wb_adr[ADDR_WIDTH-1:0];
    wire                  sel_regs   = offset[ADDR_WIDTH-1];
    wire                  reg_hit    = sel_regs && (offset[14:4] == 11'd0);
    wire [1:0]            reg_idx    = offset[3:2];
    wire [4:0]            result_word_idx = offset[6:2];
    wire                  sel_result = !sel_regs && (offset[14:7] == 8'd0);

    // ------------------------------------------------------------------
    // Control state
    // ------------------------------------------------------------------
    reg [31:0]        data_base;
    reg [CNT_W-1:0]   k_cfg;
    reg [CNT_W-1:0]   cnt;        // counts down to 0 on the last RUN cycle
    reg [31:0]        mem_addr;
    reg [1:0]         state;
    reg               go;         // CLR state leads to RUN (else back to IDLE)
    reg               issue;      // tile address is valid this cycle
    reg               issue_q;
    reg               done;

    wire idle      = (state == S_IDLE);
    wire busy      = !idle;
    wire run       = (state == S_RUN);
    wire k_nonzero = (k_cfg != {CNT_W{1'b0}});
    wire last_issue = (cnt == LAST_ISSUE_CNT);

    wire clear_acc = i_wb_rst | (state == S_CLR);

    always @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            data_base <= 32'b0;
            k_cfg     <= {CNT_W{1'b0}};
            cnt       <= {CNT_W{1'b0}};
            mem_addr  <= 32'b0;
            state     <= S_IDLE;
            go        <= 1'b0;
            issue     <= 1'b0;
            done      <= 1'b0;
        end else begin
            // ---- register writes (only while idle, except DONE clear) ----
            if (write && reg_hit) begin
                case (reg_idx)
                    REG_DATA_BASE: if (idle) data_base <= {i_wb_dat[31:5], 5'b0};
                    REG_K: if (idle) begin
                        if (i_wb_dat > K_MAX) k_cfg <= K_MAX;
                        else                  k_cfg <= i_wb_dat[CNT_W-1:0];
                    end
                    REG_CTRL: if (idle) begin
                        if (i_wb_dat[1]) done <= 1'b0;
                        if (i_wb_dat[0] && k_nonzero) done <= 1'b0;
                        if (i_wb_dat[1] || (i_wb_dat[0] && k_nonzero)) begin
                            state <= S_CLR;
                            go    <= i_wb_dat[0] && k_nonzero;
                        end
                    end
                    REG_STATUS: if (i_wb_dat[1]) done <= 1'b0;
                    default: ;
                endcase
            end

            // ---- sequencing ----
            case (state)
                S_CLR: begin
                    mem_addr <= data_base;
                    cnt      <= k_cfg + TAIL;
                    if (go) begin
                        state <= S_RUN;
                        issue <= 1'b1;
                    end else begin
                        state <= S_IDLE;
                    end
                end
                S_RUN: begin
                    if (issue) begin
                        if (last_issue) issue    <= 1'b0;
                        else            mem_addr <= mem_addr + 32'd32;
                    end
                    if (cnt == {CNT_W{1'b0}}) begin
                        state <= S_IDLE;
                        done  <= 1'b1;
                    end else begin
                        cnt <= cnt - 1'b1;
                    end
                end
                default: ;
            endcase
        end
    end

    always @(posedge i_wb_clk) begin
        if (i_wb_rst) issue_q <= 1'b0;
        else          issue_q <= issue;
    end

    assign o_mem_tile_addr = mem_addr;

    // Tile is valid in the same cycle as the address (MEM_LAT=0) or one later.
    wire feed_valid = (MEM_LAT != 0) ? issue_q : issue;

    // Zero the operands outside the valid window; zeros flow through the
    // skew registers and PEs and add nothing to the accumulators.
    wire [(8*DW)-1:0] tile_g = i_mem_tile & {(8*DW){feed_valid}};

    // ------------------------------------------------------------------
    // Edge skew: row r of A / column c of B delayed by r / c cycles
    // ------------------------------------------------------------------
    wire [DW-1:0] a_edge [0:3];
    wire [DW-1:0] b_edge [0:3];

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : GEN_SKEW
            wire [DW-1:0] a_raw = tile_g[DW*i       +: DW];
            wire [DW-1:0] b_raw = tile_g[DW*(4 + i) +: DW];
            if (i == 0) begin : GEN_NOSKEW
                assign a_edge[i] = a_raw;
                assign b_edge[i] = b_raw;
            end else begin : GEN_DELAY
                reg [DW*i-1:0] a_dl;
                reg [DW*i-1:0] b_dl;
                // {dl, raw} is truncated to DW*i bits: shift in at the LSBs.
                always @(posedge i_wb_clk) begin
                    if (i_wb_rst) begin
                        a_dl <= {(DW*i){1'b0}};
                        b_dl <= {(DW*i){1'b0}};
                    end else begin
                        a_dl <= {a_dl, a_raw};
                        b_dl <= {b_dl, b_raw};
                    end
                end
                assign a_edge[i] = a_dl[DW*i-1 -: DW];
                assign b_edge[i] = b_dl[DW*i-1 -: DW];
            end
        end
    endgenerate

    // ------------------------------------------------------------------
    // PE array. A moves left->right, B moves top->bottom (free-running,
    // flushed with zeros). Only C accumulates, and only while RUN.
    // ------------------------------------------------------------------
    reg signed [DW-1:0]        a_pipe [0:15];
    reg signed [DW-1:0]        b_pipe [0:15];
    reg signed [ACC_WIDTH-1:0] c_acc  [0:15];

    wire signed [DW-1:0]       pe_a_in [0:15];
    wire signed [DW-1:0]       pe_b_in [0:15];

    genvar r, c;
    generate
        for (r = 0; r < 4; r = r + 1) begin : GEN_ROW
            for (c = 0; c < 4; c = c + 1) begin : GEN_COL
                localparam IDX = r*4 + c;

                if (c == 0) begin : GEN_A_EDGE
                    assign pe_a_in[IDX] = a_edge[r];
                end else begin : GEN_A_LINK
                    assign pe_a_in[IDX] = a_pipe[IDX-1];
                end

                if (r == 0) begin : GEN_B_EDGE
                    assign pe_b_in[IDX] = b_edge[c];
                end else begin : GEN_B_LINK
                    assign pe_b_in[IDX] = b_pipe[IDX-4];
                end

                // Last column / last row never forward their operands.
                if (c < 3) begin : GEN_A_REG
                    always @(posedge i_wb_clk)
                        a_pipe[IDX] <= i_wb_rst ? {DW{1'b0}} : pe_a_in[IDX];
                end
                if (r < 3) begin : GEN_B_REG
                    always @(posedge i_wb_clk)
                        b_pipe[IDX] <= i_wb_rst ? {DW{1'b0}} : pe_b_in[IDX];
                end

                // Canonical signed 32x32 -> 64 multiply.
                wire signed [ACC_WIDTH-1:0] prod = pe_a_in[IDX] * pe_b_in[IDX];
                wire signed [ACC_WIDTH-1:0] prod_used;

                if (MULT_PIPE != 0) begin : GEN_PROD_REG
                    reg signed [ACC_WIDTH-1:0] prod_q;
                    always @(posedge i_wb_clk)
                        prod_q <= i_wb_rst ? {ACC_WIDTH{1'b0}} : prod;
                    assign prod_used = prod_q;
                end else begin : GEN_PROD_DIRECT
                    assign prod_used = prod;
                end

                always @(posedge i_wb_clk) begin
                    if (clear_acc)
                        c_acc[IDX] <= {ACC_WIDTH{1'b0}};
                    else if (run)
                        c_acc[IDX] <= c_acc[IDX] + prod_used;
                end
            end
        end
    endgenerate

    // ------------------------------------------------------------------
    // Wishbone read data
    // ------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] rdat;
    always @(*) begin
        rdat = {DATA_WIDTH{1'b0}};
        if (sel_result) begin
            if (result_word_idx[0])
                rdat = c_acc[result_word_idx[4:1]][ACC_WIDTH-1:DATA_WIDTH];
            else
                rdat = c_acc[result_word_idx[4:1]][DATA_WIDTH-1:0];
        end else if (reg_hit) begin
            case (reg_idx)
                REG_DATA_BASE: rdat = data_base;
                REG_K:         rdat = {{(DATA_WIDTH-CNT_W){1'b0}}, k_cfg};
                REG_STATUS:    rdat = {{(DATA_WIDTH-2){1'b0}}, done, busy};
                default:       rdat = {DATA_WIDTH{1'b0}};
            endcase
        end
    end

    assign o_wb_dat = rdat;
    assign o_wb_ack = access;
    assign o_wb_err = 1'b0;
    assign o_irq    = done;

endmodule
