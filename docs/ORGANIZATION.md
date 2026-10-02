# Flash Attention RTL - Repository Organization

## Overview

This document describes the reorganized directory structure of the Flash Attention RTL project after the three-agent optimization and consolidation effort.

## Directory Structure

### Root Directory (`/`)

The root directory contains:

- **consolidated_agent.nim** - Main executable implementing the consolidated SUBLEQ tactical agent
- **hybrid_cli.nim** - Command-line interface for the hybrid compiler
- **refuge.nim** - Reference implementation (legacy, from original RTL project)
- **subleq_bf.nim** (removed, now in `/src/`)
- **Documentation files**:
  - README.md - Main project documentation
  - AGENT3_INTEGRATION_REPORT.md - Agent 3 integration summary
  - AGENT3_FINAL_INTEGRATION.md - Final Agent 3 work summary
  - COMPILER_SPEC.md - Compiler specification
  - HYBRID_COMPILER_README.md - Hybrid compiler documentation
  - SIMULATION_SETUP.md - Simulation setup instructions

### Source Directory (`/src/`)

Core compiler and runtime components:

- **befunge_codegen.nim** - Befunge 2D language code generator
- **fa_model.nim** - Flash Attention model definitions
- **hybrid_ast.nim** - Abstract syntax tree definitions
- **hybrid_benchmark.nim** - Performance benchmarking utilities
- **hybrid_codegen.nim** - Code generation backend
- **hybrid_compiler.nim** - Orchestrator for lexer → parser → codegen pipeline
- **hybrid_ir.nim** - Intermediate representation
- **hybrid_lexer.nim** - Tokenization for hybrid languages
- **hybrid_normalizer.nim** - IR normalization
- **hybrid_optimizer.nim** - Code optimization passes
- **hybrid_parser.nim** - Parser for hybrid syntax
- **parser_pipeline.nim** - Complete front-end pipeline
- **subleq_bf.nim** - SUBLEQ interpreter + Brainfuck transpiler

### Tests Directory (`/tests/`)

Comprehensive test suite:

- **test_agent3_conformance.nim** - Final conformance test suite
- **test_agent3_determinism.nim** - Deterministic build verification
- **test_agent3_differential.nim** - Differential verification (reference vs compiled)
- **test_agent3_e2e.nim** - End-to-end tests (18+ test programs)
- **test_bf_to_subleq_j.nim** - Brainfuck transpilation tests
- **test_fa_opcode.nim** - Flash Attention opcode verification
- **test_hybrid_codegen.nim** - Code generator tests
- **test_hybrid_compiler.nim** - Full compiler pipeline tests
- **test_hybrid_frontend.nim** - Lexer/parser/AST tests

### Other Directories

- **/cstack/** - Call stack utilities
- **/rtl/** - Register transfer level implementations
- **/sim/** - Simulation infrastructure and test vectors
- **/software/** - Software utilities

## Import Paths

### Root-level files importing from `/src/`

```nim
import src/module_name
```

Example (consolidated_agent.nim):
```nim
import src/subleq_bf
```

### Test files importing from `/src/`

```nim
import ../src/module_name
```

Example (tests/test_agent3_e2e.nim):
```nim
import ../src/subleq_bf
import ../src/hybrid_compiler
```

### Internal imports within `/src/`

Modules within `/src/` import each other directly (same directory):
```nim
import module_name
```

Example (src/hybrid_compiler.nim):
```nim
import hybrid_ast
import hybrid_codegen
import subleq_bf
```

## Building

### Compile Root Executable

```bash
cd /home/user/flash-attention-rtl
nim c -d:release consolidated_agent.nim
nim c -d:release hybrid_cli.nim
```

### Compile Tests

```bash
cd /home/user/flash-attention-rtl/tests
nim c -d:release test_agent3_e2e.nim
nim c -d:release test_hybrid_compiler.nim
```

### Check Compilation (without building)

```bash
nim check consolidated_agent.nim
nim check tests/test_agent3_e2e.nim
```

## Module Relationships

### Three-Layer Architecture

1. **Frontend Layer** (`/src/hybrid_*.nim`):
   - hybrid_lexer.nim - Tokenization
   - hybrid_parser.nim - Parsing
   - hybrid_ast.nim - AST definitions
   - parser_pipeline.nim - Complete pipeline

2. **Intermediate Layer** (`/src/hybrid_*.nim`):
   - hybrid_ir.nim - IR representation
   - hybrid_normalizer.nim - IR normalization
   - hybrid_optimizer.nim - Optimization passes

3. **Codegen & Runtime** (`/src/*_codegen.nim`, `/src/subleq_bf.nim`):
   - hybrid_codegen.nim - Main code generator
   - befunge_codegen.nim - Befunge 2D support
   - subleq_bf.nim - SUBLEQ interpreter + Brainfuck transpiler

### Compilation Pipeline

```
Source Code
    ↓
hybrid_lexer → Tokens
    ↓
hybrid_parser → AST
    ↓
hybrid_normalizer → IR
    ↓
hybrid_optimizer → Optimized IR
    ↓
hybrid_codegen → SUBLEQ Machine Code
    ↓
subleq_bf.runSubleq → Execution
```

## Testing Strategy

### Test Categories

- **Conformance Tests**: Verify all features work correctly
- **Determinism Tests**: Ensure reproducible builds
- **Differential Tests**: Compare reference vs compiled execution
- **End-to-End Tests**: Full pipeline with 18+ test programs
- **Unit Tests**: Individual component verification

### Running Tests

```bash
cd /home/user/flash-attention-rtl/tests
nim c -d:release test_agent3_e2e.nim && ./test_agent3_e2e
nim c -d:release test_hybrid_compiler.nim && ./test_hybrid_compiler
```

## Import Validation

All imports have been verified to work correctly:

- Root files (consolidated_agent.nim, hybrid_cli.nim) import from `/src/`
- Test files import from `/src/` using `../src/` prefix
- Internal `/src/` imports work directly (same directory)
- No circular dependencies
- All modules compile without import errors

## Migration Notes

This organization was implemented by:
- **Agent A**: File reorganization and import path updates
- **Agent B**: Test integration and fix verification
- **Agent C**: Import validation and documentation

The reorganization maintains 100% backward compatibility with the compilation and test infrastructure while improving modularity and clarity of dependencies.
