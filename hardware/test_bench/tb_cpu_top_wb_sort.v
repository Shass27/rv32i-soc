`timescale 1ns/1ps

module tb_cpu_top_wb_sort;

    reg clk = 1'b0;
    reg reset = 1'b1;

    wire [31:0] debug_pc;

    integer i;
    integer errors = 0;

    localparam integer SRC_WORD = 32'h100 >> 2; // word 64
    localparam integer DST_WORD = 32'h140 >> 2; // word 80
    localparam integer SORT_LEN = 8;
    localparam integer MAX_CYCLES = 5000;

    reg [31:0] expected [0:SORT_LEN-1];

    always #5 clk = ~clk;

    // run the sort program (path relative to the vvp working dir = repo root)
    defparam u_dut.u_imem.PROG_FILE = "program_sort.hex";

    // Actual SoC: CPU + interconnect + SORT + data memory + DMA.
    cpu_top_wb u_dut (
        .clk      (clk),
        .reset    (reset),
        .debug_pc (debug_pc)
    );

    initial begin
        $dumpfile("sort_soc.vcd");
        $dumpvars(0, tb_cpu_top_wb_sort);

        // Expected ascending order.
        expected[0] = 1;
        expected[1] = 2;
        expected[2] = 3;
        expected[3] = 4;
        expected[4] = 5;
        expected[5] = 7;
        expected[6] = 8;
        expected[7] = 9;

        // Wait until the memories' own initial blocks have run.
        #2;

        // Source array at byte address 0x100.
        u_dut.u_mem.memory[SRC_WORD + 0] = 7;
        u_dut.u_mem.memory[SRC_WORD + 1] = 2;
        u_dut.u_mem.memory[SRC_WORD + 2] = 9;
        u_dut.u_mem.memory[SRC_WORD + 3] = 1;
        u_dut.u_mem.memory[SRC_WORD + 4] = 5;
        u_dut.u_mem.memory[SRC_WORD + 5] = 3;
        u_dut.u_mem.memory[SRC_WORD + 6] = 8;
        u_dut.u_mem.memory[SRC_WORD + 7] = 4;

        // Clear the destination before starting.
        for (i = 0; i < SORT_LEN; i = i + 1)
            u_dut.u_mem.memory[DST_WORD + i] = 32'hDEAD_BEEF;

        $display("========================================");
        $display(" CPU + Wishbone + SORT integration test");
        $display(" Source      : 0x00000100");
        $display(" Destination : 0x00000140");
        $display(" Length      : %0d words", SORT_LEN);
        $display("========================================");

        // Synchronous reset.
        #18;
        reset = 1'b0;

        // Allow the CPU to program and start SORT, then finish sorting.
        repeat (MAX_CYCLES) @(posedge clk);
        #1;

        $display("\nDestination memory after execution:");

        for (i = 0; i < SORT_LEN; i = i + 1) begin
            $display("dst[%0d] = %0d (expected %0d)",
                     i,
                     u_dut.u_mem.memory[DST_WORD + i],
                     expected[i]);

            if (u_dut.u_mem.memory[DST_WORD + i] !== expected[i]) begin
                $display("FAIL at destination index %0d", i);
                errors = errors + 1;
            end
        end

     

        if (errors == 0)
            $display("\nPASS: CPU-driven SORT integration test passed.");
        else
            $display("\nFAIL: %0d error(s) found.", errors);

        $finish;
    end

endmodule