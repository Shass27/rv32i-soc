// wb_dma.v — single-channel DMA controller (word copy, any address -> any address)
// Slave port: CPU programs the registers below (combinational ACK, like wb_mac_accel)
// Master port: internal wb_master for addresses >= 0x0001_0000 (bus side)
// Local port: data_memory port B for addresses < 0x0001_0000 (1 cycle, off-bus)
//
//   offset  name    contents
//   0x00    SRC     source byte address      (live: +4 per word)
//   0x04    DST     destination byte address (live: +4 per word)
//   0x08    LEN     words left               (live: -1 per word, 0 after a full copy)
//   0x0C    CTRL    [0] START (self clearing, ignored while BUSY or LEN == 0)
//   0x10    STATUS  [0] BUSY (read only)  [1] DONE  [2] ERR  (sticky, write 1 to clear)
//
// addr[1:0] is ignored (word-only, like the rest of the bus). SRC/DST/LEN/CTRL writes are
// ignored while BUSY, so a DMA whose DST is its own register page cannot corrupt itself.
// Cycles per word: local->bus 4, bus->local 4, local->local 2, bus->bus 6.

module wb_dma (
    input  wire        i_clk,
    input  wire        i_rst,

    // slave: register page
    input  wire [31:0] i_s_adr,
    input  wire [31:0] i_s_dat,
    input  wire        i_s_we,
    input  wire        i_s_stb,
    input  wire        i_s_cyc,
    output reg  [31:0] o_s_dat,
    output wire        o_s_ack,
    output wire        o_s_err,

    // master: bus side of the copy
    output wire        o_m_cyc,
    output wire        o_m_stb,
    output wire        o_m_we,
    output wire [31:0] o_m_adr,
    output wire [31:0] o_m_dat,
    input  wire [31:0] i_m_dat,
    input  wire        i_m_ack,
    input  wire        i_m_err,

    // local: data_memory port B
    output wire        o_b_we,
    output wire [31:0] o_b_addr,
    output wire [31:0] o_b_wdat,
    input  wire [31:0] i_b_rdat,

    output wire        o_busy      // CPU halt + bus mux select (dma_busy in cpu_top_wb)
);

    // FSM states
    localparam IDLE = 2'd0;
    localparam RD   = 2'd1;   // fetch one word into data_reg
    localparam WR   = 2'd2;   // store data_reg, then advance

    // register indices (word offsets inside the page)
    localparam REG_SRC    = 3'd0;
    localparam REG_DST    = 3'd1;
    localparam REG_LEN    = 3'd2;
    localparam REG_CTRL   = 3'd3;
    localparam REG_STATUS = 3'd4;

    reg  [1:0]  state;
    reg  [31:0] src, dst, len;
    reg  [31:0] data_reg;
    reg         done, err;

    wire busy = (state != IDLE);
    assign o_busy = busy;

    // same local/bus split as the CPU's io_sel
    wire src_local = (src[31:16] == 16'h0000);
    wire dst_local = (dst[31:16] == 16'h0000);

    // ---------------------------------------------------------------- master (reused wb_master)
    wire [31:0] m_rdat;
    wire        m_busy, m_done, m_err;

    // ~m_done: in the done-pulse cycle the master is already IDLE; without it req would re-fire
    wire m_req = ((state == RD & ~src_local) | (state == WR & ~dst_local)) & ~m_busy & ~m_done;

    wb_master u_master (
        .i_clk    (i_clk),
        .i_rst    (i_rst),
        .i_req    (m_req),
        .i_we     (state == WR),
        .i_addr   (state == WR ? dst : src),
        .i_wdat   (data_reg),
        .o_rdat   (m_rdat),
        .o_busy   (m_busy),
        .o_done   (m_done),
        .o_err    (m_err),
        .o_wb_cyc (o_m_cyc),
        .o_wb_stb (o_m_stb),
        .o_wb_we  (o_m_we),
        .o_wb_adr (o_m_adr),
        .o_wb_dat (o_m_dat),
        .i_wb_dat (i_m_dat),
        .i_wb_ack (i_m_ack),
        .i_wb_err (i_m_err)
    );

    // ---------------------------------------------------------------- local port B
    assign o_b_addr = (state == WR) ? dst : src;
    assign o_b_wdat = data_reg;
    assign o_b_we   = (state == WR) & dst_local;

    // ---------------------------------------------------------------- slave decode
    wire       s_write = i_s_cyc & i_s_stb & i_s_we;
    wire [2:0] reg_idx = i_s_adr[4:2];

    // ---------------------------------------------------------------- registers + engine
    always @(posedge i_clk) begin
        if (i_rst) begin
            state    <= IDLE;
            src      <= 0;
            dst      <= 0;
            len      <= 0;
            data_reg <= 0;
            done     <= 0;
            err      <= 0;
        end else begin

            // register writes (engine assignments below come later and win on conflict)
            if (s_write) begin
                case (reg_idx)
                    REG_SRC:  if (!busy) src <= i_s_dat;
                    REG_DST:  if (!busy) dst <= i_s_dat;
                    REG_LEN:  if (!busy) len <= i_s_dat;
                    REG_CTRL: if (!busy && i_s_dat[0] && len != 0) begin   // START
                                  done  <= 0;
                                  err   <= 0;
                                  state <= RD;
                              end
                    REG_STATUS: begin
                                  if (i_s_dat[1]) done <= 0;                // W1C DONE
                                  if (i_s_dat[2]) err  <= 0;                // W1C ERR
                              end
                    default: ;
                endcase
            end

            case (state)

                RD: begin
                    if (m_done & m_err) begin              // bus read failed: stop, nothing advances
                        done  <= 1;
                        err   <= 1;
                        state <= IDLE;
                    end else if (src_local | m_done) begin // word available this cycle
                        data_reg <= src_local ? i_b_rdat : m_rdat;
                        state    <= WR;
                    end
                end

                WR: begin
                    if (m_done & m_err) begin              // bus write failed: stop, nothing advances
                        done  <= 1;
                        err   <= 1;
                        state <= IDLE;
                    end else if (dst_local | m_done) begin // word stored (local write lands on this edge)
                        src <= src + 4;
                        dst <= dst + 4;
                        len <= len - 1;
                        if (len == 1) begin                // last word: master is IDLE here, safe to drop BUSY
                            done  <= 1;
                            state <= IDLE;
                        end else
                            state <= RD;
                    end
                end

                default: ;                                 // IDLE waits for START

            endcase
        end
    end

    // ---------------------------------------------------------------- slave read mux + ACK
    always @(*) begin
        case (reg_idx)
            REG_SRC:    o_s_dat = src;
            REG_DST:    o_s_dat = dst;
            REG_LEN:    o_s_dat = len;
            REG_STATUS: o_s_dat = {29'b0, err, done, busy};
            default:    o_s_dat = 32'b0;                   // CTRL reads back 0
        endcase
    end

    assign o_s_ack = i_s_cyc & i_s_stb;                    // zero wait states
    assign o_s_err = 1'b0;

endmodule
