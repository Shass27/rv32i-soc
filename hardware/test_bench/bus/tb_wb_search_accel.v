
`timescale 1ns/1ps

module tb_wb_search_accel;

    reg clk;
    reg reset;

    reg  [31:0] wb_adr;
    reg  [31:0] wb_dat_in;
    reg         wb_we;
    reg         wb_stb;
    reg         wb_cyc;

    wire [31:0] wb_dat_out;
    wire        wb_ack;
    wire        wb_err;

    localparam [31:0] BASE   = 32'h30000000;
    localparam [31:0] CTRL   = BASE + 32'h8000;
    localparam [31:0] STATUS = BASE + 32'h8004;
    localparam [31:0] LEN    = BASE + 32'h8008;
    localparam [31:0] KEY    = BASE + 32'h800C;
    localparam [31:0] RESULT = BASE + 32'h8010;
    localparam [31:0] COMPS  = BASE + 32'h8014;

    integer i;
    integer cycles;
    integer errors;

    reg [31:0] value;
    reg [31:0] status_value;

    wb_search_accel dut (
        .i_wb_clk (clk),
        .i_wb_rst (reset),

        .i_wb_adr (wb_adr),
        .i_wb_dat (wb_dat_in),
        .i_wb_we  (wb_we),
        .i_wb_stb (wb_stb),
        .i_wb_cyc (wb_cyc),

        .o_wb_dat (wb_dat_out),
        .o_wb_ack (wb_ack),
        .o_wb_err (wb_err)
    );

    // 100 MHz clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Wishbone write transaction
    task wb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(negedge clk);
            wb_adr   = addr;
            wb_dat_in = data;
            wb_we    = 1'b1;
            wb_cyc   = 1'b1;
            wb_stb   = 1'b1;

            @(posedge clk);
            #1;

            if (wb_ack !== 1'b1) begin
                $display("FAIL: No ACK on write to %h", addr);
                errors = errors + 1;
            end

            @(negedge clk);
            wb_cyc = 1'b0;
            wb_stb = 1'b0;
            wb_we  = 1'b0;
        end
    endtask

    // Wishbone read transaction
    task wb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(negedge clk);
            wb_adr    = addr;
            wb_dat_in = 32'b0;
            wb_we     = 1'b0;
            wb_cyc    = 1'b1;
            wb_stb    = 1'b1;

            #1;
            data = wb_dat_out;

            if (wb_ack !== 1'b1) begin
                $display("FAIL: No ACK on read from %h", addr);
                errors = errors + 1;
            end

            @(negedge clk);
            wb_cyc = 1'b0;
            wb_stb = 1'b0;
        end
    endtask

    // Start one search and wait for DONE.
    task run_search;
        input [31:0] length;
        input [31:0] key;
        input [31:0] expected_result;
        input        expected_found;
        reg [31:0] result_value;
        reg [31:0] status_read;
        begin
            wb_write(LEN, length);
            wb_write(KEY, key);
            wb_write(CTRL, 32'h1);

            cycles = 0;
            status_read = 32'b0;

            while ((status_read[1] !== 1'b1) &&
                   (cycles < 100)) begin
                wb_read(STATUS, status_read);
                cycles = cycles + 1;
            end

            if (status_read[1] !== 1'b1) begin
                $display("FAIL: Search timed out for key %0d", $signed(key));
                errors = errors + 1;
            end
            else begin
                wb_read(RESULT, result_value);

                if (result_value !== expected_result) begin
                    $display(
                        "FAIL: key=%0d expected index/result=%h got=%h",
                        $signed(key), expected_result, result_value
                    );
                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS: key=%0d result=%h",
                        $signed(key), result_value
                    );
                end

                if (status_read[2] !== expected_found) begin
                    $display(
                        "FAIL: key=%0d FOUND expected=%b got=%b",
                        $signed(key), expected_found, status_read[2]
                    );
                    errors = errors + 1;
                end

                if (status_read[0] !== 1'b0) begin
                    $display("FAIL: BUSY still set after DONE");
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        reset = 1'b1;
        wb_adr = 0;
        wb_dat_in = 0;
        wb_we = 0;
        wb_stb = 0;
        wb_cyc = 0;
        errors = 0;
        cycles = 0;
        value = 0;
        status_value = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        $display("\n===== SEARCH ACCELERATOR TEST =====");

        // Ascending signed array:
        // Index:  0    1   2  3  4   5   6
        // Value: -10  -3   0  7  7  12  25
        wb_write(BASE + 0, 32'hFFFFFFF6); // -10
        wb_write(BASE + 4, 32'hFFFFFFFD); // -3
        wb_write(BASE + 8, 32'd0);
        wb_write(BASE + 12, 32'd7);
        wb_write(BASE + 16, 32'd7);
        wb_write(BASE + 20, 32'd12);
        wb_write(BASE + 24, 32'd25);

        // First element
        run_search(7, 32'hFFFFFFF6, 32'd0, 1'b1);

        // Duplicate: must return the FIRST index
        run_search(7, 32'd7, 32'd3, 1'b1);

        // Last element
        run_search(7, 32'd25, 32'd6, 1'b1);

        // Missing value between existing values
        run_search(7, 32'd8, 32'hFFFFFFFF, 1'b0);

        // Missing value smaller than every array element
        run_search(7, 32'hFFFFFFF0, 32'hFFFFFFFF, 1'b0);

        // Empty array: should finish without finding anything
        run_search(0, 32'd7, 32'hFFFFFFFF, 1'b0);

        // Invalid length should report ERROR and finish
        wb_write(LEN, 32'd8193);
        wb_write(KEY, 32'd7);
        wb_write(CTRL, 32'h1);
        wb_read(STATUS, status_value);

        if ((status_value[1] !== 1'b1) ||
            (status_value[3] !== 1'b1)) begin
            $display("FAIL: Invalid length did not report DONE and ERROR");
            errors = errors + 1;
        end
        else begin
            $display("PASS: Invalid length reports ERROR");
        end

        if (errors == 0)
            $display("\n===== ALL SEARCH TESTS PASSED =====");
        else
            $display("\n===== TEST FAILED: %0d error(s) =====", errors);

        $finish;
    end

    // Prevent a broken clock or stalled simulation from running forever.
    initial begin
        #100000;
        $display("FATAL: Global simulation timeout");
        $finish;
    end

endmodule
