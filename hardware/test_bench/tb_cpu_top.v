`timescale 1ns / 1ps

module testbench;

    // 1. Declare signals to connect to the CPU
    reg clk;
    reg reset;

    // 2. Instantiate your top-level CPU module
    // Note: Make sure the port names (.clk, .reset) match exactly 
    // what you named them inside cpu_top.v!
    cpu_top uut (
        .clk(clk),
        .reset(reset)
    );

    // 3. Generate the clock signal (10ns period / 100MHz)
    always #5 clk = ~clk;

    // 4. Main simulation block
    initial begin
        // Setup VCD dumping for GTKWave
        // Saving it to your build folder to keep things organized
        $dumpfile("build/cpu_waveforms.vcd"); 
        
        // The '0' means dump all variables in this module and all sub-modules
        $dumpvars(0, testbench);

        // Initialize signals
        clk = 0;
        reset = 1; // Assert reset to clear out undefined 'x' states

        // Hold reset high for 20ns (2 clock cycles), then release it
        #20;
        reset = 0;

        // Let the CPU run the add.hex instructions
        // The add test is very short, so 1000ns (100 cycles) is plenty of time
        #1000;
        
        $display("Simulation complete. Open build/cpu_waveforms.vcd in GTKWave.");
        $finish; // End the simulation
    end

endmodule