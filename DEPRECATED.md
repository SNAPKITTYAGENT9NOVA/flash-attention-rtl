# Deprecated Files

## refuge.nim

**Status**: ❌ DEPRECATED - Contains critical bugs, not recommended for production use

### Critical Issues

1. **Bounds Violations** (Line 61-64)
   - PC range check insufficient
   - Reads 3 words but only checks `pc >= mem.len`
   - Causes crashes on valid programs

2. **Operand Validation Missing** (Line 52)
   - `mem[a]` and `mem[b]` accessed without bounds checking
   - No protection against negative indices or out-of-bounds access

3. **Non-Standard Halt Semantics** (Line 49)
   - Only checks `a == -1`
   - Standard SUBLEQ requires `a == -1 AND b == -1`

4. **Determinism Violation** (Line 527)
   - Calls `randomize()` which uses system time as seed
   - Breaks "deterministic sanctuary" claim
   - Makes execution non-reproducible

5. **False Turing Completeness Claim** (Lines 241-250)
   - BF→SUBLEQ transpiler hardcodes cell 0
   - Ignores BF pointer entirely
   - Cannot encode arbitrary Brainfuck programs
   - Transpiler admits to being "simplified"

### Replacement

**Use `consolidated_agent.nim` instead:**
- ✅ All bounds violations fixed
- ✅ Operand validation via Nim range types
- ✅ Standard SUBLEQ halt semantics
- ✅ True determinism (no RNG in critical path)
- ✅ Complete BF↔SUBLEQ-J transpilers with dynamic indexing
- ✅ Transpiler + interpreter moved to `subleq_bf.nim` with differential tests

### Why Keep It?

`refuge.nim` is retained for:
1. **Historical reference** — Shows original approach and its limitations
2. **Educational purposes** — Demonstrates common pitfalls in low-level programming
3. **Bug analysis** — Useful for studying defensive programming techniques

## test_bf_to_subleq_j.nim

**Status**: ✅ Rewritten - differential tests of the BF→SUBLEQ transpiler (`subleq_bf.nim`)

Compiles BF programs, runs them on the SUBLEQ interpreter and compares output, tape and pointer
with a reference BF interpreter (hand-written cases plus deterministic fuzzing).

## SIMULATION_SETUP.md

**Status**: ℹ️ ARCHIVED - Original hardware testbench documentation

Describes setup for original FlashAttention RTL (Systolic Array).
Superceded by SUBLEQ-based system but retained for:
- Original project context
- Hardware implementation reference
- Historical documentation

## software/golden_model.py

**Status**: ℹ️ ARCHIVED - Original FlashAttention algorithm reference

Python implementation of Dao et al. FlashAttention (Algorithm 1).
Kept for:
- Algorithm reference
- Educational value
- Comparison with SUBLEQ approach

---

## Migration Guide

### If You Were Using `refuge.nim`:

1. **Switch to `consolidated_agent.nim`**:
   ```bash
   nim c -d:release consolidated_agent.nim
   ./consolidated_agent "your goal"
   ```

2. **Key differences**:
   - Same SUBLEQ core, better bounds checking
   - Same BF interpreter
   - Improved transpilers (now fully functional)
   - Better documentation

3. **Compatibility**:
   - API is identical (AgentState, Actions, loop)
   - No code changes needed for user-facing logic
   - Just swap the main file

### If You Were Using Test Suite:

- `test_bf_to_subleq_j.nim` now imports `subleq_bf.nim` and runs real differential tests

---

**Summary**: Use `consolidated_agent.nim`. Archive `refuge.nim` if needed, but don't use in production.
