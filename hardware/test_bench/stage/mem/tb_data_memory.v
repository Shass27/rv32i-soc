`timescale 1ns/1ps

module tb_data_memory;

    reg         clk;
    reg         MemRead;
    reg         MemWrite;
    reg [31:0]  mem_addr;
    reg [31:0]  rs2_data;
    reg [2:0]   funct3;

    wire [31:0] mem_rdata;

    // =====================================================
    // DUT
    // =====================================================

    data_memory #(
        .MEM_SIZE(2048)
    ) dut (
        .clk       (clk),
        .MemRead   (MemRead),
        .MemWrite  (MemWrite),
        .mem_addr  (mem_addr),
        .rs2_data  (rs2_data),
        .funct3    (funct3),
        .mem_rdata (mem_rdata)
    );

    // =====================================================
    // Clock
    // =====================================================

    always #5 clk = ~clk;

    // =====================================================
    // Test
    // =====================================================

    initial begin

        clk       = 0;
        MemRead   = 0;
        MemWrite  = 0;
        mem_addr  = 0;
        rs2_data  = 0;
        funct3    = 0;

        // -------------------------------------------------
        // Put known data directly into memory for testing
        //
        // memory[0] =
        //
        // 80 FF 7F 01
        //
        // Address:
        // 0x00 -> 01
        // 0x01 -> 7F
        // 0x02 -> FF
        // 0x03 -> 80
        // -------------------------------------------------

        dut.memory[0] = 32'h80FF7F01;

        #10;

        // =================================================
        // LW
        // =================================================

        $display("\n========== LW TEST ==========");

        MemRead  = 1;
        funct3   = 3'b010;
        mem_addr = 32'h00000000;

        #1;

        if (mem_rdata == 32'h80FF7F01)
            $display("PASS: LW");
        else
            $display("FAIL: LW -> got %h", mem_rdata);


        // =================================================
        // LB offset 0
        // Expected: 01
        // =================================================

        $display("\n========== LB TESTS ==========");

        funct3   = 3'b000;
        mem_addr = 32'h00000000;

        #1;

        if (mem_rdata == 32'h00000001)
            $display("PASS: LB offset 0");
        else
            $display("FAIL: LB offset 0 -> got %h", mem_rdata);


        // =================================================
        // LB offset 1
        // 7F -> positive
        // =================================================

        mem_addr = 32'h00000001;

        #1;

        if (mem_rdata == 32'h0000007F)
            $display("PASS: LB offset 1");
        else
            $display("FAIL: LB offset 1 -> got %h", mem_rdata);


        // =================================================
        // LB offset 2
        // FF -> sign extended
        // =================================================

        mem_addr = 32'h00000002;

        #1;

        if (mem_rdata == 32'hFFFFFFFF)
            $display("PASS: LB offset 2");
        else
            $display("FAIL: LB offset 2 -> got %h", mem_rdata);


        // =================================================
        // LB offset 3
        // 80 -> sign extended
        // =================================================

        mem_addr = 32'h00000003;

        #1;

        if (mem_rdata == 32'hFFFFFF80)
            $display("PASS: LB offset 3");
        else
            $display("FAIL: LB offset 3 -> got %h", mem_rdata);


        // =================================================
        // LBU
        // =================================================

        $display("\n========== LBU TESTS ==========");

        funct3   = 3'b100;
        mem_addr = 32'h00000002;

        #1;

        if (mem_rdata == 32'h000000FF)
            $display("PASS: LBU offset 2");
        else
            $display("FAIL: LBU offset 2 -> got %h", mem_rdata);


        mem_addr = 32'h00000003;

        #1;

        if (mem_rdata == 32'h00000080)
            $display("PASS: LBU offset 3");
        else
            $display("FAIL: LBU offset 3 -> got %h", mem_rdata);


        // =================================================
        // LH offset 0
        // 7F01
        // =================================================

        $display("\n========== LH TESTS ==========");

        funct3   = 3'b001;
        mem_addr = 32'h00000000;

        #1;

        if (mem_rdata == 32'h00007F01)
            $display("PASS: LH offset 0");
        else
            $display("FAIL: LH offset 0 -> got %h", mem_rdata);


        // =================================================
        // LH offset 2
        // 80FF -> sign extended
        // =================================================

        mem_addr = 32'h00000002;

        #1;

        if (mem_rdata == 32'hFFFF80FF)
            $display("PASS: LH offset 2");
        else
            $display("FAIL: LH offset 2 -> got %h", mem_rdata);


        // =================================================
        // LHU
        // =================================================

        $display("\n========== LHU TESTS ==========");

        funct3   = 3'b101;
        mem_addr = 32'h00000002;

        #1;

        if (mem_rdata == 32'h000080FF)
            $display("PASS: LHU offset 2");
        else
            $display("FAIL: LHU offset 2 -> got %h", mem_rdata);


        // =================================================
        // SW
        // =================================================

        $display("\n========== SW TEST ==========");

        MemRead   = 0;
        MemWrite  = 1;
        funct3    = 3'b010;
        mem_addr  = 32'h00000004;
        rs2_data  = 32'hAABBCCDD;

        @(posedge clk);
        #1;

        if (dut.memory[1] == 32'hAABBCCDD)
            $display("PASS: SW");
        else
            $display("FAIL: SW -> memory = %h", dut.memory[1]);


        // =================================================
        // SB
        // =================================================

        $display("\n========== SB TEST ==========");

        MemWrite = 1;
        funct3   = 3'b000;
        mem_addr = 32'h00000004;
        rs2_data = 32'h00000011;

        @(posedge clk);
        #1;

        if (dut.memory[1] == 32'hAABBCC11)
            $display("PASS: SB offset 0");
        else
            $display("FAIL: SB offset 0 -> memory = %h",
                     dut.memory[1]);


        // SB offset 1

        mem_addr = 32'h00000005;
        rs2_data = 32'h00000022;

        @(posedge clk);
        #1;

        if (dut.memory[1] == 32'hAABB22DD)
            $display("PASS: SB offset 1");
        else
            $display("FAIL: SB offset 1 -> memory = %h",
                     dut.memory[1]);


        // SB offset 2

        mem_addr = 32'h00000006;
        rs2_data = 32'h00000033;

        @(posedge clk);
        #1;

        if (dut.memory[1] == 32'hAA33CCDD)
            $display("PASS: SB offset 2");
        else
            $display("FAIL: SB offset 2 -> memory = %h",
                     dut.memory[1]);


        // SB offset 3

        mem_addr = 32'h00000007;
        rs2_data = 32'h00000044;

        @(posedge clk);
        #1;

        if (dut.memory[1] == 32'h44BBCCDD)
            $display("PASS: SB offset 3");
        else
            $display("FAIL: SB offset 3 -> memory = %h",
                     dut.memory[1]);


        // =================================================
        // SH
        // =================================================

        $display("\n========== SH TEST ==========");

        // Reset known value

        dut.memory[2] = 32'h11223344;

        funct3   = 3'b001;
        mem_addr = 32'h00000008;
        rs2_data = 32'h0000AABB;

        @(posedge clk);
        #1;

        if (dut.memory[2] == 32'h1122AABB)
            $display("PASS: SH offset 0");
        else
            $display("FAIL: SH offset 0 -> memory = %h",
                     dut.memory[2]);


        // SH offset 2

        dut.memory[2] = 32'h11223344;

        mem_addr = 32'h0000000A;
        rs2_data = 32'h0000CCDD;

        @(posedge clk);
        #1;

        if (dut.memory[2] == 32'hCCDD3344)
            $display("PASS: SH offset 2");
        else
            $display("FAIL: SH offset 2 -> memory = %h",
                     dut.memory[2]);


        // =================================================
        // Finish
        // =================================================

        MemRead  = 0;
        MemWrite = 0;

        $display("\n========================================");
        $display("      DATA MEMORY TEST COMPLETE");
        $display("========================================\n");

        $finish;

    end

endmodule