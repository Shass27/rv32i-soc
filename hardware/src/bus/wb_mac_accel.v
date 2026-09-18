// wb_mac_accel.v — Wishbone Classic MAC (multiply-accumulate) accelerator
// 64 KB peripheral slot, base 0x1000_0000 (region 0x1, slot 0x000)
// Minimal signals (CYC/STB/WE/ACK/ERR), ACK is combinational (zero wait states)
//
// Computes  acc = acc + SUM( A[i] * B[i] )  for i = 0 .. LEN-1  (signed 32x32 -> 64)
// One element per clock.
//
//   offset            size     contents
//   0x0000 - 0x3FFF   16 KB    BUF_A  — 4096 signed 32-bit words
//   0x4000 - 0x7FFF   16 KB    BUF_B  — 4096 signed 32-bit words
//   0x8000 - 0xFFFF   32 KB    control registers (aliased every 32 bytes)
//
//   0x8000  CTRL    [0] START   (self clearing, ignored while BUSY)
//                   [1] CLR_ACC (self clearing, ignored while BUSY)
//   0x8004  STATUS  [0] BUSY    (read only)
//                   [1] DONE    (sticky, write 1 to clear)
//   0x8008  LEN     element count, 0 .. 4096 (writable while idle)
//   0x800C  ACC_LO  accumulator[31:0]   (writable while idle)
//   0x8010  ACC_HI  accumulator[63:32]  (writable while idle)

module wb_mac_accel #(
    parameter ADDR_WIDTH = 16,                                   // 2^16 = 65536 bytes = 64 KB slot
    parameter DATA_WIDTH = 32,
    parameter BUF_AW     = 12                                    // 2^12 = 4096 words per buffer
)(
    input  wire                  i_wb_clk,
    input  wire                  i_wb_rst,

    input  wire [31:0]           i_wb_adr,   // full 32-bit byte address from master
    input  wire [DATA_WIDTH-1:0] i_wb_dat,   // write data from master
    input  wire                  i_wb_we,    // 1 = write, 0 = read
    input  wire                  i_wb_stb,   // strobe — valid transfer
    input  wire                  i_wb_cyc,   // bus cycle active

    output wire [DATA_WIDTH-1:0] o_wb_dat,   // read data to master
    output wire                  o_wb_ack,   // acknowledge
    output wire                  o_wb_err,   // error — tied low, every offset in the slot responds

    output wire                  o_irq       // high while DONE is set (tie off if unused)
);

    localparam BUF_DEPTH = 2**BUF_AW;
    localparam ACC_WIDTH = 2*DATA_WIDTH;

    // FSM states
    localparam IDLE = 2'd0;
    localparam RUN  = 2'd1;
    localparam FIN  = 2'd2;

    // register indices (word offsets inside the register page)
    localparam REG_CTRL   = 3'd0;
    localparam REG_STATUS = 3'd1;
    localparam REG_LEN    = 3'd2;
    localparam REG_ACC_LO = 3'd3;
    localparam REG_ACC_HI = 3'd4;

    // ---------------------------------------------------------------- bus decode
    wire access = i_wb_cyc & i_wb_stb;
    wire write  = access & i_wb_we;

    wire [ADDR_WIDTH-1:0] offset = i_wb_adr[ADDR_WIDTH-1:0];

    wire sel_regs =  offset[ADDR_WIDTH-1];                        // 0x8000 and up
    wire sel_a    = ~offset[ADDR_WIDTH-1] & ~offset[ADDR_WIDTH-2];
    wire sel_b    = ~offset[ADDR_WIDTH-1] &  offset[ADDR_WIDTH-2];

    wire [BUF_AW-1:0] bus_word = offset[BUF_AW+1:2];              // word address inside a buffer
    wire [2:0]        reg_idx  = offset[4:2];                     // word address inside register page

    // ---------------------------------------------------------------- buffers
    reg [DATA_WIDTH-1:0] buf_a [0:BUF_DEPTH-1];
    reg [DATA_WIDTH-1:0] buf_b [0:BUF_DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < BUF_DEPTH; i = i + 1) begin
            buf_a[i] = {DATA_WIDTH{1'b0}};                        // zero-init so unwritten words are safe
            buf_b[i] = {DATA_WIDTH{1'b0}};
        end
    end

    // Buffer writes — synchronous, gated by access + WE
    // Software must not write a buffer while the engine is BUSY.
    always @(posedge i_wb_clk) begin
        if (write && sel_a) buf_a[bus_word] <= i_wb_dat;
        if (write && sel_b) buf_b[bus_word] <= i_wb_dat;
    end

    // ---------------------------------------------------------------- engine
    reg  [1:0]                  state;
    reg  [BUF_AW:0]             len;                              // 0 .. 4096
    reg  [BUF_AW:0]             idx;
    reg  signed [ACC_WIDTH-1:0] acc;
    reg                         done;

    wire busy = (state != IDLE);

    wire [BUF_AW-1:0] eng_word = idx[BUF_AW-1:0];

    wire signed [DATA_WIDTH-1:0] mul_a   = buf_a[eng_word];
    wire signed [DATA_WIDTH-1:0] mul_b   = buf_b[eng_word];
    wire signed [ACC_WIDTH-1:0]  product = mul_a * mul_b;         // signed 32x32 -> 64

    always @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            state <= IDLE;
            len   <= 0;
            idx   <= 0;
            acc   <= 0;
            done  <= 0;
        end else begin

            // register writes (engine assignments below override on conflict,
            // but every write here is gated on !busy so the two never collide)
            if (write && sel_regs) begin
                case (reg_idx)

                    REG_CTRL: begin
                        if (i_wb_dat[1] && !busy) acc <= 0;                 // CLR_ACC
                        if (i_wb_dat[0] && !busy && (len != 0)) begin       // START
                            idx   <= 0;
                            done  <= 0;
                            state <= RUN;
                        end
                    end

                    REG_STATUS: if (i_wb_dat[1]) done <= 0;                 // write 1 to clear DONE

                    // clamp to BUF_DEPTH so an out-of-range LEN saturates
                    // instead of wrapping the engine index back into the buffer
                    REG_LEN:    if (!busy) len <= (i_wb_dat > BUF_DEPTH) ? BUF_DEPTH[BUF_AW:0]
                                                                         : i_wb_dat[BUF_AW:0];

                    REG_ACC_LO: if (!busy) acc[DATA_WIDTH-1:0]          <= i_wb_dat;
                    REG_ACC_HI: if (!busy) acc[ACC_WIDTH-1:DATA_WIDTH]  <= i_wb_dat;

                    default: ;

                endcase
            end

            case (state)

                IDLE: begin
                    // waits for START via CTRL
                end

                RUN: begin
                    acc <= acc + product;
                    idx <= idx + 1;
                    if (idx == (len - 1)) state <= FIN;
                end

                FIN: begin
                    done  <= 1;
                    state <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

    // ---------------------------------------------------------------- read mux
    // Combinational, same style as wb_ram
    reg [DATA_WIDTH-1:0] rdat;

    always @(*) begin
        if (sel_a)
            rdat = buf_a[bus_word];
        else if (sel_b)
            rdat = buf_b[bus_word];
        else begin
            case (reg_idx)
                REG_STATUS: rdat = {{(DATA_WIDTH-2){1'b0}}, done, busy};
                REG_LEN:    rdat = {{(DATA_WIDTH-BUF_AW-1){1'b0}}, len};
                REG_ACC_LO: rdat = acc[DATA_WIDTH-1:0];
                REG_ACC_HI: rdat = acc[ACC_WIDTH-1:DATA_WIDTH];
                default:    rdat = {DATA_WIDTH{1'b0}};             // CTRL reads back 0
            endcase
        end
    end

    assign o_wb_dat = rdat;

    // ACK — combinational, same cycle as STB (zero wait states)
    assign o_wb_ack = access;
    assign o_wb_err = 1'b0;

    assign o_irq = done;

endmodule
