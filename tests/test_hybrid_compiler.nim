# Comprehensive Hybrid Compiler Test Suite (Agent 3)
# 18+ deterministic test programs covering all feature categories
# Tests: Parse -> IR -> Codegen -> SUBLEQ VM -> Verify Output

import std/[strutils, sequtils, tables]
import subleq_bf

# ─────────────────────────────────────────────────────────────────────────
# TEST SUITE CATEGORIES
# ─────────────────────────────────────────────────────────────────────────

type
  TestCase* = object
    name*: string
    sourceCode*: string  # Source in hybrid language (from Agent 1)
    input*: seq[int]
    expectedOutput*: seq[int]
    category*: string
    description*: string

var testCases: seq[TestCase] = @[]
var passCount = 0
var failCount = 0

# ─────────────────────────────────────────────────────────────────────────
# TEST INFRASTRUCTURE
# ─────────────────────────────────────────────────────────────────────────

proc registerTest*(tc: TestCase) =
  testCases.add tc

proc runTest*(tc: TestCase; compileFn: proc(source: string): seq[int]): bool =
  ## Compile source, run in SUBLEQ VM, verify output
  echo "\n  TEST: ", tc.name, " [", tc.category, "]"
  echo "    Description: ", tc.description

  try:
    let subleqMem = compileFn(tc.sourceCode)
    if subleqMem.len == 0:
      echo "    FAIL: Compilation returned empty memory"
      inc failCount
      return false

    var mem = subleqMem
    let result = runSubleq(mem, tc.input, 1_000_000)

    if result.fault.len > 0:
      echo "    FAIL: Execution fault: ", result.fault
      inc failCount
      return false

    if not result.halted:
      echo "    FAIL: Program did not halt (step limit reached)"
      inc failCount
      return false

    if result.output != tc.expectedOutput:
      echo "    FAIL: Output mismatch"
      echo "      Expected: ", tc.expectedOutput
      echo "      Got:      ", result.output
      inc failCount
      return false

    echo "    PASS (", result.steps, " steps)"
    inc passCount
    return true

  except Exception as e:
    echo "    ERROR: ", e.msg
    inc failCount
    return false

# ─────────────────────────────────────────────────────────────────────────
# TEST CASES (18+ programs)
# ─────────────────────────────────────────────────────────────────────────

# Category 1: Basic I/O
proc initBasicIOTests* =
  registerTest(TestCase(
    name: "io_01_output_constant",
    sourceCode: "output(42);",
    input: @[],
    expectedOutput: @[42],
    category: "Basic I/O",
    description: "Output a single constant value"
  ))

  registerTest(TestCase(
    name: "io_02_output_sequence",
    sourceCode: "output(1); output(2); output(3);",
    input: @[],
    expectedOutput: @[1, 2, 3],
    category: "Basic I/O",
    description: "Output multiple constants in sequence"
  ))

  registerTest(TestCase(
    name: "io_03_input_single",
    sourceCode: "int x = input(); output(x);",
    input: @[99],
    expectedOutput: @[99],
    category: "Basic I/O",
    description: "Read single input and output it"
  ))

  registerTest(TestCase(
    name: "io_04_input_sequence",
    sourceCode: "output(input()); output(input()); output(input());",
    input: @[10, 20, 30],
    expectedOutput: @[10, 20, 30],
    category: "Basic I/O",
    description: "Read and output multiple inputs"
  ))

  registerTest(TestCase(
    name: "io_05_empty_input",
    sourceCode: "int x = input(); int y = input(); output(x); output(y);",
    input: @[],
    expectedOutput: @[0, 0],
    category: "Basic I/O",
    description: "Input returns 0 when exhausted"
  ))

# Category 2: Stack Operations (via variable assignments)
proc initStackTests* =
  registerTest(TestCase(
    name: "stack_01_variable_assign",
    sourceCode: "int x = 5; output(x);",
    input: @[],
    expectedOutput: @[5],
    category: "Stack Operations",
    description: "Basic variable assignment and output"
  ))

  registerTest(TestCase(
    name: "stack_02_multiple_vars",
    sourceCode: "int x = 10; int y = 20; output(x); output(y);",
    input: @[],
    expectedOutput: @[10, 20],
    category: "Stack Operations",
    description: "Multiple variable declarations and output"
  ))

  registerTest(TestCase(
    name: "stack_03_swap_values",
    sourceCode: "int a = 1; int b = 2; int t = a; a = b; b = t; output(a); output(b);",
    input: @[],
    expectedOutput: @[2, 1],
    category: "Stack Operations",
    description: "Swap two variables using temporary"
  ))

# Category 3: Arithmetic Operations
proc initArithmeticTests* =
  registerTest(TestCase(
    name: "arith_01_add",
    sourceCode: "output(3 + 4);",
    input: @[],
    expectedOutput: @[7],
    category: "Arithmetic",
    description: "Integer addition"
  ))

  registerTest(TestCase(
    name: "arith_02_subtract",
    sourceCode: "output(10 - 3);",
    input: @[],
    expectedOutput: @[7],
    category: "Arithmetic",
    description: "Integer subtraction"
  ))

  registerTest(TestCase(
    name: "arith_03_multiply",
    sourceCode: "output(4 * 5);",
    input: @[],
    expectedOutput: @[20],
    category: "Arithmetic",
    description: "Integer multiplication"
  ))

  registerTest(TestCase(
    name: "arith_04_divide",
    sourceCode: "output(20 / 4);",
    input: @[],
    expectedOutput: @[5],
    category: "Arithmetic",
    description: "Integer division"
  ))

  registerTest(TestCase(
    name: "arith_05_modulo",
    sourceCode: "output(17 % 5);",
    input: @[],
    expectedOutput: @[2],
    category: "Arithmetic",
    description: "Modulo operation"
  ))

  registerTest(TestCase(
    name: "arith_06_negative",
    sourceCode: "output(-5); output(-(-10));",
    input: @[],
    expectedOutput: @[-5, 10],
    category: "Arithmetic",
    description: "Negative numbers and negation"
  ))

  registerTest(TestCase(
    name: "arith_07_chain_ops",
    sourceCode: "output(2 + 3 * 4 - 1);",
    input: @[],
    expectedOutput: @[13],
    category: "Arithmetic",
    description: "Chained arithmetic with precedence"
  ))

# Category 4: Comparisons and Logic
proc initComparisonTests* =
  registerTest(TestCase(
    name: "cmp_01_greater_than",
    sourceCode: "output(5 > 3 ? 1 : 0); output(3 > 5 ? 1 : 0);",
    input: @[],
    expectedOutput: @[1, 0],
    category: "Comparisons",
    description: "Greater-than comparison"
  ))

  registerTest(TestCase(
    name: "cmp_02_less_than",
    sourceCode: "output(3 < 5 ? 1 : 0); output(5 < 3 ? 1 : 0);",
    input: @[],
    expectedOutput: @[1, 0],
    category: "Comparisons",
    description: "Less-than comparison"
  ))

  registerTest(TestCase(
    name: "cmp_03_equality",
    sourceCode: "output(5 == 5 ? 1 : 0); output(5 == 3 ? 1 : 0);",
    input: @[],
    expectedOutput: @[1, 0],
    category: "Comparisons",
    description: "Equality comparison"
  ))

  registerTest(TestCase(
    name: "cmp_04_logical_not",
    sourceCode: "output(!1); output(!0);",
    input: @[],
    expectedOutput: @[0, 1],
    category: "Comparisons",
    description: "Logical NOT operator"
  ))

# Category 5: Control Flow - Conditionals
proc initConditionalTests* =
  registerTest(TestCase(
    name: "ctl_01_if_true",
    sourceCode: "if (1) { output(10); } output(20);",
    input: @[],
    expectedOutput: @[10, 20],
    category: "Control Flow",
    description: "If statement with true condition"
  ))

  registerTest(TestCase(
    name: "ctl_02_if_false",
    sourceCode: "if (0) { output(10); } output(20);",
    input: @[],
    expectedOutput: @[20],
    category: "Control Flow",
    description: "If statement with false condition"
  ))

  registerTest(TestCase(
    name: "ctl_03_if_else",
    sourceCode: "if (1) { output(10); } else { output(20); } output(30);",
    input: @[],
    expectedOutput: @[10, 30],
    category: "Control Flow",
    description: "If-else statement"
  ))

  registerTest(TestCase(
    name: "ctl_04_if_input_driven",
    sourceCode: "if (input()) { output(100); } else { output(200); }",
    input: @[1],
    expectedOutput: @[100],
    category: "Control Flow",
    description: "If-else driven by input"
  ))

# Category 6: Control Flow - Loops
proc initLoopTests* =
  registerTest(TestCase(
    name: "loop_01_while_countdown",
    sourceCode: "int i = 3; while (i > 0) { output(i); i = i - 1; }",
    input: @[],
    expectedOutput: @[3, 2, 1],
    category: "Loops",
    description: "While loop counting down"
  ))

  registerTest(TestCase(
    name: "loop_02_while_zero",
    sourceCode: "int i = 0; while (i > 0) { output(i); } output(99);",
    input: @[],
    expectedOutput: @[99],
    category: "Loops",
    description: "While loop that doesn't execute"
  ))

  registerTest(TestCase(
    name: "loop_03_for_count",
    sourceCode: "for (int i = 1; i <= 3; i = i + 1) { output(i); }",
    input: @[],
    expectedOutput: @[1, 2, 3],
    category: "Loops",
    description: "For loop counting up"
  ))

  registerTest(TestCase(
    name: "loop_04_nested_loops",
    sourceCode: "for (int i = 1; i <= 2; i = i + 1) { for (int j = 1; j <= 2; j = j + 1) { output(i * 10 + j); } }",
    input: @[],
    expectedOutput: @[11, 12, 21, 22],
    category: "Loops",
    description: "Nested loops"
  ))

# Category 7: Pointer/Tape Operations (Befunge-style)
proc initPointerTests* =
  registerTest(TestCase(
    name: "ptr_01_tape_write_read",
    sourceCode: "tape[0] = 42; output(tape[0]);",
    input: @[],
    expectedOutput: @[42],
    category: "Pointer Operations",
    description: "Write to tape and read back"
  ))

  registerTest(TestCase(
    name: "ptr_02_tape_indexed",
    sourceCode: "int idx = 2; tape[idx] = 55; output(tape[2]);",
    input: @[],
    expectedOutput: @[55],
    category: "Pointer Operations",
    description: "Indexed tape access"
  ))

  registerTest(TestCase(
    name: "ptr_03_tape_loop",
    sourceCode: "for (int i = 0; i < 3; i = i + 1) { tape[i] = i * 10; } for (int i = 0; i < 3; i = i + 1) { output(tape[i]); }",
    input: @[],
    expectedOutput: @[0, 10, 20],
    category: "Pointer Operations",
    description: "Tape array in loops"
  ))

# Category 8: Variable Declarations and Memory Regions
proc initMemoryTests* =
  registerTest(TestCase(
    name: "mem_01_global_var",
    sourceCode: "int global_x = 42; output(global_x);",
    input: @[],
    expectedOutput: @[42],
    category: "Memory",
    description: "Global variable declaration"
  ))

  registerTest(TestCase(
    name: "mem_02_array_vars",
    sourceCode: "int arr[4]; arr[0] = 10; arr[1] = 20; output(arr[0]); output(arr[1]);",
    input: @[],
    expectedOutput: @[10, 20],
    category: "Memory",
    description: "Array variable declaration"
  ))

# Category 9: Edge Cases and Complex Programs
proc initEdgeCaseTests* =
  registerTest(TestCase(
    name: "edge_01_zero_values",
    sourceCode: "int x = 0; output(x); output(x + 0); output(0 * 100);",
    input: @[],
    expectedOutput: @[0, 0, 0],
    category: "Edge Cases",
    description: "Program with only zero values"
  ))

  registerTest(TestCase(
    name: "edge_02_large_values",
    sourceCode: "output(1000000); output(999999);",
    input: @[],
    expectedOutput: @[1000000, 999999],
    category: "Edge Cases",
    description: "Large integer values"
  ))

  registerTest(TestCase(
    name: "edge_03_negative_arithmetic",
    sourceCode: "int x = -10; int y = -5; output(x + y); output(x - y); output(x * y);",
    input: @[],
    expectedOutput: @[-15, -5, 50],
    category: "Edge Cases",
    description: "Negative number arithmetic"
  ))

  registerTest(TestCase(
    name: "complex_01_factorial",
    sourceCode: "int n = input(); int result = 1; for (int i = 2; i <= n; i = i + 1) { result = result * i; } output(result);",
    input: @[5],
    expectedOutput: @[120],
    category: "Complex Programs",
    description: "Factorial computation (5! = 120)"
  ))

  registerTest(TestCase(
    name: "complex_02_fibonacci",
    sourceCode: "int a = 0; int b = 1; for (int i = 0; i < 6; i = i + 1) { output(a); int t = a + b; a = b; b = t; }",
    input: @[],
    expectedOutput: @[0, 1, 1, 2, 3, 5],
    category: "Complex Programs",
    description: "First 6 Fibonacci numbers"
  ))

  registerTest(TestCase(
    name: "complex_03_sum_inputs",
    sourceCode: "int sum = 0; for (int i = 0; i < 3; i = i + 1) { sum = sum + input(); } output(sum);",
    input: @[10, 20, 30],
    expectedOutput: @[60],
    category: "Complex Programs",
    description: "Sum of 3 input values"
  ))

# ─────────────────────────────────────────────────────────────────────────
# PLACEHOLDER COMPILER (to be replaced by Agent 1 + Agent 2)
# ─────────────────────────────────────────────────────────────────────────

proc placeholderCompile*(source: string): seq[int] =
  # This is a placeholder. Agent 1 parses source -> IR.
  # Agent 2 codegen: IR -> SUBLEQ memory image.
  # This will be replaced by actual compilation pipeline.
  @[]  # Return empty to signal not yet implemented

# ─────────────────────────────────────────────────────────────────────────
# MAIN TEST RUNNER
# ─────────────────────────────────────────────────────────────────────────

proc runAllTests* =
  echo "════════════════════════════════════════════════════════════"
  echo "Hybrid Compiler Test Suite (Agent 3 - Test & Verification)"
  echo "════════════════════════════════════════════════════════════"

  # Initialize all test categories
  initBasicIOTests()
  initStackTests()
  initArithmeticTests()
  initComparisonTests()
  initConditionalTests()
  initLoopTests()
  initPointerTests()
  initMemoryTests()
  initEdgeCaseTests()

  echo "\nTotal tests registered: ", testCases.len
  echo "\nRunning tests...\n"

  var categoryStats: Table[string, (int, int)] = initTable[string, (int, int)]()

  for tc in testCases:
    let passed = runTest(tc, placeholderCompile)
    if tc.category notin categoryStats:
      categoryStats[tc.category] = (0, 0)
    let (p, f) = categoryStats[tc.category]
    if passed:
      categoryStats[tc.category] = (p + 1, f)
    else:
      categoryStats[tc.category] = (p, f + 1)

  # Summary
  echo "\n════════════════════════════════════════════════════════════"
  echo "SUMMARY BY CATEGORY:"
  echo "────────────────────────────────────────────────────────────"
  for category in sorted(toSeq(categoryStats.keys)):
    let (p, f) = categoryStats[category]
    echo "  ", category, ": ", p, " passed, ", f, " failed"

  echo "────────────────────────────────────────────────────────────"
  echo "TOTAL: ", passCount, " passed, ", failCount, " failed"
  echo "════════════════════════════════════════════════════════════"

  if failCount > 0:
    quit 1

when isMainModule:
  runAllTests()
