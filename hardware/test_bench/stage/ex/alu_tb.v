`timescale 1ns / 1ps

module alu_tb;

    reg  [31:0] A;
    reg  [31:0] B;
    reg  [3:0]  ALUControl;
    reg  [31:0] pc;

    wire [31:0] ALU_result;
    wire        ALU_zero;

    // DUT
    alu_module uut (
        .A(A),
        .B(B),
        .ALUControl(ALUControl),
        .pc(pc),
        .ALU_result(ALU_result),
        .ALU_zero(ALU_zero)
    );

    // ALUControl encoding
    localparam ADD      = 4'b0000;
    localparam SUB      = 4'b0001;
    localparam AND      = 4'b0010;
    localparam OR       = 4'b0011;
    localparam XOR      = 4'b0100;
    localparam SLL      = 4'b0101;
    localparam SRL      = 4'b0110;
    localparam SRA      = 4'b0111;
    localparam SLT      = 4'b1000;
    localparam SLTU     = 4'b1001;
    localparam AUIPC_OP = 4'b1010;

    integer pass_count;
    integer fail_count;

    task test_alu;
        input [31:0] test_A;
        input [31:0] test_B;
        input [3:0]  test_control;
        input [31:0] expected_result;
        input        expected_zero;
        input [127:0] test_name;

        begin
            A = test_A;
            B = test_B;
            ALUControl = test_control;

            #10;

            if ((ALU_result === expected_result) &&
                (ALU_zero === expected_zero)) begin

                $display("PASS: %s | A=%h B=%h Result=%h Zero=%b",
                         test_name, A, B, ALU_result, ALU_zero);

                pass_count = pass_count + 1;
            end
            else begin

                $display("FAIL: %s | A=%h B=%h",
                         test_name, A, B);

                $display("      Expected: Result=%h Zero=%b",
                         expected_result, expected_zero);

                $display("      Got:      Result=%h Zero=%b",
                         ALU_result, ALU_zero);

                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin

        // Initial values
        A = 32'b0;
        B = 32'b0;
        pc = 32'b0;
        ALUControl = ADD;

        pass_count = 0;
        fail_count = 0;

        $display("");
        $display("==============================================");
        $display("          ALU TESTBENCH START");
        $display("   Milestone 1 + Milestone 2 + AUIPC");
        $display("==============================================");
        $display("");


        // =====================================================
        // MILESTONE 1
        // ADD
        // =====================================================

        test_alu(
            32'd10,
            32'd5,
            ADD,
            32'd15,
            1'b0,
            "ADD"
        );


        // =====================================================
        // SUB
        // =====================================================

        test_alu(
            32'd10,
            32'd5,
            SUB,
            32'd5,
            1'b0,
            "SUB"
        );

        // SUB resulting in zero -> BEQ zero flag
        test_alu(
            32'd10,
            32'd10,
            SUB,
            32'd0,
            1'b1,
            "SUB ZERO"
        );


        // =====================================================
        // ADDI
        // =====================================================

        test_alu(
            32'd25,
            32'd7,
            ADD,
            32'd32,
            1'b0,
            "ADDI (A + immediate)"
        );


        // =====================================================
        // MILESTONE 2
        // =====================================================

        // -----------------------------------------------------
        // AND / ANDI
        // -----------------------------------------------------

        test_alu(
            32'hF0F0F0F0,
            32'h0F0F0F0F,
            AND,
            32'h00000000,
            1'b0,
            "AND"
        );

        test_alu(
            32'h12345678,
            32'h000000FF,
            AND,
            32'h00000078,
            1'b0,
            "ANDI"
        );


        // -----------------------------------------------------
        // OR / ORI
        // -----------------------------------------------------

        test_alu(
            32'hF0000000,
            32'h0000000F,
            OR,
            32'hF000000F,
            1'b0,
            "OR"
        );

        test_alu(
            32'h12340000,
            32'h00005678,
            OR,
            32'h12345678,
            1'b0,
            "ORI"
        );


        // -----------------------------------------------------
        // XOR / XORI
        // -----------------------------------------------------

        test_alu(
            32'hAAAAAAAA,
            32'h55555555,
            XOR,
            32'hFFFFFFFF,
            1'b0,
            "XOR"
        );

        test_alu(
            32'h12345678,
            32'h0000FFFF,
            XOR,
            32'h1234A987,
            1'b0,
            "XORI"
        );


        // -----------------------------------------------------
        // SLL / SLLI
        // -----------------------------------------------------

        test_alu(
            32'd3,
            32'd2,
            SLL,
            32'd12,
            1'b0,
            "SLL"
        );

        test_alu(
            32'd5,
            32'd3,
            SLL,
            32'd40,
            1'b0,
            "SLLI"
        );


        // -----------------------------------------------------
        // SRL / SRLI
        // -----------------------------------------------------

        test_alu(
            32'h00000080,
            32'd2,
            SRL,
            32'h00000020,
            1'b0,
            "SRL"
        );

        test_alu(
            32'h80000000,
            32'd4,
            SRL,
            32'h08000000,
            1'b0,
            "SRLI"
        );


        // -----------------------------------------------------
        // SRA / SRAI
        // -----------------------------------------------------

        test_alu(
            32'd16,
            32'd2,
            SRA,
            32'd4,
            1'b0,
            "SRA positive"
        );

        test_alu(
            32'hFFFFFFF0,
            32'd2,
            SRA,
            32'hFFFFFFFC,
            1'b0,
            "SRA negative"
        );

        test_alu(
            32'hFFFFFFE0,
            32'd3,
            SRA,
            32'hFFFFFFFC,
            1'b0,
            "SRAI negative"
        );


        // -----------------------------------------------------
        // SLT / SLTI
        // -----------------------------------------------------

        test_alu(
            32'd5,
            32'd10,
            SLT,
            32'd1,
            1'b0,
            "SLT"
        );

        // -1 < 1 -> TRUE
        test_alu(
            32'hFFFFFFFF,
            32'd1,
            SLT,
            32'd1,
            1'b0,
            "SLTI signed negative"
        );


        // -----------------------------------------------------
        // SLTU / SLTIU
        // -----------------------------------------------------

        test_alu(
            32'd5,
            32'd10,
            SLTU,
            32'd1,
            1'b0,
            "SLTU"
        );

        // 0xFFFFFFFF < 1 unsigned -> FALSE
        test_alu(
            32'hFFFFFFFF,
            32'd1,
            SLTU,
            32'd0,
            1'b0,
            "SLTIU unsigned"
        );


        // =====================================================
        // AUIPC
        // =====================================================

        // PC = 0x00001000
        // B  = 0x12345000
        // Result = 0x12346000
        //
        // A is intentionally set to a garbage value because
        // AUIPC_OP should ignore A and use PC + B.
        // =====================================================

        pc = 32'h00001000;
        A  = 32'hDEADBEEF;
        B  = 32'h12345000;
        ALUControl = AUIPC_OP;

        #10;

        if ((ALU_result === 32'h12346000) &&
            (ALU_zero === 1'b0)) begin

            $display("PASS: AUIPC | PC=%h B=%h Result=%h",
                     pc, B, ALU_result);

            pass_count = pass_count + 1;
        end
        else begin

            $display("FAIL: AUIPC");
            $display("      Expected: Result=%h Zero=%b",
                     32'h12346000, 1'b0);
            $display("      Got:      Result=%h Zero=%b",
                     ALU_result, ALU_zero);

            fail_count = fail_count + 1;
        end


        // =====================================================
        // SUMMARY
        // =====================================================

        $display("");
        $display("==============================================");
        $display("                 ALU SUMMARY");
        $display("==============================================");
        $display("PASS = %0d", pass_count);
        $display("FAIL = %0d", fail_count);

        if (fail_count == 0)
            $display("ALL ALU TESTS PASSED!");
        else
            $display("SOME ALU TESTS FAILED!");

        $display("==============================================");

        $finish;

    end

endmodule