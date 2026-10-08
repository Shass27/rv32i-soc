// wb_master_64.v — 64-bit Wishbone Classic Master
// Two instances (Port A, Port B) drive parallel write/read requests
// CPU issues 32-bit requests; master outputs 64-bit transactions
// Read data back to CPU is lower 32 bits [31:0] of 64-bit response
//
// No multi-beat support: each request is one 64-bit transaction
// For CPU writes: data replicated [dat | dat] or combined [dat_b | dat_a] from parallel masters

module wb_master_64 #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter PORT = "A"  // "A" or "B" for identification
)(
    input  wire                   i_clk,
    input  wire                   i_rst,

    // User-side interface (32-bit CPU)
    input  wire                   i_req,        // pulse to start transaction
    input  wire                   i_we,         // 1 = write, 0 = read
    input  wire [ADDR_WIDTH-1:0]  i_addr,       // byte address
    input  wire [DATA_WIDTH-1:0]  i_wdat,       // write data (32-bit)
    output reg  [DATA_WIDTH-1:0]  o_rdat,       // read data (32-bit, lower half of 64-bit)
    output wire                   o_busy,       // transaction in flight
    output reg                    o_done,       // 1-cycle pulse on ACK or ERR
    output reg                    o_err,        // 1 = terminated by ERR

    // Wishbone 64-bit master output
    output reg                    o_wb_cyc,     // bus cycle active
    output reg                    o_wb_stb,     // strobe (valid transfer)
    output reg                    o_wb_we,      // write enable
    output reg  [ADDR_WIDTH-1:0]  o_wb_adr,     // address (same as CPU address)
    output reg  [63:0]            o_wb_dat,     // write data (64-bit)
    input  wire [63:0]            i_wb_dat,     // read data (64-bit)
    input  wire                   i_wb_ack,     // acknowledge
    input  wire                   i_wb_err      // error
);

    // FSM states
    localparam IDLE   = 2'd0;
    localparam ACTIVE = 2'd1;
    localparam DONE   = 2'd2;

    reg [1:0] state;
    assign o_busy = (state != IDLE);

    wire term = i_wb_ack | i_wb_err;  // transaction terminator

    always @(posedge i_clk) begin
        o_done <= 0;  // default: deassert
        o_err  <= 0;

        if (i_rst) begin
            state    <= IDLE;
            o_wb_cyc <= 0;
            o_wb_stb <= 0;
            o_wb_we  <= 0;
            o_wb_adr <= 0;
            o_wb_dat <= 0;
            o_rdat   <= 0;
        end else begin
            case (state)

                IDLE: begin
                    if (i_req) begin
                        o_wb_adr <= i_addr;
                        o_wb_we  <= i_we;
                        o_wb_cyc <= 1;
                        o_wb_stb <= 1;
                        // For single master: replicate 32-bit on both halves
                        // For parallel operation, interconnect will combine A and B
                        o_wb_dat <= {i_wdat, i_wdat};  // [upper | lower]
                        state    <= ACTIVE;
                    end
                end

                ACTIVE: begin
                    if (term) begin
                        o_rdat   <= i_wb_dat[31:0];   // CPU sees lower 32 bits
                        o_wb_cyc <= 0;
                        o_wb_stb <= 0;
                        o_done   <= 1;                 // pulse done
                        o_err    <= i_wb_err;          // set error flag if terminated by ERR
                        state    <= IDLE;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
