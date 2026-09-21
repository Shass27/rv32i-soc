# Reproducing an Official RISC-V Test

This guide builds any official `riscv-tests/isa/rv32ui` program, loads it
into the SoC's instruction (and, for load/store tests, data) memory, and
runs it under Icarus Verilog until the `TOHOST` PASS/FAIL line appears. Each
step is given twice: a PowerShell version (VS Code terminal) and a
macOS / Linux bash version.

Links: [VERIFICATION.md](VERIFICATION.md) · [project README](../../README.md)

> `tb_debug.v` is a local scratch testbench and is not committed to the repo.
> It wraps `cpu_top_wb` and prints the `TOHOST: PASS/FAIL` line that
> `data_memory.v` itself emits when a write hits `TOHOST_ADDR = 32'h000001c0`
> (value `1` = PASS, any other nonzero value = FAIL; both call `$finish`).

## 1. Set paths and select a test

Change only the paths and `$TEST` for your machine.

**PowerShell**

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

**macOS / Linux (bash)**

```bash
CPU_REPO="$HOME/rv32i-soc"
TEST_REPO="$HOME/riscv-tests"
RISCV_BIN="/opt/riscv/bin"   # directory containing riscv64-unknown-elf-*

GCC="${RISCV_BIN}/riscv64-unknown-elf-gcc"
OBJCOPY="${RISCV_BIN}/riscv64-unknown-elf-objcopy"

TEST="sw"
```

Available tests:

```bash
ls "${TEST_REPO}"/isa/rv32ui/*.S | xargs -n1 basename | sed 's/\.S$//'
```

## 2. Generate the instruction HEX

**PowerShell**

```powershell
cd $TEST_REPO

& $GCC -march=rv32i -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -I".\env\cpu" -I".\isa\macros\scalar" -T".\env\p\link_cpu.ld" ".\isa\rv32ui\$TEST.S" -o ".\${TEST}_cpu.elf"

& $OBJCOPY --remove-section .tohost ".\${TEST}_cpu.elf" ".\${TEST}_cpu_clean.elf"

& $OBJCOPY --remove-section .riscv.attributes -O verilog --verilog-data-width=4 --reverse-bytes=4 ".\${TEST}_cpu_clean.elf" ".\${TEST}_code.hex"

Copy-Item ".\${TEST}_code.hex" "$CPU_REPO\hardware\src\core\if\program.hex" -Force
```

**macOS / Linux (bash)**

```bash
cd "${TEST_REPO}"

"${GCC}" -march=rv32i -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -I./env/cpu -I./isa/macros/scalar -T./env/p/link_cpu.ld "./isa/rv32ui/${TEST}.S" -o "./${TEST}_cpu.elf"

"${OBJCOPY}" --remove-section .tohost "./${TEST}_cpu.elf" "./${TEST}_cpu_clean.elf"

"${OBJCOPY}" --remove-section .riscv.attributes -O verilog --verilog-data-width=4 --reverse-bytes=4 "./${TEST}_cpu_clean.elf" "./${TEST}_code.hex"

cp -f "./${TEST}_code.hex" "${CPU_REPO}/hardware/src/core/if/program.hex"
```

This overwrites the demo `program.hex`; see [Selecting the program image](#selecting-the-program-image)
for how to avoid that.

## 3. For load/store tests, generate the data HEX

Use this block only for:

`lb lh lw lbu lhu sb sh sw`

**PowerShell**

```powershell
$MEM_TESTS = @("lb","lh","lw","lbu","lhu","sb","sh","sw")

if ($MEM_TESTS -contains $TEST) {
    & $OBJCOPY -j .data -O verilog --verilog-data-width=4 --reverse-bytes=4 ".\${TEST}_cpu_clean.elf" ".\${TEST}_data.hex"

    (Get-Content ".\${TEST}_data.hex") -replace '^@00002000$', '@00000800' | Set-Content ".\${TEST}_data_cpu.hex"

    Copy-Item "$CPU_REPO\hardware\src\core\mem\data.hex" "$CPU_REPO\hardware\src\core\mem\data_backup_before_${TEST}.hex" -Force

    Copy-Item ".\${TEST}_data_cpu.hex" "$CPU_REPO\hardware\src\core\mem\data.hex" -Force
}
```

**macOS / Linux (bash)**

```bash
case " lb lh lw lbu lhu sb sh sw " in
  *" ${TEST} "*)
    "${OBJCOPY}" -j .data -O verilog --verilog-data-width=4 --reverse-bytes=4 "./${TEST}_cpu_clean.elf" "./${TEST}_data.hex"

    # remap data base 0x2000 -> word index 0x800
    sed -E 's/^@00002000$/@00000800/' "./${TEST}_data.hex" > "./${TEST}_data_cpu.hex"

    cp -f "${CPU_REPO}/hardware/src/core/mem/data.hex" "${CPU_REPO}/hardware/src/core/mem/data_backup_before_${TEST}.hex"

    cp -f "./${TEST}_data_cpu.hex" "${CPU_REPO}/hardware/src/core/mem/data.hex"
    ;;
esac
```

## 4. Compile the CPU

**PowerShell**

```powershell
cd $CPU_REPO

& $IVERILOG -o ".\cpu_debug_sim" -s tb_debug -g2012 (Get-ChildItem -Path ".\hardware\src" -Recurse -Filter *.v | ForEach-Object { $_.FullName }) ".\hardware\test_bench\tb_debug.v"
```

**macOS / Linux (bash)**

```bash
cd "${CPU_REPO}"

iverilog -o cpu_debug_sim -s tb_debug -g2012 $(find hardware/src -name '*.v') hardware/test_bench/tb_debug.v
```

## 5. Run the test

**PowerShell**

```powershell
& $VVP ".\cpu_debug_sim"
```

**macOS / Linux (bash)**

```bash
vvp cpu_debug_sim
```

Expected result:

```text
TOHOST: PASS (tohost=0x00000001)
```

## 6. Save the simulation log

**PowerShell**

```powershell
& $VVP ".\cpu_debug_sim" | Tee-Object "$CPU_REPO\build\${TEST}_pass.txt"
```

**macOS / Linux (bash)**

```bash
mkdir -p "${CPU_REPO}/build"
vvp cpu_debug_sim | tee "${CPU_REPO}/build/${TEST}_pass.txt"
```

## Selecting the program image

`inst_mem` takes a parameter `PROG_FILE`, defaulting to
`"hardware/src/core/if/program.hex"`: the 55-word demo program that the SoC
testbench checks. `hardware/src/core/if/program2.hex` is the committed
official rv32ui image.

To run an image without overwriting `program.hex`, override the parameter.
In a scratch testbench, instantiate:

```verilog
// point the instruction ROM at the official image
inst_mem #(.PROG_FILE("hardware/src/core/if/program2.hex")) u_imem (/* ports */);
```

or, if `inst_mem` is instantiated inside the DUT, override it hierarchically:

```verilog
// applied from the testbench before simulation starts
defparam u_dut.u_imem.PROG_FILE = "hardware/src/core/if/program2.hex";
```

Alternatively, let step 2 overwrite `program.hex` and restore the demo
program afterwards:

```bash
git checkout hardware/src/core/if/program.hex
```

For load/store tests, `data.hex` is also replaced (step 3 keeps a
`data_backup_before_<test>.hex` copy next to it); restore it from that
backup or with `git checkout hardware/src/core/mem/data.hex`.

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

See [VERIFICATION.md](VERIFICATION.md) for the full report and
[project README](../../README.md) for the project overview.
