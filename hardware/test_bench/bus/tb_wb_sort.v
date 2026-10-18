`timescale 1ns/1ps

module tb_wb_sort;

    // ------------------------------------------------------------
    // Configuration
    // ------------------------------------------------------------
    localparam integer MEM_WORDS = 256;
    localparam integer MAX_LEN   = 16;

    localparam [31:0] SRC_ADDR_REG = 32'h3000_0000;
    localparam [31:0] DST_ADDR_REG = 32'h3000_0004;
    localparam [31:0] LENGTH_REG   = 32'h3000_0008;
    localparam [31:0] CONTROL_REG  = 32'h3000_000C;
    localparam [31:0] STATUS_REG   = 32'h3000_0010;

    // Source occupies words 0..15; destination occupies words 16..31.
    localparam [31:0] SRC_BASE = 32'h0000_0000;
    localparam [31:0] DST_BASE = 32'h0000_0040;

    // Separate location used to prove that DMA writes survive arbitration.
    localparam [31:0] DMA_ADDR = 32'h0000_0300;
    localparam [31:0] DMA_DATA = 32'hDEAD_BEEF;
    localparam [31:0] DMA_SENTINEL = 32'hA5A5_5A5A;

    localparam integer MAX_SORT_CYCLES = 5000;

    // ------------------------------------------------------------
    // Clock, reset, DMA model, and Wishbone interface
    // ------------------------------------------------------------
    reg clk = 1'b0;
    reg reset = 1'b1;

    reg dma_busy = 1'b0;
    reg dma_b_we = 1'b0;
    reg [31:0] dma_b_addr = 32'b0;
    reg [31:0] dma_b_wdat = 32'b0;

    wire mem_grant = ~dma_busy;

    reg [31:0] wb_adr = 32'b0;
    reg [31:0] wb_dat_w = 32'b0;
    reg wb_we = 1'b0;
    reg wb_cyc = 1'b0;
    reg wb_stb = 1'b0;

    wire [31:0] wb_dat_r;
    wire wb_ack;
    wire wb_err;

    reg [31:0] mem [0:MEM_WORDS-1];

    wire sort_mem_we;
    wire [31:0] sort_mem_addr;
    wire [31:0] sort_mem_wdata;

    wire mem_we;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [31:0] mem_rdata;

    integer errors = 0;
    integer tests_run = 0;
    integer tests_passed = 0;
    integer i, j;
    integer wait_cycles;
    integer interrupt_count = 0;
    integer test_failed;

    reg [31:0] expected [0:MAX_LEN-1];
    reg [31:0] rand_state;
    reg [31:0] swap_temp;

    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Shared Port-B arbitration: DMA has priority, matching cpu_top_wb.
    // ------------------------------------------------------------
    assign mem_we    = dma_busy ? dma_b_we   : sort_mem_we;
    assign mem_addr  = dma_busy ? dma_b_addr : sort_mem_addr;
    assign mem_wdata = dma_busy ? dma_b_wdat : sort_mem_wdata;

    // Asynchronous read, matching the memory interface used by wb_sort.
    assign mem_rdata = mem[mem_addr >> 2];

    // Synchronous write, matching data_memory.v Port B behavior.
    always @(posedge clk) begin
        if (mem_we) begin
            if ((mem_addr[1:0] !== 2'b00) ||
                ((mem_addr >> 2) >= MEM_WORDS)) begin
                $display("FAIL: Invalid memory write: addr=%h time=%0t",
                         mem_addr, $time);
                errors = errors + 1;
            end else begin
                mem[mem_addr >> 2] <= mem_wdata;
            end
        end
    end

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    wb_sort dut (
        .i_wb_clk(clk),
        .i_wb_rst(reset),
        .i_mem_grant(mem_grant),

        .i_wb_adr(wb_adr),
        .i_wb_dat(wb_dat_w),
        .i_wb_we(wb_we),
        .i_wb_stb(wb_stb),
        .i_wb_cyc(wb_cyc),

        .o_wb_dat(wb_dat_r),
        .o_wb_ack(wb_ack),
        .o_wb_err(wb_err),

        .o_mem_we(sort_mem_we),
        .o_mem_addr(sort_mem_addr),
        .o_mem_wdata(sort_mem_wdata),
        .i_mem_rdata(mem_rdata)
    );

    // ------------------------------------------------------------
    // Protocol/arbitration monitors
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (!reset) begin
            if (dma_busy) begin
                if (mem_we !== dma_b_we) begin
                    $display("FAIL: DMA write-enable priority at t=%0t", $time);
                    errors = errors + 1;
                end
                if (mem_addr !== dma_b_addr) begin
                    $display("FAIL: DMA address priority at t=%0t", $time);
                    errors = errors + 1;
                end
                if (mem_wdata !== dma_b_wdat) begin
                    $display("FAIL: DMA data priority at t=%0t", $time);
                    errors = errors + 1;
                end
            end

            if (wb_err === 1'b1) begin
                $display("FAIL: Sorter asserted Wishbone error at t=%0t", $time);
                errors = errors + 1;
            end
        end
    end

    // ------------------------------------------------------------
    // Wishbone write task
    // ------------------------------------------------------------
    task wb_write;
        input [31:0] address;
        input [31:0] data;
        integer timeout;
        begin
            @(negedge clk);
            wb_adr   = address;
            wb_dat_w = data;
            wb_we    = 1'b1;
            wb_cyc   = 1'b1;
            wb_stb   = 1'b1;

            timeout = 0;
            begin : WAIT_WB_WRITE_ACK
                forever begin
                    @(posedge clk);
                    #1;
                    if (wb_ack === 1'b1)
                        disable WAIT_WB_WRITE_ACK;
                    if (timeout >= 20) begin
                        $display("FAIL: Wishbone write timeout addr=%h", address);
                        errors = errors + 1;
                        disable WAIT_WB_WRITE_ACK;
                    end
                    timeout = timeout + 1;
                end
            end

            @(negedge clk);
            wb_cyc = 1'b0;
            wb_stb = 1'b0;
            wb_we  = 1'b0;
        end
    endtask

    // ------------------------------------------------------------
    // Wishbone read task
    // ------------------------------------------------------------
    task wb_read;
        input [31:0] address;
        output [31:0] data;
        integer timeout;
        begin
            data = 32'hxxxx_xxxx;

            @(negedge clk);
            wb_adr = address;
            wb_we  = 1'b0;
            wb_cyc = 1'b1;
            wb_stb = 1'b1;

            timeout = 0;
            begin : WAIT_WB_READ_ACK
                forever begin
                    @(posedge clk);
                    #1;
                    if (wb_ack === 1'b1) begin
                        data = wb_dat_r;
                        disable WAIT_WB_READ_ACK;
                    end
                    if (timeout >= 20) begin
                        $display("FAIL: Wishbone read timeout addr=%h", address);
                        errors = errors + 1;
                        disable WAIT_WB_READ_ACK;
                    end
                    timeout = timeout + 1;
                end
            end

            @(negedge clk);
            wb_cyc = 1'b0;
            wb_stb = 1'b0;
        end
    endtask

    // ------------------------------------------------------------
    // Interrupt the sorter while a write is pending.
    //
    // The pending write-enable is allowed to remain asserted while
    // DMA owns the port. We save its address/data, prove that DMA
    // suppresses the sorter write, and then prove the exact pending
    // write commits after ownership returns to the sorter.
    // ------------------------------------------------------------
    task interrupt_during_pending_write;
        input integer current_test;
        reg [31:0] pending_addr;
        reg [31:0] pending_data;
        reg [31:0] old_mem_word;
        integer hold_cycle;
        begin
            wait_cycles = 0;

            // Observe at negedge, then take ownership before the next posedge.
            while ((sort_mem_we !== 1'b1) &&
                   (wait_cycles < MAX_SORT_CYCLES)) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end

            if (sort_mem_we !== 1'b1) begin
                $display("FAIL: Test %0d: no pending sorter write found", current_test);
                errors = errors + 1;
            end else begin
                pending_addr = sort_mem_addr;
                pending_data = sort_mem_wdata;

                if ((pending_addr[1:0] !== 2'b00) ||
                    ((pending_addr >> 2) >= MEM_WORDS)) begin
                    $display("FAIL: Test %0d: pending write has invalid address %h",
                             current_test, pending_addr);
                    errors = errors + 1;
                end else begin
                    old_mem_word = mem[pending_addr >> 2];
                end

                // DMA claims the port at a negedge, before the write edge.
                dma_busy   = 1'b1;
                dma_b_addr = DMA_ADDR;
                dma_b_wdat = DMA_DATA;
                dma_b_we   = 1'b1;

                // Allow several clock edges with DMA in control.
                for (hold_cycle = 0; hold_cycle < 4; hold_cycle = hold_cycle + 1) begin
                    @(negedge clk);

                    if (sort_mem_we !== 1'b1) begin
                        $display("FAIL: Test %0d: pending sorter write-enable was not held",
                                 current_test);
                        errors = errors + 1;
                    end
                    if (sort_mem_addr !== pending_addr) begin
                        $display("FAIL: Test %0d: pending address changed during DMA",
                                 current_test);
                        errors = errors + 1;
                    end
                    if (sort_mem_wdata !== pending_data) begin
                        $display("FAIL: Test %0d: pending data changed during DMA",
                                 current_test);
                        errors = errors + 1;
                    end
                    if (mem[pending_addr >> 2] !== old_mem_word) begin
                        $display("FAIL: Test %0d: sorter wrote memory while DMA owned port",
                                 current_test);
                        errors = errors + 1;
                    end
                end

                // Stop the DMA write but retain ownership for two more edges.
                dma_b_we = 1'b0;
                repeat (2) @(negedge clk);

                if (mem[pending_addr >> 2] !== old_mem_word) begin
                    $display("FAIL: Test %0d: sorter write occurred before DMA released port",
                             current_test);
                    errors = errors + 1;
                end

                // DMA's own independent write must have happened.
                if (mem[DMA_ADDR >> 2] !== DMA_DATA) begin
                    $display("FAIL: Test %0d: DMA write did not reach memory",
                             current_test);
                    errors = errors + 1;
                end

                // Return ownership. The first rising edge commits the
                // preserved pending sorter write using the saved address/data.
                dma_busy = 1'b0;
                @(posedge clk);
                #1;

                if (mem[pending_addr >> 2] !== pending_data) begin
                    $display("FAIL: Test %0d: pending write not committed correctly; addr=%h expected=%h got=%h",
                             current_test, pending_addr, pending_data,
                             mem[pending_addr >> 2]);
                    errors = errors + 1;
                end

                // Wait until the following negedge before returning to caller.
                @(negedge clk);
                interrupt_count = interrupt_count + 1;
                $display("INFO: Test %0d DMA interruption/resume checked (pending addr=%h)",
                         current_test, pending_addr);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Generate test input patterns.
    // pattern:
    //   0 ascending
    //   1 descending
    //   2 repeated/duplicate values
    //   3 all equal
    //   4 unsigned boundary values
    //   5 deterministic pseudo-random values
    // ------------------------------------------------------------
    task load_pattern;
        input integer len;
        input integer pattern;
        integer idx;
        begin
            rand_state = 32'h1357_9BDF ^ (len * 32'h1021) ^ pattern;

            for (idx = 0; idx < len; idx = idx + 1) begin
                case (pattern)
                    0: mem[idx] = idx;
                    1: mem[idx] = len - idx;
                    2: mem[idx] = (idx % 4);
                    3: mem[idx] = 32'd7;
                    4: begin
                        case (idx % 8)
                            0: mem[idx] = 32'hFFFF_FFFF;
                            1: mem[idx] = 32'h0000_0000;
                            2: mem[idx] = 32'h8000_0000;
                            3: mem[idx] = 32'h7FFF_FFFF;
                            4: mem[idx] = 32'h0000_0001;
                            5: mem[idx] = 32'hFFFF_FFFE;
                            6: mem[idx] = 32'h8000_0001;
                            default: mem[idx] = 32'h7FFF_FFFE;
                        endcase
                    end
                    default: begin
                        rand_state = rand_state * 32'd1664525 + 32'd1013904223;
                        mem[idx] = rand_state;
                    end
                endcase
            end

            // Snapshot the generated input into the reference array.
            for (idx = 0; idx < len; idx = idx + 1)
                expected[idx] = mem[idx];

            // Reference sort: unsigned ascending bubble sort.
            for (idx = 0; idx < len; idx = idx + 1) begin
                for (j = 0; j < len - 1 - idx; j = j + 1) begin
                    if (expected[j] > expected[j+1]) begin
                        swap_temp = expected[j];
                        expected[j] = expected[j+1];
                        expected[j+1] = swap_temp;
                    end
                end
            end
        end
    endtask

    // ------------------------------------------------------------
    // Run one test: configure, start, optionally interrupt, wait,
    // check status and every output word.
    // ------------------------------------------------------------
    task run_test;
        input integer len;
        input integer pattern;
        input integer do_interrupt;
        integer idx;
        integer cycles;
        reg [31:0] status_value;
        reg [31:0] src_reg_value;
        reg [31:0] dst_reg_value;
        reg [31:0] len_reg_value;
        integer errors_before;
        begin
            tests_run = tests_run + 1;
            test_failed = 0;
            errors_before = errors;

            // Ensure the previous test left the interface and DMA idle.
            dma_busy = 1'b0;
            dma_b_we = 1'b0;
            wb_cyc = 1'b0;
            wb_stb = 1'b0;
            wb_we = 1'b0;

            // Keep test regions separate and fill output with a canary.
            for (idx = 0; idx < MAX_LEN; idx = idx + 1) begin
                mem[idx] = 32'hCAFE_0000 + idx;
                mem[16 + idx] = 32'hBAD0_BAD0;
            end
            mem[DMA_ADDR >> 2] = DMA_SENTINEL;

            load_pattern(len, pattern);

            // Configure and start the sorter.
            wb_write(SRC_ADDR_REG, SRC_BASE);
            wb_write(DST_ADDR_REG, DST_BASE);
            wb_write(LENGTH_REG, len);
            wb_write(CONTROL_REG, 1);

            // Wait for busy to assert (or for the zero-length operation to finish).
            cycles = 0;
            status_value = 0;
            while ((dut.busy !== 1'b1) &&
                   (cycles < 30)) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            if ((len != 0) && (dut.busy !== 1'b1)) begin
                $display("FAIL: Test %0d did not enter busy state (len=%0d)",
                         tests_run, len);
                errors = errors + 1;
            end

            if ((do_interrupt != 0) && (len > 0) && (dut.busy === 1'b1))
                interrupt_during_pending_write(tests_run);

            // Poll STATUS until done=1; bit 1 is done in {30'b0, done, busy}.
            cycles = 0;
            status_value = 0;
            while ((status_value[1] !== 1'b1) &&
                   (cycles < MAX_SORT_CYCLES)) begin
                wb_read(STATUS_REG, status_value);
                cycles = cycles + 1;
            end

            if (status_value[1] !== 1'b1) begin
                $display("FAIL: Test %0d timed out (len=%0d pattern=%0d status=%h)",
                         tests_run, len, pattern, status_value);
                errors = errors + 1;
                test_failed = 1;
            end else begin
                if (status_value[0] !== 1'b0) begin
                    $display("FAIL: Test %0d DONE asserted while BUSY remained high",
                             tests_run);
                    errors = errors + 1;
                    test_failed = 1;
                end

                // Check the destination data in unsigned ascending order.
                for (idx = 0; idx < len; idx = idx + 1) begin
                    if (mem[16 + idx] !== expected[idx]) begin
                        $display("FAIL: Test %0d len=%0d pattern=%0d index=%0d expected=%h got=%h",
                                 tests_run, len, pattern, idx,
                                 expected[idx], mem[16 + idx]);
                        errors = errors + 1;
                        test_failed = 1;
                    end
                end
            end

            // Read back configuration only after sorting has finished.
            // Doing this before the interruption could consume the short
            // length-one operation before the test can catch its pending write.
            wb_read(SRC_ADDR_REG, src_reg_value);
            wb_read(DST_ADDR_REG, dst_reg_value);
            wb_read(LENGTH_REG, len_reg_value);

            if (src_reg_value !== SRC_BASE) begin
                $display("FAIL: Test %0d SRC_ADDR readback got %h", tests_run, src_reg_value);
                errors = errors + 1;
            end
            if (dst_reg_value !== DST_BASE) begin
                $display("FAIL: Test %0d DST_ADDR readback got %h", tests_run, dst_reg_value);
                errors = errors + 1;
            end
            if (len_reg_value !== len) begin
                $display("FAIL: Test %0d LENGTH readback expected %0d got %h",
                         tests_run, len, len_reg_value);
                errors = errors + 1;
            end

            // Check DMA result if this test requested an interruption.
            if ((do_interrupt != 0) && (len > 0)) begin
                if (mem[DMA_ADDR >> 2] !== DMA_DATA) begin
                    $display("FAIL: Test %0d DMA memory value expected=%h got=%h",
                             tests_run, DMA_DATA, mem[DMA_ADDR >> 2]);
                    errors = errors + 1;
                    test_failed = 1;
                end
            end else begin
                if (mem[DMA_ADDR >> 2] !== DMA_SENTINEL) begin
                    $display("FAIL: Test %0d unexpected DMA memory modification",
                             tests_run);
                    errors = errors + 1;
                    test_failed = 1;
                end
            end

            if (errors == errors_before) begin
                tests_passed = tests_passed + 1;
                if ((do_interrupt != 0) && (len > 0))
                    $display("PASS: Test %0d len=%0d pattern=%0d with DMA interruption",
                             tests_run, len, pattern);
                else
                    $display("PASS: Test %0d len=%0d pattern=%0d",
                             tests_run, len, pattern);
            end else begin
                $display("FAIL: Test %0d len=%0d pattern=%0d", tests_run, len, pattern);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Test suite
    // ------------------------------------------------------------
    initial begin
        $dumpfile("wb_sort.vcd");
        $dumpvars(0, tb_wb_sort);

        for (i = 0; i < MEM_WORDS; i = i + 1)
            mem[i] = 32'b0;

        errors = 0;
        tests_run = 0;
        tests_passed = 0;
        interrupt_count = 0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Exercise every length from 0 through MAX_LEN with varied patterns.
        // Each nonzero-length case interrupts a pending write, exercising
        // pause/resume and the pending-write handshake.
        for (i = 0; i <= MAX_LEN; i = i + 1) begin
            run_test(i, 0, (i > 0)); // already sorted
            run_test(i, 1, (i > 0)); // reverse order
            run_test(i, 2, (i > 0)); // duplicates
            run_test(i, 3, (i > 0)); // all equal
            run_test(i, 4, (i > 0)); // unsigned boundary values
            run_test(i, 5, (i > 0)); // deterministic pseudo-random
        end

        // Same-buffer one-element operation should finish without copying.
        // This is checked separately because SRC_ADDR == DST_ADDR.
        wb_write(SRC_ADDR_REG, SRC_BASE);
        wb_write(DST_ADDR_REG, SRC_BASE);
        wb_write(LENGTH_REG, 1);
        wb_write(CONTROL_REG, 1);

        // Wait until the new command has actually been accepted. Otherwise,
        // STATUS could still contain DONE=1 from the previous operation.
        wait_cycles = 0;
        while ((dut.busy !== 1'b1) && (wait_cycles < 30)) begin
            @(negedge clk);
            wait_cycles = wait_cycles + 1;
        end
        if (dut.busy !== 1'b1) begin
            $display("FAIL: Same-buffer length-one case never entered busy");
            errors = errors + 1;
        end

        wait_cycles = 0;
        begin : WAIT_SAME_BUFFER_DONE
            reg [31:0] same_status;
            same_status = 0;
            while ((same_status[1] !== 1'b1) &&
                   (wait_cycles < MAX_SORT_CYCLES)) begin
                wb_read(STATUS_REG, same_status);
                wait_cycles = wait_cycles + 1;
            end
            if (same_status[1] !== 1'b1) begin
                $display("FAIL: Same-buffer length-one case timed out");
                errors = errors + 1;
            end else begin
                $display("PASS: Same-buffer length-one case");
                tests_passed = tests_passed + 1;
            end
        end
        tests_run = tests_run + 1;

        $display("--------------------------------------------------");
        $display("Tests passed: %0d / %0d", tests_passed, tests_run);
        $display("DMA interruptions checked: %0d", interrupt_count);
        $display("Total errors: %0d", errors);
        $display("--------------------------------------------------");

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST SUITE FAILED");

        $finish;
    end

    // Global watchdog: catches deadlocks even if a task's own timeout fails.
    initial begin
        #5000000;
        $display("FATAL: Global simulation watchdog expired");
        $finish;
    end

endmodule
