# FlashAttention RTL - Simulation Setup & Run Guide

## Overview

This guide helps you set up and run the Cocotb testbench for the FlashAttention RTL engine.

**Simulator Stack:**
- **Verilator**: Open-source Verilog/SystemVerilog simulator (C++ based, Windows-compatible)
- **Cocotb**: Coroutine-based testbench framework (Python)
- **Python 3.8+**: Scripting language for testbench

**Target Module:** 8×8 Systolic Array for matrix multiplication (Q4.4 fixed-point)

---

## Prerequisites

### Windows System Requirements

Before proceeding, ensure you have:

1. **Python 3.8 or later**
   ```
   python --version  # Should show 3.8+
   ```

2. **Git Bash or WSL2** (for Unix-like commands on Windows)
   - Recommended: Git Bash (lightweight)
   - Alternative: Windows Subsystem for Linux 2

3. **C++ Compiler** (required by Verilator)
   - Option A: **Microsoft Visual C++ (MSVC)**
     - Install Visual Studio Community (free)
     - Select "Desktop Development with C++"
   - Option B: **MinGW-w64** (lightweight alternative)
     - Download from: https://www.mingw-w64.org/
     - Add `bin/` to Windows PATH

4. **Verilator 5.0+** (Verilog/SystemVerilog simulator)
   ```
   # Download Windows binary or build from source
   # https://www.veripool.org/verilator/
   verilator --version
   ```

---

## Step 1: Install Verilator (Windows)

### Option A: Using Pre-built Binary (Easiest)

1. Download Verilator Windows binary from: https://www.veripool.org/verilator/
2. Extract to `C:\Program Files\verilator\` (or custom location)
3. Add to Windows PATH:
   ```
   setx PATH "%PATH%;C:\Program Files\verilator\bin"
   ```
4. Verify:
   ```
   verilator --version
   ```

### Option B: Build from Source

```bash
# Clone Verilator
git clone https://github.com/verilated/verilator

cd verilator
git checkout v5.012  # Latest stable

# Configure and build
autoconf
./configure --prefix=C:\Program Files\verilator
make
make install

# Add to PATH
setx PATH "%PATH%;C:\Program Files\verilator\bin"
```

---

## Step 2: Set Up Python Environment

Navigate to project directory:

```bash
cd d:\goml\flashattentionv1
```

Create virtual environment:

```bash
# Create venv
python -m venv venv

# Activate (Windows Command Prompt)
venv\Scripts\activate

# OR activate (PowerShell)
venv\Scripts\Activate.ps1
```

Install dependencies:

```bash
pip install cocotb cocotb-test pytest numpy
```

Verify installation:

```bash
python -c "import cocotb; print(f'Cocotb {cocotb.__version__} installed')"
```

---

## Step 3: Verify RTL Files

Check that all RTL source files are present:

```bash
# From project root
dir rtl\src\*.sv
# Should show:
#   processing_element.sv
#   systolic_array.sv
```

Optionally, check SystemVerilog syntax:

```bash
cd sim
verilator --lint-only ..\rtl\src\processing_element.sv ..\rtl\src\systolic_array.sv --top-module systolic_array
```

---

## Step 4: Run Testbench

### Quick Test (Syntax Check Only)

```bash
cd sim
make check_syntax
```

Expected output:
```
Checking SystemVerilog syntax with Verilator...
(no errors = success)
```

### Full Simulation with Cocotb

**Important:** Cocotb testbenches must be run from `sim/` directory.

```bash
cd sim

# Run all tests
python -m cocotb.simulator --simulator verilator \
    --testbench test_systolic_array \
    --toplevel systolic_array \
    --verilog_sources ../rtl/src/processing_element.sv \
    --verilog_sources ../rtl/src/systolic_array.sv
```

Or use the Makefile:

```bash
cd sim
make sim
```

---

## Expected Output

When simulation runs successfully, you should see:

```
===========================
TEST: Systolic Array Basic Functionality
===========================
Starting 10ns clock...
Asserting reset...

Test 1: Small values (easy validation)
...
RTL output:
[[result matrix]]

Golden C: ...
RTL: ...
Result C[0,0]: golden=X, rtl=Y

✓ TEST PASSED
===========================
```

---

## Troubleshooting

### Error: "verilator: command not found"

**Solution:** Verilator is not in PATH. Verify installation:
```bash
where verilator    # Should show path
verilator --version
```

If not found, manually add Verilator `bin/` directory to Windows PATH:
- Settings → Environment Variables → Edit PATH → Add `C:\Program Files\verilator\bin`
- Restart terminal and try again

### Error: "cocotb: command not found" or "ModuleNotFoundError: No module named cocotb"

**Solution:** Cocotb not installed in Python environment:
```bash
# Make sure venv is activated
pip list | grep cocotb    # Should show installed packages
pip install cocotb cocotb-test
```

### Error: "C++ compiler not found"

**Solution:** Required for Verilator compilation. Install:
- **MSVC:** Visual Studio Community with C++ workload
- **OR MinGW:** Download from mingw-w64.org, add to PATH

### Error: SystemVerilog Syntax Issues

**Solution:** Verify RTL files are valid:
```bash
verilator --lint-only ../rtl/src/*.sv
```

Fix any reported syntax errors (modern SystemVerilog constructs like `interface` may need simulation-specific flags).

---

## Next Steps (For Development)

After verifying the systolic array works:

### 1. Run Simplified Tests

Create simpler test vectors for quicker iteration:

```bash
python test_data_gen.py  # Generate test vectors
python test_systolic_array.py  # Run basic tests
```

### 2. Generate Waveforms (Optional)

To visualize signal behavior:

```bash
# Run with trace enabled
verilator --trace ../rtl/src/systolic_array.sv

# View waveform
gtkwave trace.vcd
```

### 3. Extend Testbench

Add more complex test cases to `test_systolic_array.py`:
- Multi-block cascades
- Edge cases (saturation, boundary conditions)
- Performance metrics (throughput, latency)

---

## Configuration Options

Edit `sim/Makefile` or `pyproject.toml` to customize:

- **Simulator:** Change `SIM = verilator` to other simulators (iverilog, ModelSim, etc.)
- **Trace:** Add `--trace` to capture waveforms
- **Optimization:** Add `-O3` for simulation speed

---

## References

- **Verilator:** https://www.veripool.org/verilator/
- **Cocotb:** https://docs.cocotb.org/
- **SystemVerilog:** https://en.wikipedia.org/wiki/SystemVerilog
- **Fixed-Point Arithmetic:** Q-format reference in golden_model.py

---

## Support

For issues:
1. Check RTL syntax: `verilator --lint-only ../rtl/src/*.sv`
2. Verify Python environment: `pip list`
3. Review Cocotb logs: Check console output for detailed error messages
4. Consult RTL comments: Each module has inline documentation

Good luck with your FlashAttention RTL! 🚀
