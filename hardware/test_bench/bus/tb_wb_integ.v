// tb_wb_integ.v — integration testbench: wb_master + wb_ram end-to-end
// all Wishbone signals are real wires; no manual ack/dat driving

`timescale 1ns/1ps

module tb_wb_integ;

    // ----------------------------------------------------------------
    // System signals
    // ----------------------------------------------------------------
    reg clk = 0;
    reg rst;
    always #5 clk = ~clk; // 10 ns

    // ----------------------------------------------------------------
    // User-side → master
    // ----------------------------------------------------------------
    reg         i_req;
    reg         i_we;
    reg  [31:0] i_addr;
    reg  [31:0] i_wdat;

    // ----------------------------------------------------------------
    // Master outputs → user
    // ----------------------------------------------------------------
    wire [31:0] o_rdat;
    wire        o_busy;
    wire        o_done;

    // ----------------------------------------------------------------
    // Wishbone bus wires (master ↔ ram)
    // ----------------------------------------------------------------
    wire        wb_cyc;
    wire        wb_stb;
    wire        wb_we;
    wire [31:0] wb_adr;
    wire [31:0] wb_dat_ms; // master → slave
    wire [31:0] wb_dat_sm; // slave  → master
    wire        wb_ack;

    // ----------------------------------------------------------------
    // DUT: wb_master
    // ----------------------------------------------------------------
    wb_master #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) u_master (
        .i_clk    (clk),     .i_rst    (rst),
        .i_req    (i_req),   .i_we     (i_we),
        .i_addr   (i_addr),  .i_wdat   (i_wdat),
        .o_rdat   (o_rdat),  .o_busy   (o_busy),   .o_done (o_done),
        .o_wb_cyc (wb_cyc),  .o_wb_stb (wb_stb),   .o_wb_we(wb_we),
        .o_wb_adr (wb_adr),  .o_wb_dat (wb_dat_ms),
        .i_wb_dat (wb_dat_sm), .i_wb_ack(wb_ack)
    );

    // ----------------------------------------------------------------
    // DUT: wb_ram  (MEM_FILE="" — memory seeded below via hier ref)
    // ----------------------------------------------------------------
    wb_ram #(.ADDR_WIDTH(8), .DATA_WIDTH(32), .MEM_FILE("")) u_ram (
        .i_wb_clk (clk),     .i_wb_rst (rst),
        .i_wb_adr (wb_adr),  .i_wb_dat (wb_dat_ms),
        .i_wb_we  (wb_we),   .i_wb_stb (wb_stb),
        .i_wb_cyc (wb_cyc),
        .o_wb_dat (wb_dat_sm), .o_wb_ack(wb_ack)
    );

    // seed known words before time 0
    initial begin
        u_ram.mem[0] = 32'hDEAD_BEEF; // byte addr 0x00
        u_ram.mem[1] = 32'hCAFE_BABE; // byte addr 0x04
        u_ram.mem[2] = 32'h1234_5678; // byte addr 0x08
    end

    // ----------------------------------------------------------------
    // Waveform dump — explicit signal order:
    //   clk, rst | user inputs | user outputs | wishbone bus
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("tb_wb_integ.vcd");
        $dumpvars(0, clk, rst,
                     i_req, i_we, i_addr, i_wdat,
                     o_rdat, o_busy, o_done,
                     wb_cyc, wb_stb, wb_we, wb_adr,
                     wb_dat_ms, wb_dat_sm, wb_ack);
    end

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    integer pass = 0, fail = 0;

    task check;
        input [63:0]  got;
        input [63:0]  exp;
        input [127:0] tag;
        begin
            if (got === exp) begin $display("PASS  %0s", tag); pass = pass + 1; end
            else             begin $display("FAIL  %0s  exp=%0h  got=%0h", tag, exp, got); fail = fail + 1; end
        end
    endtask

    // issue one transaction and wait for o_done
    task wb_txn;
        input        we;
        input [31:0] addr;
        input [31:0] wdata;
        begin
            @(negedge clk);
            i_req = 1; i_we = we; i_addr = addr; i_wdat = wdata;
            @(posedge clk); #1; i_req = 0; // one-cycle req pulse
            // wait for master to complete (o_done pulse)
            @(posedge o_done); #1;
        end
    endtask

    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        i_req = 0; i_we = 0; i_addr = 0; i_wdat = 0;
        rst = 1; repeat(2) @(posedge clk); rst = 0; #1;

        // T1: bus quiet after reset
        check(wb_cyc, 0, "T1_cyc=0_idle");
        check(wb_stb, 0, "T1_stb=0_idle");
        check(o_busy, 0, "T1_busy=0_idle");
        check(wb_ack, 0, "T1_ack=0_idle");

        // T2: read preloaded word 0 (byte addr 0x00 → mem[0] = DEADBEEF)
        wb_txn(0, 32'h00, 0);
        check(o_rdat, 32'hDEAD_BEEF, "T2_preload_word0");

        // T3: read preloaded word 1 (byte addr 0x04 → mem[1] = CAFEBABE)
        wb_txn(0, 32'h04, 0);
        check(o_rdat, 32'hCAFE_BABE, "T3_preload_word1");

        // T4: write to word 5 (byte addr 0x14) then read back
        wb_txn(1, 32'h14, 32'hBEEF_CAFE);
        wb_txn(0, 32'h14, 0);
        check(o_rdat, 32'hBEEF_CAFE, "T4_write_readback");

        // T5: Wishbone handshake — cyc+stb asserted when busy, ack completes it
        @(negedge clk);
        i_req = 1; i_we = 0; i_addr = 32'h08; i_wdat = 0;
        @(posedge clk); #1; i_req = 0;
        check(wb_cyc, 1, "T5_cyc=1_during_txn");
        check(wb_stb, 1, "T5_stb=1_during_txn");
        check(o_busy, 1, "T5_busy=1_during_txn");
        @(posedge o_done); #1;
        check(o_rdat,  32'h1234_5678, "T5_read_word2");
        check(wb_cyc,  0, "T5_cyc=0_after_ack");
        check(wb_stb,  0, "T5_stb=0_after_ack");
        check(o_busy,  0, "T5_busy=0_after_ack");
        check(wb_ack,  0, "T5_ack=0_after_txn");

        // T6: o_done pulses exactly one cycle
        @(negedge clk);
        i_req = 1; i_we = 0; i_addr = 32'h00; i_wdat = 0;
        @(posedge clk); #1; i_req = 0;
        @(posedge o_done);          // catch the rising edge
        check(o_done, 1, "T6_done=1_on_ack");
        @(posedge clk); #1;
        check(o_done, 0, "T6_done=0_next_cycle");

        // T7: overwrite then verify
        wb_txn(1, 32'h00, 32'hFFFF_FFFF);
        wb_txn(0, 32'h00, 0);
        check(o_rdat, 32'hFFFF_FFFF, "T7_overwrite_word0");

        // T8: back-to-back — write addr 0x20, read it back immediately
        wb_txn(1, 32'h20, 32'hA5A5_5A5A);
        wb_txn(0, 32'h20, 0);
        check(o_rdat, 32'hA5A5_5A5A, "T8_back_to_back");

        // T9: address independence — word 0 holds T7 value after T8
        wb_txn(0, 32'h00, 0);
        check(o_rdat, 32'hFFFF_FFFF, "T9_addr_independence");

        // T10: unwritten location returns 0 (word 20 = byte 0x50)
        wb_txn(0, 32'h50, 0);
        check(o_rdat, 32'h0000_0000, "T10_uninit_reads_zero");

        $display("\n=============================");
        $display("  PASS: %0d   FAIL: %0d", pass, fail);
        $display("=============================\n");
        $finish;
    end

endmodule
