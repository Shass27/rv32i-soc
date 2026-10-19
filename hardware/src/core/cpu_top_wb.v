module cpu_top_wb #(
    // Matrix scratch window (matrix_mem). Size = 32*MAT_K_MAX bytes (8 KB for 256).
    // MAT_BASE must be aligned to that size and must not overlap local data_memory
    // (0x0000_0000-0x0000_FFFF) or any Wishbone slave page (0x1000_xxxx..0x3000_xxxx).
    // MAT_K_MAX must be a power of two. MAT_MEM_LAT / MAT_MULT_PIPE are passed to both
    // matrix_mem and wb_mac_accel (MAT_MEM_LAT must match on both sides).
    parameter [31:0] MAT_BASE      = 32'h4000_0000,
    parameter        MAT_K_MAX     = 256,
    parameter        MAT_MEM_LAT   = 0,
    parameter        MAT_MULT_PIPE = 0
)(
    input wire clk,
    input wire reset,
    output wire [31:0] debug_pc
);

    // =========================================================
    //  Internal wires
    // =========================================================

    // --- IF stage ---
    wire [31:0] pc;
    wire [31:0] instr;

    // --- Stall: held only while a Wishbone (IO) access is in flight ---
    wire        stall;
    wire        dma_busy;       // DMA owns the bus and the CPU is frozen

    // --- Gated RegWrite: suppressed while stall is asserted ---
    wire        RegWrite_gated;

    // --- ID stage (control_unit.v) ---
    wire        RegWrite;
    wire        ALUSrc;
    wire        ALUSrcA;
    wire        MemRead;
    wire        MemWrite;
    wire        MemToReg;
    wire        branch;
    wire        jump1;          // JAL
    wire        jump2;          // JALR
    wire [1:0]  ALUOp;

    // --- Derived jump signal (JAL or JALR) ---
    wire        jump;
    assign jump = jump1 | jump2;
    assign RegWrite_gated = RegWrite & ~stall;

    // --- ID stage (immediate_gen.v) ---
    wire [31:0] imm;

    // --- EX stage (alu_control decode) ---
    wire [4:0]  rs1;
    wire [4:0]  rs2;
    wire [4:0]  rd;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire [3:0]  ALUControl;

    // --- EX stage (register file + ALU) ---
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] alu_A;          // muxed ALU operand A (rs1_data or pc)
    wire [31:0] alu_B;          // muxed ALU operand B (rs2_data or imm)
    wire [31:0] ALU_result;

    // --- Branch / Jump ---
    wire        branch_taken;
    wire [31:0] branch_target;
    wire [31:0] jump_target;
    wire [31:0] jump_ret_addr;

    // --- MEM/WB ---
    wire [31:0] mem_rdata;          // local or Wishbone read data (muxed in MEM stage)
    wire [31:0] mem_rdata_local;
    wire [31:0] wb_data;
    // port B wires — declared here so data_memory instantiation can use them
     // DMA and SORT share data_memory Port B
    wire        dma_b_we;
    wire [31:0] dma_b_addr, dma_b_wdat;

    wire        sort_b_we;
    wire [31:0] sort_b_addr, sort_b_wdat;

    wire        b_we;
    wire [31:0] b_addr, b_wdat, b_rdat;

    // DMA has priority; SORT runs when DMA is idle
    wire sort_mem_grant = ~dma_busy;

    assign b_we   = dma_busy ? dma_b_we   : sort_b_we;
    assign b_addr = dma_busy ? dma_b_addr : sort_b_addr;
    assign b_wdat = dma_busy ? dma_b_wdat : sort_b_wdat;
    wire [31:0] sort_b_rdat;
    assign sort_b_rdat = b_rdat;

    // --- Muxed signals ---
    wire [31:0] target;         // final target for PC

    // =========================================================
    //  Target MUX — select between branch and jump targets
    // =========================================================
    //  Priority: jump takes precedence over branch
    assign target = jump ? jump_target : branch_target;

    // =========================================================
    //  ALU A-side MUX — AUIPC feeds pc, everything else feeds rs1_data
    // =========================================================
    assign alu_A = ALUSrcA ? pc : rs1_data;

    // =========================================================
    //  IF STAGE
    // =========================================================
    program_counter u_pc (
        .clk          (clk),
        .reset        (reset),
        .stall        (stall),
        .branch_taken (branch_taken),
        .jump1        (jump1),
        .jump2        (jump2),
        .target       (target),
        .pc           (pc)
    );

    inst_mem u_imem (
        .i_addr (pc),
        .o_inst (instr)
    );

    // =========================================================
    //  ID STAGE
    // =========================================================
    control_unit u_ctrl (
        .instr    (instr),
        .RegWrite (RegWrite),
        .ALUSrc   (ALUSrc),
        .ALUSrcA  (ALUSrcA),
        .MemRead  (MemRead),
        .MemWrite (MemWrite),
        .MemToReg (MemToReg),
        .branch   (branch),
        .jump1    (jump1),
        .jump2    (jump2),
        .ALUOp    (ALUOp)
    );

    imm_gen u_immgen (
        .instr (instr),
        .imm   (imm)
    );

    // =========================================================
    //  EX STAGE
    // =========================================================
    alu_control u_alu_ctrl (
        .instr      (instr),
        .ALUOp      (ALUOp),
        .rs1        (rs1),
        .rs2        (rs2),
        .rd         (rd),
        .funct3     (funct3),
        .funct7     (funct7),
        .ALUControl (ALUControl)
    );

    reg_file u_regfile (
        .clk       (clk),
        .reset     (reset),
        .RegWrite  (RegWrite_gated),
        .ReadReg1  (rs1),
        .ReadReg2  (rs2),
        .WriteReg  (rd),
        .WriteData (wb_data),
        .ReadData1 (rs1_data),
        .ReadData2 (rs2_data)
    );

    alu_src_mux u_alu_mux (
        .ALUSrc   (ALUSrc),
        .rs2_data (rs2_data),
        .imm      (imm),
        .alu_B    (alu_B)
    );

    alu_module u_alu (
        .A          (alu_A),
        .B          (alu_B),
        .ALUControl (ALUControl),
        .pc         (pc),
        .ALU_result (ALU_result)
    );

    // =========================================================
    //  BRANCH / JUMP LOGIC
    // =========================================================
    branch_logic u_branch (
        .branch       (branch),
        .pc           (pc),
        .imm          (imm),
        .ReadData1    (rs1_data),
        .ReadData2    (rs2_data),
        .funct3       (funct3),
        .branch_taken (branch_taken),
        .target       (branch_target)
    );

    jump_logic u_jump (
        .jump1         (jump1),
        .jump2         (jump2),
        .pc            (pc),
        .imm           (imm),
        .ReadData1     (rs1_data),
        .target        (jump_target),
        .jump_ret_addr (jump_ret_addr)
    );

    // =========================================================
    //  MEM STAGE
    // =========================================================
    // Bottom 64 KB is local data_memory; the matrix window (matrix_mem) is a
    // single-cycle, write-only 32-bit-store target; everything else above 64 KB
    // goes out on Wishbone.
    localparam MAT_WIN_BITS = $clog2(MAT_K_MAX) + 5;   // window size = 2**MAT_WIN_BITS bytes

    wire        mat_sel = (MemRead | MemWrite) &
                          (ALU_result[31:MAT_WIN_BITS] == MAT_BASE[31:MAT_WIN_BITS]);
    // sw only; SB/SH to the window are ignored. Held off while the DMA freezes the CPU,
    // so a frozen store executes once, after the DMA releases it.
    wire        mat_we  = MemWrite & mat_sel & (funct3 == 3'b010) & ~dma_busy;
    wire        io_sel  = (MemRead | MemWrite) & (ALU_result[31:16] != 16'h0000) & ~mat_sel;

    data_memory u_mem (
        .clk       (clk),
        .MemRead   (MemRead  & ~io_sel & ~mat_sel),
        .MemWrite  (MemWrite & ~io_sel & ~mat_sel & ~dma_busy),   // a frozen SW must not collide with DMA port B
        .mem_addr  (ALU_result),
        .rs2_data  (rs2_data),
        .funct3    (funct3),
        .mem_rdata (mem_rdata_local),
        // port B: DMA local access path
        .i_b_we    (b_we),
        .i_b_addr  (b_addr),
        .i_b_wdat  (b_wdat),
        .o_b_rdat  (b_rdat)
    );

    // Matrix scratch memory: CPU writes via mat_we, accelerator reads a 256-bit tile per cycle
    wire [255:0] mat_tile;
    wire [31:0]  mat_tile_addr;

    matrix_mem #(
        .K_MAX   (MAT_K_MAX),
        .MEM_LAT (MAT_MEM_LAT)
    ) u_matmem (
        .clk       (clk),
        .we        (mat_we),
        .waddr     (ALU_result),
        .wdata     (rs2_data),
        .tile_addr (mat_tile_addr),
        .tile      (mat_tile)
    );

    // =========================================================
    //  WISHBONE (IO) PATH
    // =========================================================
    // ponytail: bus is word-only (no SEL); SB/SH to IO space writes a full word.
    // Add o_wb_sel[3:0] to wb_master + wb_ram/wb_mac_accel if sub-word IO is ever needed.
    wire        wb_busy, wb_done, wb_err_flag, wb_req;
    wire [31:0] wb_rdat;

    // Master -> slave broadcast (WE/ADR/DAT go to every slave; CYC/STB are gated by the interconnect)
    wire        m_cyc, m_stb, m_we;
    wire [31:0] m_adr, m_dat;

    // Per-master bus signals, muxed onto m_* by dma_busy
    wire        cpu_cyc, cpu_stb, cpu_we, cpu_ack, cpu_err;
    wire [31:0] cpu_adr, cpu_dat;
    wire        dma_cyc, dma_stb, dma_we, dma_ack, dma_err;
    wire [31:0] dma_adr, dma_dat;

    // Slave -> interconnect
    wire        ram_cyc, ram_stb, mac_cyc, mac_stb, err_cyc, err_stb;
    wire        sort_cyc, sort_stb;                 
    wire [31:0] mac_dat, err_dat, sort_dat;         
    wire        mac_ack, mac_err, err_ack, err_err;
    wire        sort_ack, sort_err;                 
    wire        ic_ack, ic_err;
    wire [31:0] ic_dat;
    // DMA slave port (interconnect → wb_dma register page)
    wire        dma_s_cyc, dma_s_stb, dma_s_ack;
    wire [31:0] dma_s_rdat;

    // One request pulse per IO instruction; never while the DMA owns the bus
    assign wb_req = io_sel & ~wb_busy & ~wb_done & ~dma_busy;
    // done pulse always releases, so the START store advances even though dma_busy rose on the same edge
    assign stall  = ~wb_done & (io_sel | dma_busy);

    wb_dma u_dma (
        .i_clk    (clk),       .i_rst    (reset),
        .i_s_cyc  (dma_s_cyc), .i_s_stb  (dma_s_stb),
        .i_s_we   (m_we),      .i_s_adr  (m_adr),      // WE/ADR/DAT are broadcast
        .i_s_dat  (m_dat),     .o_s_dat  (dma_s_rdat),
        .o_s_ack  (dma_s_ack), .o_s_err  (),
        .o_m_cyc  (dma_cyc),   .o_m_stb  (dma_stb),
        .o_m_we   (dma_we),    .o_m_adr  (dma_adr),
        .o_m_dat  (dma_dat),   .i_m_dat  (ic_dat),
        .i_m_ack  (dma_ack),   .i_m_err  (dma_err),
        .o_b_we   (dma_b_we),   .o_b_addr (dma_b_addr),
        .o_b_wdat (dma_b_wdat), .i_b_rdat (b_rdat),
        .o_busy   (dma_busy)
    );

    // ponytail: CPU halts during DMA, so ownership is a plain mux on dma_busy.
    // Swap for a round-robin wb_arbiter when background DMA (UART streaming, double-buffering) is needed.
    assign m_cyc = dma_busy ? dma_cyc : cpu_cyc;
    assign m_stb = dma_busy ? dma_stb : cpu_stb;
    assign m_we  = dma_busy ? dma_we  : cpu_we;
    assign m_adr = dma_busy ? dma_adr : cpu_adr;
    assign m_dat = dma_busy ? dma_dat : cpu_dat;
    assign cpu_ack = ic_ack & ~dma_busy;   // ACK/ERR only reach the owner; ic_dat goes to both
    assign cpu_err = ic_err & ~dma_busy;
    assign dma_ack = ic_ack &  dma_busy;
    assign dma_err = ic_err &  dma_busy;

    // Matrix window is write-only: a load from it returns 0 rather than aliasing data_memory
    assign mem_rdata = io_sel ? wb_rdat : mat_sel ? 32'b0 : mem_rdata_local;

    wb_master u_wb_master (
        .i_clk    (clk),
        .i_rst    (reset),
        .i_req    (wb_req),
        .i_we     (MemWrite),
        .i_addr   (ALU_result),
        .i_wdat   (rs2_data),
        .o_rdat   (wb_rdat),
        .o_busy   (wb_busy),
        .o_done   (wb_done),
        .o_err    (wb_err_flag),
        .o_wb_cyc (cpu_cyc),
        .o_wb_stb (cpu_stb),
        .o_wb_we  (cpu_we),
        .o_wb_adr (cpu_adr),
        .o_wb_dat (cpu_dat),
        .i_wb_dat (ic_dat),
        .i_wb_ack (cpu_ack),
        .i_wb_err (cpu_err)
    );

    wb_interconnect u_wb_ic (
        .i_wb_cyc    (m_cyc),
        .i_wb_stb    (m_stb),
        .i_wb_we     (m_we),
        .i_wb_adr    (m_adr),
        .i_wb_dat_ms (m_dat),
        .o_wb_dat_sm (ic_dat),
        .o_wb_ack    (ic_ack),
        .o_wb_err    (ic_err),
        // Slave 0 (wb_ram) unused: local data_memory owns 0x0000_0000-0x0000_FFFF
        .o_ram_cyc   (ram_cyc),
        .o_ram_stb   (ram_stb),
        .i_ram_dat   (32'b0),
        .i_ram_ack   (1'b0),
        // Slave 1: MAC accelerator
        .o_mac_cyc   (mac_cyc),
        .o_mac_stb   (mac_stb),
        .i_mac_dat   (mac_dat),
        .i_mac_ack   (mac_ack),
        .i_mac_err   (mac_err),
        // Slave 2: catch-all error slave
        .o_err_cyc   (err_cyc),
        .o_err_stb   (err_stb),
        .i_err_dat   (err_dat),
        .i_err_ack   (err_ack),
        .i_err_err   (err_err),
        // Slave 3: DMA register page at 0x2000_xxxx
        .o_dma_cyc   (dma_s_cyc),
        .o_dma_stb   (dma_s_stb),
        .i_dma_dat   (dma_s_rdat),
        .i_dma_ack   (dma_s_ack),
        .i_dma_err   (1'b0),
      // Slave 4: SORT register page at 0x3000_xxxx
        .o_sort_cyc   (sort_cyc),       // NEW
        .o_sort_stb   (sort_stb),       // NEW
        .i_sort_dat   (sort_dat),       // NEW
        .i_sort_ack   (sort_ack),       // NEW
        .i_sort_err   (sort_err)        // NEW
    );

    wb_mac_accel #(
        .K_MAX     (MAT_K_MAX),
        .MEM_LAT   (MAT_MEM_LAT),
        .MULT_PIPE (MAT_MULT_PIPE)
    ) u_mac (
        .i_wb_clk (clk),
        .i_wb_rst (reset),
        .i_wb_adr (m_adr),
        .i_wb_dat (m_dat),
        .i_wb_we  (m_we),
        .i_wb_stb (mac_stb),
        .i_wb_cyc (mac_cyc),
        .o_wb_dat (mac_dat),
        .o_wb_ack (mac_ack),
        .o_wb_err (mac_err),
        .o_irq    (),
        // tile port to matrix_mem
        .o_mem_tile_addr (mat_tile_addr),
        .i_mem_tile      (mat_tile)
    );

    wb_err u_wb_err (
        .i_wb_clk (clk),
        .i_wb_rst (reset),
        .i_wb_adr (m_adr),
        .i_wb_dat (m_dat),
        .i_wb_we  (m_we),
        .i_wb_stb (err_stb),
        .i_wb_cyc (err_cyc),
        .o_wb_dat (err_dat),
        .o_wb_ack (err_ack),
        .o_wb_err (err_err)
    );

    // =========================================================
    //  WB STAGE
    // =========================================================
    writeback_mux u_wb (
        .MemToReg      (MemToReg),
        .jump1         (jump1),
        .jump2         (jump2),
        .alu_result    (ALU_result),
        .mem_rdata     (mem_rdata),
        .jump_ret_addr (jump_ret_addr),
        .wb_data       (wb_data)
    );
   

    wb_sort u_sort (
    .i_wb_clk(clk),
    .i_wb_rst(reset),
    .i_wb_adr(m_adr),
    .i_wb_dat(m_dat),
    .i_wb_we(m_we),
    .i_wb_stb(sort_stb),
    .i_wb_cyc(sort_cyc),
    .o_wb_dat(sort_dat),
    .o_wb_ack(sort_ack),
    .o_wb_err(sort_err),
    .o_mem_we(sort_b_we),
    .o_mem_addr(sort_b_addr),
    .o_mem_wdata(sort_b_wdat),
    .i_mem_rdata(sort_b_rdat),
    .i_mem_grant(sort_mem_grant)
);
assign debug_pc = pc;
endmodule
