// wb_master.v — Minimal Wishbone Classic master
// Single-transaction FSM: IDLE → ACTIVE → DONE → IDLE
// Drives CYC/STB/WE/ADR/DAT; waits for combinational ACK from slave

module wb_master #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                   i_clk,
    input  wire                   i_rst,

    // user-side interface
    input  wire                   i_req,     // pulse to start a transaction
    input  wire                   i_we,      // 1=write, 0=read
    input  wire [ADDR_WIDTH-1:0]  i_addr,    // byte address
    input  wire [DATA_WIDTH-1:0]  i_wdat,    // write data
    output reg  [DATA_WIDTH-1:0]  o_rdat,    // captured read data
    output wire                   o_busy,    // high while transaction in flight
    output reg                    o_done,    // 1-cycle pulse on ACK

    // Wishbone master → slave
    output reg                    o_wb_cyc,
    output reg                    o_wb_stb,
    output reg                    o_wb_we,
    output reg  [ADDR_WIDTH-1:0]  o_wb_adr,
    output reg  [DATA_WIDTH-1:0]  o_wb_dat,
    input  wire [DATA_WIDTH-1:0]  i_wb_dat,
    input  wire                   i_wb_ack
);

    // FSM states
    localparam IDLE   = 2'd0;
    localparam ACTIVE = 2'd1;
    localparam DONE   = 2'd2;

    reg [1:0] state;

    assign o_busy = (state != IDLE);

    always @(posedge i_clk) begin
        o_done <= 0; // default: deassert every cycle

        if (i_rst) begin
            state     <= IDLE;
            o_wb_cyc  <= 0;
            o_wb_stb  <= 0;
            o_wb_we   <= 0;
            o_wb_adr  <= 0;
            o_wb_dat  <= 0;
            o_rdat    <= 0;
        end else begin
            case (state)

                IDLE: begin
                    if (i_req) begin
                        o_wb_adr <= i_addr;   // latch transaction parameters
                        o_wb_dat <= i_wdat;
                        o_wb_we  <= i_we;
                        o_wb_cyc <= 1;
                        o_wb_stb <= 1;
                        state    <= ACTIVE;
                    end
                end

                ACTIVE: begin
                    if (i_wb_ack) begin       // slave acknowledged
                        o_rdat   <= i_wb_dat; // capture read data (valid on reads)
                        o_wb_cyc <= 0;
                        o_wb_stb <= 0;
                        o_done   <= 1;        // pulse done for one cycle
                        state    <= IDLE;     // return directly to IDLE
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
