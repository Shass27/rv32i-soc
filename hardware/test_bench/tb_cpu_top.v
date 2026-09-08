`timescale 1ns / 1ps

module testbench;

    // 1. Declare signals and INITIALIZE clock immediately
    // This prevents the "x" (unknown) state race condition
    reg clk = 0;
    reg reset;

    // 2. Instantiate your top-level CPU module
    cpu_top uut (
        .clk(clk),
        .reset(reset)
    );

    // 3. Generate the clock signal (10ns period / 100MHz)
    always #5 clk = ~clk;

    // 4. Dedicated VCD Dump Block (Best Practice)
    initial begin
        $dumpfile("build/cpu_waveforms.vcd"); 
        $dumpvars(0, testbench);
    end

    // 5. Main simulation logic
    initial begin
        // Assert reset to clear out undefined 'x' states
        reset = 1; 

        // Hold reset high for 20ns (2 clock cycles), then release it
        #20;
        reset = 0;

        // Let the CPU run the add.hex instructions
        #1000;
        
        $display("Simulation complete. Open build/cpu_waveforms.vcd in GTKWave.");
        $finish; // End the simulation safely to flush the VCD file
    end

endmodule