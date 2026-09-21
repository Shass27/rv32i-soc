<img width="1527" height="867" alt="image" src="https://github.com/user-attachments/assets/5048e599-8977-4322-b471-f6ac689a4833" /># RV32I SoC — Functional Verification Report

This document records the functional verification of the RV32I SoC processor
using the **official RISC-V architectural test suite** (`riscv-tests`,
`isa/rv32ui`). It covers the verification methodology, the full instruction
result matrix, and a detailed waveform-level walkthrough for six
representative instructions.

**Result: 37/37 implemented RV32I instructions passed their corresponding
official `rv32ui` tests.**

---

## 1. Scope

The processor implements 37 instructions from the RV32I base integer ISA:

| Group | Count | Instructions |
|---|---|---|
| Arithmetic / Logical | 10 | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU |
| Immediate | 9 | ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU |
| Load / Store | 8 | LB, LH, LW, LBU, LHU, SB, SH, SW |
| Branch / Jump | 8 | BEQ, BNE, BLT, BGE, BLTU, BGEU, JAL, JALR |
| Upper Immediate | 2 | LUI, AUIPC |
| **Total** | **37** | |

Passing the official tests is functional verification evidence for the
tested instruction behavior — it is not a formal proof of full RISC-V
compliance, nor does it guarantee coverage of every microarchitectural
corner case.

---

## 2. Verification Methodology

Each official test program (e.g. `add.S`, `lw.S`, `sw.S`) from
`riscv-tests/isa/rv32ui/` is used **unmodified**. A CPU-specific target
environment (`env/cpu/riscv_test.h`, `env/p/link_cpu.ld`) supplies only the
startup, linking, and test-completion interface required by this processor.

### Flow

```text
Official .S  →  RISC-V GCC  →  ELF  →  objcopy  →  Verilog HEX
                                                         ↓
                                          program.hex / data.hex
                                                         ↓
                                                 CPU RTL (Icarus Verilog)
                                                         ↓
                                                TOHOST PASS / FAIL
```

1. **Compilation (ELF).** Each test is cross-compiled for RV32I / ILP32 with
   `riscv64-unknown-elf-gcc`, using `-nostdlib -nostartfiles` and the
   CPU-specific linker script.
2. **HEX generation.** `riscv64-unknown-elf-objcopy` strips unneeded
   sections and converts the ELF to a Verilog memory image
   (`--verilog-data-width=4 --reverse-bytes=4`).
3. **Data memory initialization (load/store tests only).** The official
   `.data` section is placed at `0x2000`. Since this processor's data
   memory indexes words as `address >> 2`, the load address in the HEX
   file is remapped from `@00002000` to `@00000800` before loading.
4. **Simulation.** The instruction/data images are loaded into the RTL and
   run with Icarus Verilog (`iverilog` + `vvp`).
5. **Result reporting.** Each test writes its result to a fixed `TOHOST`
   location at address `0x000001C0`. `TOHOST = 1` indicates `PASS`:
   ```text
   TOHOST: PASS (tohost=0x00000001)
   ```

---

## 3. Instruction-Level Results

| # | Instr | Test | Result | # | Instr | Test | Result | # | Instr | Test | Result |
|---|-------|------|--------|---|-------|------|--------|---|-------|------|--------|
| 1 | ADD | add.S | PASS | 14 | XORI | xori.S | PASS | 27 | SW | sw.S | PASS |
| 2 | SUB | sub.S | PASS | 15 | SLLI | slli.S | PASS | 28 | BEQ | beq.S | PASS |
| 3 | ADDI | addi.S | PASS | 16 | SRLI | srli.S | PASS | 29 | BNE | bne.S | PASS |
| 4 | AND | and.S | PASS | 17 | SRAI | srai.S | PASS | 30 | BLT | blt.S | PASS |
| 5 | OR | or.S | PASS | 18 | SLTI | slti.S | PASS | 31 | BGE | bge.S | PASS |
| 6 | XOR | xor.S | PASS | 19 | SLTIU | sltiu.S | PASS | 32 | BLTU | bltu.S | PASS |
| 7 | SLL | sll.S | PASS | 20 | LB | lb.S | PASS | 33 | BGEU | bgeu.S | PASS |
| 8 | SRL | srl.S | PASS | 21 | LH | lh.S | PASS | 34 | JAL | jal.S | PASS |
| 9 | SRA | sra.S | PASS | 22 | LW | lw.S | PASS | 35 | JALR | jalr.S | PASS |
| 10 | SLT | slt.S | PASS | 23 | LBU | lbu.S | PASS | 36 | LUI | lui.S | PASS |
| 11 | SLTU | sltu.S | PASS | 24 | LHU | lhu.S | PASS | 37 | AUIPC | auipc.S | PASS |
| 12 | ANDI | andi.S | PASS | 25 | SB | sb.S | PASS | | | | |
| 13 | ORI | ori.S | PASS | 26 | SH | sh.S | PASS | | | | |

**Aggregate: 37/37 tests passed.**

---

## 4. Representative Waveform Analysis

Reproducing all 37 traces would be redundant, so six waveforms — one per
principal datapath class — are used as verification evidence: **ADD**
(register-register arithmetic), **SLLI** (immediate/shift), **LW** and
**SW** (load/store), and **BEQ** and **JAL** (control flow).

All captures use the processor's control/datapath debug bus: `ALUControl`,
`ALUOp`, `ALUSrc`, `ALU_result`, `alu_A`/`alu_B`, `RegWrite`, `imm`,
`instr`, `pc`, `rd`/`rs1`/`rs2`, `rs1_data`/`rs2_data`, `MemRead`/
`MemWrite`, `mem_rdata`, and `wb_data`.

### 4.1 ADD — register-register arithmetic

<img width="1527" height="867" alt="image" src="https://github.com/user-attachments/assets/9b5a7ae6-5810-41a7-b2c4-c79e4c6c9ba2" />



Testbench: `tb_official_add`. `ALUOp = 2` selects R-type ALU decode, and
`ALUControl` resolves to the ADD operation. `alu_A`/`alu_B` are driven
directly from `rs1_data`/`rs2_data` (`ALUSrc = 0`), the ALU produces
`ALU_result`, and the result is latched into `wb_data` with `RegWrite`
asserted for the destination register in `rd`. The instruction stream
steps through the full `add.S` sequence, each `ADD` correctly committing
its computed sum to the register file.

### 4.2 SLLI — immediate shift




Testbench: `tb_official_slli`. The 5-bit shift amount is decoded from the
immediate field (`imm`) rather than a register, with `ALUSrc` selecting
the immediate operand for `alu_B`. `ALUControl` switches to the
left-shift operation while `ALUOp` reflects the immediate-instruction
encoding. `ALU_result` shows the source operand progressively shifted
left by the encoded amount (e.g. `00000002 → ff010000 → ff00ff00 → …`),
confirming correct immediate extraction and shift-amount decode across
the `slli.S` sequence.

### 4.3 LW — word load




Testbench: `tb_cpu_top` (`lw.vcd`). The effective address is computed as
`rs1_data + imm` through the ALU (`ALUOp = 2`, base+offset addressing),
`MemRead` is asserted, and the returned `mem_rdata` is routed to
`wb_data` for register write-back. `pc` and `jump_ret_addr` progress in
step through the `lw.S` program, confirming correct sequencing of
address generation, memory read, and write-back for every load in the
test.

### 4.4 SW — word store

 <img width="1532" height="877" alt="image" src="https://github.com/user-attachments/assets/198d1586-425e-49cc-9c75-1d0564684b3e" />


Testbench: `tb_cpu_top` (`sw.vcd`). As with LW, the effective address is
generated via `rs1_data + imm`, but here `MemWrite` is the active memory
control signal instead of `MemRead`, and `rs2_data` supplies the store
data rather than a register destination write. The instruction and PC
trace step consistently through `sw.S`, verifying correct effective-address
computation and store-data routing for each store.

### 4.5 BEQ — branch-equal / control flow
<img width="1525" height="862" alt="image" src="https://github.com/user-attachments/assets/21ab8b5e-b54e-4de6-a42e-48c765cf6492" />


Testbench: `tb_official_beq`. `ALUOp` alternates between `1` (branch
compare) and `2` (address/offset arithmetic) as the test exercises both
taken and not-taken branch cases. `branch_target` is computed each cycle,
and `RegWrite`/`RegWrite_gate` toggle to reflect the bookkeeping
instructions between branches in `beq.S`. The repeating pattern across
the trace (`rs1`/`rs2` compare → `ALU_result` → branch decision) confirms
the branch-condition and target-computation logic behaves correctly for
both equal and not-equal operand pairs.

### 4.6 JAL — unconditional jump and link

<img width="1535" height="886" alt="image" src="https://github.com/user-attachments/assets/83e42c0d-652e-4764-92b2-b04ca32244ba" />


Testbench: `tb_official_jal`. `jump`/`jump1`/`jump2` and `jump_target` are
asserted while `pc` is redirected to the computed jump target
(`alu_A + alu_B`, with `alu_B` carrying the signed jump offset, e.g.
`00000010`, `fffffff4`). `RegWrite` commits the return address (`pc + 4`)
into `rd`, visible as `wb_data` tracking `jump_ret_addr`. The trace
confirms correct target-address computation, PC redirection, and
link-register write-back across the `jal.S` sequence.

---

## 5. Reproducing a Test

Commands below are written for the VS Code PowerShell terminal.

### 5.1 Set paths and select a test

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

List all available official tests:

```powershell
Get-ChildItem "$TEST_REPO\isa\rv32ui\*.S" | Select-Object -ExpandProperty BaseName
```

### 5.2 Generate the instruction HEX

```powershell
cd $TEST_REPO

& $GCC -march=rv32i -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -I".\env\cpu" -I".\isa\macros\scalar" -T".\env\p\link_cpu.ld" ".\isa\rv32ui\$TEST.S" -o ".\${TEST}_cpu.elf"

& $OBJCOPY --remove-section .tohost ".\${TEST}_cpu.elf" ".\${TEST}_cpu_clean.elf"

& $OBJCOPY --remove-section .riscv.attributes -O verilog --verilog-data-width=4 --reverse-bytes=4 ".\${TEST}_cpu_clean.elf" ".\${TEST}_code.hex"

Copy-Item ".\${TEST}_code.hex" "$CPU_REPO\hardware\src\core\if\program.hex" -Force
```

### 5.3 For load/store tests, generate the data HEX

Only for: `lb lh lw lbu lhu sb sh sw`

```powershell
$MEM_TESTS = @("lb","lh","lw","lbu","lhu","sb","sh","sw")

if ($MEM_TESTS -contains $TEST) {
    & $OBJCOPY -j .data -O verilog --verilog-data-width=4 --reverse-bytes=4 ".\${TEST}_cpu_clean.elf" ".\${TEST}_data.hex"

    (Get-Content ".\${TEST}_data.hex") -replace '^@00002000$', '@00000800' | Set-Content ".\${TEST}_data_cpu.hex"

    Copy-Item "$CPU_REPO\hardware\src\core\mem\data.hex" "$CPU_REPO\hardware\src\core\mem\data_backup_before_${TEST}.hex" -Force

    Copy-Item ".\${TEST}_data_cpu.hex" "$CPU_REPO\hardware\src\core\mem\data.hex" -Force
}
```

### 5.4 Compile and run

```powershell
cd $CPU_REPO

& $IVERILOG -o ".\cpu_debug_sim" -s tb_debug -g2012 (Get-ChildItem -Path ".\hardware\src" -Recurse -Filter *.v | ForEach-Object { $_.FullName }) ".\hardware\test_bench\tb_debug.v"

& $VVP ".\cpu_debug_sim"
```

Expected output:

```text
TOHOST: PASS (tohost=0x00000001)
```

Save the log:

```powershell
& $VVP ".\cpu_debug_sim" | Tee-Object "$CPU_REPO\build\${TEST}_pass.txt"
```

---

## 6. Discussion

Using the official architectural tests gives stronger coverage than
isolated hand-written checks, since each test exercises an instruction as
part of a complete program involving register operations, comparisons,
memory accesses, and control flow — rather than a single instruction in
isolation. The assembly-to-HEX flow (Section 2) also gives a reproducible
path from an unmodified official test source to processor execution,
and the retained waveforms (Section 4) and logs (Section 5) serve as
evidence for future debugging and regression testing.

## 7. Conclusion

All 37 RV32I instructions implemented by this processor were functionally
verified against their corresponding official `riscv-tests/isa/rv32ui`
programs, with a **37/37 pass rate**. Six representative waveforms — ADD,
SLLI, LW, SW, BEQ, and JAL — are included above to illustrate correct
behavior across the arithmetic, immediate, load/store, and control-flow
datapath classes.

## References

- RISC-V Software, *RISC-V Architectural Tests (riscv-tests)*, GitHub.
  https://github.com/riscv-software-src/riscv-tests
- A. Waterman and K. Asanović, Eds., *The RISC-V Instruction Set Manual,
  Volume I: Unprivileged ISA*, RISC-V International.
