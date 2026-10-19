`timescale 1ns/1ps

module tb_wb_search_integration;

    reg clk;
    reg reset;

    // Wishbone master signals
    reg         wb_cyc;
    reg         wb_stb;
    reg         wb_we;
    reg  [31:0] wb_adr;
    reg  [31:0] wb_wdata;

    wire [31:0] wb_rdata;
    wire        wb_ack;
    wire        wb_err;

    // Interconnect slave signals
    wire        ram_cyc, ram_stb;
    wire        mac_cyc, mac_stb;
    wire        err_cyc, err_stb;
    wire        dma_cyc, dma_stb;
    wire        search_cyc, search_stb;

    wire [31:0] search_rdata;
    wire        search_ack;
    wire        search_err;

    integer i;
    integer poll_count;

    reg [31:0] status;
    reg [31:0] result;
    reg [31:0] comparisons;

    // -----------------------------------------------------
    // Clock
    // -----------------------------------------------------

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -----------------------------------------------------
    // Wishbone interconnect
    // -----------------------------------------------------

    wb_interconnect #(
        .DATA_WIDTH(32)
    ) dut_interconnect (
        .i_wb_cyc    (wb_cyc),
        .i_wb_stb    (wb_stb),
        .i_wb_we     (wb_we),
        .i_wb_adr    (wb_adr),
        .i_wb_dat_ms (wb_wdata),

        .o_wb_dat_sm (wb_rdata),
        .o_wb_ack    (wb_ack),
        .o_wb_err    (wb_err),

        // RAM stub
        .o_ram_cyc   (ram_cyc),
        .o_ram_stb   (ram_stb),
        .i_ram_dat   (32'b0),
        .i_ram_ack   (1'b0),

        // MAC stub
        .o_mac_cyc   (mac_cyc),
        .o_mac_stb   (mac_stb),
        .i_mac_dat   (32'b0),
        .i_mac_ack   (1'b0),
        .i_mac_err   (1'b0),

        // Error slave stub
        .o_err_cyc   (err_cyc),
        .o_err_stb   (err_stb),
        .i_err_dat   (32'b0),
        .i_err_ack   (1'b0),
        .i_err_err   (1'b0),

        // DMA stub
        .o_dma_cyc   (dma_cyc),
        .o_dma_stb   (dma_stb),
        .i_dma_dat   (32'b0),
        .i_dma_ack   (1'b0),
        .i_dma_err   (1'b0),

        // SEARCH accelerator
        .o_search_cyc (search_cyc),
        .o_search_stb (search_stb),
        .i_search_dat (search_rdata),
        .i_search_ack (search_ack),
        .i_search_err (search_err)
    );

    // -----------------------------------------------------
    // SEARCH accelerator
    // -----------------------------------------------------

    wb_search_accel dut_search (
        .i_wb_clk (clk),
        .i_wb_rst (reset),

        .i_wb_adr (wb_adr),
        .i_wb_dat (wb_wdata),
        .i_wb_we  (wb_we),
        .i_wb_stb (search_stb),
        .i_wb_cyc (search_cyc),

        .o_wb_dat (search_rdata),
        .o_wb_ack (search_ack),
        .o_wb_err (search_err)
    );

    // -----------------------------------------------------
    // Wishbone write task
    // -----------------------------------------------------

    task wb_write;
        input [31:0] address;
        input [31:0] data;

        begin
            @(negedge clk);

            wb_adr   = address;
            wb_wdata = data;
            wb_we    = 1'b1;
            wb_cyc   = 1'b1;
            wb_stb   = 1'b1;

            #1;

            if (!wb_ack || wb_err) begin
                $display(
                    "FAIL: WRITE address=%h ACK=%b ERR=%b",
                    address, wb_ack, wb_err
                );
                $fatal(1);
            end

            @(negedge clk);

            wb_cyc = 1'b0;
            wb_stb = 1'b0;
            wb_we  = 1'b0;
        end
    endtask

    // -----------------------------------------------------
    // Wishbone read task
    // -----------------------------------------------------

    task wb_read;
        input  [31:0] address;
        output [31:0] data;

        begin
            @(negedge clk);

            wb_adr   = address;
            wb_wdata = 32'b0;
            wb_we    = 1'b0;
            wb_cyc   = 1'b1;
            wb_stb   = 1'b1;

            #1;

            if (!wb_ack || wb_err) begin
                $display(
                    "FAIL: READ address=%h ACK=%b ERR=%b",
                    address, wb_ack, wb_err
                );
                $fatal(1);
            end

            data = wb_rdata;

            @(negedge clk);

            wb_cyc = 1'b0;
            wb_stb = 1'b0;
        end
    endtask

    // -----------------------------------------------------
    // Wait for search completion
    // -----------------------------------------------------

    task wait_for_done;
        begin
            status = 32'b0;
            poll_count = 0;

            while (!status[1] && poll_count < 100) begin
                wb_read(32'h30008004, status);
                poll_count = poll_count + 1;
            end

            if (!status[1]) begin
                $display("FAIL: SEARCH timeout");
                $fatal(1);
            end
        end
    endtask

    // -----------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------
     initial begin
        $dumpfile("search_integration.vcd");
        $dumpvars(0, tb_wb_search_integration);
    end

    initial begin

        reset   = 1'b1;
        wb_cyc  = 1'b0;
        wb_stb  = 1'b0;
        wb_we   = 1'b0;
        wb_adr  = 32'b0;
        wb_wdata = 32'b0;

        repeat (3) @(negedge clk);
        reset = 1'b0;

        $display("");
        $display("========================================");
        $display(" SEARCH WISHBONE INTEGRATION TEST");
        $display("========================================");

        // -------------------------------------------------
        // Test 1: Load sorted array through Wishbone
        // -------------------------------------------------

        $display("\nTEST 1: Loading sorted array");

        wb_write(32'h30000000, -32'sd8);
        wb_write(32'h30000004, -32'sd3);
        wb_write(32'h30000008,  32'sd2);
        wb_write(32'h3000000C,  32'sd7);
        wb_write(32'h30000010,  32'sd12);
        wb_write(32'h30000014,  32'sd19);
        wb_write(32'h30000018,  32'sd25);

        wb_write(32'h30008008, 32'd7);

        $display("PASS: Array and length written through bus");

        // -------------------------------------------------
        // Test 2: Find positive value
        // -------------------------------------------------

        $display("\nTEST 2: Find key 12");

        wb_write(32'h3000800C, 32'd12);
        wb_write(32'h30008000, 32'd1);

        wait_for_done();

        wb_read(32'h30008010, result);
        wb_read(32'h30008014, comparisons);

        if (status[3:0] !== 4'b0110 || result !== 32'd4) begin
            $display(
                "FAIL: key=12 STATUS=%h RESULT=%h",
                status, result
            );
            $fatal(1);
        end

        if (comparisons == 0) begin
            $display("FAIL: Comparison count is zero");
            $fatal(1);
        end

        $display(
            "PASS: key=12 result=%0d comparisons=%0d",
            result, comparisons
        );

        // -------------------------------------------------
        // Test 3: Missing value
        // -------------------------------------------------

        $display("\nTEST 3: Search for missing key 8");

        wb_write(32'h3000800C, 32'd8);
        wb_write(32'h30008000, 32'd1);

        wait_for_done();

        wb_read(32'h30008010, result);

        if (status[3:0] !== 4'b0010 ||
            result !== 32'hFFFFFFFF) begin

            $display(
                "FAIL: key=8 STATUS=%h RESULT=%h",
                status, result
            );
            $fatal(1);
        end

        $display("PASS: Missing key correctly reported");

        // -------------------------------------------------
        // Test 4: Find negative value
        // -------------------------------------------------

        $display("\nTEST 4: Find negative key -3");

        wb_write(32'h3000800C, -32'sd3);
        wb_write(32'h30008000, 32'd1);

        wait_for_done();

        wb_read(32'h30008010, result);

        if (status[3:0] !== 4'b0110 ||
            result !== 32'd1) begin

            $display(
                "FAIL: key=-3 STATUS=%h RESULT=%h",
                status, result
            );
            $fatal(1);
        end

        $display("PASS: Negative key found at index 1");

        // -------------------------------------------------
        // Test 5: Invalid length
        // -------------------------------------------------

        $display("\nTEST 5: Invalid length 8193");

        wb_write(32'h30008008, 32'd8193);
        wb_write(32'h30008000, 32'd1);

        wb_read(32'h30008004, status);

        if (status[3:1] !== 3'b101) begin
            $display(
                "FAIL: Invalid length STATUS=%h",
                status
            );
            $fatal(1);
        end

        $display("PASS: Invalid length raises DONE and ERROR");

        // -------------------------------------------------
        // Finish
        // -------------------------------------------------

        $display("");
        $display("========================================");
        $display(" ALL INTEGRATION TESTS PASSED");
        $display("========================================");

        $finish;
    end

endmodule