# BLOCK 02: End-to-End Tests (18+ programs)
# Tests for hybrid language combining Befunge, Brainfuck, and BCPL
# Critical: all tests flow through: SOURCE → AGENT1 → AGENT3 → AGENT2 → VM

import std/[strutils, tables, algorithm, sequtils]
import subleq_bf
import hybrid_compiler

type
  E2ETest* = object
    id*: int
    name*: string
    description*: string
    sourceCode*: string
    input*: seq[int]
    expectedOutput*: seq[int]
    expectedMemory*: Table[int, int]  # optional
    expectedPtr*: int  # optional (-1 = don't check)
    category*: string

var testSuite: seq[E2ETest] = @[]
var passCount = 0
var failCount = 0

# ─────────────────────────────────────────────────────────────────────────
# TEST INFRASTRUCTURE
# ─────────────────────────────────────────────────────────────────────────

proc registerE2ETest*(test: E2ETest) =
  testSuite.add test

proc runE2ETest*(test: E2ETest; compileFn: proc(source: string): seq[int]): bool =
  echo "\n[TEST ", test.id, "] ", test.name, " (", test.category, ")"
  echo "  Description: ", test.description

  try:
    let subleqMem = compileFn(test.sourceCode)
    if subleqMem.len == 0:
      echo "  ✗ FAIL: Compilation returned empty memory"
      inc failCount
      return false

    var mem = subleqMem
    let result = runSubleq(mem, test.input, 1_000_000)

    if result.fault.len > 0:
      echo "  ✗ FAIL: Execution fault: ", result.fault
      inc failCount
      return false

    if not result.halted:
      echo "  ✗ FAIL: Program did not halt"
      inc failCount
      return false

    if result.output != test.expectedOutput:
      echo "  ✗ FAIL: Output mismatch"
      echo "    Expected: ", test.expectedOutput
      echo "    Got:      ", result.output
      inc failCount
      return false

    echo "  ✓ PASS (", result.steps, " steps)"
    inc passCount
    return true

  except Exception as e:
    echo "  ✗ ERROR: ", e.msg
    inc failCount
    return false

# ─────────────────────────────────────────────────────────────────────────
# 18+ END-TO-END TEST CASES
# ─────────────────────────────────────────────────────────────────────────

proc initE2ETests* =
  # TEST 1: Integer increment
  registerE2ETest(E2ETest(
    id: 1,
    name: "Integer increment",
    description: "Basic increment operation (+)",
    sourceCode: "int x = 5; x = x + 1; output(x);",
    input: @[],
    expectedOutput: @[6],
    category: "Arithmetic"
  ))

  # TEST 2: Integer decrement
  registerE2ETest(E2ETest(
    id: 2,
    name: "Integer decrement",
    description: "Basic decrement operation (-)",
    sourceCode: "int x = 10; x = x - 1; output(x);",
    input: @[],
    expectedOutput: @[9],
    category: "Arithmetic"
  ))

  # TEST 3: Pointer movement
  registerE2ETest(E2ETest(
    id: 3,
    name: "Pointer movement",
    description: "Move pointer in tape (>, <)",
    sourceCode: "tape[0] = 10; tape[1] = 20; output(tape[0]); output(tape[1]);",
    input: @[],
    expectedOutput: @[10, 20],
    category: "Pointer/Tape"
  ))

  # TEST 4: Memory load
  registerE2ETest(E2ETest(
    id: 4,
    name: "Memory load",
    description: "Load value from memory (BCPL LOAD)",
    sourceCode: "int x = 42; int y = x; output(y);",
    input: @[],
    expectedOutput: @[42],
    category: "Memory"
  ))

  # TEST 5: Memory store
  registerE2ETest(E2ETest(
    id: 5,
    name: "Memory store",
    description: "Store value to memory (BCPL STORE)",
    sourceCode: "int x = 0; x = 99; output(x);",
    input: @[],
    expectedOutput: @[99],
    category: "Memory"
  ))

  # TEST 6: Indirect load
  registerE2ETest(E2ETest(
    id: 6,
    name: "Indirect load",
    description: "Load from address (BCPL LOAD_INDIRECT)",
    sourceCode: "int data[3]; data[0] = 100; int ptr = 0; output(data[ptr]);",
    input: @[],
    expectedOutput: @[100],
    category: "Memory"
  ))

  # TEST 7: Indirect store
  registerE2ETest(E2ETest(
    id: 7,
    name: "Indirect store",
    description: "Store to address (BCPL STORE_INDIRECT)",
    sourceCode: "int data[3]; int ptr = 1; data[ptr] = 77; output(data[1]);",
    input: @[],
    expectedOutput: @[77],
    category: "Memory"
  ))

  # TEST 8: Zero test
  registerE2ETest(E2ETest(
    id: 8,
    name: "Zero test",
    description: "Test if value is zero ([...] semantics)",
    sourceCode: "int x = 0; if (x == 0) { output(1); } else { output(0); }",
    input: @[],
    expectedOutput: @[1],
    category: "Conditionals"
  ))

  # TEST 9: Conditional branch
  registerE2ETest(E2ETest(
    id: 9,
    name: "Conditional branch",
    description: "Branch on condition (_ or | semantics)",
    sourceCode: "int x = input(); if (x > 5) { output(10); } else { output(20); }",
    input: @[7],
    expectedOutput: @[10],
    category: "Conditionals"
  ))

  # TEST 10: Simple loop
  registerE2ETest(E2ETest(
    id: 10,
    name: "Simple loop",
    description: "Loop construct ([...] with decrement)",
    sourceCode: "int i = 3; while (i > 0) { output(i); i = i - 1; }",
    input: @[],
    expectedOutput: @[3, 2, 1],
    category: "Loops"
  ))

  # TEST 11: Nested loop
  registerE2ETest(E2ETest(
    id: 11,
    name: "Nested loop",
    description: "Nested loop constructs ([[...][...]])",
    sourceCode: "for (int i = 1; i <= 2; i = i + 1) { for (int j = 1; j <= 2; j = j + 1) { output(i * 10 + j); } }",
    input: @[],
    expectedOutput: @[11, 12, 21, 22],
    category: "Loops"
  ))

  # TEST 12: Brainfuck program
  registerE2ETest(E2ETest(
    id: 12,
    name: "Brainfuck program",
    description: "Full Brainfuck program (++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.)",
    sourceCode: "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.",
    input: @[],
    expectedOutput: @[72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 33],  # "Hello World!"
    category: "Befunge"
  ))

  # TEST 13: Befunge direction changes
  registerE2ETest(E2ETest(
    id: 13,
    name: "Befunge direction changes",
    description: "2D control flow with > < ^ v",
    sourceCode: ">:#,_@",
    input: @[65],
    expectedOutput: @[65],
    category: "Befunge"
  ))

  # TEST 14: Befunge conditional
  registerE2ETest(E2ETest(
    id: 14,
    name: "Befunge conditional",
    description: "Befunge conditional branch (_ or |)",
    sourceCode: "5_@#,_@",
    input: @[],
    expectedOutput: @[],
    category: "Befunge"
  ))

  # TEST 15: BCPL pointer operation
  registerE2ETest(E2ETest(
    id: 15,
    name: "BCPL pointer operation",
    description: "Address-of and dereference",
    sourceCode: "int x = 42; int* p = &x; output(*p);",
    input: @[],
    expectedOutput: @[42],
    category: "BCPL"
  ))

  # TEST 16: Mixed BF + BCPL
  registerE2ETest(E2ETest(
    id: 16,
    name: "Mixed BF + BCPL",
    description: "Tape operations with BCPL variables",
    sourceCode: "int x = 10; tape[0] = x; output(tape[0]); int y = input(); tape[1] = y; output(tape[1]);",
    input: @[20],
    expectedOutput: @[10, 20],
    category: "Hybrid"
  ))

  # TEST 17: Mixed Befunge + BF
  registerE2ETest(E2ETest(
    id: 17,
    name: "Mixed Befunge + BF",
    description: "2D control flow with tape operations",
    sourceCode: "+++[>+++<-]>.",
    input: @[],
    expectedOutput: @[9],
    category: "Hybrid"
  ))

  # TEST 18: Full hybrid program
  registerE2ETest(E2ETest(
    id: 18,
    name: "Full hybrid program",
    description: "All three paradigms combined",
    sourceCode: "int sum = 0; for (int i = 0; i < 3; i = i + 1) { tape[i] = input(); sum = sum + tape[i]; } output(sum);",
    input: @[1, 2, 3],
    expectedOutput: @[6],
    category: "Hybrid"
  ))

  # ADDITIONAL TESTS

  # TEST 19: Complex arithmetic with precedence
  registerE2ETest(E2ETest(
    id: 19,
    name: "Complex arithmetic",
    description: "Multi-operation with correct precedence",
    sourceCode: "output(2 + 3 * 4 - 5);",
    input: @[],
    expectedOutput: @[9],
    category: "Arithmetic"
  ))

  # TEST 20: Factorial
  registerE2ETest(E2ETest(
    id: 20,
    name: "Factorial",
    description: "Factorial computation (5! = 120)",
    sourceCode: "int n = input(); int result = 1; for (int i = 2; i <= n; i = i + 1) { result = result * i; } output(result);",
    input: @[5],
    expectedOutput: @[120],
    category: "Algorithms"
  ))

  # TEST 21: Fibonacci
  registerE2ETest(E2ETest(
    id: 21,
    name: "Fibonacci sequence",
    description: "First 6 Fibonacci numbers",
    sourceCode: "int a = 0; int b = 1; for (int i = 0; i < 6; i = i + 1) { output(a); int t = a + b; a = b; b = t; }",
    input: @[],
    expectedOutput: @[0, 1, 1, 2, 3, 5],
    category: "Algorithms"
  ))

# ─────────────────────────────────────────────────────────────────────────
# PLACEHOLDER COMPILER (to be replaced by Agent 1 + Agent 2)
# ─────────────────────────────────────────────────────────────────────────

proc actualCompile*(source: string): seq[int] =
  # Use the real hybrid compiler pipeline
  let (tr, err) = compileToSubleq(source, 256)
  if err.len > 0:
    echo "  Compiler error: " & err
    return @[]
  tr.mem

# ─────────────────────────────────────────────────────────────────────────
# MAIN TEST RUNNER
# ─────────────────────────────────────────────────────────────────────────

proc runAllE2ETests* =
  echo "════════════════════════════════════════════════════════════"
  echo "End-to-End Test Suite (Agent 3 - Block 02)"
  echo "21 deterministic tests covering hybrid language"
  echo "════════════════════════════════════════════════════════════"

  initE2ETests()

  echo "\nTotal tests: ", testSuite.len, "\n"

  var categoryStats: Table[string, (int, int)]

  for test in testSuite:
    let passed = runE2ETest(test, actualCompile)
    if test.category notin categoryStats:
      categoryStats[test.category] = (0, 0)
    let (p, f) = categoryStats[test.category]
    if passed:
      categoryStats[test.category] = (p + 1, f)
    else:
      categoryStats[test.category] = (p, f + 1)

  echo "\n════════════════════════════════════════════════════════════"
  echo "RESULTS BY CATEGORY:"
  echo "────────────────────────────────────────────────────────────"
  for category in sorted(toSeq(categoryStats.keys)):
    let (p, f) = categoryStats[category]
    let status = if f == 0: "✓" else: "✗"
    echo "  ", status, " ", category, ": ", p, " passed, ", f, " failed"

  echo "────────────────────────────────────────────────────────────"
  echo "TOTAL: ", passCount, " passed, ", failCount, " failed"
  echo "════════════════════════════════════════════════════════════"

  if failCount > 0:
    quit 1

when isMainModule:
  runAllE2ETests()
