// dma_driver.vh — DMA-based driver for the MAC accelerator (dot product).
// Replaces mac_driver.vh: uses the DMA controller to copy vectors into MAC buffers
// instead of a CPU SW loop. Include inside tb_cpu_top_wb after rv32i_asm.vh.
//
// Computes  dot(A, B) = 1*5 + 2*6 + 3*7 + 4*8 = 70
//   A[0..3] @ 0x200, B[0..3] @ 0x220   (local data_memory)
//   DMA base @ 0x2000_0000, MAC BUF_A @ 0x1000_0000, BUF_B @ 0x1000_4000
// Result ends up in x17 (ACC_LO), x18 (ACC_HI); core parks at DRV_DONE.
//
// No DONE polling needed for DMA: SW to DMA_CTRL=1 stalls the CPU (via dma_busy)
// until the copy completes. CPU resumes with the MAC buffer already populated.
// DMA: 4 cycles/word × 4 words × 2 transfers = 32 cycles.
// CPU loop equivalent: ~14 cycles/word × 4 words × 2 copies = ~112 cycles.

localparam DRV_BASE = 32'h0000_00E0;    // right after the 56-instruction base program
localparam DRV_LEN  = 4;               // elements per vector

// DMA register offsets from DMA base (x2 = 0x2000_0000)
localparam DMA_SRC  = 12'd0;
localparam DMA_DST  = 12'd4;
localparam DMA_LEN  = 12'd8;
localparam DMA_CTRL = 12'd12;

// MAC register offsets from x7 (= 0x1000_8000)
localparam MAC_CTRL   = 12'd0;
localparam MAC_STATUS = 12'd4;
localparam MAC_LEN    = 12'd8;
localparam MAC_ACC_LO = 12'd12;
localparam MAC_ACC_HI = 12'd16;

integer asm_pc;                         // address the next emit() lands at
integer L_poll, DRV_DONE;              // labels
integer k;

task emit (input [31:0] word);
    begin
        u_dut.u_imem.mem[asm_pc >> 2] = word;
        asm_pc = asm_pc + 4;
    end
endtask

task load_dma_driver;
    begin
        asm_pc = DRV_BASE;

        // --- setup registers ---
        emit(LUI (x2, 20'h20000));              // x2 = 0x2000_0000  DMA base
        emit(ADDI(x3, x0, 12'h200));            // x3 = 0x200        src_A byte addr
        emit(ADDI(x8, x0, 12'h220));            // x8 = 0x220        src_B byte addr
        emit(LUI (x4, 20'h10000));              // x4 = 0x1000_0000  MAC BUF_A
        emit(LUI (x5, 20'h10004));              // x5 = 0x1000_4000  MAC BUF_B
        emit(ADDI(x6, x0, DRV_LEN));            // x6 = 4            LEN
        emit(ADDI(x1, x0, 1));                  // x1 = 1            START bit
        emit(LUI (x7, 20'h10008));              // x7 = 0x1000_8000  MAC reg base

        // --- clear MAC accumulator ---
        emit(ADDI(x9, x0, 2));                  // x9 = 2  CLR_ACC bit
        emit(SW  (x7, x9, MAC_CTRL));           // MAC_CTRL = CLR_ACC

        // --- DMA transfer 1: A (0x200) → BUF_A (0x1000_0000) ---
        emit(SW  (x2, x3, DMA_SRC));            // DMA_SRC = 0x200
        emit(SW  (x2, x4, DMA_DST));            // DMA_DST = 0x1000_0000
        emit(SW  (x2, x6, DMA_LEN));            // DMA_LEN = 4
        emit(SW  (x2, x1, DMA_CTRL));           // DMA_CTRL = START → CPU stalls until DONE

        // --- DMA transfer 2: B (0x220) → BUF_B (0x1000_4000) ---
        emit(SW  (x2, x8, DMA_SRC));            // DMA_SRC = 0x220
        emit(SW  (x2, x5, DMA_DST));            // DMA_DST = 0x1000_4000
        emit(SW  (x2, x6, DMA_LEN));            // DMA_LEN = 4
        emit(SW  (x2, x1, DMA_CTRL));           // DMA_CTRL = START → CPU stalls until DONE

        // --- start MAC ---
        emit(SW  (x7, x6, MAC_LEN));            // MAC_LEN = 4
        emit(SW  (x7, x1, MAC_CTRL));           // MAC_CTRL = START

        // --- poll STATUS until DONE (bit 1) ---
        L_poll = asm_pc;
        emit(LW  (x15, x7, MAC_STATUS));
        emit(ANDI(x16, x15, 2));
        emit(BEQ (x16, x0, L_poll - asm_pc));

        // --- read 64-bit result ---
        emit(LW  (x17, x7, MAC_ACC_LO));        // x17 = dot product result
        emit(LW  (x18, x7, MAC_ACC_HI));

        // --- park ---
        DRV_DONE = asm_pc;
        emit(JAL (x0, DRV_DONE - asm_pc));      // jump to self
    end
endtask

// Input vectors in local data_memory (unchanged from mac_driver.vh)
task load_mac_data;
    begin
        for (k = 0; k < DRV_LEN; k = k + 1) begin
            u_dut.u_mem.memory[32'h200 / 4 + k] = k + 1;  // A = 1,2,3,4
            u_dut.u_mem.memory[32'h220 / 4 + k] = k + 5;  // B = 5,6,7,8
        end
    end
endtask
