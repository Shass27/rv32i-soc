# RISC-V 32I SoC Makefile

# Tools
IVERILOG = iverilog
VVP = vvp

# Directories
SRC_DIR = hardware/src/core
INC_DIR = hardware/src/include
TB_DIR = hardware/test_bench
BUILD_DIR = build

# Files
# Find all Verilog files in the core directory
SRC_FILES = $(wildcard $(SRC_DIR)/**/*.v $(SRC_DIR)/*.v)
# Main testbench
TB_FILE = $(TB_DIR)/tb_cpu_top.v

# Output executable
OUT = $(BUILD_DIR)/cpu_tb.out

# Default target
all: compile run

# Create build directory if it doesn't exist
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Compile Verilog sources
compile: $(BUILD_DIR) $(SRC_FILES) $(TB_FILE)
	@echo "Compiling hardware sources..."
	$(IVERILOG) -I $(INC_DIR) -o $(OUT) $(SRC_FILES) $(TB_FILE)
	@echo "Compilation successful!"

# Run simulation
run: compile
	@echo "Running simulation..."
	$(VVP) $(OUT)

# Clean build artifacts
clean:
	@echo "Cleaning up..."
	rm -rf $(BUILD_DIR)
	rm -f *.vcd

.PHONY: all compile run clean
