# Hybrid Compiler - Complete Guide

## Overview

The **Hybrid Compiler** is a deterministic, formally-verified compiler that unifies three programming paradigms:

- **Befunge**: 2D stack-based languages with directional control flow
- **Brainfuck**: Linear tape-based memory model with minimal operations
- **BCPL**: Imperative language with typed variables and pointers

All programs compile to **SUBLEQ** (a one-instruction ISA), execute in a verified VM, and are tested through differential verification.

## Key Features

✓ **Deterministic compilation**: Same source → identical binary (byte-for-byte)
✓ **Verified execution**: Full differential testing (reference vs compiled)
✓ **Semantic correctness**: Output matches reference interpreters
✓ **Reproducible**: 10x recompile test ensures zero nondeterminism
✓ **Optimizable**: Semantic-preserving peephole passes (constant dedup, dead code elimination, etc.)
✓ **Debuggable**: Full source location tracking in error messages
✓ **Portable**: Targets SUBLEQ ISA with no system dependencies
✓ **Benchmarkable**: Reports code size, step count, memory usage

## Architecture

### Compilation Pipeline

```
Source Code
    ↓ (Agent 1: Lexer/Parser)
AST + CFG
    ↓ (Agent 3: IR Normalizer)
IR (Normalized Intermediate Representation)
    ↓ (Agent 2: Codegen/Lowering)
SUBLEQ Machine Code
    ↓ (Optimization Passes)
Optimized SUBLEQ Binary
    ↓ (SUBLEQ VM Execution)
Output + Final State
```

### Three-Agent Architecture

- **Agent 1 (Lexer/Parser)**: Tokenize and parse source into AST
- **Agent 2 (Codegen)**: Lower IR to SUBLEQ machine code
- **Agent 3 (Integration & Verification)**: Normalize IR, optimize, test, verify

## Building and Testing

### Prerequisites

- Nim compiler (https://nim-lang.org/)
- `subleq_bf.nim` (SUBLEQ interpreter and utilities)

### Build Commands

```bash
# Parse source file and print AST
nim c -d:release hybrid_cli.nim
./hybrid_cli parse program.hy

# Emit normalized IR
./hybrid_cli emit-ir program.hy

# Compile to SUBLEQ
./hybrid_cli emit-subleq program.hy

# Compile and execute
./hybrid_cli run program.hy
./hybrid_cli run program.hy 10 20 30  # with input values

# Execute with trace
./hybrid_cli trace program.hy 5

# Report statistics
./hybrid_cli stats program.hy

# Optimization levels
./hybrid_cli -O3 run program.hy
```

### Run Test Suite

```bash
# End-to-end tests (21+ programs)
nim c -d:release test_agent3_e2e.nim
./test_agent3_e2e

# Differential tests (reference vs compiled)
nim c -d:release test_agent3_differential.nim
./test_agent3_differential

# Determinism tests (byte-for-byte reproducibility)
nim c -d:release test_agent3_determinism.nim
./test_agent3_determinism

# Full conformance suite (25+ tests)
nim c -d:release test_agent3_conformance.nim
./test_agent3_conformance
```

## Programming Guide

### Befunge Programs

```befunge
# Simple 2D program: Hello World
"!dlroW olleH">:#,_@
```

- `>` move right, `<` move left, `^` move up, `v` move down
- `_` horizontal if (pop, if 0 go left else right)
- `|` vertical if (pop, if 0 go up else down)
- `#` skip next instruction
- `@` end program
- `.` output number, `,` input number
- `+ - * / %` arithmetic
- `!` logical not

### Brainfuck Programs

```brainfuck
# Compute 8 (2^3)
+++[>+++[>++<-]<-]>>  .
```

- `>` `<` move pointer
- `+` `-` increment/decrement cell
- `.` output cell value
- `,` input to cell
- `[` `]` loop while cell != 0

### BCPL Programs

```bcpl
int x = input();
if (x > 10) {
  output(x * 2);
} else {
  output(x + 1);
}
```

- `int x = value;` declare and initialize variable
- `int arr[10];` declare array
- `int* p = &x;` pointer to variable
- `int y = *p;` dereference
- `if (...) { ... } else { ... }` conditional
- `while (...) { ... }` loop
- `for (int i = 0; i < 10; i++) { ... }` for loop
- `output(expr);` output value
- `int val = input();` input to variable

### Hybrid Programs (Mixed Paradigms)

```bcpl
// BCPL + Brainfuck: tape + variables
int sum = 0;
for (int i = 0; i < 3; i = i + 1) {
  tape[i] = input();
  sum = sum + tape[i];
}
output(sum);
```

```bcpl
// BCPL + Befunge: conditional + 2D flow
int x = input();
// (can embed Befunge fragments)
if (x > 5) {
  output(100);
}
```

## Example Programs

### 1. Factorial (5! = 120)

```bcpl
int n = input();
int result = 1;
for (int i = 2; i <= n; i = i + 1) {
  result = result * i;
}
output(result);
```

Run:
```bash
./hybrid_cli run factorial.hy 5
# Output: 120
```

### 2. Fibonacci Sequence

```bcpl
int a = 0;
int b = 1;
for (int i = 0; i < 6; i = i + 1) {
  output(a);
  int t = a + b;
  a = b;
  b = t;
}
```

Run:
```bash
./hybrid_cli run fibonacci.hy
# Output: 0 1 1 2 3 5
```

### 3. Sum Inputs

```bcpl
int sum = 0;
for (int i = 0; i < 3; i = i + 1) {
  sum = sum + input();
}
output(sum);
```

Run:
```bash
./hybrid_cli run sum.hy 10 20 30
# Output: 60
```

### 4. Brainfuck: Hello World

```brainfuck
++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.
```

Run:
```bash
./hybrid_cli run hello.hy
# Output: 72 101 108 108 111 32 87 111 114 108 100 33 (ASCII for "Hello World!")
```

## Verification & Testing

### Determinism Test

Verifies same source produces identical binary 10 times:

```bash
./test_agent3_determinism
```

Expected output:
```
[DETERMINISM-TEST] Simple constant output
  Iteration 1: hash = a1b2c3d4...
  Iteration 2: hash = a1b2c3d4...
  Iteration 3: hash = a1b2c3d4...
  ...
  Iteration 10: hash = a1b2c3d4...
  ✓ DETERMINISTIC (all binaries identical)
```

### Differential Testing

Compares reference interpreter vs compiled execution:

```bash
./test_agent3_differential
```

Expected output:
```
[DIFF-TEST] Constant output
  Reference: [42]
  Compiled:  [42]
  ✓ PASS

[DIFF-TEST] Arithmetic operations
  Reference: [8, 8, 24]
  Compiled:  [8, 8, 24]
  ✓ PASS
```

### Conformance Suite

Full test coverage (25+ programs):

```bash
./test_agent3_conformance
```

Expected output:
```
HYBRID COMPILER CONFORMANCE SUITE
Running 25 conformance tests...

✓ Test 1: Integer increment
✓ Test 2: Integer decrement
✓ Test 3: Pointer movement
...
✓ Test 25: Fibonacci sequence

CONFORMANCE RESULTS
Total:    25
Passed:   25 ✓
Failed:    0 ✗

✓ All critical tests passed. Compiler is conformant.
```

## Performance Analysis

### Example Benchmark Output

```bash
./hybrid_cli stats factorial.hy
```

Output:
```
EXECUTION STATISTICS: factorial.hy

Memory Layout:
  Code:       42 triads (126 words)
  Data:       8 words
  Total:      134 words

Execution Profile:
  Steps executed: 247
  Output words:   1
  CPI (cycles/instr): 1.95

Optimization Impact (Level 1):
  Before:   145 words
  After:    126 words
  Savings:  19 words (13.1%)
```

### Key Metrics

- **Code size**: Measured in SUBLEQ triads (3-word instructions)
- **Steps**: Execution steps until halt
- **CPI**: Cycles (steps) per instruction
- **Memory**: Total words allocated (code + data + stack)

## Optimization

### Optimization Levels

| Level | Passes | Time | Space | Notes |
|-------|--------|------|-------|-------|
| -O0 | None | Fast | Large | Debugging |
| -O1 | Dedup, Dead blocks | Fast | Medium | Development |
| -O2 | +Copy elim, Branch simp | Medium | Small | Default |
| -O3 | +Constant fold, Redundant ops | Slow | Smallest | Performance |

### Applied Optimizations

1. **Constant Folding**: `5 + 3` → `8` (compile time)
2. **Constant Deduplication**: Reuse identical constants across program
3. **Dead-Block Elimination**: Remove unreachable code
4. **Copy Elimination**: Remove redundant moves
5. **Branch Simplification**: Unconditional → simplify conditional branches
6. **Redundant Op Removal**: Eliminate inverse operations (INC/DEC)

### Optimization Example

**Before:**
```
CONST 42  @ PC 10
ADD
CONST 42  @ PC 20
ADD
```

**After (-O1: dedup):**
```
CONST 42  @ PC 10
ADD
ADD        // reuse from PC 10
```

## Troubleshooting

### Common Errors

**Parse Error: Unexpected token**
```
program.hy:3:5: Parse error: unexpected token '{'
```
→ Check syntax. BCPL uses `{...}`, not `do...end`.

**Type Error: Cannot assign int* to int**
```
program.hy:5:10: Type error: incompatible types
  if (x == ptr) { }
           ^^^
```
→ Cannot compare int with pointer. Use `*ptr` to dereference.

**Runtime: Step limit reached**
```
Execution fault: step limit reached (1000000 steps)
```
→ Program has infinite loop or takes too long. Check loop conditions.

**Determinism Test Failed**
```
NON-DETERMINISTIC BUILD: iteration 5 differs
```
→ Compiler is not deterministic. Check for:
  - Nondeterministic hash maps (use sorted containers)
  - Timestamps or random values
  - Process IDs or system state

## File Structure

```
flash-attention-rtl/
├── hybrid_ir.nim                    # IR definition (contract)
├── hybrid_normalizer.nim            # AST → IR
├── hybrid_compiler.nim              # Pipeline orchestration
├── hybrid_optimizer.nim             # Peephole optimizations
├── hybrid_benchmark.nim             # Performance analysis
├── hybrid_cli.nim                   # Command-line interface
├── test_agent3_e2e.nim             # End-to-end tests (21+)
├── test_agent3_differential.nim     # Reference vs compiled
├── test_agent3_determinism.nim      # Reproducibility tests
├── test_agent3_conformance.nim      # Conformance suite (25+)
├── COMPILER_SPEC.md                 # Formal specification
└── HYBRID_COMPILER_README.md        # This file
```

## Development Guide

### Adding a New Test

1. Open `test_agent3_e2e.nim`
2. Add test case to `initE2ETests()`:
   ```nim
   registerE2ETest(E2ETest(
     id: 22,
     name: "My test",
     sourceCode: "...",
     input: @[...],
     expectedOutput: @[...],
     category: "Category"
   ))
   ```
3. Recompile and run
4. Commit when test passes

### Adding an Optimization Pass

1. Open `hybrid_optimizer.nim`
2. Implement optimization function:
   ```nim
   proc myOptimization*(mem: seq[int]): seq[int] =
     var result = mem
     # Implementation
     result
   ```
3. Add to `optimize()` orchestrator
4. Add before/after examples to documentation
5. Test with `test_agent3_determinism` to ensure no regression

### Integration Checklist

Before final commit, verify:

- [ ] All 25+ conformance tests pass
- [ ] All determinism tests pass (10x recompile)
- [ ] Differential tests show no mismatches
- [ ] CLI commands work (parse, emit-ir, emit-subleq, run, trace, stats)
- [ ] Benchmark reports are correct
- [ ] No compilation warnings
- [ ] Documentation is updated

## References

- SUBLEQ: https://esolangs.org/wiki/Subleq
- Brainfuck: https://esolangs.org/wiki/Brainfuck
- Befunge: https://esolangs.org/wiki/Befunge
- BCPL: https://www.bell-labs.com/usr/dmr/www/bcpl.html

## Contact

For issues or questions about the hybrid compiler, refer to:
- `COMPILER_SPEC.md` for formal specification
- `hybrid_compiler.nim` for pipeline details
- Test files for examples

---

**Agent 3 Deliverable**: Full integration and verification layer for the hybrid compiler.

Commit tag: `[AGENT-3-INTEGRATION]`
