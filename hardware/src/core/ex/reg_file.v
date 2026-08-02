<<<<<<< HEAD

`timescale 1ns / 1ps

=======
`timescale 1ns / 1ps
>>>>>>> 67c45e14c1987f2fcb1dfa84bfe05d54cf8170b5
module reg_file(

    input clk,
    input reset,

    input RegWrite,

    input [4:0] ReadReg1,
    input [4:0] ReadReg2,

    input [4:0] WriteReg,
    input [31:0] WriteData,

    output [31:0] ReadData1,
    output [31:0] ReadData2

);

    reg [31:0] registers [0:31];

    integer i;

    assign ReadData1 = registers[ReadReg1];
    assign ReadData2 = registers[ReadReg2];

    always @(posedge clk)
    begin
        if(reset)
        begin
            for(i=0;i<=31;i=i+1)
                registers[i] <= 32'b0;
        end
        else if(RegWrite && WriteReg != 5'b0)
            registers[WriteReg] <= WriteData;
    end

endmodule

