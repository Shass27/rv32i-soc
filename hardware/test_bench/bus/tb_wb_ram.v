// tb_wb_ram.v — testbench for wb_ram Wishbone slave
// verifies: reset, write, read-back, ACK, o_wb_dat=0 during write

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
    // DUT instantiation
    // ----------------------------------------------------------------
    wb_ram #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) dut (
        .i_wb_clk(i_wb_clk), .i_wb_rst(i_wb_rst),
        .i_wb_adr(i_wb_adr), .i_wb_dat(i_wb_dat),
        .i_wb_we(i_wb_we),   .i_wb_stb(i_wb_stb),
        .i_wb_cyc(i_wb_cyc),
        .o_wb_dat(o_wb_dat), .o_wb_ack(o_wb_ack)
    );

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

    // drive bus idle between transactions
    task bus_idle;
        begin i_wb_stb = 0; i_wb_cyc = 0; i_wb_we = 0; end
    endtask

    // synchronous write: assert signals, clock, de-assert
    task wb_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(negedge i_wb_clk); // drive just before rising edge
            i_wb_adr = addr; i_wb_dat = data;
            i_wb_we = 1; i_wb_stb = 1; i_wb_cyc = 1;
            @(posedge i_wb_clk); // latch write
            #1; // let ACK settle
            check(o_wb_ack, 1, "ACK during write");
            check(o_wb_dat, 0, "o_wb_dat=0 during write");
            @(negedge i_wb_clk);
            bus_idle();
        end
    endtask

    // combinational read: assert read signals, check ACK + data same cycle
    task wb_read;
        input  [7:0]  addr;
        input  [31:0] exp_data;
        input  [127:0] tag;
        begin
            @(negedge i_wb_clk);
            i_wb_adr = addr; i_wb_dat = 0;
            i_wb_we = 0; i_wb_stb = 1; i_wb_cyc = 1;
            #1; // combinational settle
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
        $dumpfile("tb_wb_ram.vcd"); // waveform at project root
        $dumpvars(0, tb_wb_ram);

        // -- reset --
        bus_idle(); i_wb_rst = 1; i_wb_adr = 0; i_wb_dat = 0;
        @(posedge i_wb_clk); @(posedge i_wb_clk);
        i_wb_rst = 0;

        // T1: ACK=0 and o_wb_dat=0 when bus idle (no CYC/STB)
        #1;
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
        // read back — should still be 0 (write was blocked by rst)
        wb_read(8'hAA, 32'h0000_0000, "reset_write_blocked");

        // T3: basic write then read-back
        wb_write(8'h00, 32'hCAFE_BABE);
        wb_read (8'h00, 32'hCAFE_BABE, "write_readback_0x00");

        // T4: different address
        wb_write(8'h01, 32'h1234_5678);
        wb_read (8'h01, 32'h1234_5678, "write_readback_0x01");

        // T5: addresses are independent (0x00 still holds its value)
        wb_read(8'h00, 32'hCAFE_BABE, "independence_0x00");

        // T6: overwrite same address
        wb_write(8'h00, 32'hFFFF_FFFF);
        wb_read (8'h00, 32'hFFFF_FFFF, "overwrite_0x00");

        // T7: upper address boundary
        wb_write(8'hFF, 32'hABCD_EF01);
        wb_read (8'hFF, 32'hABCD_EF01, "boundary_0xFF");

        // T8: unaccessed location reads as 0
        wb_read(8'h80, 32'h0000_0000, "uninit_0x80");

        // T9: STB without CYC — no access (ACK=0, dat=0)
        @(negedge i_wb_clk);
        i_wb_adr = 8'h00; i_wb_we = 0; i_wb_stb = 1; i_wb_cyc = 0; #1;
        check(o_wb_ack, 0, "ACK=0 STB_without_CYC");
        check(o_wb_dat, 0, "DAT=0 STB_without_CYC");
        bus_idle();

        // T10: CYC without STB — no access
        @(negedge i_wb_clk);
        i_wb_adr = 8'h00; i_wb_we = 0; i_wb_stb = 0; i_wb_cyc = 1; #1;
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
