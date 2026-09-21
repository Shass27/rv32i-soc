# RV32I SoC

A single-cycle RISC-V RV32I CPU implemented in Verilog. The processor executes one instruction per clock cycle with a classic five-stage datapath — **Fetch → Decode → Execute → Memory → Writeback** — wired combinationally in a single cycle. The design is fully simulatable with [Icarus Verilog](https://steveicarus.github.io/iverilog/) and includes a self-checking testbench that verifies arithmetic, memory, branch, and jump operations.

## Table of Contents

- [Repository Structure](#repository-structure)
- [CPU Datapath](#cpu-datapath)
- [Supported Instructions](#supported-instructions)
- [Waveform Output](#waveform-output)
- [Setup](#setup)
- [Compile & Run](#compile--run)
- [License](#license)

## Repository Structure

```
rv32i-soc/
├── README.md
├── LICENSE
├── build/                             # Generated simulation outputs
├── documentation/
│   ├── RV32I_Processor_Control_Signals.md
│   ├── data_path.png
│   └── waveform.png
├── hardware/
│   ├── src/
│   │   └── core/
│   │       ├── cpu_top.v              # Top-level single-cycle CPU
│   │       ├── if/
│   │       │   ├── inst_mem.v         # Instruction memory, reads program.hex
│   │       │   ├── program_counter.v  # PC update logic with branch/jump support
│   │       │   └── program.hex       # Program image for the CPU testbench
│   │       ├── id/
│   │       │   ├── branch.v           # Branch condition and target generation
│   │       │   ├── control_unit.v     # Opcode decode and control signals
│   │       │   ├── immediate_gen.v    # Sign-/zero-extended immediate generation
│   │       │   └── jump.v             # JAL / JALR target logic
│   │       ├── ex/
│   │       │   ├── alu_control.v      # Decodes ALU op, funct3/funct7 and register fields
│   │       │   ├── alu_module.v       # Arithmetic / logical ALU implementation
│   │       │   ├── alu_src_mux.v      # Selects rs2_data or immediate for ALU input B
│   │       │   └── reg_file.v         # 32 x 32 register file
│   │       ├── mem/
│   │       │   ├── data.hex           # Initial data memory contents
│   │       │   └── data_memory.v      # Memory read/write implementation
│   │       └── wb/
│   │           └── writeback_mux.v    # Selects ALU result, memory data, or return address
│   └── test_bench/
│       ├── tb_cpu_top.v               # Top-level self-checking RTL testbench
│       └── stage/
│           ├── ex/
│           ├── id/
│           ├── if/
│           ├── mem/
│           └── wb/
└──
```

## CPU Datapath

<!-- Add your CPU datapath diagram here -->
![CPU Datapath](documentation/data_path.png)

## Supported Instructions

The current RTL implements a RV32I-style integer core with the following instruction groups:

| Type | Instructions |
|------|-------------|
| **R-type** | `ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLL`, `SRL`, `SRA`, `SLT`, `SLTU` |
| **I-type ALU** | `ADDI`, `ANDI`, `ORI`, `XORI`, `SLLI`, `SRLI`, `SRAI`, `SLTI`, `SLTIU` |
| **Load** | `LB`, `LH`, `LW`, `LBU`, `LHU` |
| **Store** | `SB`, `SH`, `SW` |
| **Branch** | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| **Jump / link** | `JAL`, `JALR` |
| **U-type** | `LUI`, `AUIPC` |

This matches the control decode and ALU handling implemented in `control_unit.v`, `alu_control.v`, and `jump.v`.

## Waveform Output

The self-checking testbench [`tb_cpu_top.v`](hardware/test_bench/tb_cpu_top.v) runs a small program that exercises all supported instruction types — including arithmetic, load/store, branching, and jumping — and verifies correct execution at each cycle.

The waveform below shows the simulation output captured from the `.vcd` dump:

![Waveform Output](documentation/waveform.png)

Refer to [Processor_Control_Signals](documentation/RV32I_Processor_Control_Signals.md) for explanation of what these signals mean.

## Setup

### Prerequisites

1. **Icarus Verilog** — open-source Verilog simulation and synthesis tool.

   Download and install from the official site: [https://steveicarus.github.io/iverilog/](https://steveicarus.github.io/iverilog/)

   Or install via a package manager:

   ```bash
   # macOS (Homebrew)
   brew install icarus-verilog

   # Ubuntu / Debian
   sudo apt install iverilog

   # Arch Linux
   sudo pacman -S iverilog
   ```

2. **Waveform Viewer** — to inspect `.vcd` signal dumps.

   Install any waveform viewer that supports VCD files. Recommended options:

   - [GTKWave](https://gtkwave.github.io/gtkwave/) — classic, widely-used VCD viewer
   - [Surfer](https://surfer-project.org/) — modern, fast waveform viewer

## Compile & Run

All commands are run from the repository root using `make`.

### 1. Compile & Execute

To compile the RTL sources and run the simulation in one step:

```bash
make run
```
Or simply:
```bash
make
```

When successful, a run will output:

```text
Compilation successful!
Running simulation...
...
```

This generates `cpu_top.vcd` in the working directory when the simulation completes successfully.

### 2. Compile Only

To just compile the design without running the simulation:

```bash
make compile
```

### 3. Clean Workspace

To remove build artifacts and waveform files:

```bash
make clean
```

### 4. View Waveform

Once a successful simulation has run and generated `cpu_top.vcd`, you can view it:

```bash
# GTKWave
gtkwave cpu_top.vcd

# Surfer
surfer cpu_top.vcd
```

# RV32I SoC — Verification

The processor implements **37 RV32I instructions** and all 37 were verified
using the corresponding official `riscv-tests/isa/rv32ui` programs.

**Result: 37/37 PASS**

See `documentation/VERIFICATION.md` for the detailed verification report.

---

## Reproduce an Official RISC-V Test

The commands below are intended to be copied directly into the **VS Code
PowerShell terminal**. Each code block has GitHub's copy button.

### 1. Set paths and select a test

Change only the paths and `$TEST` for your machine.

```powershell
$CPU_REPO  = "D:\VS code\rv32i-soc"
$TEST_REPO = "D:\VS code\riscv-tests"
$RISCV_BIN = "C:\SysGCC\risc-v\bin"

$GCC      = "$RISCV_BIN\riscv64-unknown-elf-gcc.exe"
$OBJCOPY  = "$RISCV_BIN\riscv64-unknown-elf-objcopy.exe"
$IVERILOG = "C:\iverilog\bin\iverilog.exe"
$VVP      = "C:\iverilog\bin\vvp.exe"

$TEST = "sw"
```

Available tests are the official files in:

```powershell
Get-ChildItem "$TEST_REPO\isa\rv32ui\*.S" | Select-Object -ExpandProperty BaseName
```

### 2. Generate the instruction HEX

```powershell
cd $TEST_REPO

& $GCC -march=rv32i -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -I".\env\cpu" -I".\isa\macros\scalar" -T".\env\p\link_cpu.ld" ".\isa\rv32ui\$TEST.S" -o ".\${TEST}_cpu.elf"

& $OBJCOPY --remove-section .tohost ".\${TEST}_cpu.elf" ".\${TEST}_cpu_clean.elf"

& $OBJCOPY --remove-section .riscv.attributes -O verilog --verilog-data-width=4 --reverse-bytes=4 ".\${TEST}_cpu_clean.elf" ".\${TEST}_code.hex"

Copy-Item ".\${TEST}_code.hex" "$CPU_REPO\hardware\src\core\if\program.hex" -Force
```

### 3. For load/store tests, generate the data HEX

Use this block only for:

`lb lh lw lbu lhu sb sh sw`

```powershell
$MEM_TESTS = @("lb","lh","lw","lbu","lhu","sb","sh","sw")

if ($MEM_TESTS -contains $TEST) {
    & $OBJCOPY -j .data -O verilog --verilog-data-width=4 --reverse-bytes=4 ".\${TEST}_cpu_clean.elf" ".\${TEST}_data.hex"

    (Get-Content ".\${TEST}_data.hex") -replace '^@00002000$', '@00000800' | Set-Content ".\${TEST}_data_cpu.hex"

    Copy-Item "$CPU_REPO\hardware\src\core\mem\data.hex" "$CPU_REPO\hardware\src\core\mem\data_backup_before_${TEST}.hex" -Force

    Copy-Item ".\${TEST}_data_cpu.hex" "$CPU_REPO\hardware\src\core\mem\data.hex" -Force
}
```

### 4. Compile the CPU

```powershell
cd $CPU_REPO

& $IVERILOG -o ".\cpu_debug_sim" -s tb_debug -g2012 (Get-ChildItem -Path ".\hardware\src" -Recurse -Filter *.v | ForEach-Object { $_.FullName }) ".\hardware\test_bench\tb_debug.v"
```

### 5. Run the test

```powershell
& $VVP ".\cpu_debug_sim"
```

Expected result:

```text
TOHOST: PASS (tohost=0x00000001)
```

### 6. Save the simulation log

```powershell
& $VVP ".\cpu_debug_sim" | Tee-Object "$CPU_REPO\build\${TEST}_pass.txt"
```

---

## Verification Flow

```text
Official .S
   ↓
RISC-V GCC
   ↓
ELF
   ↓
objcopy
   ↓
Verilog HEX
   ↓
program.hex / data.hex
   ↓
CPU RTL
   ↓
Icarus Verilog
   ↓
TOHOST PASS/FAIL
```

## Verified Instruction Set

```text
ADD SUB AND OR XOR SLL SRL SRA SLT SLTU
ADDI ANDI ORI XORI SLLI SRLI SRAI SLTI SLTIU
LB LH LW LBU LHU SB SH SW
BEQ BNE BLT BGE BLTU BGEU JAL JALR
LUI AUIPC
```

**37/37 implemented RV32I instructions passed their corresponding official
`rv32ui` tests.**


## License

This project is licensed under the [MIT License](LICENSE).
