// tb_wb_mac_accel.v — unit testbench for wb_mac_accel (bare Wishbone slave drive)
// verifies: reset, bus guards, BUF_A/BUF_B memory, control registers,
//           signed MAC engine, BUSY/DONE handshake, IRQ
//
// Engine timing: START written at posedge N -> RUN for LEN edges -> FIN at N+LEN+1,
// so DONE appears LEN+2 posedges after the START write. The TB polls STATUS instead.

`timescale 1ns/1ps
`include "wb_defs.vh"

module tb_wb_mac_accel;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    reg         i_wb_clk = 0;
    reg         i_wb_rst;
    reg  [31:0] i_wb_adr;
    reg  [31:0] i_wb_dat;
    reg         i_wb_we;
    reg         i_wb_stb;
    reg         i_wb_cyc;
    wire [31:0] o_wb_dat;
    wire        o_wb_ack;
    wire        o_wb_err;
    wire        o_irq;

    wb_mac_accel #(
        .ADDR_WIDTH(16), .DATA_WIDTH(32), .BUF_AW(12)
    ) dut (
        .i_wb_clk(i_wb_clk), .i_wb_rst(i_wb_rst),
        .i_wb_adr(i_wb_adr), .i_wb_dat(i_wb_dat),
        .i_wb_we (i_wb_we),  .i_wb_stb(i_wb_stb),
        .i_wb_cyc(i_wb_cyc),
        .o_wb_dat(o_wb_dat), .o_wb_ack(o_wb_ack), .o_wb_err(o_wb_err),
        .o_irq   (o_irq)
    );

    always #5 i_wb_clk = ~i_wb_clk; // 10 ns period

    // ----------------------------------------------------------------
    // Waveform dump — explicit order: clk, rst | inputs | outputs | internals
    // buf_a/buf_b arrays are not dumped by iverilog; mul_a/mul_b/product
    // expose the buffer contents the engine is consuming each cycle
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("tb_wb_mac_accel.vcd");
        $dumpvars(0, i_wb_clk, i_wb_rst,
                     i_wb_adr, i_wb_dat, i_wb_we, i_wb_stb, i_wb_cyc,
                     o_wb_dat, o_wb_ack, o_wb_err, o_irq,
                     dut.state, dut.busy, dut.done, dut.len, dut.idx, dut.acc,
                     dut.sel_a, dut.sel_b, dut.sel_regs,
                     dut.reg_idx, dut.bus_word,
                     dut.eng_word, dut.mul_a, dut.mul_b, dut.product);
    end

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    integer pass = 0, fail = 0;
    reg [31:0] rd_tmp;   // scratch for polled reads
    integer    poll_n;

    task check; // one-line assertion helper
        input [63:0]  got;
        input [63:0]  exp;
        input [255:0] tag;
        begin
            if (got === exp) begin $display("PASS  %0s", tag); pass = pass + 1; end
            else             begin $display("FAIL  %0s  exp=%0h  got=%0h", tag, exp, got); fail = fail + 1; end
        end
    endtask

    task bus_idle; // drive bus to idle state
        begin i_wb_stb = 0; i_wb_cyc = 0; i_wb_we = 0; end
    endtask

    task wb_write; // synchronous write — one cycle, no checks
        input [31:0] addr;
        input [31:0] data;
        begin
            @(negedge i_wb_clk);
            i_wb_adr = addr; i_wb_dat = data;
            i_wb_we = 1; i_wb_stb = 1; i_wb_cyc = 1;
            @(posedge i_wb_clk); #1;
            @(negedge i_wb_clk);
            bus_idle();
        end
    endtask

    task wb_write_chk; // same as wb_write but also checks ACK/ERR during the write
        input [31:0]  addr;
        input [31:0]  data;
        input [255:0] tag;
        begin
            @(negedge i_wb_clk);
            i_wb_adr = addr; i_wb_dat = data;
            i_wb_we = 1; i_wb_stb = 1; i_wb_cyc = 1;
            @(posedge i_wb_clk); #1;
            check({o_wb_err, o_wb_ack}, 2'b01, tag);   // ACK=1, ERR=0 in the write cycle
            @(negedge i_wb_clk);
            bus_idle();
        end
    endtask

    task wb_read; // combinational read — checks ACK + data in the same cycle
        input  [31:0]  addr;
        input  [31:0]  exp_data;
        input  [255:0] tag;
        begin
            @(negedge i_wb_clk);
            i_wb_adr = addr; i_wb_dat = 0;
            i_wb_we = 0; i_wb_stb = 1; i_wb_cyc = 1;
            #1;
            check(o_wb_dat, exp_data, tag);
            @(negedge i_wb_clk);
            bus_idle();
        end
    endtask

    task wait_done; // poll STATUS until DONE (bit 1) sets, with timeout
        input [255:0] tag;
        begin
            rd_tmp = 0; poll_n = 0;
            while (!rd_tmp[`WB_MAC_DONE] && poll_n < 5000) begin
                @(negedge i_wb_clk);
                i_wb_adr = `WB_MAC_STATUS; i_wb_we = 0; i_wb_stb = 1; i_wb_cyc = 1;
                #1; rd_tmp = o_wb_dat;
                poll_n = poll_n + 1;
            end
            @(negedge i_wb_clk); bus_idle();
            check(rd_tmp[`WB_MAC_DONE], 1, tag);
        end
    endtask

    task clear_done; // write 1 to STATUS[DONE]
        begin wb_write(`WB_MAC_STATUS, 32'h2); end
    endtask

    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        bus_idle(); i_wb_adr = 0; i_wb_dat = 0;
        i_wb_rst = 1; @(posedge i_wb_clk); @(posedge i_wb_clk); i_wb_rst = 0; #1;

        // T1: idle after reset — no ACK/ERR/IRQ, all registers clear
        check(o_wb_ack, 0, "T1_ACK=0_idle");
        check(o_wb_err, 0, "T1_ERR=0_idle");
        check(o_irq,    0, "T1_IRQ=0_idle");
        wb_read(`WB_MAC_STATUS, 32'h0, "T1_STATUS=0");
        wb_read(`WB_MAC_LEN,    32'h0, "T1_LEN=0");
        wb_read(`WB_MAC_ACC_LO, 32'h0, "T1_ACC_LO=0");
        wb_read(`WB_MAC_ACC_HI, 32'h0, "T1_ACC_HI=0");
        wb_read(`WB_MAC_CTRL,   32'h0, "T1_CTRL_reads_0");

        // T2: bus guards — o_wb_dat is intentionally ungated here (unlike wb_ram),
        // so only ACK/ERR are meaningful when the bus is not granted
        @(negedge i_wb_clk);
        i_wb_adr = `WB_MAC_BASE; i_wb_we = 0; i_wb_stb = 1; i_wb_cyc = 0; #1;
        check(o_wb_ack, 0, "T2_ACK=0_STB_without_CYC");
        check(o_wb_err, 0, "T2_ERR=0_STB_without_CYC");
        @(negedge i_wb_clk);
        i_wb_stb = 0; i_wb_cyc = 1; #1;
        check(o_wb_ack, 0, "T2_ACK=0_CYC_without_STB");
        check(o_wb_err, 0, "T2_ERR=0_CYC_without_STB");
        bus_idle();

        // T3: buffer memory — write/read-back, A/B independence, boundary, unwritten
        wb_write_chk(`WB_MAC_BASE + `WB_MAC_BUFA_OFF + 32'h0, 32'hDEAD_BEEF, "T3_bufA_write_ACK1_ERR0");
        wb_write    (`WB_MAC_BASE + `WB_MAC_BUFA_OFF + 32'h4, 32'h1234_5678);
        wb_write    (`WB_MAC_BASE + `WB_MAC_BUFB_OFF + 32'h0, 32'hCAFE_BABE);
        wb_write    (`WB_MAC_BASE + `WB_MAC_BUFB_OFF + 32'h4, 32'hA5A5_5A5A);
        wb_read (`WB_MAC_BASE + `WB_MAC_BUFA_OFF + 32'h0, 32'hDEAD_BEEF, "T3_bufA_word0");
        wb_read (`WB_MAC_BASE + `WB_MAC_BUFB_OFF + 32'h0, 32'hCAFE_BABE, "T3_bufB_word0_independent");
        wb_read (`WB_MAC_BASE + `WB_MAC_BUFA_OFF + 32'h4, 32'h1234_5678, "T3_bufA_word1");
        wb_read (`WB_MAC_BASE + `WB_MAC_BUFB_OFF + 32'h4, 32'hA5A5_5A5A, "T3_bufB_word1");
        wb_write(`WB_MAC_BASE + 32'h3FFC, 32'hFFFF_0001);              // BUF_A word 4095
        wb_write(`WB_MAC_BASE + 32'h7FFC, 32'h0000_FFFE);              // BUF_B word 4095
        wb_read (`WB_MAC_BASE + 32'h3FFC, 32'hFFFF_0001, "T3_bufA_top_word4095");
        wb_read (`WB_MAC_BASE + 32'h7FFC, 32'h0000_FFFE, "T3_bufB_top_word4095");
        wb_read (`WB_MAC_BASE + 32'h0190, 32'h0000_0000, "T3_bufA_unwritten_reads_0");

        // T4: control registers — write/read-back, 32-byte alias, unmapped index
        wb_write(`WB_MAC_LEN,    32'd8);
        wb_write(`WB_MAC_ACC_LO, 32'h1111_2222);
        wb_write(`WB_MAC_ACC_HI, 32'h3333_4444);
        wb_read (`WB_MAC_LEN,    32'd8,         "T4_LEN_readback");
        wb_read (`WB_MAC_ACC_LO, 32'h1111_2222, "T4_ACC_LO_readback");
        wb_read (`WB_MAC_ACC_HI, 32'h3333_4444, "T4_ACC_HI_readback");
        wb_read (`WB_MAC_BASE + 32'h8028, 32'd8, "T4_LEN_alias_0x8028"); // page aliases every 32 B
        wb_read (`WB_MAC_BASE + 32'h8014, 32'h0, "T4_unmapped_reg_reads_0");

        // T5: LEN clamps to BUF_DEPTH (4096) instead of wrapping
        wb_write(`WB_MAC_LEN, 32'd5000);
        wb_read (`WB_MAC_LEN, 32'd4096, "T5_LEN_clamped_5000");
        wb_write(`WB_MAC_LEN, 32'd4096);
        wb_read (`WB_MAC_LEN, 32'd4096, "T5_LEN_max_4096");

        // T6: START ignored when LEN=0
        wb_write(`WB_MAC_LEN,  32'd0);
        wb_write(`WB_MAC_CTRL, 32'h1);
        repeat (4) @(posedge i_wb_clk);
        wb_read(`WB_MAC_STATUS, 32'h0, "T6_START_ignored_when_LEN=0");
        check(o_irq, 0, "T6_IRQ=0_no_run");

        // T7: signed MAC run — 3*5 + (-4)*7 + (-6)*(-8) + 100*(-3) = -265
        wb_write(`WB_MAC_CTRL, 32'h2);                                 // CLR_ACC
        wb_write(`WB_MAC_BASE + 32'h0000, 32'h0000_0003);              // A[0] =   3
        wb_write(`WB_MAC_BASE + 32'h0004, 32'hFFFF_FFFC);              // A[1] =  -4
        wb_write(`WB_MAC_BASE + 32'h0008, 32'hFFFF_FFFA);              // A[2] =  -6
        wb_write(`WB_MAC_BASE + 32'h000C, 32'h0000_0064);              // A[3] = 100
        wb_write(`WB_MAC_BASE + 32'h4000, 32'h0000_0005);              // B[0] =   5
        wb_write(`WB_MAC_BASE + 32'h4004, 32'h0000_0007);              // B[1] =   7
        wb_write(`WB_MAC_BASE + 32'h4008, 32'hFFFF_FFF8);              // B[2] =  -8
        wb_write(`WB_MAC_BASE + 32'h400C, 32'hFFFF_FFFD);              // B[3] =  -3
        wb_write(`WB_MAC_LEN,  32'd4);
        wb_read (`WB_MAC_ACC_LO, 32'h0, "T7_ACC_cleared_before_run");
        wb_write(`WB_MAC_CTRL, 32'h1);                                 // START
        wb_read (`WB_MAC_STATUS, 32'h1, "T7_BUSY=1_during_run");
        wait_done("T7_DONE_set");
        check(o_irq, 1, "T7_IRQ=1_while_DONE");
        wb_read(`WB_MAC_ACC_LO, 32'hFFFF_FEF7, "T7_ACC_LO=-265");
        wb_read(`WB_MAC_ACC_HI, 32'hFFFF_FFFF, "T7_ACC_HI_sign_extended");
        clear_done();
        wb_read(`WB_MAC_STATUS, 32'h0, "T7_DONE_cleared_by_write1");
        check(o_irq, 0, "T7_IRQ=0_after_clear");

        // T8: second run accumulates onto the old value (no CLR_ACC) -> -530
        wb_write(`WB_MAC_CTRL, 32'h1);
        wait_done("T8_DONE_set");
        wb_read(`WB_MAC_ACC_LO, 32'hFFFF_FDEE, "T8_ACC_LO=-530_accumulated");
        wb_read(`WB_MAC_ACC_HI, 32'hFFFF_FFFF, "T8_ACC_HI_still_sign");
        clear_done();

        // T9: LEN / ACC_LO writes are ignored while BUSY -> third run gives -795
        wb_write(`WB_MAC_CTRL,   32'h1);                               // START (LEN still 4)
        wb_write(`WB_MAC_LEN,    32'd1);                               // ignored — busy
        wb_write(`WB_MAC_ACC_LO, 32'hDEAD_BEEF);                       // ignored — busy
        wait_done("T9_DONE_set");
        wb_read(`WB_MAC_LEN,    32'd4,         "T9_LEN_unchanged_during_busy");
        wb_read(`WB_MAC_ACC_LO, 32'hFFFF_FCE5, "T9_ACC_LO=-795_not_corrupted");
        clear_done();

        // T10: single element + 64-bit carry — 0x40000000 * 4 = 0x1_0000_0000
        wb_write(`WB_MAC_CTRL, 32'h2);                                 // CLR_ACC
        wb_write(`WB_MAC_BASE + 32'h0000, 32'h4000_0000);              // A[0]
        wb_write(`WB_MAC_BASE + 32'h4000, 32'h0000_0004);              // B[0]
        wb_write(`WB_MAC_LEN,  32'd1);
        wb_write(`WB_MAC_CTRL, 32'h1);
        wait_done("T10_DONE_set_LEN=1");
        wb_read(`WB_MAC_ACC_LO, 32'h0000_0000, "T10_ACC_LO_carry_out");
        wb_read(`WB_MAC_ACC_HI, 32'h0000_0001, "T10_ACC_HI_carry_in");

        // T11: reset clears engine state (buffers are not reset-gated and survive)
        i_wb_rst = 1; @(posedge i_wb_clk); @(posedge i_wb_clk); i_wb_rst = 0; #1;
        wb_read(`WB_MAC_STATUS, 32'h0, "T11_STATUS_cleared_by_reset");
        wb_read(`WB_MAC_LEN,    32'h0, "T11_LEN_cleared_by_reset");
        wb_read(`WB_MAC_ACC_LO, 32'h0, "T11_ACC_LO_cleared_by_reset");
        wb_read(`WB_MAC_ACC_HI, 32'h0, "T11_ACC_HI_cleared_by_reset");
        check(o_irq, 0, "T11_IRQ=0_after_reset");
        wb_read(`WB_MAC_BASE + 32'h3FFC, 32'hFFFF_0001, "T11_bufA_survives_reset");

        $display("\n=============================");
        $display("  PASS: %0d   FAIL: %0d", pass, fail);
        $display("=============================\n");
        $finish;
    end

endmodule
