// tb_wb_dma.v — unit testbench for wb_dma on the real SoC bus
// DMA master -> wb_interconnect -> wb_mac_accel (0x1000_0000) / wb_err (catch-all)
// A behavioural array stands in for data_memory port B (local, addr < 0x0001_0000).
// wb_ram is not used: the DMA treats 0x0-0x3FF as local, so it would never reach it over the bus.
// The slave (register) port is driven directly by tasks, as the CPU would via the bus.

`timescale 1ns/1ps
`include "wb_defs.vh"

module tb_wb_dma;

    localparam DMA      = 32'h2000_0000;
    localparam R_SRC    = 32'h00, R_DST = 32'h04, R_LEN = 32'h08, R_CTRL = 32'h0C, R_STATUS = 32'h10;
    localparam BUF_A    = `WB_MAC_BASE;
    localparam BUF_B    = `WB_MAC_BASE + 32'h4000;

    // ----------------------------------------------------------------
    // Signals
    // ----------------------------------------------------------------
    reg         clk = 0;
    reg         rst;

    // slave port (driven by the TB)
    reg  [31:0] i_s_adr, i_s_dat;
    reg         i_s_we, i_s_stb, i_s_cyc;
    wire [31:0] o_s_dat;
    wire        o_s_ack, o_s_err;

    // master port -> interconnect
    wire        o_m_cyc, o_m_stb, o_m_we;
    wire [31:0] o_m_adr, o_m_dat;
    wire [31:0] ic_dat;
    wire        ic_ack, ic_err;

    // local port B
    wire        o_b_we;
    wire [31:0] o_b_addr, o_b_wdat;
    wire [31:0] i_b_rdat;

    wire        o_busy;

    // slaves
    wire        ram_cyc, ram_stb, mac_cyc, mac_stb, err_cyc, err_stb;
    wire [31:0] mac_dat, err_dat;
    wire        mac_ack, mac_err, err_ack, err_err;

    // ----------------------------------------------------------------
    // DUT + bus
    // ----------------------------------------------------------------
    wb_dma dut (
        .i_clk   (clk),     .i_rst   (rst),
        .i_s_adr (i_s_adr), .i_s_dat (i_s_dat), .i_s_we (i_s_we),
        .i_s_stb (i_s_stb), .i_s_cyc (i_s_cyc),
        .o_s_dat (o_s_dat), .o_s_ack (o_s_ack), .o_s_err (o_s_err),
        .o_m_cyc (o_m_cyc), .o_m_stb (o_m_stb), .o_m_we (o_m_we),
        .o_m_adr (o_m_adr), .o_m_dat (o_m_dat),
        .i_m_dat (ic_dat),  .i_m_ack (ic_ack),  .i_m_err (ic_err),
        .o_b_we  (o_b_we),  .o_b_addr(o_b_addr), .o_b_wdat(o_b_wdat), .i_b_rdat(i_b_rdat),
        .o_busy  (o_busy)
    );

    wb_interconnect u_ic (
        .i_wb_cyc (o_m_cyc), .i_wb_stb (o_m_stb), .i_wb_we (o_m_we),
        .i_wb_adr (o_m_adr), .i_wb_dat_ms (o_m_dat),
        .o_wb_dat_sm (ic_dat), .o_wb_ack (ic_ack), .o_wb_err (ic_err),
        .o_ram_cyc (ram_cyc), .o_ram_stb (ram_stb), .i_ram_dat (32'b0), .i_ram_ack (1'b0),
        .o_mac_cyc (mac_cyc), .o_mac_stb (mac_stb), .i_mac_dat (mac_dat),
        .i_mac_ack (mac_ack), .i_mac_err (mac_err),
        .o_err_cyc (err_cyc), .o_err_stb (err_stb), .i_err_dat (err_dat),
        .i_err_ack (err_ack), .i_err_err (err_err)
    );

    wb_mac_accel u_mac (
        .i_wb_clk (clk), .i_wb_rst (rst),
        .i_wb_adr (o_m_adr), .i_wb_dat (o_m_dat), .i_wb_we (o_m_we),
        .i_wb_stb (mac_stb), .i_wb_cyc (mac_cyc),
        .o_wb_dat (mac_dat), .o_wb_ack (mac_ack), .o_wb_err (mac_err),
        .o_irq    ()
    );

    wb_err u_err (
        .i_wb_clk (clk), .i_wb_rst (rst),
        .i_wb_adr (o_m_adr), .i_wb_dat (o_m_dat), .i_wb_we (o_m_we),
        .i_wb_stb (err_stb), .i_wb_cyc (err_cyc),
        .o_wb_dat (err_dat), .o_wb_ack (err_ack), .o_wb_err (err_err)
    );

    // behavioural data_memory port B: async read, sync word write (256 words = 1 KB)
    reg [31:0] lmem [0:255];
    assign i_b_rdat = lmem[o_b_addr[9:2]];
    always @(posedge clk) if (o_b_we) lmem[o_b_addr[9:2]] <= o_b_wdat;

    always #5 clk = ~clk; // 10 ns period

    // ----------------------------------------------------------------
    // Waveform dump — explicit order: clk, rst | inputs | outputs | internals
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("tb_wb_dma.vcd");
        $dumpvars(0, clk, rst,
                     i_s_adr, i_s_dat, i_s_we, i_s_stb, i_s_cyc, ic_dat, ic_ack, ic_err, i_b_rdat,
                     o_s_dat, o_s_ack, o_s_err, o_m_cyc, o_m_stb, o_m_we, o_m_adr, o_m_dat,
                     o_b_we, o_b_addr, o_b_wdat, o_busy,
                     dut.state, dut.src, dut.dst, dut.len, dut.data_reg, dut.done, dut.err,
                     dut.m_req, dut.m_busy, dut.m_done, dut.m_err);
    end

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    integer fails = 0, checks = 0;
    integer i, n;
    reg [31:0] rd;

    task check; // one-line assertion helper, Makefile-contract failure format
        input [31:0]  got;
        input [31:0]  exp;
        input [255:0] tag;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("FAIL: %0s got=%0h exp=%0h", tag, got, exp);
                fails = fails + 1;
            end
        end
    endtask

    task reg_wr; // one-cycle register write on the slave port
        input [31:0] off;
        input [31:0] data;
        begin
            @(negedge clk);
            i_s_adr = DMA + off; i_s_dat = data;
            i_s_we = 1; i_s_stb = 1; i_s_cyc = 1;
            @(posedge clk); #1;
            i_s_we = 0; i_s_stb = 0; i_s_cyc = 0;
        end
    endtask

    task reg_rd; // combinational register read
        input  [31:0] off;
        output [31:0] data;
        begin
            @(negedge clk);
            i_s_adr = DMA + off; i_s_we = 0; i_s_stb = 1; i_s_cyc = 1;
            #1 data = o_s_dat;
            i_s_stb = 0; i_s_cyc = 0;
        end
    endtask

    task run; // program SRC/DST/LEN, START, count posedges until BUSY drops
        input  [31:0] s, d, l;
        output integer cycles;
        begin
            reg_wr(R_SRC, s);
            reg_wr(R_DST, d);
            reg_wr(R_LEN, l);
            reg_wr(R_CTRL, 1);
            cycles = 0;
            while (o_busy && cycles < 1000) begin
                @(posedge clk); #1;
                cycles = cycles + 1;
            end
        end
    endtask

    // Invariant 2: whenever BUSY falls, the DMA's bus master must already be idle
    reg prev_busy = 0;
    integer cut_xfers = 0;
    always @(posedge clk) begin
        #1;
        if (prev_busy && !o_busy && o_m_cyc) cut_xfers = cut_xfers + 1;
        prev_busy = o_busy;
    end

    // ----------------------------------------------------------------
    // Tests
    // ----------------------------------------------------------------
    initial begin
        i_s_adr = 0; i_s_dat = 0; i_s_we = 0; i_s_stb = 0; i_s_cyc = 0;
        for (i = 0; i < 256; i = i + 1) lmem[i] = 0;
        for (i = 0; i < 4; i = i + 1)   lmem[32'h100/4 + i] = i + 1;   // source vector 1,2,3,4 @ 0x100

        rst = 1;
        repeat (2) @(posedge clk);
        #1 rst = 0;

        // --- 1. mem -> BUF_A (the MAC use case) ---
        run(32'h100, BUF_A, 4, n);
        for (i = 0; i < 4; i = i + 1) check(u_mac.buf_a[i], i + 1, "mem->BUF_A data");
        $display("INFO: mem->MAC took %0d cycles for 4 words (%0d/word)", n, n / 4);
        check(n, 16, "mem->BUF_A 4 cycles/word");
        reg_rd(R_STATUS, rd); check(rd, 32'b010, "STATUS after copy = DONE");
        reg_rd(R_LEN, rd);    check(rd, 0, "LEN live counter ends at 0");
        reg_rd(R_SRC, rd);    check(rd, 32'h110, "SRC live counter +16");
        reg_rd(R_DST, rd);    check(rd, BUF_A + 16, "DST live counter +16");

        // --- 2. DONE is write-1-to-clear ---
        reg_wr(R_STATUS, 32'b010);
        reg_rd(R_STATUS, rd); check(rd, 0, "DONE W1C");

        // --- 3. BUF_A -> mem ---
        run(BUF_A, 32'h200, 4, n);
        for (i = 0; i < 4; i = i + 1) check(lmem[32'h200/4 + i], i + 1, "BUF_A->mem data");
        check(n, 16, "BUF_A->mem 4 cycles/word");

        // --- 4. mem -> mem ---
        run(32'h100, 32'h300, 4, n);
        for (i = 0; i < 4; i = i + 1) check(lmem[32'h300/4 + i], i + 1, "mem->mem data");
        check(n, 8, "mem->mem 2 cycles/word");

        // --- 5. BUF_A -> BUF_B (bus -> bus) ---
        run(BUF_A, BUF_B, 4, n);
        for (i = 0; i < 4; i = i + 1) check(u_mac.buf_b[i], i + 1, "BUF_A->BUF_B data");
        check(n, 24, "bus->bus 6 cycles/word");

        // --- 6. LEN = 0: START ignored ---
        reg_wr(R_LEN, 0);
        reg_wr(R_CTRL, 1);
        check(o_busy, 0, "LEN=0 START ignored");

        // --- 7. register writes ignored while BUSY ---
        for (i = 0; i < 4; i = i + 1) lmem[32'h100/4 + i] = 32'hA0 + i;
        reg_wr(R_SRC, 32'h100);
        reg_wr(R_DST, BUF_A);
        reg_wr(R_LEN, 4);
        reg_wr(R_CTRL, 1);
        reg_wr(R_LEN, 99);                              // all land while BUSY
        reg_wr(R_SRC, 32'h0);
        reg_wr(R_CTRL, 1);
        while (o_busy) @(posedge clk);
        #1;
        for (i = 0; i < 4; i = i + 1) check(u_mac.buf_a[i], 32'hA0 + i, "busy-write ignored: data");
        reg_rd(R_LEN, rd); check(rd, 0, "busy-write ignored: LEN");

        // --- 8. bus error: DST in unmapped space ---
        run(32'h100, 32'h3000_0000, 4, n);
        reg_rd(R_STATUS, rd); check(rd, 32'b110, "ERR + DONE on unmapped DST");
        reg_rd(R_LEN, rd);    check(rd, 4, "ERR stops before advancing");
        reg_wr(R_STATUS, 32'b100);
        reg_rd(R_STATUS, rd); check(rd, 32'b010, "ERR W1C (DONE kept)");

        // --- 9. invariant 2 held for every transfer above ---
        check(cut_xfers, 0, "master idle whenever BUSY falls");

        // --- 10. reset clears everything ---
        rst = 1; @(posedge clk); #1 rst = 0;
        reg_rd(R_STATUS, rd); check(rd, 0, "reset clears STATUS");
        reg_rd(R_LEN, rd);    check(rd, 0, "reset clears LEN");

        if (fails == 0) $display("PASS: all checks passed (%0d)", checks);
        else            $display("FAIL: %0d check(s) failed", fails);
        $finish;
    end

endmodule
