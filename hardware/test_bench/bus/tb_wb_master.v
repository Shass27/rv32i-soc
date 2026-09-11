// tb_wb_master.v — unit testbench for wb_master (no slave connected)
// slave responses (ack, dat) are driven manually to isolate master FSM behaviour

`timescale 1ns/1ps

module tb_wb_master;

    reg         clk = 0;
    reg         rst;
    reg         i_req, i_we;
    reg  [31:0] i_addr, i_wdat;
    wire [31:0] o_rdat;
    wire        o_busy, o_done;
    wire        o_wb_cyc, o_wb_stb, o_wb_we;
    wire [31:0] o_wb_adr, o_wb_dat;
    reg  [31:0] i_wb_dat;  // fake slave read data
    reg         i_wb_ack;  // fake slave ack

    wb_master dut (
        .i_clk(clk), .i_rst(rst),
        .i_req(i_req), .i_we(i_we), .i_addr(i_addr), .i_wdat(i_wdat),
        .o_rdat(o_rdat), .o_busy(o_busy), .o_done(o_done),
        .o_wb_cyc(o_wb_cyc), .o_wb_stb(o_wb_stb), .o_wb_we(o_wb_we),
        .o_wb_adr(o_wb_adr), .o_wb_dat(o_wb_dat),
        .i_wb_dat(i_wb_dat), .i_wb_ack(i_wb_ack)
    );

    always #5 clk = ~clk; // 10 ns period

    integer pass = 0, fail = 0;

    task check; // one-line assertion
        input [63:0] got;
        input [63:0] exp;
        input [127:0] tag;
        begin
            if (got === exp) begin $display("PASS  %0s", tag); pass = pass + 1; end
            else             begin $display("FAIL  %0s  exp=%0h  got=%0h", tag, exp, got); fail = fail + 1; end
        end
    endtask

    task ack_next; // drive slave ack for one cycle then drop
        begin @(posedge clk); i_wb_ack = 1; #1; i_wb_ack = 0; end
    endtask

    initial begin
        $dumpfile("tb_wb_master.vcd");
        $dumpvars(0, tb_wb_master);

        // -- reset --
        i_req = 0; i_we = 0; i_addr = 0; i_wdat = 0; i_wb_dat = 0; i_wb_ack = 0;
        rst = 1; @(posedge clk); @(posedge clk); rst = 0;

        // T1: idle — bus lines quiet, not busy
        #1;
        check(o_wb_cyc, 0, "T1_CYC=0_idle");
        check(o_wb_stb, 0, "T1_STB=0_idle");
        check(o_busy,   0, "T1_busy=0_idle");

        // T2: write transaction — assert req for one cycle, then fake ack
        @(negedge clk);
        i_req = 1; i_we = 1; i_addr = 32'h10; i_wdat = 32'hDEAD_BEEF;
        @(posedge clk); #1; i_req = 0;         // req pulse done; master should be ACTIVE now
        check(o_wb_cyc, 1, "T2_CYC=1_active");
        check(o_wb_stb, 1, "T2_STB=1_active");
        check(o_wb_we,  1, "T2_WE=1_write");
        check(o_wb_adr, 32'h10,        "T2_ADR");
        check(o_wb_dat, 32'hDEAD_BEEF, "T2_DAT");
        check(o_busy,   1, "T2_busy=1_active");
        // now ack from fake slave
        i_wb_ack = 1; @(posedge clk); #1; i_wb_ack = 0;
        check(o_wb_cyc, 0, "T2_CYC=0_after_ack");
        check(o_wb_stb, 0, "T2_STB=0_after_ack");
        check(o_busy,   0, "T2_busy=0_after_ack");

        // T3: read transaction — fake slave returns data on ack
        @(negedge clk);
        i_req = 1; i_we = 0; i_addr = 32'h20; i_wdat = 0; i_wb_dat = 32'hCAFE_BABE;
        @(posedge clk); #1; i_req = 0;
        check(o_wb_we, 0, "T3_WE=0_read");
        check(o_wb_adr, 32'h20, "T3_ADR");
        i_wb_ack = 1; @(posedge clk); #1; i_wb_ack = 0;
        check(o_rdat, 32'hCAFE_BABE, "T3_rdat_captured");
        check(o_busy, 0, "T3_busy=0_after_read");

        // T4: o_done pulses exactly one cycle on ack
        @(negedge clk);
        i_req = 1; i_we = 0; i_addr = 32'h30; i_wdat = 0; i_wb_dat = 32'h5A5A;
        @(posedge clk); #1; i_req = 0;
        i_wb_ack = 1; @(posedge clk); #1; // ack cycle — wait for NBA settle
        check(o_done, 1, "T4_done=1_on_ack");
        i_wb_ack = 0; @(posedge clk); #1; // next cycle — done must be gone
        check(o_done, 0, "T4_done=0_next_cycle");

        // T5: busy blocks second req mid-flight
        @(negedge clk);
        i_req = 1; i_we = 1; i_addr = 32'h40; i_wdat = 32'hFF;
        @(posedge clk); #1; i_req = 0;         // master now ACTIVE
        check(o_busy, 1, "T5_busy_while_active");
        // fire another req while busy — should be ignored
        @(negedge clk); i_req = 1; @(posedge clk); #1; i_req = 0;
        check(o_wb_adr, 32'h40, "T5_addr_unchanged_during_busy"); // still the first txn
        i_wb_ack = 1; @(posedge clk); #1; i_wb_ack = 0;
        check(o_busy, 0, "T5_busy_cleared");

        // T6: back-to-back transactions
        @(negedge clk);
        i_req = 1; i_we = 1; i_addr = 32'h50; i_wdat = 32'hAA;
        @(posedge clk); #1; i_req = 0;
        i_wb_ack = 1; @(posedge clk); #1; i_wb_ack = 0; // finish first
        check(o_busy, 0, "T6_idle_between_txns");
        @(negedge clk);
        i_req = 1; i_we = 0; i_addr = 32'h54; i_wb_dat = 32'hBB;
        @(posedge clk); #1; i_req = 0;
        i_wb_ack = 1; @(posedge clk); #1; i_wb_ack = 0;
        check(o_rdat, 32'hBB, "T6_second_txn_rdat");

        $display("\n=============================");
        $display("  PASS: %0d   FAIL: %0d", pass, fail);
        $display("=============================\n");
        $finish;
    end

endmodule
