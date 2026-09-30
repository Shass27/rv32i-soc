`timescale 1ns/1ps
// Dual-port data_memory check: A<->B visibility, SB merge, port B skips TOHOST
module tb_dp_mem;

    reg         clk = 0;
    reg         MemRead = 0, MemWrite = 0;
    reg  [2:0]  funct3 = 3'b010;
    reg  [31:0] mem_addr = 0, rs2_data = 0;
    reg         i_b_we = 0;
    reg  [31:0] i_b_addr = 0, i_b_wdat = 0;
    wire [31:0] mem_rdata, o_b_rdat;
    integer     errors = 0;

    data_memory dut (
        .clk(clk), .MemWrite(MemWrite), .MemRead(MemRead), .funct3(funct3),
        .mem_addr(mem_addr), .rs2_data(rs2_data), .mem_rdata(mem_rdata),
        .i_b_we(i_b_we), .i_b_addr(i_b_addr), .i_b_wdat(i_b_wdat), .o_b_rdat(o_b_rdat)
    );

    always #5 clk = ~clk;

    task check(input [8*24-1:0] label, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL: %0s got=%h exp=%h", label, got, exp);
            errors = errors + 1;
        end
    endtask

    // port A store, one clock edge
    task a_store(input [2:0] f3, input [31:0] addr, input [31:0] data);
        begin
            @(negedge clk); funct3 = f3; mem_addr = addr; rs2_data = data; MemWrite = 1;
            @(negedge clk); MemWrite = 0;
        end
    endtask

    // port B word write, one clock edge
    task b_store(input [31:0] addr, input [31:0] data);
        begin
            @(negedge clk); i_b_addr = addr; i_b_wdat = data; i_b_we = 1;
            @(negedge clk); i_b_we = 0;
        end
    endtask

    initial begin
        $dumpfile("build/tb_dp_mem.vcd");
        $dumpvars(1, clk);
        $dumpvars(1, MemRead, MemWrite, funct3, mem_addr, rs2_data, i_b_we, i_b_addr, i_b_wdat);
        $dumpvars(1, mem_rdata, o_b_rdat);

        // SW via A, read via B
        a_store(3'b010, 32'h100, 32'hDEADBEEF);
        i_b_addr = 32'h100; #1 check("A SW -> B read", o_b_rdat, 32'hDEADBEEF);

        // write via B, LW via A
        b_store(32'h104, 32'hCAFEF00D);
        funct3 = 3'b010; mem_addr = 32'h104; MemRead = 1;
        #1 check("B write -> A LW", mem_rdata, 32'hCAFEF00D);
        MemRead = 0;

        // SB via A merges into word seen by B
        a_store(3'b010, 32'h108, 32'h0);
        a_store(3'b000, 32'h109, 32'hAB);
        i_b_addr = 32'h108; #1 check("A SB -> B read", o_b_rdat, 32'h0000AB00);

        // B write to tohost must not $finish
        b_store(32'h1c0, 32'h1);
        funct3 = 3'b010; mem_addr = 32'h1c0; MemRead = 1;
        #1 check("B tohost -> A LW", mem_rdata, 32'h1);
        MemRead = 0;

        if (errors == 0) $display("PASS: all checks passed");
        else             $display("FAIL: %0d check(s) failed", errors);
        $finish;
    end

endmodule
