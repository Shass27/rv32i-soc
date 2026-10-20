// Self-checking bench for wb_mac_accel.v (4x4 systolic matrix MAC, 256-bit tile port)
// Icarus:  iverilog -g2012 -s tb_wb_mac_accel -o sim tb_wb_mac_accel.v ../../src/bus/wb_mac_accel.v && vvp sim
//          (add -Ptb_wb_mac_accel.MEM_LAT=1 -Ptb_wb_mac_accel.MULT_PIPE=1 to test the other options)
`timescale 1ns/1ps
module tb_wb_mac_accel;
    parameter MEM_LAT   = 0;
    parameter MULT_PIPE = 0;
    localparam [31:0] BASE = 32'h0000_4000;
    localparam [31:0] P    = 32'h1000_0000;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg  [31:0] adr = 0, dat = 0;
    reg         we = 0, stb = 0, cyc = 0;
    wire [31:0] rdat;
    wire        ack, err, irq;
    wire [31:0] mem_addr;
    wire [255:0] tile;

    reg [255:0] mem [0:255];
    wire [31:0] idx = (mem_addr - BASE) >> 5;

    generate
        if (MEM_LAT == 0) begin : G_ASYNC
            assign tile = (idx < 256) ? mem[idx] : {256{1'bx}};
        end else begin : G_SYNC
            reg [255:0] tile_r;
            always @(posedge clk) tile_r <= (idx < 256) ? mem[idx] : {256{1'bx}};
            assign tile = tile_r;
        end
    endgenerate

    wb_mac_accel #(.K_MAX(256), .MEM_LAT(MEM_LAT), .MULT_PIPE(MULT_PIPE)) dut (
        .i_wb_clk(clk), .i_wb_rst(rst),
        .i_wb_adr(adr), .i_wb_dat(dat), .i_wb_we(we), .i_wb_stb(stb), .i_wb_cyc(cyc),
        .o_wb_dat(rdat), .o_wb_ack(ack), .o_wb_err(err), .o_irq(irq),
        .o_mem_tile_addr(mem_addr), .i_mem_tile(tile));

    task wb_write(input [15:0] off, input [31:0] d);
        begin
            @(negedge clk); adr = P | off; dat = d; we = 1; stb = 1; cyc = 1;
            @(negedge clk); we = 0; stb = 0; cyc = 0;
        end
    endtask

    task wb_read(input [15:0] off, output [31:0] d);
        begin
            @(negedge clk); adr = P | off; we = 0; stb = 1; cyc = 1;
            #1 d = rdat;
            @(negedge clk); stb = 0; cyc = 0;
        end
    endtask

    integer run_cycles, errors, tests;
    reg [31:0] max_addr;
    always @(posedge clk) begin
        if (dut.state == 2'd2) begin
            run_cycles = run_cycles + 1;
            if (mem_addr > max_addr) max_addr = mem_addr;
        end
    end

    reg signed [31:0] Am [0:4*256-1];
    reg signed [31:0] Bm [0:4*256-1];

    task run_test(input integer K, input integer mode);
        integer r, c, k;
        reg signed [63:0] ref_c, p;
        reg [31:0] lo, hi, st;
        reg signed [31:0] v;
        begin
            for (k = 0; k < K; k = k + 1) begin
                for (r = 0; r < 4; r = r + 1) begin
                    case (mode)
                        0: v = $random;
                        1: v = (($random & 3) == 0) ? 32'sh8000_0000 :
                               (($random & 1) ? 32'sh7FFF_FFFF : -1);
                        default: v = ($random % 11) - 5;
                    endcase
                    Am[r*256+k] = v;
                    mem[k][32*r +: 32] = v;
                end
                for (c = 0; c < 4; c = c + 1) begin
                    case (mode)
                        0: v = $random;
                        1: v = (($random & 3) == 0) ? 32'sh8000_0000 :
                               (($random & 1) ? 32'sh7FFF_FFFF : -1);
                        default: v = ($random % 11) - 5;
                    endcase
                    Bm[k*4+c] = v;
                    mem[k][128 + 32*c +: 32] = v;
                end
            end
            wb_write(16'h8000, BASE);
            wb_write(16'h8004, K);
            run_cycles = 0; max_addr = 0;
            wb_write(16'h8008, 32'h1);
            st = 0;
            while (!st[1]) wb_read(16'h800C, st);
            for (r = 0; r < 4; r = r + 1)
                for (c = 0; c < 4; c = c + 1) begin
                    ref_c = 0;
                    for (k = 0; k < K; k = k + 1) begin
                        p = Am[r*256+k] * Bm[k*4+c];
                        ref_c = ref_c + p;
                    end
                    wb_read((r*4+c)*8,     lo);
                    wb_read((r*4+c)*8 + 4, hi);
                    if ({hi, lo} !== ref_c) begin
                        errors = errors + 1;
                        $display("MISMATCH K=%0d mode=%0d C[%0d][%0d] got %h exp %h",
                                 K, mode, r, c, {hi, lo}, ref_c);
                    end
                end
            if (run_cycles != K + 6 + MEM_LAT + MULT_PIPE) begin
                errors = errors + 1;
                $display("LATENCY K=%0d: %0d RUN cycles, expected %0d",
                         K, run_cycles, K + 6 + MEM_LAT + MULT_PIPE);
            end
            if (max_addr != BASE + 32*(K-1)) begin
                errors = errors + 1;
                $display("ADDR K=%0d: max addr %h, expected %h", K, max_addr, BASE + 32*(K-1));
            end
            wb_write(16'h800C, 32'h2);     // clear DONE
            tests = tests + 1;
        end
    endtask

    integer i, m;
    reg [31:0] rb;
    initial begin
        errors = 0; tests = 0; run_cycles = 0; max_addr = 0;
        repeat (4) @(negedge clk);
        rst = 0;
        // K clamp
        wb_write(16'h8004, 32'd300);
        wb_read(16'h8004, rb);
        if (rb !== 32'd256) begin errors = errors + 1; $display("K clamp failed: %0d", rb); end

        for (m = 0; m < 3; m = m + 1) begin
            run_test(1, m);  run_test(2, m);  run_test(3, m);  run_test(4, m);
            run_test(5, m);  run_test(6, m);  run_test(7, m);  run_test(8, m);
            run_test(9, m);  run_test(16, m); run_test(33, m); run_test(100, m);
            run_test(255, m); run_test(256, m);
        end
        for (i = 0; i < 30; i = i + 1) run_test(1 + ($random & 63), i % 3);

        // CLEAR_RESULTS must zero the array
        wb_write(16'h8008, 32'h2);
        for (i = 0; i < 32; i = i + 1) begin
            wb_read(i*4, rb);
            if (rb !== 0) begin errors = errors + 1; $display("CLEAR failed word %0d", i); end
        end

        if (errors == 0) $display("PASS: %0d tests (MEM_LAT=%0d MULT_PIPE=%0d)", tests, MEM_LAT, MULT_PIPE);
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

    initial begin #200000000; $display("TIMEOUT"); $finish; end
endmodule
