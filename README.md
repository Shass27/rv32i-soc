# RV32I SoC

A single-cycle RISC-V RV32I core in Verilog, extended into a small SoC: a Wishbone B4 Classic bus, a 4x4 matrix-multiply (MAC) accelerator, a merge-sort accelerator, a binary-search accelerator, a DMA controller, and an error slave. The core executes one instruction per clock cycle (**Fetch → Decode → Execute → Memory → Writeback**, wired combinationally) and stalls only on bus (IO) accesses and while the DMA is copying. Simulated with [Icarus Verilog](https://steveicarus.github.io/iverilog/); self-checking benches cover each accelerator, and the core passes all 37 official `rv32ui` tests.

## Table of Contents

- [Repository Structure](#repository-structure)
- [CPU Datapath](#cpu-datapath)
- [Supported Instructions](#supported-instructions)
- [Wishbone Bus](#wishbone-bus)
- [Accelerators and Analysis](#accelerators-and-analysis)
- [DMA Controller](#dma-controller)
- [Setup](#setup)
- [Compile & Run](#compile--run)
- [Verification](#verification)
- [Known issues](#known-issues)
- [License](#license)

## Repository Structure

```
rv32i-soc/
├── README.md
├── LICENSE
├── Makefile                           # make run / sort / compile / bus / clean
├── program_sort.hex                   # 10-word driver for tb_cpu_top_wb_sort.v
├── build/                             # Generated simulation outputs (gitignored)
├── documentation/
│   ├── RV32I_Processor_Control_Signals.md
│   ├── data_path.png
│   └── riscv-tests/
│       ├── VERIFICATION.md            # Official rv32ui verification report
│       └── REPRODUCING.md             # Re-run any single official test
└── hardware/
    ├── src/
    │   ├── bus/
    │   │   ├── wb_defs.vh             # Address-map / bus macros
    │   │   ├── wb_master.v            # CPU-side Wishbone master
    │   │   ├── wb_interconnect.v      # Address decode + slave mux
    │   │   ├── wb_mac_accel.v         # 4x4 systolic matrix-multiply (MAC) slave
    │   │   ├── wb_dma.v               # DMA controller (slave registers + bus master)
    │   │   ├── wb_sort.v              # Merge-sort accelerator (slave registers + data_memory port B)
│   │   ├── wb_search_accel.v      # Binary-search accelerator (array + registers in the slave)
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
    │       │   ├── data_memory.v      # Local data memory (dual-port: A = CPU, B = DMA / SORT)
    │       │   └── matrix_memory.v    # Write-only matrix window feeding the MAC with 256-bit tiles
    │       └── wb/
    │           └── writeback_mux.v    # Selects ALU result, memory data, or return address
    └── test_bench/
        ├── tb_cpu_top_wb_mac.v        # Self-checking SoC testbench (CPU + matrix MAC + DMA), make run
        ├── tb_cpu_top_wb_sort.v       # Self-checking SoC testbench (SORT), make sort
        ├── tb_cpu_search.v            # CPU-driven SEARCH bench (one search)
        ├── tb_cpu_search_multi.v      # CPU-driven SEARCH bench (several searches; same module name)
        ├── rv32i_asm.vh               # Tiny RV32I assembler functions
        ├── mac_driver.vh              # Used by make run: CPU fills the matrix window, runs the MAC, DMA copies C to RAM
        ├── bus/
        │   ├── tb_wb_ram.v
        │   ├── tb_wb_master.v
        │   ├── tb_wb_integ.v
        │   ├── tb_wb_mac_accel.v
        │   ├── tb_wb_dma.v
        │   ├── tb_wb_sort.v
        │   ├── tb_wb_search_accel.v
        │   ├── tb_wb_search_integration.v
        │   └── tb_wb_data.hex
        └── stage/                     # Per-stage unit testbenches (ex, id, if, mem, wb)
            └── mem/tb_dp_mem.v        # Dual-port data_memory testbench
```

## SoC Datapath

![SoC Datapath](documentation/data_path.png)

The diagram shows the RISC V core, Wishbone bus, DMA integrations and Slaves.

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

Top level is [`cpu_top_wb.v`](hardware/src/core/cpu_top_wb.v) (module `cpu_top_wb`, ports `clk`, `reset`). It instantiates `wb_master` (`u_wb_master`), `wb_interconnect` (`u_wb_ic`), `wb_mac_accel` (`u_mac`), `wb_dma` (`u_dma`), `wb_sort` (`u_sort`), `wb_search_accel` (`u_search`), `wb_err` (`u_wb_err`) and the core-local `matrix_mem` (`u_matmem`). It also exposes a `debug_pc` output (the current `pc`).

```
                  ┌────────────┐   ┌───────┐   ┌───────────────┐   ┌──────────────┐
  RV32I core ───► │ wb_master  │──►│  2:1  │──►│ wb_interconn. │──►│ wb_mac_accel │  0x1000_xxxx
  (io_sel=1)      └────────────┘   │  mux  │   │               │   └──────────────┘
                  ┌────────────┐   │       │   │               │   ┌──────────────┐
                  │ wb_dma     │──►│       │   │               │──►│ wb_dma regs  │  0x2000_xxxx
                  │ (master)   │   └───▲───┘   │               │   └──────────────┘
                  └─────┬──────┘       │       │               │   ┌──────────────┐
                        │ port B    dma_busy   │               │──►│  wb_sort     │  0x3000_xxxx
                        │              │       │               │   └──────┬───────┘
                        │              │       │               │   ┌──────┼───────┐
                        │              │       │               │──►│ wb_search    │  0x5000_xxxx
                        │              │       │               │   └──────┼───────┘
                        │              │       │               │   ┌──────┼───────┐
                        │              │       └───────────────┘──►│   wb_err     │  everything else
                        ▼              ▼                           └──────┼───────┘
  RV32I core ───► data_memory (dual-port, 0x0000_0000-0x0000_FFFF) ◄──────┘ sort (port B, idle-DMA only)
  (io_sel=0)  port A
  RV32I core ───► matrix_mem (0x4000_0000, write-only `sw` window, mat_sel) ──► wb_mac_accel (256-bit tile)
```

`u_dma` appears twice: as a slave (its register page) and as a second bus master. The 2:1 mux hands the bus to the DMA while `dma_busy` is high; `ACK`/`ERR` go only to the current owner, read data goes to both. `u_matmem` is not on the bus: the core writes it directly and `wb_mac_accel` reads it through its tile port. `u_sort` is a plain slave on the bus but reaches `data_memory` through port B, which it shares with the DMA: while `dma_busy` is high the DMA owns port B and the sorter pauses (`sort_mem_grant = ~dma_busy`).

**Flavour:** Wishbone Classic, non-pipelined, zero wait-state (`ACK` is combinational, `cyc & stb`), word-only. There is no `SEL`, so `SB`/`SH` to IO space write a full word. Signals: `CYC`, `STB`, `WE`, `ADR`, `DAT` (master to slave); `ACK`, `ERR`, `DAT` (slave to master). `ADDR_WIDTH = DATA_WIDTH = 32`. `wb_master` runs an effective IDLE → ACTIVE → IDLE FSM.

<details>
<summary><b>IO split</b></summary>

Local `data_memory` owns `0x0000_0000`-`0x0000_FFFF`. The matrix window (`MAT_BASE = 0x4000_0000`, 8 KB for `MAT_K_MAX = 256`) is also core-local. A load/store goes to the bus when `(MemRead | MemWrite) & ALU_result[31:16] != 0 & ~mat_sel`:

| Signal | Definition |
|--------|-----------|
| `mat_sel` | Access falls inside the matrix window: single-cycle, never on the bus |
| `mat_we` | `MemWrite & mat_sel & (funct3 == SW) & ~dma_busy`; `SB`/`SH` to the window are ignored |
| `io_sel` | Access targets the bus |
| `dma_busy` | DMA is copying: it owns the bus and the CPU is frozen |
| `wb_req` | `io_sel & ~wb_busy & ~wb_done & ~dma_busy` |
| `stall` | `~wb_done & (io_sel \| dma_busy)` (freezes the PC) |
| Port A write | `MemWrite & ~io_sel & ~dma_busy` (a frozen `SW` cannot collide with DMA port B) |
| `RegWrite_gated` | `RegWrite & ~stall` |
| `mem_rdata` | `io_sel ? wb_rdat : mat_sel ? 0 : mem_rdata_local` (the window is write-only, loads read 0) |

A bus store takes 3 core cycles (4 to `wb_sort`, whose `ACK` is registered); a local load or a matrix-window store takes 1.

</details>

<details>
<summary><b>Address map (decoded in `wb_interconnect.v`)</b></summary>

| Slave | Select | Range | Notes |
|-------|--------|-------|-------|
| `wb_ram` | `adr[31:10] == 0` | `0x0000_0000`-`0x0000_03FF` (1 KB) | **Not instantiated in the SoC**; RAM port is stubbed. Local `data_memory` handles this range |
| `wb_mac_accel` | `adr[31:16] == 16'h1000` | `0x1000_0000`-`0x1000_FFFF` (64 KB) | Result window + 4 registers; see [Accelerators and Analysis](#accelerators-and-analysis) |
| `wb_dma` | `adr[31:16] == 16'h2000` | `0x2000_0000`-`0x2000_FFFF` (64 KB) | DMA register page, aliased every 32 B; see [DMA Controller](#dma-controller) |
| `wb_sort` | `adr[31:16] == 16'h3000` | `0x3000_0000`-`0x3000_FFFF` (64 KB) | Sort register page, decoded on `adr[5:2]` (aliased every 64 B); see [Accelerators and Analysis](#accelerators-and-analysis) |
| `wb_search_accel` | `adr[31:16] == 16'h5000` | `0x5000_0000`-`0x5000_FFFF` (64 KB) | 32 KB array + registers; see [Accelerators and Analysis](#accelerators-and-analysis) |
| `wb_err` | catch-all (`~sel_ram & ~sel_mac & ~sel_dma & ~sel_sort & ~sel_search`) | everything else | Always `ERR`, never `ACK`, reads 0 |

`0x4000_0000` is not a bus slave (it is the core-local matrix window), so a DMA transfer aimed at it goes to `wb_err`. Bus errors are observed, not trapped: `wb_err_flag` is observation-only and there is no trap. `o_irq` of the MAC is tied off.

</details>

## Accelerators and Analysis

Three accelerators offload work from the CPU. Expand each for its register map, usage sequence and performance. Cycle totals marked *simulated* come from a testbench; those marked *derived* or *estimate* come from the RTL or hand calculation and were not measured.

<details>
<summary><b>MAC Accelerator (4x4 matrix multiply)</b></summary>

[`wb_mac_accel.v`](hardware/src/bus/wb_mac_accel.v) computes `C = A(4xK) * B(Kx4)`: signed 32-bit inputs, signed 64-bit outputs, on a 4x4 output-stationary systolic array of 16 multiply-accumulate PEs. One K step (a 4x4 outer product, 16 MACs) is issued per clock. Params: `K_MAX = 256`, `MEM_LAT = 0` (combinational tile read, `1` = registered), `MULT_PIPE = 0` (`1` registers the product, +1 cycle). The operands come from the core-local [`matrix_memory.v`](hardware/src/core/mem/matrix_memory.v), not over the bus, so the slave only holds the result and control registers.

**Matrix window:** software fills `matrix_mem` with ordinary `sw` stores to `MAT_BASE = 0x4000_0000` (8 KB for `K_MAX = 256`), laid out like C arrays: `int32_t A[4][K_MAX]` at word offset 0 (row pitch `K_MAX`), `int32_t B[K_MAX][4]` at word offset `4*K_MAX`. Only the first `K` columns of A and `K` rows of B are used. The window is write-only (loads read 0, `SB`/`SH` are ignored), takes 1 cycle per store, and is not on the bus, so the DMA cannot fill it.

<details>
<summary><b>Register map</b></summary>

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| `0x1000_0000`-`0x1000_007C` | `C[r][c]` | R | 16 results, word `2*(4r+c)` = low 32 bits, word `2*(4r+c)+1` = high 32 bits; writes ignored |
| `0x1000_8000` | `DATA_BASE` | R/W | Byte address of tile 0; low 5 bits forced to 0; write ignored while busy. Set it to `MAT_BASE` |
| `0x1000_8004` | `K` | R/W | Inner dimension `1..K_MAX`, larger values clamp; write ignored while busy |
| `0x1000_8008` | `CTRL` | W | bit0 `START` (ignored if busy or `K == 0`), bit1 `CLEAR_RESULTS` (zeroes `C` and clears `DONE`); reads 0 |
| `0x1000_800C` | `STATUS` | R/W1C | bit0 `BUSY` (RO), bit1 `DONE` (sticky, write 1 to clear) |

Registers are selected by `offset[3:2]` within `0x8000`-`0x800F`; other offsets read 0. `CTRL`/`DATA_BASE`/`K` writes are ignored while busy, but `DONE` can be cleared at any time. `C` is cleared at every `START`, so results are **not** accumulated across runs. Do not write the window while `BUSY`.

</details>

**Sequence:** fill the window with `sw` → write `DATA_BASE` (= `MAT_BASE`) → write `K` → write `CTRL = 1` → poll `STATUS.DONE` → read `C[r][c]` low/high words → write `STATUS = 2` to clear `DONE`. The CPU is **not** stalled while the array runs.

**Performance:** after `START` the slave spends one `BUSY` cycle clearing the accumulators, then `K + 6 + MEM_LAT + MULT_PIPE` run cycles (`K` tile fetches plus pipeline fill/drain through the skew registers and PEs), so `K + 7` busy cycles with the defaults. `tb_wb_mac_accel` checks the run-cycle count for every K it tries, for both `MEM_LAT`/`MULT_PIPE` = 0 and 1 (*simulated*, 72 tests each). The array does 16 MACs per cycle once full, independent of operand width; every bus access to the slave costs the CPU 3 cycles, and filling A and B costs at least `8K` store cycles on top (one `sw` each, address and data generation not counted).

<details>
<summary>Derived totals vs software estimate</summary>

Accelerator cycles are **derived** from the formula above (compute only, window fill excluded); the checked part is the `K + 6` run count.

| K | Busy cycles (`K + 7`) | MACs done | Window fill (`8K` stores, min.) |
|---|-----|-----|-----|
| 4 | 11 | 64 | 32 |
| 16 | 23 | 256 | 128 |
| 64 | 71 | 1024 | 512 |
| 256 | 263 | 4096 | 2048 |

The software baseline is an **estimate**, not measured: RV32I has no `M` extension, so each multiply is a shift-add routine whose cost depends on data width, and a 4xK by Kx4 product needs `16K` multiply-accumulates.

| Operand width | Software cycles/MAC (est.) | Software cycles for K = 64 (est.) | Speed-up vs accelerator compute (71 cycles) |
|---|---|---|---|
| Tiny, <= 4-bit | ~40 | ~41k | ~580x |
| 16-bit operands, 32-bit result | ~106 | ~109k | ~1500x |
| Full signed 32x32 -> 64 | ~339 | ~347k | ~4900x |

Including the minimum window fill (512 stores) the K = 64 totals are ~583 cycles, so the real end-to-end gain is ~70x-600x; it is large because the array performs 16 multiplies per cycle against one shift-add multiply at a time.

</details>

**Tests:** `tb_wb_mac_accel` (bus-level, 72 tests; run it alone with `iverilog -g2012 -o sim hardware/src/bus/wb_mac_accel.v hardware/test_bench/bus/tb_wb_mac_accel.v`, add `-Ptb_wb_mac_accel.MEM_LAT=1 -Ptb_wb_mac_accel.MULT_PIPE=1` for the other options; only the defaults are exercised by `make bus`), `tb_wb_dma` (the DMA drives the MAC's registers and copies its results) and `tb_cpu_top_wb_mac` (the CPU fills the window with `sw`; `make run`).

</details>

<details>
<summary><b>SORT Accelerator</b></summary>

[`wb_sort.v`](hardware/src/bus/wb_sort.v) sorts `LEN` 32-bit words into ascending order (**unsigned** compare) with a bottom-up merge sort: run width 1, 2, 4, … doubles each pass, ping-ponging between the `SRC` and `DST` buffers. If the last pass lands in `SRC` it copies the result back to `DST`, so the sorted data is always at `DST`. **`SRC` is overwritten** with intermediate runs. Both buffers are in the local `data_memory`, which the sorter reaches through port B, so addresses must be below `0x0001_0000`.

<details>
<summary><b>Register map</b></summary>

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| `0x3000_0000` | `SRC` | R/W | Source buffer byte address |
| `0x3000_0004` | `DST` | R/W | Destination buffer byte address (sorted result) |
| `0x3000_0008` | `LEN` | R/W | Word count; `0` finishes immediately, `1` copies (or does nothing if `SRC == DST`) |
| `0x3000_000C` | `CTRL` | W | bit0 `START` (one-cycle pulse; only acted on in `IDLE`) |
| `0x3000_0010` | `STATUS` | R | bit0 `BUSY`, bit1 `DONE` |

Registers are selected by `adr[5:2]`, so the page aliases every 64 bytes. Unlike the MAC and DMA, `DONE` is **not** write-1-to-clear: it stays set until the next `START`. Register writes are not blocked while busy, so do not change `SRC`/`DST`/`LEN` mid-sort.

</details>

**Sequence:** write `SRC` → `DST` → `LEN` → `START` → poll `STATUS.DONE` → read the sorted words from `DST`. The CPU is **not** stalled while sorting (unlike the DMA), so software must poll and must not touch the buffers meanwhile; a CPU store into `data_memory` in the same cycle as a sorter write wins and the sorter's write is dropped.

**DMA interaction:** if the DMA starts during a sort, the sorter holds its pending write and resumes when `dma_busy` falls (checked by `tb_wb_sort`).

**Performance:** a merge step takes 5 cycles while both runs have data (`MERGE → READ_LEFT → READ_RIGHT → WRITE_OUT → ADVANCE`) and 4 once one run is exhausted, so the sorter costs about 5.4 cycles per element per pass (`p = ⌈log2 N⌉` passes), independent of the value width. The CPU is free while it runs.

<details>
<summary>Measured totals vs software estimate</summary>

Sorter totals are **simulated** (`START` write to `DONE`, `wb_sort` driven directly on the bus with a zero-wait memory, DMA idle, in a scratch bench not in the repo). The fit is `T ≈ 5.4·N·p`, bounded above by `5·N·p + N + 2p + 5` (+ `3N` copy-back when `p` is even).

| N | Passes | Random data (cycles) | Reversed data (cycles) |
|---|---|-----|-----|
| 8 | 3 | 128 | 125 |
| 16 | 4 | 378 | 363 |
| 64 | 6 | 2114 | 1999 |
| 256 | 8 | 10967 | 10259 |

The software sort is an **estimate**, not measured: a merge loop on RV32I needs roughly 12-18 instructions per element per pass (two loads, compare, branch, store, pointer and bounds updates; 1 cycle each on this core).

| Software merge loop | Software cycles/element-pass (est.) | Speed-up vs sorter (~5.4/elem-pass) |
|---|---|---|
| Tight, hand-scheduled | ~12 | ~2.2x |
| Typical | ~15 | ~2.8x |
| Compiler output, bounds checks | ~18 | ~3.3x |

For N = 256 that is ~24.6k-36.9k software cycles against 10,967 for the sorter (the speed-up holds at ~2.0x-3.4x for all N above). The gain is modest because the sorter is a serial FSM on a single memory port, so its main benefit is freeing the CPU. Register setup (four bus stores) is not included.

</details>

**Tests:** `tb_wb_sort` (bus-level, 103 tests over many lengths and patterns, 96 with a DMA interruption; prints `ALL TESTS PASSED`) and `tb_cpu_top_wb_sort` (the CPU runs `program_sort.hex`, programs the sorter and sorts 8 words at `0x100` into `0x140`; prints `PASS: CPU-driven SORT integration test passed.`). Run it with `make sort` (not part of `make run`).

</details>

<details>
<summary><b>SEARCH Accelerator</b></summary>

[`wb_search_accel.v`](hardware/src/bus/wb_search_accel.v) runs a binary search (lower bound) for `KEY` in a sorted array of up to 8192 **signed** 32-bit words held *inside the slave* (`array_mem`, 32 KB). It finds the first element `>= KEY` and reports its index if it equals `KEY`. The array must be sorted ascending (signed) before `START`; the slave does not check. Unlike SORT it has its own array and does not use `data_memory`, so fill it with ordinary bus stores or with the DMA (any bus-to-bus or local-to-bus copy into `0x5000_0000`).

<details>
<summary><b>Register map</b></summary>

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| `0x5000_0000`-`0x5000_7FFC` | `ARRAY` | R/W | 8192 signed words; writes dropped while busy |
| `0x5000_8000` | `CTRL` | W | bit0 `START` (wins over bit1), bit1 `CLEAR` (clears `DONE` and `ERROR`); reads 0 |
| `0x5000_8004` | `STATUS` | R | bit0 `BUSY`, bit1 `DONE`, bit2 `FOUND`, bit3 `ERROR` |
| `0x5000_8008` | `LEN` | R/W | Element count `0..8192` |
| `0x5000_800C` | `KEY` | R/W | Signed search key |
| `0x5000_8010` | `RESULT` | R | Index of `KEY`, or `0xFFFF_FFFF` if not found or on error |
| `0x5000_8014` | `COMPS` | R | Comparisons performed by the last search |

Register writes are ignored while busy. `START` clears `DONE`/`FOUND`/`ERROR`, sets `RESULT = 0xFFFF_FFFF` and `COMPS = 0`. `STATUS` is read-only and `DONE` is not write-1-to-clear: use `CTRL.CLEAR`. A `LEN` above 8192 finishes on the spot with `DONE` and `ERROR` set and `BUSY` clear. `ACK` is combinational, so each access costs the CPU 3 cycles.

</details>

**Sequence:** write the sorted array → `LEN` → `KEY` → `CTRL = 1` → poll `STATUS.DONE` → check `STATUS.FOUND` / `ERROR` → read `RESULT` and `COMPS`. The CPU is **not** stalled while searching; the array cannot be modified until `DONE`.

**Performance:** the engine does one compare per clock. A lower-bound search over `N` elements takes `floor(log2 N) + 1` loop iterations and then one finishing cycle (which does one more compare when the lower bound lies inside the array), so `COMPS` is at most `floor(log2 N) + 2` and the slave is busy about `floor(log2 N) + 2` cycles *(derived from the RTL)*. `tb_wb_search_integration` and `tb_cpu_search` observe `COMPS = 4` for `N = 7`, `KEY = 12` (*simulated*).

<details>
<summary>Derived totals vs software estimate</summary>

| N | Search cycles in the slave (derived) | Compares (max) |
|---|-----|-----|
| 8 | 5 | 5 |
| 256 | 10 | 10 |
| 4096 | 14 | 14 |
| 8192 | 15 | 15 |

A software binary search is an **estimate**: roughly 8-12 instructions per iteration (load, compare, branch, pointer update), so ~`10 * (floor(log2 N) + 1)` cycles, e.g. ~90 for `N = 256`. The search itself is therefore ~9x faster, but the CPU still pays 3 cycles for each of the `LEN`, `KEY`, `CTRL`, `STATUS` and `RESULT` accesses (and `COMPS` if read), about 18 cycles of overhead, and loading the array through the bus costs 3 cycles per word. The accelerator pays off when the array is loaded once and searched many times; for a single search of a fresh array software wins.

</details>

**Tests:** `tb_wb_search_accel` (bus-level; prints `ALL SEARCH TESTS PASSED`), `tb_wb_search_integration` (through `wb_interconnect`; prints `ALL INTEGRATION TESTS PASSED`) and `tb_cpu_search` / `tb_cpu_search_multi` (the CPU programs the slave from instructions assembled in the bench; `tb_cpu_search` prints `ALL CPU-LEVEL SEARCH TESTS PASSED`). They are not in `make run`; `make bus` picks up the two bus-level ones.

</details>

## DMA Controller

[`wb_dma.v`](hardware/src/bus/wb_dma.v) is a single-channel word-copy engine: any address to any address. It is a slave at `0x2000_0000` (the CPU programs its registers) and a second bus master (it moves the data).

<details>
<summary><b>Register map</b></summary>

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| `0x2000_0000` | `SRC` | R/W | Source byte address; live, +4 per word |
| `0x2000_0004` | `DST` | R/W | Destination byte address; live, +4 per word |
| `0x2000_0008` | `LEN` | R/W | Words left; live, −1 per word, reads 0 after a full copy |
| `0x2000_000C` | `CTRL` | W | bit0 `START` (self-clearing; ignored if busy or `LEN == 0`) |
| `0x2000_0010` | `STATUS` | R/W1C | bit0 `BUSY` (RO), bit1 `DONE`, bit2 `ERR` (sticky, write 1 to clear) |

Registers alias every 32 bytes across `0x2000_0000`-`0x2000_FFFF`. `addr[1:0]` is ignored (word-only). `SRC`/`DST`/`LEN`/`CTRL` writes are ignored while busy.

</details>

**Routing:** each side of the copy is chosen by address, like the CPU's `io_sel`. `addr[31:16] == 0` uses local `data_memory` port B (1 cycle, off the bus); anything else goes over the bus through the DMA's internal `wb_master` (3 cycles).

| Copy | Cycles/word |
|------|-------------|
| local → bus | 4 |
| bus → local | 4 |
| local → local | 2 |
| bus → bus | 6 |

**CPU halt:** while `BUSY` the CPU is frozen (`stall` includes `dma_busy`) and the bus mux gives the DMA ownership, so there is no polling: the `SW` to `CTRL` acts like a blocking `memcpy`, and the next instruction runs after the copy is done.

**Errors:** a bus `ERR` stops the copy early without advancing `SRC`/`DST`/`LEN`, and sets `DONE` and `ERR`.

**Sequence:** write `SRC` → `DST` → `LEN` → `START` (optionally check `STATUS.ERR` afterwards).

Refer to [Processor_Control_Signals](documentation/RV32I_Processor_Control_Signals.md) for what the signals in the dumped waveforms mean.

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

This builds the SoC with [`tb_cpu_top_wb_mac.v`](hardware/test_bench/tb_cpu_top_wb_mac.v), simulates it, and exits non-zero if any check fails (`vvp` itself always exits 0, so the Makefile scans the log for `FAIL`). After the 56-instruction demo program it runs `mac_driver.vh` at the driver address: the CPU `sw`s a 4xK by Kx4 pair (K = 4) into the matrix window, programs `DATA_BASE`/`K`/`CTRL`, polls `STATUS.DONE`, and the DMA copies all 32 result words from `0x1000_0000` into local RAM, where the bench checks every `C[r][c]` against a software-computed 64-bit value. A successful run ends with:

```text
VCD info: dumpfile cpu_top_wb.vcd opened for output.
MAC driver: 127 cycles (DRV_BASE -> DRV_DONE, K=4)
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
  hardware/test_bench/tb_cpu_top_wb_mac.v && vvp build/cpu_tb.out
```

</details>

<details>
<summary><b>Makefile targets</b></summary>

```bash
make run      # compile + simulate the MAC/DMA SoC testbench, fail on any FAIL 
make sort     # compile + simulate the SORT SoC testbench (loads program_sort.hex), fail on any FAIL
make compile  # compile only, build/cpu_tb.out
make bus      # run every bench in hardware/test_bench/bus/tb_*.v, stop at the first failure
make clean    # remove build artifacts and *.vcd
```

</details>

<details>
<summary><b>Bus testbenches</b></summary>

`make bus` runs every `hardware/test_bench/bus/tb_*.v` in alphabetical order and stops at the first failure. Current state (each run by hand):

| Bench | Result |
|-------|--------|
| `tb_wb_ram` | 35 pass |
| `tb_wb_master` | 32 pass |
| `tb_wb_integ` | 21 pass |
| `tb_wb_sort` | 103 / 103, `ALL TESTS PASSED` |
| `tb_wb_search_accel` | `ALL SEARCH TESTS PASSED` |
| `tb_wb_search_integration` | `ALL INTEGRATION TESTS PASSED` |
| `tb_wb_mac_accel` | 72 tests (tile model; checks results, `K + 6 + MEM_LAT + MULT_PIPE` run cycles, K clamp, `CLEAR`) |
| `tb_wb_dma` | 30 checks (DMA programs and reads the matrix MAC; cycles per word 4 / 4 / 2 / 6; unmapped-DST error) |

All of them pass under `make bus`. To run one by hand (SORT shown; `-I hardware/src/bus` is needed by every bench that includes `wb_defs.vh`, and benches that go through the interconnect need all of `hardware/src`):

```bash
iverilog -I hardware/src/bus -s tb_wb_sort -o /tmp/tb_sort.out $(find hardware/src -name '*.v' ! -name wb_ram.v) hardware/test_bench/bus/tb_wb_sort.v && vvp /tmp/tb_sort.out
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

## Known issues

- **SEARCH moved to `0x5000_0000`.** It and SORT both decoded `0x3000_xxxx` in the merged branches, so SORT keeps `0x3000_0000` and SEARCH was relocated to `0x5000_0000` (the `tb_*search*` benches were updated to match).
- **Duplicate module name.** `tb_cpu_search.v` and `tb_cpu_search_multi.v` both declare `module tb_cpu_search`; compile one at a time.

## License

This project is licensed under the [MIT License](LICENSE).
