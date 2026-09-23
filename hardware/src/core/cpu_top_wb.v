module cpu_top_wb (
    input wire clk,
    input wire reset
);

    // =========================================================
    //  Internal wires
    // =========================================================

    // --- IF stage ---
    wire [31:0] pc;
    wire [31:0] instr;

    // --- Stall: held only while a Wishbone (IO) access is in flight ---
    wire        stall;

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
    // Bottom 64 KB is local data_memory; everything above goes out on Wishbone
    wire        io_sel = (MemRead | MemWrite) & (ALU_result[31:16] != 16'h0000);

    data_memory u_mem (
        .clk       (clk),
        .MemRead   (MemRead  & ~io_sel),
        .MemWrite  (MemWrite & ~io_sel),
        .mem_addr  (ALU_result),
        .rs2_data  (rs2_data),
        .funct3    (funct3),
        .mem_rdata (mem_rdata_local)
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

    // Slave -> interconnect
    wire        ram_cyc, ram_stb, mac_cyc, mac_stb, err_cyc, err_stb;
    wire [31:0] mac_dat, err_dat;
    wire        mac_ack, mac_err, err_ack, err_err;
    wire        ic_ack, ic_err;
    wire [31:0] ic_dat;

    // One request pulse per IO instruction; stall holds the core until the done pulse
    assign wb_req = io_sel & ~wb_busy & ~wb_done;
    assign stall  = io_sel & ~wb_done;

    assign mem_rdata = io_sel ? wb_rdat : mem_rdata_local;

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
        .o_wb_cyc (m_cyc),
        .o_wb_stb (m_stb),
        .o_wb_we  (m_we),
        .o_wb_adr (m_adr),
        .o_wb_dat (m_dat),
        .i_wb_dat (ic_dat),
        .i_wb_ack (ic_ack),
        .i_wb_err (ic_err)
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
        .i_err_err   (err_err)
    );

    wb_mac_accel u_mac (
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
        .o_irq    ()
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

endmodule
