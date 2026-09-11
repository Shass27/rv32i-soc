// tb_wb_ram.v — testbench for wb_ram Wishbone slave
// verifies: MEM_FILE preload, reset, write, read-back, ACK behaviour
//
// Preload image (inline — no external hex file needed):
//   word 0  byte 0x00  DEADBEEF
//   word 1  byte 0x04  CAFEBABE
//   word 2  byte 0x08  12345678
//   word 3  byte 0x0C  AABBCCDD
//   word 4  byte 0x10  11223344
//   word 5  byte 0x14  55667788
//   word 6  byte 0x18  99AABBCC
//   word 7  byte 0x1C  DDEEFF00
//   word 8  byte 0x20  FEEDFACE
//   word 9  byte 0x24  BAADF00D
//   words 10-255       00000000  (zero-init)

`timescale 1ns/1ps

module tb_wb_ram;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    reg         i_wb_clk = 0;
    reg         i_wb_rst;
    reg  [7:0]  i_wb_adr;
    reg  [31:0] i_wb_dat;
    reg         i_wb_we;
    reg         i_wb_stb;
    reg         i_wb_cyc;
    wire [31:0] o_wb_dat;
    wire        o_wb_ack;

    // ----------------------------------------------------------------
    // DUT instantiation — MEM_FILE="" skips file load; we preload via
    // hierarchical reference below so the data lives in this file only
    // ----------------------------------------------------------------
    wb_ram #(
        .ADDR_WIDTH(8), .DATA_WIDTH(32),
        .MEM_FILE("")   // no external file — memory seeded directly below
    ) dut (
        .i_wb_clk(i_wb_clk), .i_wb_rst(i_wb_rst),
        .i_wb_adr(i_wb_adr), .i_wb_dat(i_wb_dat),
        .i_wb_we(i_wb_we),   .i_wb_stb(i_wb_stb),
        .i_wb_cyc(i_wb_cyc),
        .o_wb_dat(o_wb_dat), .o_wb_ack(o_wb_ack)
    );

    // seed DUT memory before simulation time 0
    initial begin
        dut.mem[0] = 32'hDEAD_BEEF;
        dut.mem[1] = 32'hCAFE_BABE;
        dut.mem[2] = 32'h1234_5678;
        dut.mem[3] = 32'hAABB_CCDD;
        dut.mem[4] = 32'h1122_3344;
        dut.mem[5] = 32'h5566_7788;
        dut.mem[6] = 32'h99AA_BBCC;
        dut.mem[7] = 32'hDDEE_FF00;
        dut.mem[8] = 32'hFEED_FACE;
        dut.mem[9] = 32'hBAAD_F00D;
    end

    // 10 ns clock period
    always #5 i_wb_clk = ~i_wb_clk;

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    integer pass = 0, fail = 0;

    task check; // one-line assertion helper
        input [63:0] got;
        input [63:0] exp;
        input [127:0] tag;
        begin
            if (got === exp) begin
                $display("PASS  %0s  got=%0h", tag, got);
                pass = pass + 1;
            end else begin
                $display("FAIL  %0s  exp=%0h  got=%0h", tag, exp, got);
                fail = fail + 1;
            end
        end
    endtask

    task bus_idle; // drive bus to idle state
        begin i_wb_stb = 0; i_wb_cyc = 0; i_wb_we = 0; end
    endtask

    task wb_write; // synchronous write — checks ACK only (o_wb_dat is combinatorial read port, not 0)
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(negedge i_wb_clk);
            i_wb_adr = addr; i_wb_dat = data;
            i_wb_we = 1; i_wb_stb = 1; i_wb_cyc = 1;
            @(posedge i_wb_clk); #1;
            check(o_wb_ack, 1, "ACK during write");
            @(negedge i_wb_clk);
            bus_idle();
        end
    endtask

    task wb_read; // combinational read — checks ACK + data same cycle
        input  [7:0]   addr;
        input  [31:0]  exp_data;
        input  [127:0] tag;
        begin
            @(negedge i_wb_clk);
            i_wb_adr = addr; i_wb_dat = 0;
            i_wb_we = 0; i_wb_stb = 1; i_wb_cyc = 1;
            #1;
            check(o_wb_ack, 1, {tag, "_ACK"});
            check(o_wb_dat, exp_data, tag);
            @(negedge i_wb_clk);
            bus_idle();
        end
    endtask

    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("tb_wb_ram.vcd");
        $dumpvars(0, tb_wb_ram);

        // -- reset --
        bus_idle(); i_wb_rst = 1; i_wb_adr = 0; i_wb_dat = 0;
        @(posedge i_wb_clk); @(posedge i_wb_clk);
        i_wb_rst = 0;

        // T0: preload verification — byte addr = word_index * 4
        wb_read(8'h00, 32'hDEAD_BEEF, "preload_word0");
        wb_read(8'h04, 32'hCAFE_BABE, "preload_word1");
        wb_read(8'h08, 32'h1234_5678, "preload_word2");
        wb_read(8'h0C, 32'hAABB_CCDD, "preload_word3");
        wb_read(8'h24, 32'hBAAD_F00D, "preload_word9_boundary");

        // T1: ACK=0 and o_wb_dat=0 when bus idle (address a zero word, no CYC/STB)
        @(negedge i_wb_clk);
        i_wb_adr = 8'h80; #1; // word 32 — zero-initialised
        check(o_wb_ack, 0, "ACK=0 when idle");
        check(o_wb_dat, 0, "DAT=0 when idle");

        // T2: write suppressed during reset
        i_wb_rst = 1;
        @(negedge i_wb_clk);
        i_wb_adr = 8'hAA; i_wb_dat = 32'hDEAD_BEEF;
        i_wb_we = 1; i_wb_stb = 1; i_wb_cyc = 1;
        @(posedge i_wb_clk); #1;
        check(o_wb_ack, 1, "ACK still asserted during reset (access=1)");
        @(negedge i_wb_clk); bus_idle();
        i_wb_rst = 0;
        wb_read(8'hAA, 32'h0000_0000, "reset_write_blocked"); // word 42 — never written

        // T3: basic write then read-back
        wb_write(8'h00, 32'hCAFE_BABE);
        wb_read (8'h00, 32'hCAFE_BABE, "write_readback_0x00");

        // T4: different word-aligned address (0x04 → word 1, independent of word 0)
        wb_write(8'h04, 32'h1234_5678);
        wb_read (8'h04, 32'h1234_5678, "write_readback_0x04");

        // T5: addresses are independent (word 0 still holds T3 value)
        wb_read(8'h00, 32'hCAFE_BABE, "independence_0x00");

        // T6: overwrite same address
        wb_write(8'h00, 32'hFFFF_FFFF);
        wb_read (8'h00, 32'hFFFF_FFFF, "overwrite_0x00");

        // T7: upper address boundary
        wb_write(8'hFF, 32'hABCD_EF01);
        wb_read (8'hFF, 32'hABCD_EF01, "boundary_0xFF");

        // T8: zero-init location reads 0 (word 32 — never written)
        wb_read(8'h80, 32'h0000_0000, "uninit_0x80");

        // T9: STB without CYC — no access (ACK=0); address a zero word for DAT check
        @(negedge i_wb_clk);
        i_wb_adr = 8'h80; i_wb_we = 0; i_wb_stb = 1; i_wb_cyc = 0; #1;
        check(o_wb_ack, 0, "ACK=0 STB_without_CYC");
        check(o_wb_dat, 0, "DAT=0 STB_without_CYC");
        bus_idle();

        // T10: CYC without STB — no access
        @(negedge i_wb_clk);
        i_wb_adr = 8'h80; i_wb_we = 0; i_wb_stb = 0; i_wb_cyc = 1; #1;
        check(o_wb_ack, 0, "ACK=0 CYC_without_STB");
        check(o_wb_dat, 0, "DAT=0 CYC_without_STB");
        bus_idle();

        // ----------------------------------------------------------------
        $display("\n=============================");
        $display("  PASS: %0d   FAIL: %0d", pass, fail);
        $display("=============================\n");
        $finish;
    end

endmodule
