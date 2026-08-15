module cpu_top (
    input wire clk,
    input wire reset
);

    // =========================================================
    //  Internal wires
    // =========================================================

    // --- IF stage ---
    wire [31:0] pc;
    wire [31:0] instr;

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
    wire [31:0] mem_rdata;
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
        .RegWrite  (RegWrite),
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
    data_memory u_mem (
        .clk       (clk),
        .MemRead   (MemRead),
        .MemWrite  (MemWrite),
        .mem_addr  (ALU_result),
        .rs2_data  (rs2_data),
        .funct3    (funct3),
        .mem_rdata (mem_rdata)
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
