`timescale 1ns / 1ps
module reg_file_tb();

    reg clk;
    reg reset;
    reg RegWrite;

    reg [4:0] ReadReg1;
    reg [4:0] ReadReg2;
    reg [4:0] WriteReg;

    reg [31:0] WriteData;

    wire [31:0] ReadData1;
    wire [31:0] ReadData2;

    // Instantiate DUT
    reg_file uut(
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

        // Initialize
        clk = 0;
        reset = 1;
        RegWrite = 0;

        ReadReg1 = 0;
        ReadReg2 = 0;
        WriteReg = 0;
        WriteData = 0;

        //----------------------------------
        // Reset
        //----------------------------------
        #10;
        reset = 0;

        //----------------------------------
        // Write 100 to x5
        //----------------------------------
        RegWrite = 1;
        WriteReg = 5;
        WriteData = 32'd100;

        #10;

        //----------------------------------
        // Read x5
        //----------------------------------
        RegWrite = 0;
        ReadReg1 = 5;

        #2;

        if(ReadData1 == 100)
            $display("PASS : x5 = %d", ReadData1);
        else
            $display("FAIL : x5 = %d", ReadData1);

        //----------------------------------
        // Write 250 to x10
        //----------------------------------
        RegWrite = 1;
        WriteReg = 10;
        WriteData = 32'd250;

        #10;

        //----------------------------------
        // Read x5 and x10 simultaneously
        //----------------------------------
        RegWrite = 0;
        ReadReg1 = 5;
        ReadReg2 = 10;

        #2;

        if(ReadData1 == 100 && ReadData2 == 250)
            $display("PASS : Dual Read");
        else
            $display("FAIL : Dual Read");

        //----------------------------------
        // Try writing to x0
        //----------------------------------
        RegWrite = 1;
        WriteReg = 0;
        WriteData = 32'd999;

        #10;

        RegWrite = 0;
        ReadReg1 = 0;

        #2;

        if(ReadData1 == 0)
            $display("PASS : x0 protected");
        else
            $display("FAIL : x0 = %d", ReadData1);

        //----------------------------------
        // Overwrite x5
        //----------------------------------
        RegWrite = 1;
        WriteReg = 5;
        WriteData = 32'd777;

        #10;

        RegWrite = 0;
        ReadReg1 = 5;

        #2;

        if(ReadData1 == 777)
            $display("PASS : Overwrite x5");
        else
            $display("FAIL : x5 = %d", ReadData1);

        //----------------------------------
        // Reset again
        //----------------------------------
        reset = 1;

        #10;

        reset = 0;
        ReadReg1 = 5;
        ReadReg2 = 10;

        #2;

        if(ReadData1 == 0 && ReadData2 == 0)
            $display("PASS : Reset works");
        else
            $display("FAIL : Reset");

        //----------------------------------
        $display("Simulation Finished");
        $finish;

    end

endmodule
