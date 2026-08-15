`timescale 1ns/1ps

module tb_writeback_mux;

    reg        MemToReg;
    reg        jump;

    reg [31:0] alu_result;
    reg [31:0] mem_rdata;
    reg [31:0] jump_ret_addr;

    wire [31:0] wb_data;

    // =====================================================
    // DUT
    // =====================================================

    writeback_mux dut (
        .MemToReg     (MemToReg),
        .jump         (jump),
        .alu_result   (alu_result),
        .mem_rdata    (mem_rdata),
        .jump_ret_addr(jump_ret_addr),
        .wb_data      (wb_data)
    );

    // =====================================================
    // Tests
    // =====================================================

    initial begin

        alu_result    = 32'h11111111;
        mem_rdata     = 32'h22222222;
        jump_ret_addr = 32'h33333333;

        // =================================================
        // Test 1: Normal ALU instruction
        // jump = 0
        // MemToReg = 0
        //
        // Expected = alu_result
        // =================================================

        jump     = 0;
        MemToReg = 0;

        #10;

        if (wb_data == 32'h11111111)
            $display("PASS: ALU writeback");
        else
            $display("FAIL: ALU writeback -> got %h",
                     wb_data);


        // =================================================
        // Test 2: Load instruction
        // jump = 0
        // MemToReg = 1
        //
        // Expected = mem_rdata
        // =================================================

        jump     = 0;
        MemToReg = 1;

        #10;

        if (wb_data == 32'h22222222)
            $display("PASS: Memory writeback");
        else
            $display("FAIL: Memory writeback -> got %h",
                     wb_data);


        // =================================================
        // Test 3: JAL / JALR
        // jump = 1
        //
        // Expected = jump_ret_addr
        //
        // Notice that jump has priority over MemToReg
        // =================================================

        jump     = 1;
        MemToReg = 0;

        #10;

        if (wb_data == 32'h33333333)
            $display("PASS: Jump writeback");
        else
            $display("FAIL: Jump writeback -> got %h",
                     wb_data);


        // =================================================
        // Test 4: Jump priority
        //
        // Even if MemToReg = 1,
        // jump must select jump_ret_addr.
        // =================================================

        jump     = 1;
        MemToReg = 1;

        #10;

        if (wb_data == 32'h33333333)
            $display("PASS: Jump priority");
        else
            $display("FAIL: Jump priority -> got %h",
                     wb_data);


        // =================================================
        // Finish
        // =================================================

        $display("\n========================================");
        $display("      WRITEBACK MUX TEST COMPLETE");
        $display("========================================\n");

        $finish;

    end

endmodule