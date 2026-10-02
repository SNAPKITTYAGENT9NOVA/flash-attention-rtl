# Hybrid Compiler Specification

## Overview

The Hybrid Compiler unifies three programming paradigms into a single compilation pipeline:

1. **Befunge** - 2D stack-based control flow
2. **Brainfuck** - Linear tape-based memory model
3. **BCPL** - Imperative language with typed variables and pointers

The compiler architecture ensures **deterministic compilation**, **semantic correctness**, and **full verification** through differential testing.

## Architecture

### Pipeline

```
SOURCE CODE
    ↓
[AGENT 1: LEXER/PARSER]
    ↓
AST (Abstract Syntax Tree) + CFG (Control Flow Graph)
    ↓
[AGENT 3: IR NORMALIZER]
    ↓
IR (Normalized Intermediate Representation)
    ↓
[AGENT 2: CODEGEN + LOWERING]
    ↓
SUBLEQ MACHINE CODE (3-operand format)
    ↓
[OPTIMIZATION PASSES]
    ↓
OPTIMIZED SUBLEQ BINARY
    ↓
SUBLEQ VM EXECUTION
    ↓
OUTPUT + FINAL STATE
```

### Key Properties

- **Deterministic**: Same source always produces identical binary
- **Verifiable**: Each stage produces testable intermediate forms
- **Debuggable**: Full source location tracking in all diagnostics
- **Optimizable**: Semantic-preserving peephole optimization passes
- **Portable**: Compiles to SUBLEQ, an ISA with no system dependencies

## Intermediate Representation (IR)

### IR Node Types

```nim
type IRExpr = ref object
  case kind: string
  of "lit":       litValue: int
  of "var":       varName: string; varId: int
  of "binop":     binOp: BinaryOp; left, right: IRExpr
  of "unop":      unOp: UnaryOp; operand: IRExpr
  of "call":      funcName: string; args: seq[IRExpr]
  of "index":     arrayExpr: IRExpr; indexExpr: IRExpr

type IRStmt = ref object
  case kind: string
  of "assign":    assignTarget: string; assignValue: IRExpr
  of "output":    outputExpr: IRExpr
  of "input":     inputTarget: string
  of "if":        condition: IRExpr; thenBranch, elseBranch: seq[IRStmt]
  of "while":     whileCondition: IRExpr; whileBody: seq[IRStmt]
  of "for":       forVar: string; forStart, forEnd: IRExpr; forBody: seq[IRStmt]
  of "memset":    memAddr, memValue, memSize: IRExpr
  of "pointerMove": pointerDelta: int
```

### IR Properties

- **Normalized**: Variables sorted, memory layout deterministic
- **SSA-like**: Single assignment form (assignments are statements, not expressions)
- **Type-aware**: Carries type information from source
- **Location-aware**: Preserves source line/column for error reporting
- **Expressible**: Can represent any valid Befunge, Brainfuck, or BCPL program

## SUBLEQ Machine Code

### Instruction Format

```
[a, b, c]  → mem[b] -= mem[a];  if (mem[b] <= 0) pc = c else pc += 3
```

### Special Operands

| Value | Meaning |
|-------|---------|
| a = -1 | Read input into mem[b] |
| a = -2 | FlashAttention trap (extended opcode) |
| b < 0 | Output mem[a] to stdout |
| c < 0 | Halt execution |

### Memory Layout

```
[0..2]      Entry point (mem[0] is constant 0)
[3..4]      Constants (+1, -1)
[5..8]      Pointer, negated pointer, scratch cells
[9..]       Compiled code (triads)
[codeEnd..] Data and tape (Brainfuck cell array)
```

## Compilation Process

### Stage 1: Parsing (Agent 1)

- Lexical analysis: tokenize source
- Syntax analysis: build AST
- Semantic analysis: type checking, symbol resolution
- Output: AST + CFG + error/warning list

### Stage 2: IR Normalization (Agent 3)

- Convert AST to normalized IR form
- Sort all sequences for determinism
- Deduplicate constants
- Standardize variable names (g_0, g_1, ...)
- Validate IR structure
- Output: Normalized IR program

### Stage 3: Codegen (Agent 2)

- Lower IR to SUBLEQ instructions
- Allocate memory for variables, arrays, stack
- Generate indirect addressing sequences (for pointer operations)
- Handle control flow (branches, loops) via conditional jumps
- Output: SUBLEQ memory image

### Stage 4: Optimization

Semantic-preserving optimizations:

1. **Constant folding**: Evaluate constants at compile time
2. **Constant deduplication**: Reuse identical constants
3. **Dead-block elimination**: Remove unreachable code
4. **Copy elimination**: Remove redundant moves
5. **Branch simplification**: Simplify conditional branches
6. **Redundant op removal**: Eliminate inverse operations

### Stage 5: Verification

- Check binary is valid (all jumps in range, no uninitialized reads)
- Run differential tests (reference vs compiled)
- Verify determinism (10x recompile, all identical)
- Benchmark execution (code size, step count, memory)

## Source Language

### Befunge (2D Control)

```befunge
> < ^ v    Direction change
# _       Conditional (vertical/horizontal)
!         Logical not
+ - * / % Arithmetic (pop b, pop a, push a op b)
. ,       Output number, input number
"..."     String push
[ ]       Loop (zero test)
@         End program
```

### Brainfuck (Linear Tape)

```brainfuck
> <       Move pointer right/left
+ -       Increment/decrement cell
. ,       Output cell, input to cell
[ ]       Loop (while cell != 0)
```

### BCPL (Imperative)

```bcpl
int x = 5;                    // Variable declaration
int arr[10];                  // Array declaration
if (x > 0) { ... }           // Conditional
while (x > 0) { ... }        // Loop
for (int i = 0; i < 10; i++) { ... }  // For loop
output(x);                    // Output expression
int y = input();              // Input into variable
int* p = &x;                 // Pointer
int z = *p;                  // Dereference
```

## Testing Strategy

### 1. Unit Tests (Blocks 02-07)

- **E2E Tests**: 21+ programs covering all features
- **Differential Tests**: Reference vs compiled execution
- **Determinism Tests**: Byte-for-byte reproducibility
- **Conformance Tests**: 25+ comprehensive test cases
- **Optimization Tests**: Before/after semantics

### 2. Property-Based Tests

- **Determinism**: Same source → identical binary (10x recompile)
- **Correctness**: Output matches reference interpreter
- **Memory safety**: No out-of-bounds access
- **Halting**: Program terminates within step limit

### 3. Regression Tests

- **Standard benchmark programs**
- **Edge cases**: zero, negatives, large values
- **Complex programs**: factorial, Fibonacci, sorting
- **Hybrid programs**: mixing all three paradigms

## Error Handling

**Rule**: No intermediate step fails silently.

All errors report:
- Source file and location (line:column)
- Error category (parse, type, runtime)
- Diagnostic message
- Example of correct usage (when applicable)

Example:
```
test.hy:5:10: Type error: cannot assign int* to int
  if (x == ptr) { }  // error: comparing int with pointer
           ^^^
```

## Optimization Levels

| Level | Passes | Use Case |
|-------|--------|----------|
| -O0 | None | Debugging (preserve source structure) |
| -O1 | Dedup, Dead blocks | Development (fast compile) |
| -O2 | +Copy elim, Branch simp | Production (balanced) |
| -O3 | +Constant fold, Redundant ops | Performance-critical |

## Performance Metrics

For each compiled program, report:

```
Code size:    X triads (Y words)
Data size:    Z words
Total memory: A words
Steps:        B
CPI:          B/A (cycles per instruction)
```

## Deliverables (Agent 3)

1. `hybrid_compiler.nim` — Main pipeline and API
2. `hybrid_normalizer.nim` — AST → IR normalization
3. `test_agent3_e2e.nim` — 21+ end-to-end tests
4. `test_agent3_differential.nim` — Reference vs compiled
5. `test_agent3_determinism.nim` — Reproducibility
6. `hybrid_optimizer.nim` — Peephole optimization passes
7. `hybrid_benchmark.nim` — Performance analysis
8. `hybrid_cli.nim` — CLI interface
9. `test_agent3_conformance.nim` — 25+ conformance tests
10. `COMPILER_SPEC.md` — This document
11. `README.md` — Usage and architecture guide

## Integration Steps

1. **Agent 1 commits**: Lexer/parser with `[AGENT-1-PARSER]` tag
2. **Agent 2 commits**: Codegen backend with `[AGENT-2-CODEGEN]` tag
3. **Agent 3 integrates**: Links all three, runs test suite
4. **If tests fail**: Iterate with agents on fixes
5. **Final commit**: `[AGENT-3-INTEGRATION]` tag when all tests pass

## Quality Assurance

### Pre-Commit Checks

- [ ] All 25+ conformance tests pass
- [ ] All 10+ determinism iterations match
- [ ] Differential tests show no output mismatches
- [ ] No stack overflow or memory corruption
- [ ] CLI commands work for all test files
- [ ] Performance benchmarks recorded

### Code Quality

- [ ] No compiler warnings
- [ ] Code follows project style
- [ ] Comments for complex algorithms
- [ ] No dead code
- [ ] Clean git history (meaningful commits)

## References

- SUBLEQ: https://esolangs.org/wiki/Subleq
- Brainfuck: https://esolangs.org/wiki/Brainfuck
- Befunge: https://esolangs.org/wiki/Befunge
- BCPL: https://www.bell-labs.com/usr/dmr/www/bcpl.html
