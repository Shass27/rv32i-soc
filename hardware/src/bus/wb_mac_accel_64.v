// wb_mac_accel_64.v — Wishbone Classic MAC Accelerator with 64-bit Parallel Write Support
// Accepts simultaneous writes from Port A and Port B combined into 64-bit data
// Data format: i_wb_dat[63:32] = MAT_B, i_wb_dat[31:0] = MAT_A
//
// When both ports write to adjacent offsets (MAT_A and MAT_B):
//   Port A (0x1000_XXXX): buf_a[word] <= i_wb_dat[31:0]
//   Port B (0x1000_4XXX): buf_b[word] <= i_wb_dat[63:32]
// Both complete in one cycle (vs. two cycles with 32-bit bus)

module wb_mac_accel_64 #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter BUF_AW     = 12  // 2^12 = 4096 words per buffer
)(
    input  wire                  i_wb_clk,
    input  wire                  i_wb_rst,

    input  wire [31:0]           i_wb_adr,      // 32-bit address
    input  wire [63:0]           i_wb_dat,      // 64-bit: [upper=B | lower=A]
    input  wire                  i_wb_we,       // write enable
    input  wire                  i_wb_stb,      // strobe
    input  wire                  i_wb_cyc,      // cycle active

    output wire [63:0]           o_wb_dat,      // 64-bit read data
    output wire                  o_wb_ack,      // acknowledge (combinational)
    output wire                  o_wb_err,      // error (tied low)

    output wire                  o_irq          // interrupt: DONE flag
);

    localparam BUF_DEPTH = 2**BUF_AW;
    localparam ACC_WIDTH = 2*DATA_WIDTH;  // 64-bit accumulator

    // FSM states
    localparam IDLE = 2'd0;
    localparam RUN  = 2'd1;
    localparam FIN  = 2'd2;

    // Register indices (word offsets inside the register page)
    localparam REG_CTRL   = 3'd0;
    localparam REG_STATUS = 3'd1;
    localparam REG_LEN    = 3'd2;
    localparam REG_ACC_LO = 3'd3;
    localparam REG_ACC_HI = 3'd4;

    // ────────────────────────────────────────────────────────────────────── Bus Decode
    wire access = i_wb_cyc & i_wb_stb;
    wire write  = access & i_wb_we;

    wire [ADDR_WIDTH-1:0] offset = i_wb_adr[ADDR_WIDTH-1:0];

    wire sel_regs =  offset[ADDR_WIDTH-1];                      // 0x8000 and up: registers
    wire sel_a    = ~offset[ADDR_WIDTH-1] & ~offset[ADDR_WIDTH-2];  // 0x0000-0x3FFF: BUF_A
    wire sel_b    = ~offset[ADDR_WIDTH-1] &  offset[ADDR_WIDTH-2];  // 0x4000-0x7FFF: BUF_B

    wire [BUF_AW-1:0] bus_word = offset[BUF_AW+1:2];  // Word address inside buffer
    wire [2:0]        reg_idx  = offset[4:2];         // Register index

    // Extract 32-bit values from 64-bit input
    wire [DATA_WIDTH-1:0] dat_a = i_wb_dat[31:0];
    wire [DATA_WIDTH-1:0] dat_b = i_wb_dat[63:32];

    // ────────────────────────────────────────────────────────────────────── Buffers (Dual 16 KB each)
    reg [DATA_WIDTH-1:0] buf_a [0:BUF_DEPTH-1];
    reg [DATA_WIDTH-1:0] buf_b [0:BUF_DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < BUF_DEPTH; i = i + 1) begin
            buf_a[i] = 0;  // Zero-init for safe reads
            buf_b[i] = 0;
        end
    end

    // Parallel dual writes: MAT_A and MAT_B simultaneously
    // When Port A writes sel_a and Port B writes sel_b, both occur in same cycle
    always @(posedge i_wb_clk) begin
        if (write) begin
            if (sel_a) buf_a[bus_word] <= dat_a;  // Port A data
            if (sel_b) buf_b[bus_word] <= dat_b;  // Port B data (upper 32 bits)
        end
    end

    // ────────────────────────────────────────────────────────────────────── Engine (Computation)
    reg  [1:0]                  state;
    reg  [BUF_AW:0]             len;   // Element count 0..4096
    reg  [BUF_AW:0]             idx;   // Current index
    reg  signed [ACC_WIDTH-1:0] acc;   // 64-bit accumulator
    reg                         done;  // Done flag (sticky)

    wire busy = (state != IDLE);
    wire [BUF_AW-1:0] eng_word = idx[BUF_AW-1:0];

    // Multiply: A[idx] * B[idx]
    wire signed [DATA_WIDTH-1:0] mul_a   = buf_a[eng_word];
    wire signed [DATA_WIDTH-1:0] mul_b   = buf_b[eng_word];
    wire signed [ACC_WIDTH-1:0]  product = mul_a * mul_b;  // 32x32 -> 64

    always @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            state <= IDLE;
            len   <= 0;
            idx   <= 0;
            acc   <= 0;
            done  <= 0;
        end else begin

            // Register writes (gated on !busy to prevent conflicts with engine)
            if (write && sel_regs) begin
                case (reg_idx)

                    REG_CTRL: begin
                        if (i_wb_dat[1] && !busy) acc <= 0;  // CLR_ACC
                        if (i_wb_dat[0] && !busy && (len != 0)) begin  // START
                            idx   <= 0;
                            done  <= 0;
                            state <= RUN;
                        end
                    end

                    REG_STATUS: if (i_wb_dat[1]) done <= 0;  // Write 1 to clear DONE

                    // LEN: Clamp to BUF_DEPTH to prevent wrap-around
                    REG_LEN: if (!busy) 
                        len <= (i_wb_dat[31:0] > BUF_DEPTH) ? BUF_DEPTH[BUF_AW:0] : i_wb_dat[BUF_AW:0];

                    // Accumulator direct writes (while idle)
                    REG_ACC_LO: if (!busy) acc[DATA_WIDTH-1:0]          <= i_wb_dat[31:0];
                    REG_ACC_HI: if (!busy) acc[ACC_WIDTH-1:DATA_WIDTH]  <= i_wb_dat[31:0];

                    default: ;

                endcase
            end

            // Engine state machine
            case (state)

                IDLE: begin
                    // Waits for START via CTRL register
                end

                RUN: begin
                    // Accumulate: acc += A[idx] * B[idx]
                    acc <= acc + product;
                    idx <= idx + 1;
                    // Check if this was the last element
                    if (idx == (len - 1)) state <= FIN;
                end

                FIN: begin
                    // Set DONE flag, return to IDLE
                    done  <= 1;
                    state <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

    // ────────────────────────────────────────────────────────────────────── Read Mux (64-bit output)
    reg [DATA_WIDTH-1:0] rdat_lo, rdat_hi;

    always @(*) begin
        rdat_lo = 32'b0;
        rdat_hi = 32'b0;

        if (sel_a)
            rdat_lo = buf_a[bus_word];  // Read MAT_A
        else if (sel_b)
            rdat_hi = buf_b[bus_word];  // Read MAT_B (upper 32 bits)
        else begin
            // Register reads
            case (reg_idx)
                REG_STATUS: rdat_lo = {{(DATA_WIDTH-2){1'b0}}, done, busy};
                REG_LEN:    rdat_lo = {{(DATA_WIDTH-BUF_AW-1){1'b0}}, len};
                REG_ACC_LO: rdat_lo = acc[DATA_WIDTH-1:0];
                REG_ACC_HI: rdat_lo = acc[ACC_WIDTH-1:DATA_WIDTH];
                default:    rdat_lo = 32'b0;  // CTRL reads as 0
            endcase
        end
    end

    // 64-bit output: [hi | lo]
    assign o_wb_dat = {rdat_hi, rdat_lo};

    // ACK is combinational (same cycle as STB)
    assign o_wb_ack = access;
    assign o_wb_err = 1'b0;  // Never error

    // Interrupt: high while DONE is set
    assign o_irq = done;

endmodule
