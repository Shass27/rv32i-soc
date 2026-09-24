# RV32I SoC

A single-cycle RISC-V RV32I core in Verilog, extended into a small SoC: a Wishbone B4 Classic bus, a MAC accelerator, and an error slave. The core executes one instruction per clock cycle (**Fetch → Decode → Execute → Memory → Writeback**, wired combinationally) and stalls only on bus (IO) accesses. Simulated with [Icarus Verilog](https://steveicarus.github.io/iverilog/); a self-checking SoC testbench verifies the demo program and a MAC dot-product, and the core passes all 37 official `rv32ui` tests.

## Table of Contents

- [Repository Structure](#repository-structure)
- [CPU Datapath](#cpu-datapath)
- [Supported Instructions](#supported-instructions)
- [Wishbone Bus](#wishbone-bus)
- [MAC Accelerator](#mac-accelerator)
- [Waveform Output](#waveform-output)
- [Setup](#setup)
- [Compile & Run](#compile--run)
- [Verification](#verification)
- [License](#license)

## Repository Structure

```
rv32i-soc/
├── README.md
├── LICENSE
├── Makefile                           # Currently broken, see Compile & Run
├── build/                             # Generated simulation outputs (gitignored)
├── documentation/
│   ├── RV32I_Processor_Control_Signals.md
│   ├── data_path.png
│   ├── waveform.png
│   └── riscv-tests/
│       ├── VERIFICATION.md            # Official rv32ui verification report
│       └── REPRODUCING.md             # Re-run any single official test
└── hardware/
    ├── src/
    │   ├── bus/
    │   │   ├── wb_defs.vh             # Address-map / bus macros
    │   │   ├── wb_master.v            # CPU-side Wishbone master
    │   │   ├── wb_interconnect.v      # Address decode + slave mux
    │   │   ├── wb_mac_accel.v         # MAC accelerator slave
    │   │   ├── wb_err.v               # Catch-all error slave
    │   │   └── wb_ram.v               # Testbench-only RAM slave
    │   └── core/
    │       ├── cpu_top_wb.v           # SoC top: core + bus + peripherals
    │       ├── if/
    │       │   ├── inst_mem.v         # Instruction memory (PROG_FILE parameter)
    │       │   ├── program_counter.v  # PC update logic with branch/jump support
    │       │   ├── program.hex        # 56-word demo program
    │       │   └── program2.hex       # Official rv32ui image
    │       ├── id/
    │       │   ├── branch.v           # Branch condition and target generation
    │       │   ├── control_unit.v     # Opcode decode and control signals
    │       │   ├── immediate_gen.v    # Immediate generation
    │       │   └── jump.v             # JAL / JALR target logic
    │       ├── ex/
    │       │   ├── alu_control.v      # Decodes ALU op, funct3/funct7
    │       │   ├── alu_module.v       # Arithmetic / logical ALU
    │       │   ├── alu_src_mux.v      # Selects rs2_data or immediate for ALU input B
    │       │   └── reg_file.v         # 32 x 32 register file
    │       ├── mem/
    │       │   ├── data.hex           # Zero-initialised data memory
    │       │   └── data_memory.v      # Local data memory
    │       └── wb/
    │           └── writeback_mux.v    # Selects ALU result, memory data, or return address
    └── test_bench/
        ├── tb_cpu_top_wb.v            # Self-checking SoC testbench
        ├── rv32i_asm.vh               # Tiny RV32I assembler functions
        ├── dma_driver.vh              # DMA-based driver: copies vectors into MAC, computes dot product
        ├── bus/
        │   ├── tb_wb_ram.v
        │   ├── tb_wb_master.v
        │   ├── tb_wb_integ.v
        │   ├── tb_wb_mac_accel.v
        │   └── tb_wb_data.hex
        └── stage/                     # Per-stage unit testbenches (ex, id, if, mem, wb)
```

## CPU Datapath

![CPU Datapath](documentation/data_path.png)

The diagram shows the core only and predates the bus.

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

## Wishbone Bus

Top level is [`cpu_top_wb.v`](hardware/src/core/cpu_top_wb.v) (module `cpu_top_wb`, ports `clk`, `reset`). It instantiates `wb_master` (`u_wb_master`), `wb_interconnect` (`u_wb_ic`), `wb_mac_accel` (`u_mac`) and `wb_err` (`u_wb_err`).

```
                      ┌────────────┐   ┌───────────────┐   ┌──────────────┐
  RV32I core ───────► │ wb_master  │──►│ wb_interconn. │──►│ wb_mac_accel │
 (ALU_result, store   └────────────┘   │               │   └──────────────┘
  data, io_sel)                        │               │   ┌──────────────┐
                                       │               │──►│   wb_err     │
  local data_memory (0x0000_0000-      └───────────────┘   └──────────────┘
  0x0000_FFFF), used when io_sel=0
```

**Flavour:** Wishbone Classic, non-pipelined, zero wait-state (`ACK` is combinational, `cyc & stb`), word-only. There is no `SEL`, so `SB`/`SH` to IO space write a full word. Signals: `CYC`, `STB`, `WE`, `ADR`, `DAT` (master to slave); `ACK`, `ERR`, `DAT` (slave to master). `ADDR_WIDTH = DATA_WIDTH = 32`. `wb_master` runs an effective IDLE → ACTIVE → IDLE FSM.

<details>
<summary><b>IO split</b></summary>

Local `data_memory` owns `0x0000_0000`-`0x0000_FFFF`. A load/store goes to the bus when `(MemRead | MemWrite) & ALU_result[31:16] != 0`:

| Signal | Definition |
|--------|-----------|
| `io_sel` | Access targets the bus |
| `wb_req` | `io_sel & ~wb_busy & ~wb_done` |
| `stall` | `io_sel & ~wb_done` (freezes the PC) |
| `RegWrite_gated` | `RegWrite & ~stall` |
| `mem_rdata` | `io_sel ? wb_rdat : mem_rdata_local` |

A bus store takes 3 core cycles; a local load takes 1.

</details>

<details>
<summary><b>Address map (decoded in `wb_interconnect.v`)</b></summary>

| Slave | Select | Range | Notes |
|-------|--------|-------|-------|
| `wb_ram` | `adr[31:10] == 0` | `0x0000_0000`-`0x0000_03FF` (1 KB) | **Not instantiated in the SoC**; RAM port is stubbed. Local `data_memory` handles this range |
| `wb_mac_accel` | `adr[31:16] == 16'h1000` | `0x1000_0000`-`0x1000_FFFF` (64 KB) | See below |
| `wb_dma` | `adr[31:16] == 16'h2000` | `0x2000_0000`-`0x2000_00FF` (5 regs) | DMA register page; CPU stalls while DMA owns the bus |
| `wb_err` | catch-all (`~sel_ram & ~sel_mac & ~sel_dma`) | everything else | Always `ERR`, never `ACK`, reads 0 |

Bus errors are observed, not trapped: `wb_err_flag` is observation-only and there is no trap. `o_irq` of the MAC is tied off.

</details>

## MAC Accelerator

[`wb_mac_accel.v`](hardware/src/bus/wb_mac_accel.v) computes `acc += SUM(A[i] * B[i])`, signed 32x32 to 64-bit, one element per clock. Params: `ADDR_WIDTH=16`, `DATA_WIDTH=32`, `BUF_AW=12` (4096-word buffers). `DONE` appears `LEN + 2` posedges after the `START` write.

<details>
<summary><b>Register map</b></summary>

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| `0x1000_0000` (+`0x0000`-`0x3FFF`) | `BUF_A` | R/W | 4096 words |
| `0x1000_4000` (+`0x4000`-`0x7FFF`) | `BUF_B` | R/W | 4096 words |
| `0x1000_8000` | `CTRL` | W | bit0 `START` (self-clearing; ignored if busy or `LEN == 0`), bit1 `CLR_ACC` (self-clearing) |
| `0x1000_8004` | `STATUS` | R/W1C | bit0 `BUSY` (RO), bit1 `DONE` (sticky, write 1 to clear) |
| `0x1000_8008` | `LEN` | R/W | Element count, clamps to 4096, ignored while busy |
| `0x1000_800C` | `ACC_LO` | R/W | Accumulator [31:0], writes ignored while busy |
| `0x1000_8010` | `ACC_HI` | R/W | Accumulator [63:32], writes ignored while busy |

Registers at `0x1000_8000`+ alias every 32 bytes. The accumulator is **not** auto-cleared between runs.

</details>

**Sequence:** `CLR_ACC` → fill `BUF_A` / `BUF_B` → write `LEN` → `START` → poll `STATUS.DONE` → read `ACC_LO` / `ACC_HI` → write `STATUS = 2` to clear `DONE`.

**Performance:** roughly 8x faster than a software MAC loop. The bottleneck is the CPU feeding the accelerator over the bus, not the MAC computing.

<details>
<summary>How the ~8x is derived</summary>

Estimate from the cycle budget, not a simulator-measured benchmark.

| Operation | Cycles |
|-----------|--------|
| LW from local RAM | 1 |
| SW to MAC over bus | 3 |
| Per element (2 loads + 2 stores) | ~12 |
| MAC compute | 1 |
| Fixed overhead | ~20 |

Net: ~13N + 20 cycles with the accelerator vs ~106N in software (RV32I has no `M` extension, so each multiply is a shift-add routine) => roughly 8x for large N.

</details>

## Waveform Output

The self-checking testbench [`tb_cpu_top_wb.v`](hardware/test_bench/tb_cpu_top_wb.v) checks the 56-instruction demo program cycle by cycle, then runs a DMA driver at `0xE0` that copies vectors into the MAC over the DMA controller and computes `dot([1,2,3,4],[5,6,7,8]) = 70`, printing `PASS: all checks passed`. It writes `cpu_top_wb.vcd` in the repo root (the working directory).

The waveform below was captured from `tb_cpu_top_wb.v`:

![Waveform Output](documentation/waveform.png)

Refer to [Processor_Control_Signals](documentation/RV32I_Processor_Control_Signals.md) for explanation of what these signals mean.

## Setup

<details>
<summary><b>Prerequisites</b></summary>

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

</details>

## Compile & Run

All commands are run from the repository root.

### 1. Compile & Execute

```bash
make run
```

This builds the SoC with [`tb_cpu_top_wb.v`](hardware/test_bench/tb_cpu_top_wb.v), simulates it, and exits non-zero if any check fails (`vvp` itself always exits 0, so the Makefile scans the log for `FAIL`). A successful run ends with:

```text
VCD info: dumpfile cpu_top_wb.vcd opened for output.
PASS: all checks passed
```

`$readmemh` "Not enough words" warnings are expected. The waveform is written to `cpu_top_wb.vcd` in the repo root, and the log to `build/cpu_tb.log`.

<details>
<summary><b>Compile by hand</b></summary>

To compile by hand instead:

```bash
mkdir -p build
iverilog -I hardware/src/bus -I hardware/test_bench -o build/cpu_tb.out \
  $(find hardware/src -name '*.v' ! -name 'wb_ram.v') \
  hardware/test_bench/tb_cpu_top_wb.v && vvp build/cpu_tb.out
```

</details>

<details>
<summary><b>Makefile targets</b></summary>

```bash
make run      # compile + simulate the SoC testbench, fail on any FAIL
make compile  # compile only, build/cpu_tb.out
make bus      # run all four bus testbenches, stop at the first failure
make clean    # remove build artifacts and *.vcd
```

</details>

<details>
<summary><b>Bus testbenches</b></summary>

`make bus` runs `tb_wb_ram`, `tb_wb_master`, `tb_wb_integ` and `tb_wb_mac_accel` in turn; each prints PASS/FAIL counts. To run one by hand (MAC accelerator shown; `-I hardware/src/bus` is needed by every bench that includes `wb_defs.vh`):

```bash
iverilog -I hardware/src/bus -o /tmp/tb_mac.out hardware/src/bus/wb_mac_accel.v hardware/test_bench/bus/tb_wb_mac_accel.v && vvp /tmp/tb_mac.out
```

</details>

<details>
<summary><b>View Waveform</b></summary>

Once a successful simulation has generated `cpu_top_wb.vcd`:

```bash
# GTKWave
gtkwave cpu_top_wb.vcd

# Surfer
surfer cpu_top_wb.vcd
```

</details>

## Verification

**37/37 PASS** on the official `riscv-tests` `rv32ui` suite. The suite image is `hardware/src/core/if/program2.hex`; select it with `inst_mem #(.PROG_FILE("..."))`.

- [`documentation/riscv-tests/VERIFICATION.md`](documentation/riscv-tests/VERIFICATION.md) — the report: scope, methodology, the 37-row result matrix, and six waveform walkthroughs.
- [`documentation/riscv-tests/REPRODUCING.md`](documentation/riscv-tests/REPRODUCING.md) — how to rebuild and re-run any single official test (PowerShell and bash).

## License

This project is licensed under the [MIT License](LICENSE).
