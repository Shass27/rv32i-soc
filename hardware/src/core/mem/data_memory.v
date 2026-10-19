```verilog
module data_memory #(
    parameter MEM_SIZE = 4097,
    // Address used by riscv-tests proxy to report pass/fail
    parameter TOHOST_ADDR = 32'h000001c0
)(
    input  wire        clk,
    input  wire        MemWrite,
    input  wire        MemRead,
    input  wire [2:0]  funct3,

    input  wire [31:0] mem_addr,
    input  wire [31:0] rs2_data,
    output reg  [31:0] mem_rdata,

    // DMA Port B
    input  wire        i_b_we,
    input  wire [31:0] i_b_addr,
    input  wire [31:0] i_b_wdat,
    output wire [31:0] o_b_rdat
);

    // =========================================================
    // MEMORY
    // =========================================================

    // Request distributed RAM implementation from Vivado.
    (* ram_style = "distributed" *)
    reg [31:0] memory [0:MEM_SIZE-1];

    wire [31:0] word_index;
    wire [31:0] b_word_index;
    wire [1:0]  byte_offset;

    assign word_index   = mem_addr >> 2;
    assign b_word_index = i_b_addr >> 2;
    assign byte_offset  = mem_addr[1:0];

    // =========================================================
    // TOHOST
    // =========================================================

    reg [31:0] tohost;

    initial begin
        $readmemh("hardware/src/core/mem/data.hex", memory);
        tohost = 32'b0;
    end

    // =========================================================
    // DMA PORT B: ASYNCHRONOUS WORD READ
    // =========================================================

    assign o_b_rdat = memory[b_word_index];

    // =========================================================
    // CPU: ASYNCHRONOUS READ
    // =========================================================

    always @(*) begin

        // Default value prevents unintended latch inference.
        mem_rdata = 32'b0;

        if (MemRead) begin

            case (funct3)

                // -------------------------------------------------
                // LB: Load Byte, Sign Extended
                // -------------------------------------------------

                3'b000: begin
                    case (byte_offset)

                        2'b00:
                            mem_rdata =
                                {{24{memory[word_index][7]}},
                                  memory[word_index][7:0]};

                        2'b01:
                            mem_rdata =
                                {{24{memory[word_index][15]}},
                                  memory[word_index][15:8]};

                        2'b10:
                            mem_rdata =
                                {{24{memory[word_index][23]}},
                                  memory[word_index][23:16]};

                        2'b11:
                            mem_rdata =
                                {{24{memory[word_index][31]}},
                                  memory[word_index][31:24]};

                    endcase
                end

                // -------------------------------------------------
                // LH: Load Halfword, Sign Extended
                // -------------------------------------------------

                3'b001: begin
                    case (byte_offset)

                        2'b00:
                            mem_rdata =
                                {{16{memory[word_index][15]}},
                                  memory[word_index][15:0]};

                        2'b10:
                            mem_rdata =
                                {{16{memory[word_index][31]}},
                                  memory[word_index][31:16]};

                        default:
                            mem_rdata = 32'b0;

                    endcase
                end

                // -------------------------------------------------
                // LW: Load Word
                // -------------------------------------------------

                3'b010:
                    mem_rdata = memory[word_index];

                // -------------------------------------------------
                // LBU: Load Byte, Zero Extended
                // -------------------------------------------------

                3'b100: begin
                    case (byte_offset)

                        2'b00:
                            mem_rdata =
                                {24'b0, memory[word_index][7:0]};

                        2'b01:
                            mem_rdata =
                                {24'b0, memory[word_index][15:8]};

                        2'b10:
                            mem_rdata =
                                {24'b0, memory[word_index][23:16]};

                        2'b11:
                            mem_rdata =
                                {24'b0, memory[word_index][31:24]};

                    endcase
                end

                // -------------------------------------------------
                // LHU: Load Halfword, Zero Extended
                // -------------------------------------------------

                3'b101: begin
                    case (byte_offset)

                        2'b00:
                            mem_rdata =
                                {16'b0, memory[word_index][15:0]};

                        2'b10:
                            mem_rdata =
                                {16'b0, memory[word_index][31:16]};

                        default:
                            mem_rdata = 32'b0;

                    endcase
                end

                default:
                    mem_rdata = 32'b0;

            endcase
        end
    end

    // =========================================================
    // SYNCHRONOUS WRITES: CPU AND DMA
    // =========================================================

    // Both write ports are handled in this one clocked block.
    //
    // Priority:
    //   1. CPU write, when MemWrite = 1
    //   2. DMA write, when MemWrite = 0 and i_b_we = 1
    //
    // This assumes the SoC prevents conflicting simultaneous
    // CPU and DMA writes.

    always @(posedge clk) begin

        // -------------------------------------------------------
        // CPU WRITE
        // -------------------------------------------------------

        if (MemWrite) begin

            // TOHOST: intercept the test pass/fail address.
            if (mem_addr == TOHOST_ADDR) begin

                tohost <= rs2_data;

                // Writing 1 indicates PASS.
                if (rs2_data == 32'h00000001) begin
                    $display(
                        "TOHOST: PASS (tohost=0x%h)",
                        rs2_data
                    );
                    $finish;
                end

                // Any nonzero value other than 1 indicates FAIL.
                else if (rs2_data != 32'h00000000) begin
                    $display(
                        "TOHOST: FAIL (tohost=0x%h)",
                        rs2_data
                    );
                    $finish;
                end

            end
            else begin

                case (funct3)

                    // -------------------------------------------------
                    // SB: Store Byte
                    // -------------------------------------------------

                    3'b000: begin
                        case (byte_offset)

                            2'b00:
                                memory[word_index][7:0]
                                    <= rs2_data[7:0];

                            2'b01:
                                memory[word_index][15:8]
                                    <= rs2_data[7:0];

                            2'b10:
                                memory[word_index][23:16]
                                    <= rs2_data[7:0];

                            2'b11:
                                memory[word_index][31:24]
                                    <= rs2_data[7:0];

                        endcase
                    end

                    // -------------------------------------------------
                    // SH: Store Halfword
                    // -------------------------------------------------

                    3'b001: begin
                        case (byte_offset)

                            2'b00:
                                memory[word_index][15:0]
                                    <= rs2_data[15:0];

                            2'b10:
                                memory[word_index][31:16]
                                    <= rs2_data[15:0];

                            default:
                                ;

                        endcase
                    end

                    // -------------------------------------------------
                    // SW: Store Word
                    // -------------------------------------------------

                    3'b010:
                        memory[word_index] <= rs2_data;

                    default:
                        ;

                endcase
            end
        end

        // -------------------------------------------------------
        // DMA WRITE: WORD ONLY
        // -------------------------------------------------------

        else if (i_b_we) begin

            memory[b_word_index] <= i_b_wdat;

        end

    end

endmodule