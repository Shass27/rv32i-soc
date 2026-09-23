# RISC-V 32I SoC Makefile

# Tools
IVERILOG = iverilog
VVP = vvp

# Directories
SRC_DIR = hardware/src/core
INC_DIR = hardware/src/include
BUS_DIR = hardware/src/bus
TB_DIR = hardware/test_bench
BUILD_DIR = build

IFLAGS = -I $(INC_DIR) -I $(BUS_DIR) -I $(TB_DIR)

# wb_ram is unused (local data_memory is the CPU RAM), so it is left out
SRC_FILES = $(wildcard $(SRC_DIR)/*/*.v $(SRC_DIR)/*.v) $(filter-out $(BUS_DIR)/wb_ram.v,$(wildcard $(BUS_DIR)/*.v))
# Main testbench (self-checking SoC bench)
TB_FILE = $(TB_DIR)/tb_cpu_top_wb.v

# Bus testbenches compile against every bus source (wb_ram included)
BUS_SRCS = $(wildcard $(BUS_DIR)/*.v)
BUS_TBS = $(wildcard $(TB_DIR)/bus/tb_*.v)

# vvp always exits 0, so exit 1 if any log line has FAIL that is not "FAIL: 0" (awk: same on BSD and GNU)
CHECK_LOG = awk '/FAIL/ && !/FAIL: *0/ {bad=1} END {exit bad}' $(1)

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
	$(IVERILOG) $(IFLAGS) -o $(OUT) $(SRC_FILES) $(TB_FILE)
	@echo "Compilation successful!"

# Run simulation
run: compile
	@echo "Running simulation..."
	@$(VVP) $(OUT) | tee $(BUILD_DIR)/cpu_tb.log
	@$(call CHECK_LOG,$(BUILD_DIR)/cpu_tb.log) || { echo "SoC testbench FAILED"; exit 1; }

# Run every bus testbench, stop at the first failure
bus: $(BUILD_DIR)
	@for tb in $(BUS_TBS); do \
		name=$$(basename $$tb .v); \
		echo "== $$name"; \
		$(IVERILOG) $(IFLAGS) -s $$name -o $(BUILD_DIR)/$$name.out $(BUS_SRCS) $$tb || exit 1; \
		$(VVP) $(BUILD_DIR)/$$name.out | tee $(BUILD_DIR)/$$name.log; \
		$(call CHECK_LOG,$(BUILD_DIR)/$$name.log) || { echo "$$name FAILED"; exit 1; }; \
	done; \
	echo "All bus testbenches passed."

# Clean build artifacts
clean:
	@echo "Cleaning up..."
	rm -rf $(BUILD_DIR)
	rm -f *.vcd

.PHONY: all compile run bus clean
