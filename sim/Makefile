# Makefile for Cocotb + Verilator Simulation
# FlashAttention RTL Testbench
#
# Usage:
#   make sim              - Run all tests
#   make sim_systolic     - Run systolic array tests only
#   make clean            - Remove all generated files
#   make help             - Show this help message

# =====================================================================
# Variables
# =====================================================================

# Simulation tool
SIM ?= verilator
SIM_ARGS ?= --trace

# Cocotb settings
COCOTB_RUNNER ?= $(COCOTB)/share/cocotbutils/simulator_list.txt

# Project structure
RTL_DIR = ./rtl/src
SIM_DIR = ./sim
WORK_DIR = $(SIM_DIR)/work

# Verilator (C++ simulator)
VERILATOR_BIN ?= verilator
VERILATOR_FLAGS = --trace --trace-fst -Wall -Wno-DECLFILENAME -Wno-IMPLICIT

# Python/Cocotb
PYTHON ?= python
PYTEST ?= pytest

# Source files
RTL_FILES = $(RTL_DIR)/processing_element.sv \
            $(RTL_DIR)/systolic_array.sv

TESTBENCH_TOP = systolic_array

# =====================================================================
# Targets
# =====================================================================

.PHONY: help sim sim_systolic clean

help:
	@echo "FlashAttention RTL Simulation Makefile"
	@echo "========================================"
	@echo "Targets:"
	@echo "  make sim              - Run all Cocotb tests"
	@echo "  make sim_systolic     - Run systolic array tests only"
	@echo "  make clean            - Clean all generated files"
	@echo "  make help             - Show this help"
	@echo ""
	@echo "Environment Variables:"
	@echo "  SIM=verilator         - Simulator (default: verilator)"
	@echo "  COCOTB_RUNNER         - Path to cocotb runner"
	@echo ""

# Primary simulation target
sim: $(RTL_FILES)
	@echo "==================================================="
	@echo "Running Cocotb Testbench (Verilator Backend)"
	@echo "==================================================="
	@mkdir -p $(WORK_DIR)
	cd $(SIM_DIR) && $(PYTHON) -m cocotb.simulator \
		--simulator verilator \
		--testbench test_systolic_array \
		--toplevel systolic_array \
		--verilog_sources $(RTL_DIR)/processing_element.sv \
		--verilog_sources $(RTL_DIR)/systolic_array.sv \
		--work_dir work

# Alternative target using pytest (if available)
sim_systolic:
	@echo "==================================================="
	@echo "Running Systolic Array Test Suite"
	@echo "==================================================="
	@cd $(SIM_DIR) && $(PYTHON) -m pytest test_systolic_array.py -v

# Verilator compilation only (syntax check)
check_syntax:
	@echo "Checking SystemVerilog syntax with Verilator..."
	$(VERILATOR_BIN) --lint-only -Wall $(RTL_FILES) --top-module $(TESTBENCH_TOP)

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	rm -rf $(WORK_DIR)
	rm -rf obj_dir
	rm -f *.vcd *.fst *.vvp *.o *.so
	rm -rf __pycache__
	rm -rf .cocotb
	@echo "Clean complete."

# =====================================================================
# Special targets
# =====================================================================

.PHONY: setup_env install_deps

# Setup Python environment
setup_env:
	@echo "Setting up Python environment..."
	$(PYTHON) -m venv .venv
	.venv\Scripts\pip install -r requirements.txt
	@echo "Environment ready. Activate with: .venv\Scripts\activate"

# Install Cocotb and dependencies
install_deps:
	@echo "Installing Cocotb and dependencies..."
	pip install cocotb cocotb-test pytest numpy
	@echo "Dependencies installed."
