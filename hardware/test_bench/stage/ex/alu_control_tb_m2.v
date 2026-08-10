`timescale 1ns / 1ps

module alu_control_tb;

    reg  [31:0] instr;
    reg  [1:0]  ALUOp;

    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [6:0] funct7;
    wire [3:0] ALUControl;

    // DUT
    alu_control uut (
        .instr(instr),
        .ALUOp(ALUOp),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .funct3(funct3),
        .funct7(funct7),
        .ALUControl(ALUControl)
    );


    // =========================================================
    // OPCODES
    // =========================================================

    localparam R_TYPE = 7'b0110011;
    localparam I_TYPE = 7'b0010011;


    // =========================================================
    // ALUOp
    // =========================================================

    localparam ALU_ADD    = 2'b00;
    localparam ALU_SUB    = 2'b01;
    localparam ALU_DECODE = 2'b10;
    localparam ALU_JAL    = 2'b11;


    // =========================================================
    // ALUControl
    // =========================================================

    localparam ADD  = 4'b0000;
    localparam SUB  = 4'b0001;
    localparam AND  = 4'b0010;
    localparam OR   = 4'b0011;
    localparam XOR  = 4'b0100;
    localparam SLL  = 4'b0101;
    localparam SRL  = 4'b0110;
    localparam SRA  = 4'b0111;
    localparam SLT  = 4'b1000;
    localparam SLTU = 4'b1001;


    integer pass_count;
    integer fail_count;


    // =========================================================
    // R-TYPE INSTRUCTION GENERATOR
    //
    // funct7 | rs2 | rs1 | funct3 | rd | opcode
    // =========================================================

    function [31:0] make_r;
        input [6:0] funct7_in;
        input [4:0] rs2_in;
        input [4:0] rs1_in;
        input [2:0] funct3_in;
        input [4:0] rd_in;

        begin
            make_r = {
                funct7_in,
                rs2_in,
                rs1_in,
                funct3_in,
                rd_in,
                R_TYPE
            };
        end
    endfunction


    // =========================================================
    // NORMAL I-TYPE INSTRUCTION GENERATOR
    //
    // imm[11:0] | rs1 | funct3 | rd | opcode
    // =========================================================

    function [31:0] make_i;
        input [11:0] imm_in;
        input [4:0]  rs1_in;
        input [2:0]  funct3_in;
        input [4:0]  rd_in;

        begin
            make_i = {
                imm_in,
                rs1_in,
                funct3_in,
                rd_in,
                I_TYPE
            };
        end
    endfunction


    // =========================================================
    // SHIFT I-TYPE INSTRUCTION GENERATOR
    //
    // funct7/upper | shamt | rs1 | funct3 | rd | opcode
    //
    // IMPORTANT:
    // This is NOT a funct7 field in the RISC-V sense.
    // These are instr[31:25] bits used by shift-immediate encoding.
    // =========================================================

    function [31:0] make_shift_i;
        input [6:0] funct7_bits;
        input [4:0] shamt_in;
        input [4:0] rs1_in;
        input [2:0] funct3_in;
        input [4:0] rd_in;

        begin
            make_shift_i = {
                funct7_bits,
                shamt_in,
                rs1_in,
                funct3_in,
                rd_in,
                I_TYPE
            };
        end
    endfunction


    // =========================================================
    // TEST TASK
    // =========================================================

    task check_instruction;
        input [31:0] instruction;
        input [3:0]  expected_control;
        input [4:0]  expected_rs1;
        input [4:0]  expected_rs2;
        input [4:0]  expected_rd;
        input [127:0] instruction_name;

        begin

            instr = instruction;
            ALUOp = ALU_DECODE;

            #10;

            if ((ALUControl === expected_control) &&
                (rs1 === expected_rs1) &&
                (rs2 === expected_rs2) &&
                (rd === expected_rd)) begin

                $display(
                    "PASS: %-8s | ALUControl=%b rs1=%0d rs2=%0d rd=%0d",
                    instruction_name,
                    ALUControl,
                    rs1,
                    rs2,
                    rd
                );

                pass_count = pass_count + 1;
            end

            else begin

                $display(
                    "FAIL: %-8s",
                    instruction_name
                );

                $display(
                    "      Expected: ALUControl=%b rs1=%0d rs2=%0d rd=%0d",
                    expected_control,
                    expected_rs1,
                    expected_rs2,
                    expected_rd
                );

                $display(
                    "      Got:      ALUControl=%b rs1=%0d rs2=%0d rd=%0d",
                    ALUControl,
                    rs1,
                    rs2,
                    rd
                );

                fail_count = fail_count + 1;
            end

        end
    endtask


    // =========================================================
    // TESTS
    // =========================================================

    initial begin

        pass_count = 0;
        fail_count = 0;

        $display("");
        $display("======================================================");
        $display("             ALU CONTROL TESTBENCH");
        $display("        MILESTONE 1 + MILESTONE 2");
        $display("======================================================");
        $display("");


        // =====================================================
        // MILESTONE 1
        // =====================================================

        // -----------------------------------------------------
        // 1. ADD x5,x6,x7
        // funct7=0000000, funct3=000
        // -----------------------------------------------------

        check_instruction(
            make_r(
                7'b0000000,
                5'd7,
                5'd6,
                3'b000,
                5'd5
            ),
            ADD,
            5'd6,
            5'd7,
            5'd5,
            "ADD"
        );


        // -----------------------------------------------------
        // 2. SUB x5,x6,x7
        // funct7=0100000, funct3=000
        // -----------------------------------------------------

        check_instruction(
            make_r(
                7'b0100000,
                5'd7,
                5'd6,
                3'b000,
                5'd5
            ),
            SUB,
            5'd6,
            5'd7,
            5'd5,
            "SUB"
        );


        // -----------------------------------------------------
        // 3. ADDI x5,x6,10
        // funct3=000
        // -----------------------------------------------------

        check_instruction(
            make_i(
                12'd10,
                5'd6,
                3'b000,
                5'd5
            ),
            ADD,
            5'd6,
            5'd0,
            5'd5,
            "ADDI"
        );


        // =====================================================
        // MILESTONE 2
        // =====================================================


        // -----------------------------------------------------
        // 4. AND x5,x6,x7
        // -----------------------------------------------------

        check_instruction(
            make_r(
                7'b0000000,
                5'd7,
                5'd6,
                3'b111,
                5'd5
            ),
            AND,
            5'd6,
            5'd7,
            5'd5,
            "AND"
        );


        // -----------------------------------------------------
        // 5. OR x5,x6,x7
        // -----------------------------------------------------

        check_instruction(
            make_r(
                7'b0000000,
                5'd7,
                5'd6,
                3'b110,
                5'd5
            ),
            OR,
            5'd6,
            5'd7,
            5'd5,
            "OR"
        );


        // -----------------------------------------------------
        // 6. XOR x5,x6,x7
        // -----------------------------------------------------

        check_instruction(
            make_r(
                7'b0000000,
                5'd7,
                5'd6,
                3'b100,
                5'd5
            ),
            XOR,
            5'd6,
            5'd7,
            5'd5,
            "XOR"
        );


        // -----------------------------------------------------
        // 7. SLL x5,x6,x7
        // -----------------------------------------------------

        check_instruction(
            make_r(
                7'b0000000,
                5'd7,
                5'd6,
                3'b001,
                5'd5
            ),
            SLL,
            5'd6,
            5'd7,
            5'd5,
            "SLL"
        );


        // -----------------------------------------------------
        // 8. SRL x5,x6,x7
        // -----------------------------------------------------

        check_instruction(
            make_r(
                7'b0000000,
                5'd7,
                5'd6,
                3'b101,
                5'd5
            ),
            SRL,
            5'd6,
            5'd7,
            5'd5,
            "SRL"
        );


        // -----------------------------------------------------
        // 9. SRA x5,x6,x7
        // -----------------------------------------------------

        check_instruction(
            make_r(
                7'b0100000,
                5'd7,
                5'd6,
                3'b101,
                5'd5
            ),
            SRA,
            5'd6,
            5'd7,
            5'd5,
            "SRA"
        );


        // -----------------------------------------------------
        // 10. SLT x5,x6,x7
        // -----------------------------------------------------

        check_instruction(
            make_r(
                7'b0000000,
                5'd7,
                5'd6,
                3'b010,
                5'd5
            ),
            SLT,
            5'd6,
            5'd7,
            5'd5,
            "SLT"
        );


        // -----------------------------------------------------
        // 11. SLTU x5,x6,x7
        // -----------------------------------------------------

        check_instruction(
            make_r(
                7'b0000000,
                5'd7,
                5'd6,
                3'b011,
                5'd5
            ),
            SLTU,
            5'd6,
            5'd7,
            5'd5,
            "SLTU"
        );


        // -----------------------------------------------------
        // 12. ANDI x5,x6,10
        // -----------------------------------------------------

        check_instruction(
            make_i(
                12'd10,
                5'd6,
                3'b111,
                5'd5
            ),
            AND,
            5'd6,
            5'd0,
            5'd5,
            "ANDI"
        );


        // -----------------------------------------------------
        // 13. ORI x5,x6,10
        // -----------------------------------------------------

        check_instruction(
            make_i(
                12'd10,
                5'd6,
                3'b110,
                5'd5
            ),
            OR,
            5'd6,
            5'd0,
            5'd5,
            "ORI"
        );


        // -----------------------------------------------------
        // 14. XORI x5,x6,10
        // -----------------------------------------------------

        check_instruction(
            make_i(
                12'd10,
                5'd6,
                3'b100,
                5'd5
            ),
            XOR,
            5'd6,
            5'd0,
            5'd5,
            "XORI"
        );


        // -----------------------------------------------------
        // 15. SLLI x5,x6,3
        // instr[31:25] = 0000000
        // shamt = 3
        // funct3 = 001
        // -----------------------------------------------------

        check_instruction(
            make_shift_i(
                7'b0000000,
                5'd3,
                5'd6,
                3'b001,
                5'd5
            ),
            SLL,
            5'd6,
            5'd0,
            5'd5,
            "SLLI"
        );


        // -----------------------------------------------------
        // 16. SRLI x5,x6,3
        // instr[31:25] = 0000000
        // shamt = 3
        // funct3 = 101
        // -----------------------------------------------------

        check_instruction(
            make_shift_i(
                7'b0000000,
                5'd3,
                5'd6,
                3'b101,
                5'd5
            ),
            SRL,
            5'd6,
            5'd0,
            5'd5,
            "SRLI"
        );


        // -----------------------------------------------------
        // 17. SRAI x5,x6,3
        // instr[31:25] = 0100000
        // shamt = 3
        // funct3 = 101
        // -----------------------------------------------------

        check_instruction(
            make_shift_i(
                7'b0100000,
                5'd3,
                5'd6,
                3'b101,
                5'd5
            ),
            SRA,
            5'd6,
            5'd0,
            5'd5,
            "SRAI"
        );


        // -----------------------------------------------------
        // 18. SLTI x5,x6,10
        // -----------------------------------------------------

        check_instruction(
            make_i(
                12'd10,
                5'd6,
                3'b010,
                5'd5
            ),
            SLT,
            5'd6,
            5'd0,
            5'd5,
            "SLTI"
        );


        // -----------------------------------------------------
        // 19. SLTIU x5,x6,10
        // -----------------------------------------------------

        check_instruction(
            make_i(
                12'd10,
                5'd6,
                3'b011,
                5'd5
            ),
            SLTU,
            5'd6,
            5'd0,
            5'd5,
            "SLTIU"
        );


        // =====================================================
        // ALSO TEST YOUR NON-DECODE ALUOp CASES
        // =====================================================

        // LW/SW -> forced ADD
        instr = 32'b0;
        ALUOp = ALU_ADD;

        #10;

        if (ALUControl === ADD) begin
            $display("PASS: ALU_ADD -> ADD");
            pass_count = pass_count + 1;
        end
        else begin
            $display("FAIL: ALU_ADD -> expected ADD, got %b",
                     ALUControl);
            fail_count = fail_count + 1;
        end


        // BEQ -> forced SUB
        instr = 32'b0;
        ALUOp = ALU_SUB;

        #10;

        if (ALUControl === SUB) begin
            $display("PASS: ALU_SUB -> SUB");
            pass_count = pass_count + 1;
        end
        else begin
            $display("FAIL: ALU_SUB -> expected SUB, got %b",
                     ALUControl);
            fail_count = fail_count + 1;
        end


        // JAL -> ADD
        instr = 32'b0;
        ALUOp = ALU_JAL;

        #10;

        if (ALUControl === ADD) begin
            $display("PASS: ALU_JAL -> ADD");
            pass_count = pass_count + 1;
        end
        else begin
            $display("FAIL: ALU_JAL -> expected ADD, got %b",
                     ALUControl);
            fail_count = fail_count + 1;
        end


        // =====================================================
        // SUMMARY
        // =====================================================

        $display("");
        $display("======================================================");
        $display("                  TEST SUMMARY");
        $display("======================================================");
        $display("PASS = %0d", pass_count);
        $display("FAIL = %0d", fail_count);

        if (fail_count == 0)
            $display("ALL ALU CONTROL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");

        $display("======================================================");

        $finish;

    end

endmodule