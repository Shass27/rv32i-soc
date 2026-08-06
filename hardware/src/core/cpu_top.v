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
    wire        MemRead;
    wire        MemWrite;
    wire        MemToReg;
    wire        branch;
    wire        jump;
    wire [1:0]  ALUOp;

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
    wire [31:0] alu_B;
    wire [31:0] ALU_result;
    wire        ALU_zero;

    // --- Branch / Jump ---
    wire        branch_taken;
    wire [31:0] branch_target;
    wire [31:0] jump_target;
    wire [31:0] jump_ret_addr;

    // --- MEM/WB ---
    wire [31:0] mem_rdata;
    wire [31:0] wb_data;

    // --- Muxed signals ---
    wire [31:0] target;        // final target for PC
    wire [31:0] final_wb_data;    // final data written to register file

    //  Target MUX — select between branch and jump targets
    // =========================================================
    //  Priority: jump takes precedence over branch
    assign target = jump ? jump_target : branch_target;

    // =========================================================
    //  Writeback MUX — JAL writes pc+4, everything else writes
    //  the normal wb_data path
    // =========================================================
    assign final_wb_data = jump ? jump_ret_addr : wb_data;

    // =========================================================
    //  IF STAGE
    // =========================================================
    program_counter u_pc (
        .clk          (clk),
        .reset        (reset),
        .stall        (1'b0),           // no stall logic yet
        .branch_taken (branch_taken),
        .jump         (jump),
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
        .MemRead  (MemRead),
        .MemWrite (MemWrite),
        .MemToReg (MemToReg),
        .branch   (branch),
        .jump     (jump),
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
        .WriteData (final_wb_data),
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
        .A          (rs1_data),
        .B          (alu_B),
        .ALUControl (ALUControl),
        .ALU_result (ALU_result),
        .ALU_zero   (ALU_zero)
    );

    // =========================================================
    //  BRANCH / JUMP LOGIC
    // =========================================================
    branch_logic u_branch (
        .branch       (branch),
        .alu_zero     (ALU_zero),
        .pc           (pc),
        .imm          (imm),
        .branch_taken (branch_taken),
        .target       (branch_target)   // drives branch_target, NOT target directly
    );

    jump_logic u_jump (
        .jump          (jump),
        .pc            (pc),
        .imm           (imm),
        .target        (jump_target),   // drives jump_target, NOT target directly
        .jump_ret_addr (jump_ret_addr)
    );

    // =========================================================
    //  MEM / WB STAGE
    // =========================================================
    mem_stage u_mem (
        .clk       (clk),
        .MemRead   (MemRead),
        .MemWrite  (MemWrite),
        .MemToReg  (MemToReg),
        .alu_result(ALU_result), //NOTE: variable name changed from ALU_result to alu_result
        .rs2_data  (rs2_data),
        .mem_rdata (mem_rdata),
        .wb_data   (wb_data)
    );

endmodule
