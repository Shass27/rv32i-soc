`timescale 1ns/1ps

module tb_cpu_top;

    // ---------------------------------------------------------
    // Clock / reset
    // ---------------------------------------------------------
    reg clk;
    reg reset;

    integer cycle;
    integer errors;

    // DUT: top-level CPU
    cpu_top u_dut (
        .clk   (clk),
        .reset (reset)
    );

    // ---------------------------------------------------------
    // Test program in program.hex
    //
    // 0x00: 00000093  addi x1, x0, 0
    // 0x04: 00A00113  addi x2, x0, 10
    // 0x08: 0020A023  sw   x2, 0(x1)
    // 0x0C: 0000A183  lw   x3, 0(x1)
    // 0x10: 00A00213  addi x4, x0, 10
    // 0x14: 00418463  beq  x3, x4, +8
    // 0x18: 06300293  addi x5, x0, 99   (should be skipped when branch is taken)
    // 0x1C: 00418333  add  x6, x3, x4
    // 0x20: 404303B3  sub  x7, x6, x4
    // 0x24: 0000006F  jal  x0, 0        (infinite loop)
    //
    // Expected behavior:
    // - store 10 to memory at address 0
    // - load it back into x3
    // - branch is taken because x3 == x4
    // - x5 is skipped
    // - arithmetic instructions execute
    // - CPU ends in a self-loop
    // ---------------------------------------------------------

    // ---------------------------------------------------------
    // Waveform dump
    // This recreates cpu_top.vcd on each simulation run.
    // ---------------------------------------------------------
    initial begin
        $dumpfile("cpu_top.vcd");
        $dumpvars(0, tb_cpu_top);
    end

    // Clock: 10 ns period
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Reset: hold high for a few cycles, then release
    initial begin
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
    end

    // ---------------------------------------------------------
    // Simple helper for checks
    // ---------------------------------------------------------
    task automatic check_eq32;
        input [255:0] label;
        input [31:0] got;
        input [31:0] exp;
        begin
            if (got !== exp) begin
                $display("FAIL: %0s got=%08h exp=%08h @%0t", label, got, exp, $time);
                errors = errors + 1;
            end
        end
    endtask

    task automatic check_eq1;
        input [255:0] label;
        input got;
        input exp;
        begin
            if (got !== exp) begin
                $display("FAIL: %0s got=%b exp=%b @%0t", label, got, exp, $time);
                errors = errors + 1;
            end
        end
    endtask

    // ---------------------------------------------------------
    // Main self-checking monitor
    //
    // Single-cycle CPU: each instruction should appear in order.
    // The branch at 0x14 should skip the addi at 0x18.
    // The program ends in a jal x0,0 self-loop at 0x24.
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            cycle  <= 0;
            errors <= 0;
        end else begin
            case (cycle)
                0: begin
                    check_eq32("pc[0]",   u_dut.pc,    32'h00000000);
                    check_eq32("instr[0]", u_dut.instr, 32'h00000093);
                end
                1: begin
                    check_eq32("pc[1]",   u_dut.pc,    32'h00000004);
                    check_eq32("instr[1]", u_dut.instr, 32'h00A00113);
                end
                2: begin
                    check_eq32("pc[2]",   u_dut.pc,    32'h00000008);
                    check_eq32("instr[2]", u_dut.instr, 32'h0020A023);
                end
                3: begin
                    check_eq32("pc[3]",   u_dut.pc,    32'h0000000C);
                    check_eq32("instr[3]", u_dut.instr, 32'h0000A183);
                    // Store/load path should deliver 10 back to the WB path.
                    check_eq32("load-data", u_dut.mem_rdata, 32'h0000000A);
                    check_eq32("wb-data",   u_dut.final_wb_data, 32'h0000000A);
                end
                4: begin
                    check_eq32("pc[4]",   u_dut.pc,    32'h00000010);
                    check_eq32("instr[4]", u_dut.instr, 32'h00A00213);
                end
                5: begin
                    check_eq32("pc[5]",   u_dut.pc,    32'h00000014);
                    check_eq32("instr[5]", u_dut.instr, 32'h00418463);
                    check_eq1("branch-taken", u_dut.branch_taken, 1'b1);
                end
                6: begin
                    // Branch should skip 0x18 and land on 0x1C.
                    check_eq32("pc[6]",   u_dut.pc,    32'h0000001C);
                    check_eq32("instr[6]", u_dut.instr, 32'h00418333);
                end
                7: begin
                    check_eq32("pc[7]",   u_dut.pc,    32'h00000020);
                    check_eq32("instr[7]", u_dut.instr, 32'h404303B3);
                end
                8: begin
                    check_eq32("pc[8]",   u_dut.pc,    32'h00000024);
                    check_eq32("instr[8]", u_dut.instr, 32'h0000006F);
                    check_eq1("jump", u_dut.jump, 1'b1);
                end
                default: begin
                    // The program ends in a self-loop at 0x24.
                    check_eq32("pc-loop",   u_dut.pc,    32'h00000024);
                    check_eq32("instr-loop", u_dut.instr, 32'h0000006F);
                end
            endcase

            cycle <= cycle + 1;
        end
    end

    // ---------------------------------------------------------
    // Stop after enough cycles and report result
    // ---------------------------------------------------------
    initial begin
        cycle  = 0;
        errors = 0;

        repeat (30) @(posedge clk);

        if (errors == 0) begin
            $display("PASS: all checks passed");
        end else begin
            $display("FAIL: %0d check(s) failed", errors);
        end

        $finish;
    end

endmodule