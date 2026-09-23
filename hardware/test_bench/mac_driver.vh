// mac_driver.vh — CPU-side driver for the MAC accelerator (dot product).
// Include inside tb_cpu_top after rv32i_asm.vh. Writes straight into the DUT's
// instruction/data memories, so it must run after their $readmemh (see tb: #1).
//
// Computes  dot(A, B) = 1*5 + 2*6 + 3*7 + 4*8 = 70
//   A[0..3] @ 0x200, B[0..3] @ 0x220   (local data_memory)
//   MAC BUF_A @ 0x1000_0000, BUF_B @ 0x1000_4000, registers @ 0x1000_8000
// Result ends up in x17 (ACC_LO) and x18 (ACC_HI), then the core parks at DRV_DONE.
//
// Register use:
//   x7  MAC register base      x8/x9    source pointers A/B (local RAM)
//   x10/x11 BUF_A/BUF_B dst pointers   x12  elements left
//   x13/x14 element temps      x6/x15/x16 scratch (command, status, DONE bit)

localparam DRV_BASE = 32'h0000_00E0;     // right after the 56-instruction base program
localparam DRV_LEN  = 4;                 // number of elements

// MAC register offsets from x7 (= 0x1000_8000)
localparam MAC_CTRL   = 12'd0;           // [0]=START [1]=CLR_ACC
localparam MAC_STATUS = 12'd4;           // [0]=BUSY  [1]=DONE
localparam MAC_LEN    = 12'd8;
localparam MAC_ACC_LO = 12'd12;
localparam MAC_ACC_HI = 12'd16;

integer asm_pc;                          // address the next emit() lands at
integer L_copy, L_poll, DRV_DONE;        // labels
integer k;

task emit (input [31:0] word);
    begin
        u_dut.u_imem.mem[asm_pc >> 2] = word;
        asm_pc = asm_pc + 4;
    end
endtask

task load_mac_driver;
    begin
        asm_pc = DRV_BASE;

        // --- clear the accumulator ---
        emit(LUI (x7, 20'h10008));                   // x7 = 0x1000_8000 (MAC registers)
        emit(ADDI(x6, x0, 2));                       // CLR_ACC
        emit(SW  (x7, x6, MAC_CTRL));

        // --- set up copy pointers ---
        emit(ADDI(x8,  x0, 12'h200));                // &A (local RAM)
        emit(ADDI(x9,  x0, 12'h220));                // &B (local RAM)
        emit(LUI (x10, 20'h10000));                  // &BUF_A (MAC)
        emit(LUI (x11, 20'h10004));                  // &BUF_B (MAC)
        emit(ADDI(x12, x0, DRV_LEN));                // elements left

        // --- copy A[i], B[i] into the MAC buffers (local load = 1 cycle, bus store = 3) ---
        L_copy = asm_pc;
        emit(LW  (x13, x8,  0));
        emit(SW  (x10, x13, 0));
        emit(LW  (x14, x9,  0));
        emit(SW  (x11, x14, 0));
        emit(ADDI(x8,  x8,  4));
        emit(ADDI(x9,  x9,  4));
        emit(ADDI(x10, x10, 4));
        emit(ADDI(x11, x11, 4));
        emit(ADDI(x12, x12, -1));
        emit(BNE (x12, x0, L_copy - asm_pc));        // loop until x12 == 0

        // --- program length and start ---
        emit(ADDI(x6, x0, DRV_LEN));
        emit(SW  (x7, x6, MAC_LEN));
        emit(ADDI(x6, x0, 1));                       // START
        emit(SW  (x7, x6, MAC_CTRL));

        // --- poll STATUS until DONE (bit 1) ---
        L_poll = asm_pc;
        emit(LW  (x15, x7,  MAC_STATUS));
        emit(ANDI(x16, x15, 2));
        emit(BEQ (x16, x0, L_poll - asm_pc));

        // --- read the 64-bit result ---
        emit(LW  (x17, x7, MAC_ACC_LO));
        emit(LW  (x18, x7, MAC_ACC_HI));

        // --- park ---
        DRV_DONE = asm_pc;
        emit(JAL (x0, DRV_DONE - asm_pc));           // jump to self
    end
endtask

// Input vectors in local data_memory (word index = byte address / 4)
task load_mac_data;
    begin
        for (k = 0; k < DRV_LEN; k = k + 1) begin
            u_dut.u_mem.memory[32'h200 / 4 + k] = k + 1;   // A = 1,2,3,4
            u_dut.u_mem.memory[32'h220 / 4 + k] = k + 5;   // B = 5,6,7,8
        end
    end
endtask
