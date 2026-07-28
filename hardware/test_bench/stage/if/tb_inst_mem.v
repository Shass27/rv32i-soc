`timescale 1ns / 1ps
module tb_inst_mem;
    reg  [31:0] i_addr;
    wire [31:0] o_inst;

    inst_mem uut (
        .i_addr (i_addr),
        .o_inst (o_inst)
    );

    initial begin
        i_addr = 32'h00; #10;
        if (o_inst !== 32'h00500093) $display("FAIL addr00: got %h", o_inst);

        i_addr = 32'h04; #10;
        if (o_inst !== 32'h00300113) $display("FAIL addr04: got %h", o_inst);

        i_addr = 32'h08; #10;
        if (o_inst !== 32'h002081B3) $display("FAIL addr08: got %h", o_inst);

        i_addr = 32'h0C; #10;
        if (o_inst !== 32'h40208233) $display("FAIL addr0C: got %h", o_inst);

        i_addr = 32'h10; #10;
        if (o_inst !== 32'h0020F2B3) $display("FAIL addr10: got %h", o_inst);

        i_addr = 32'h14; #10;
        if (o_inst !== 32'h0020E333) $display("FAIL addr14: got %h", o_inst);

        i_addr = 32'h18; #10;
        if (o_inst !== 32'h0020C3B3) $display("FAIL addr18: got %h", o_inst);

        i_addr = 32'h1C; #10;
        if (o_inst !== 32'h0000006F) $display("FAIL addr1C: got %h", o_inst);

        $display("done");
        $finish;
    end
endmodule