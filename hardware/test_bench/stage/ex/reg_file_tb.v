`timescale 1ns / 1ps

module reg_file_tb;

    reg clk;
    reg reset;
    reg RegWrite;
    reg [4:0] ReadReg1, ReadReg2, WriteReg;
    reg [31:0] WriteData;

    wire [31:0] ReadData1, ReadData2;

    // Instantiate DUT
    reg_file uut (
        .clk(clk),
        .reset(reset),
        .RegWrite(RegWrite),
        .ReadReg1(ReadReg1),
        .ReadReg2(ReadReg2),
        .WriteReg(WriteReg),
        .WriteData(WriteData),
        .ReadData1(ReadData1),
        .ReadData2(ReadData2)
    );

    // Clock generation
    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        RegWrite = 0;
        ReadReg1 = 0;
        ReadReg2 = 0;
        WriteReg = 0;
        WriteData = 0;

        // ---------------- Reset ----------------
        @(posedge clk);      // Reset occurs here
        reset = 0;

        ReadReg1 = 5;
        ReadReg2 = 10;
        #1;
        $display("After Reset: x5=%h x10=%h", ReadData1, ReadData2);

        // --------------- Write x5 --------------
        @(posedge clk);
        RegWrite = 1;
        WriteReg = 5;
        WriteData = 32'h12345678;

        @(posedge clk);
        RegWrite = 0;

        ReadReg1 = 5;
        #1;
        $display("x5 = %h (Expected 12345678)", ReadData1);

        // -------------- Write x10 --------------
        @(posedge clk);
        RegWrite = 1;
        WriteReg = 10;
        WriteData = 32'hABCDEF01;

        @(posedge clk);
        RegWrite = 0;

        ReadReg1 = 10;
        #1;
        $display("x10 = %h (Expected ABCDEF01)", ReadData1);

        // -------- Dual Read Test --------
        ReadReg1 = 5;
        ReadReg2 = 10;
        #1;
        $display("Dual Read: x5=%h x10=%h", ReadData1, ReadData2);

        // -------- x0 Protection --------
        @(posedge clk);
        RegWrite = 1;
        WriteReg = 0;
        WriteData = 32'hFFFFFFFF;

        @(posedge clk);
        RegWrite = 0;

        ReadReg1 = 0;
        #1;
        $display("x0 = %h (Expected 00000000)", ReadData1);

        $display("Register File Test Completed.");
        $finish;
    end

endmodule
