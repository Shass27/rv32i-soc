`timescale 1ns/1ps

module wb_search_accel (
    input  wire        i_wb_clk,
    input  wire        i_wb_rst,

    input  wire [31:0] i_wb_adr,
    input  wire [31:0] i_wb_dat,
    input  wire        i_wb_we,
    input  wire        i_wb_stb,
    input  wire        i_wb_cyc,

    output reg  [31:0] o_wb_dat,
    output wire        o_wb_ack,
    output wire        o_wb_err
);

    // -----------------------------------------------------
    // Wishbone response: zero-wait-state slave
    // -----------------------------------------------------
    assign o_wb_ack = i_wb_cyc & i_wb_stb;
    assign o_wb_err = 1'b0;

    // -----------------------------------------------------
    // Memory map
    // Array: offsets 0x0000-0x7FFF
    // Regs : offsets 0x8000 and above
    // -----------------------------------------------------
    reg signed [31:0] array_mem [0:8191];

    reg [31:0] len_reg;
    reg signed [31:0] key_reg;
    reg [31:0] result_reg;
    reg [31:0] comps_reg;

    reg busy_reg;
    reg done_reg;
    reg found_reg;
    reg error_reg;

    // Binary-search lower-bound state.
    // high is exclusive, so it can equal 8192.
    reg [13:0] low_reg;
    reg [13:0] high_reg;

    wire [13:0] mid_calc;
    assign mid_calc = low_reg + ((high_reg - low_reg) >> 1);

    localparam [13:0] MAX_LEN = 14'd8192;

    // -----------------------------------------------------
    // Wishbone read mux
    // -----------------------------------------------------
    always @(*) begin
        o_wb_dat = 32'b0;

        if (i_wb_cyc && i_wb_stb && !i_wb_we) begin
            if (!i_wb_adr[15]) begin
                // Array buffer read
                o_wb_dat = array_mem[i_wb_adr[14:2]];
            end else begin
                // Register-page read
                case (i_wb_adr[15:2])
                    14'h2000: o_wb_dat = {31'b0, 1'b0};
                    14'h2001: o_wb_dat = {
                        28'b0,
                        error_reg,
                        found_reg,
                        done_reg,
                        busy_reg
                    };
                    14'h2002: o_wb_dat = len_reg;
                    14'h2003: o_wb_dat = key_reg;
                    14'h2004: o_wb_dat = result_reg;
                    14'h2005: o_wb_dat = comps_reg;
                    default:  o_wb_dat = 32'b0;
                endcase
            end
        end
    end

    // -----------------------------------------------------
    // Search engine and register writes
    // -----------------------------------------------------
    always @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            len_reg    <= 32'b0;
            key_reg    <= 32'b0;
            result_reg <= 32'hFFFF_FFFF;
            comps_reg  <= 32'b0;

            busy_reg   <= 1'b0;
            done_reg   <= 1'b0;
            found_reg  <= 1'b0;
            error_reg  <= 1'b0;

            low_reg    <= 14'b0;
            high_reg   <= 14'b0;
        end else begin

            // =============================================
            // CPU/DMA Wishbone writes
            // =============================================
            if (i_wb_cyc && i_wb_stb && i_wb_we) begin

                if (!i_wb_adr[15]) begin
                    // Do not modify the input array mid-search.
                    if (!busy_reg)
                        array_mem[i_wb_adr[14:2]] <= i_wb_dat;

                end else if (!busy_reg) begin

                    case (i_wb_adr[15:2])

                        // CTRL: START has priority over CLEAR.
                        14'h2000: begin
                            if (i_wb_dat[0]) begin
                                done_reg   <= 1'b0;
                                found_reg  <= 1'b0;
                                error_reg  <= 1'b0;
                                result_reg <= 32'hFFFF_FFFF;
                                comps_reg  <= 32'b0;

                                if (len_reg > MAX_LEN) begin
                                    // Invalid length: finish with error.
                                    busy_reg <= 1'b0;
                                    done_reg <= 1'b1;
                                    error_reg <= 1'b1;
                                end else begin
                                    low_reg  <= 14'd0;
                                    high_reg <= len_reg[13:0];
                                    busy_reg <= 1'b1;
                                end

                            end else if (i_wb_dat[1]) begin
                                // Clear completion/error flags.
                                done_reg  <= 1'b0;
                                error_reg <= 1'b0;
                            end
                        end

                        14'h2002: len_reg <= i_wb_dat;
                        14'h2003: key_reg <= i_wb_dat;

                        default: begin
                            // Read-only or unmapped register.
                        end
                    endcase
                end
            end

            // =============================================
            // Binary-search engine
            // =============================================
            if (busy_reg) begin

                if (low_reg < high_reg) begin
                    // Find lower bound: first element >= key.
                    comps_reg <= comps_reg + 1'b1;

                    if (array_mem[mid_calc[12:0]] < key_reg)
                        low_reg <= mid_calc + 1'b1;
                    else
                        high_reg <= mid_calc;

                end else begin
                    // Lower bound reached. Check for equality.
                    busy_reg <= 1'b0;
                    done_reg <= 1'b1;

                    if (low_reg < len_reg[13:0]) begin
                        comps_reg <= comps_reg + 1'b1;

                        if (array_mem[low_reg[12:0]] == key_reg) begin
                            found_reg  <= 1'b1;
                            result_reg <= {18'b0, low_reg};
                        end else begin
                            found_reg  <= 1'b0;
                            result_reg <= 32'hFFFF_FFFF;
                        end
                    end else begin
                        found_reg  <= 1'b0;
                        result_reg <= 32'hFFFF_FFFF;
                    end
                end
            end
        end
    end

endmodule