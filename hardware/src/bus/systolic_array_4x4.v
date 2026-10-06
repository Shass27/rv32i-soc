// systolic_array_4x4.v — 4×4 Systolic Array for Matrix Multiplication
// Computes: C = A × B where A is 4×K, B is K×4, C is 4×4
// Uses 16 Processing Elements (PEs) arranged in 2D grid
// Data flows: A left-to-right (each cycle), B top-to-bottom (each cycle)
// Result: Accumulation in each PE after K pipeline stages
//
// Performance: K + 4 + 4 - 2 = K + 6 cycles total (K cycles to fill, 6 to drain)
// For K=4: 10 cycles per 4×4×4 matrix multiply
// vs. single MAC: 64 cycles (6.4× speedup)

module systolic_array_4x4 #(
    parameter DATA_WIDTH = 32,
    parameter K_MAX = 256,  // Max reduction dimension
    parameter K_AW = 8      // Address width for K_MAX
)(
    input  wire                     i_clk,
    input  wire                     i_rst,

    // Control interface
    input  wire                     i_start,
    input  wire [K_AW-1:0]          i_k,          // Number of products to accumulate
    output wire                     o_busy,
    output wire                     o_done,

    // Data injection (A flows left-to-right, B flows top-to-bottom)
    input  wire [DATA_WIDTH-1:0]    i_a_in [0:3],   // 4 A values per cycle
    input  wire [DATA_WIDTH-1:0]    i_b_in [0:3],   // 4 B values per cycle
    input  wire                     i_data_valid,   // strobe for A/B injection

    // Result readout (16 accumulators, each 64-bit)
    output wire [63:0]              o_c [0:15],     // C[row*4 + col]
    output wire                     o_c_valid       // results ready
);

    localparam ACC_WIDTH = 2 * DATA_WIDTH;  // 64-bit accumulator
    localparam PIPE_DEPTH = 4;              // K values pipeline through array

    // ========================================================================
    // States: IDLE → LOAD → COMPUTE → DRAIN → DONE
    // ========================================================================
    localparam IDLE    = 3'd0;
    localparam LOAD    = 3'd1;  // Loading K cycles of A/B data
    localparam COMPUTE = 3'd2;  // Computing (K cycles)
    localparam DRAIN   = 3'd3;  // Draining pipeline (PIPE_DEPTH cycles)
    localparam DONE_S  = 3'd4;  // Results ready

    reg [2:0]  state;
    reg [K_AW:0]  cycle_cnt, k_val;
    reg [K_AW:0]  k_idx;

    // ========================================================================
    // Array of 16 Processing Elements (4×4 grid)
    // PE(i,j) computes row i, column j of result
    // ========================================================================

    // Pipelines for A (left-to-right) and B (top-to-bottom)
    // A_pipe[i][k] = row i, stage k
    // B_pipe[j][k] = col j, stage k
    reg signed [DATA_WIDTH-1:0]  a_pipe [0:3][0:PIPE_DEPTH-1];
    reg signed [DATA_WIDTH-1:0]  b_pipe [0:3][0:PIPE_DEPTH-1];

    // Accumulators in each PE
    reg signed [ACC_WIDTH-1:0]   pe_acc [0:3][0:3];

    genvar gi, gj, gk;

    // Compute products: PE(i,j) multiplies a_pipe[i][PIPE_DEPTH-1] × b_pipe[j][PIPE_DEPTH-1]
    wire signed [ACC_WIDTH-1:0]  product [0:3][0:3];
    wire signed [ACC_WIDTH-1:0]  pe_acc_next [0:3][0:3];

    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : gen_rows
            for (gj = 0; gj < 4; gj = gj + 1) begin : gen_cols
                assign product[gi][gj] = 
                    $signed(a_pipe[gi][PIPE_DEPTH-1]) * 
                    $signed(b_pipe[gj][PIPE_DEPTH-1]);
                
                assign pe_acc_next[gi][gj] = pe_acc[gi][gj] + product[gi][gj];
            end
        end
    endgenerate

    // ========================================================================
    // Control FSM
    // ========================================================================
    assign o_busy = (state != IDLE);
    assign o_done = (state == DONE_S);

    always @(posedge i_clk) begin
        if (i_rst) begin
            state     <= IDLE;
            cycle_cnt <= 0;
            k_val     <= 0;
            k_idx     <= 0;
        end else begin
            case (state)

                IDLE: begin
                    if (i_start) begin
                        state   <= LOAD;
                        k_val   <= i_k;
                        k_idx   <= 0;
                        cycle_cnt <= 0;
                    end
                end

                LOAD: begin
                    // Inject K cycles of A and B data
                    if (k_idx < k_val) begin
                        k_idx <= k_idx + 1;
                    end

                    if (cycle_cnt < k_val) begin
                        cycle_cnt <= cycle_cnt + 1;
                    end else begin
                        state <= COMPUTE;
                        cycle_cnt <= 0;
                    end
                end

                COMPUTE: begin
                    // Continue pipelined computation for PIPE_DEPTH - 1 cycles
                    // (one more than k_val since pipeline is PIPE_DEPTH stages)
                    if (cycle_cnt < (PIPE_DEPTH - 1)) begin
                        cycle_cnt <= cycle_cnt + 1;
                    end else begin
                        state <= DRAIN;
                        cycle_cnt <= 0;
                    end
                end

                DRAIN: begin
                    // Let results settle (optional, combinational in this design)
                    if (cycle_cnt < 1) begin
                        cycle_cnt <= cycle_cnt + 1;
                    end else begin
                        state <= DONE_S;
                    end
                end

                DONE_S: begin
                    state <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

    // ========================================================================
    // Data Flow: A Shift Left, B Shift Down
    // ========================================================================
    always @(posedge i_clk) begin
        if (i_rst) begin
            for (gi = 0; gi < 4; gi = gi + 1) begin
                for (gk = 0; gk < PIPE_DEPTH; gk = gk + 1) begin
                    a_pipe[gi][gk] <= 0;
                    b_pipe[gi][gk] <= 0;
                end
            end
        end else if (state == LOAD && i_data_valid && k_idx < k_val) begin
            // Inject A column and B row into pipeline
            for (gi = 0; gi < 4; gi = gi + 1) begin
                // Shift A right: a_pipe[i][0] <= a_in[i], others shift
                a_pipe[gi][0] <= i_a_in[gi];
                for (gk = 1; gk < PIPE_DEPTH; gk = gk + 1) begin
                    a_pipe[gi][gk] <= a_pipe[gi][gk-1];
                end

                // Shift B down: b_pipe[j][0] <= b_in[j], others shift
                b_pipe[gi][0] <= i_b_in[gi];
                for (gk = 1; gk < PIPE_DEPTH; gk = gk + 1) begin
                    b_pipe[gi][gk] <= b_pipe[gi][gk-1];
                end
            end
        end else if (state == COMPUTE || state == DRAIN) begin
            // Continue shifting even after LOAD to drain pipeline
            for (gi = 0; gi < 4; gi = gi + 1) begin
                for (gk = 1; gk < PIPE_DEPTH; gk = gk + 1) begin
                    a_pipe[gi][gk] <= a_pipe[gi][gk-1];
                    b_pipe[gi][gk] <= b_pipe[gi][gk-1];
                end
                a_pipe[gi][0] <= 0;
                b_pipe[gi][0] <= 0;
            end
        end
    end

    // ========================================================================
    // Accumulation: Update after pipeline has valid products
    // ========================================================================
    always @(posedge i_clk) begin
        if (i_rst) begin
            for (gi = 0; gi < 4; gi = gi + 1) begin
                for (gj = 0; gj < 4; gj = gj + 1) begin
                    pe_acc[gi][gj] <= 0;
                end
            end
        end else if (state == IDLE && i_start) begin
            // Clear accumulators on start
            for (gi = 0; gi < 4; gi = gi + 1) begin
                for (gj = 0; gj < 4; gj = gj + 1) begin
                    pe_acc[gi][gj] <= 0;
                end
            end
        end else if ((state == LOAD || state == COMPUTE || state == DRAIN) && cycle_cnt >= (PIPE_DEPTH - 1)) begin
            // Valid products after pipeline is full
            for (gi = 0; gi < 4; gi = gi + 1) begin
                for (gj = 0; gj < 4; gj = gj + 1) begin
                    pe_acc[gi][gj] <= pe_acc_next[gi][gj];
                end
            end
        end
    end

    // ========================================================================
    // Output: Read results from accumulators (combinational)
    // ========================================================================
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : gen_out_rows
            for (gj = 0; gj < 4; gj = gj + 1) begin : gen_out_cols
                assign o_c[gi * 4 + gj] = pe_acc[gi][gj];
            end
        end
    endgenerate

    assign o_c_valid = (state == DONE_S);

endmodule
