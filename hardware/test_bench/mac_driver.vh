// mac_driver.vh — CPU-side driver for the 4x4 matrix MAC (C = A(4xK) * B(Kx4), K = 4).
// Include inside tb_cpu_top_wb_mac after rv32i_asm.vh. Writes straight into the DUT's
// instruction memory, so it must run after its $readmemh (see tb: #1).
//
// The CPU `sw`s A and B into the write-only matrix window at MAT_BASE (0x4000_0000):
//   A[r][k] at word r*256+k,  B[k][c] at word 1024+4*k+c   (K_MAX = 256)
// then programs DATA_BASE/K/CTRL, polls STATUS.DONE, reads C[0][0] and C[3][3] into
// x17/x18 and x19/x20, and DMA-copies all 32 result words (bus slave -> local RAM 0x240).
//
// Register use: x2 DMA base, x3 result base, x4/x5 A-row/B window ptrs, x6/x13 temps,
//               x7 MAC regs, x15/x16 poll, x1 DMA start/len temps.

localparam DRV_BASE = 32'h0000_00E0;     // right after the 56-instruction base program
localparam DRV_K    = 4;                 // inner dimension
localparam RES_RAM  = 32'h0000_0240;     // DMA destination of the 32 result words

integer asm_pc;                          // address the next emit() lands at
integer L_poll, DRV_DONE;                // labels
integer ar, ak, bk, bc;

task emit (input [31:0] word);
    begin
        u_dut.u_imem.mem[asm_pc >> 2] = word;
        asm_pc = asm_pc + 4;
    end
endtask

// Test matrices (signed, small): A[r][k], B[k][c]
function integer a_val (input integer r, input integer k); a_val = 3*r - 2*k + 1; endfunction
function integer b_val (input integer k, input integer c); b_val = 2*k - c - 3;   endfunction

task load_mac_driver;
    begin
        asm_pc = DRV_BASE;
        emit(LUI (x4, 20'h40000));                       // x4 = &A[0][0] (MAT_BASE)
        emit(LUI (x5, 20'h40001));                       // x5 = &B[0][0] (MAT_BASE + 4*K_MAX words)
        for (ar = 0; ar < 4; ar = ar + 1) begin
            for (ak = 0; ak < DRV_K; ak = ak + 1) begin
                emit(ADDI(x13, x0, a_val(ar, ak)));
                emit(SW  (x4, x13, 4*ak));
            end
            emit(ADDI(x4, x4, 1024));                    // next A row (K_MAX words)
        end
        for (bk = 0; bk < DRV_K; bk = bk + 1)
            for (bc = 0; bc < 4; bc = bc + 1) begin
                emit(ADDI(x13, x0, b_val(bk, bc)));
                emit(SW  (x5, x13, 16*bk + 4*bc));
            end

        // --- program and start the accelerator ---
        emit(LUI (x7, 20'h10008));                       // x7 = 0x1000_8000 (MAC regs)
        emit(LUI (x6, 20'h40000));
        emit(SW  (x7, x6, 0));                           // DATA_BASE = MAT_BASE
        emit(ADDI(x6, x0, DRV_K));
        emit(SW  (x7, x6, 4));                           // K
        emit(ADDI(x6, x0, 1));
        emit(SW  (x7, x6, 8));                           // CTRL.START

        // --- poll STATUS until DONE (bit 1) ---
        L_poll = asm_pc;
        emit(LW  (x15, x7, 12));
        emit(ANDI(x16, x15, 2));
        emit(BEQ (x16, x0, L_poll - asm_pc));

        // --- read C[0][0] and C[3][3] (64-bit, lo/hi) ---
        emit(LUI (x3, 20'h10000));                       // x3 = result window
        emit(LW  (x17, x3, 0));
        emit(LW  (x18, x3, 4));
        emit(LW  (x19, x3, 120));
        emit(LW  (x20, x3, 124));

        // --- DMA: 32 result words (bus slave) -> local RAM; CPU stalls until done ---
        emit(LUI (x2, 20'h20000));                       // x2 = DMA base
        emit(SW  (x2, x3, 0));                           // SRC = 0x1000_0000
        emit(ADDI(x1, x0, 12'h240));
        emit(SW  (x2, x1, 4));                           // DST = RES_RAM
        emit(ADDI(x1, x0, 32));
        emit(SW  (x2, x1, 8));                           // LEN = 32
        emit(ADDI(x1, x0, 1));
        emit(SW  (x2, x1, 12));                          // START

        DRV_DONE = asm_pc;
        emit(JAL (x0, 0));                               // park
    end
endtask
