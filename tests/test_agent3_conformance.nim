# BLOCK 07: Final Conformance Suite
# Complete test coverage: all features, paradigms, and properties

import std/[strutils, tables, sequtils]
import ../src/subleq_bf

type
  ConformanceTest* = object
    id*: int
    name*: string
    category*: string
    sourceCode*: string
    input*: seq[int]
    expectedOutput*: seq[int]
    expectedMemoryMarkers*: Table[int, int]  # optional markers to verify
    expectedPtrMarker*: int  # optional
    critical*: bool  # whether test is blocking

var conformanceSuite: seq[ConformanceTest]
var results: tuple[total: int, passed: int, failed: int, critical_failures: seq[string]]

results.total = 0
results.passed = 0
results.failed = 0

# ─────────────────────────────────────────────────────────────────────────
# CONFORMANCE TEST SUITE (18 Core + Extended)
# ─────────────────────────────────────────────────────────────────────────

proc buildConformanceSuite* =
  ## Build complete test suite covering all features

  # ─────────────────────────────────────────────────────────────
  # CORE 18 TESTS (from specification)
  # ─────────────────────────────────────────────────────────────

  conformanceSuite.add ConformanceTest(
    id: 1, name: "Integer increment",
    category: "Arithmetic", sourceCode: "int x = 5; x = x + 1; output(x);",
    input: @[], expectedOutput: @[6], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 2, name: "Integer decrement",
    category: "Arithmetic", sourceCode: "int x = 10; x = x - 1; output(x);",
    input: @[], expectedOutput: @[9], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 3, name: "Pointer movement",
    category: "Befunge", sourceCode: "tape[0] = 10; tape[1] = 20; output(tape[0]); output(tape[1]);",
    input: @[], expectedOutput: @[10, 20], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 4, name: "Memory load",
    category: "BCPL", sourceCode: "int x = 42; int y = x; output(y);",
    input: @[], expectedOutput: @[42], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 5, name: "Memory store",
    category: "BCPL", sourceCode: "int x = 0; x = 99; output(x);",
    input: @[], expectedOutput: @[99], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 6, name: "Indirect load",
    category: "BCPL", sourceCode: "int data[3]; data[0] = 100; int ptr = 0; output(data[ptr]);",
    input: @[], expectedOutput: @[100], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 7, name: "Indirect store",
    category: "BCPL", sourceCode: "int data[3]; int ptr = 1; data[ptr] = 77; output(data[1]);",
    input: @[], expectedOutput: @[77], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 8, name: "Zero test",
    category: "Conditionals", sourceCode: "int x = 0; if (x == 0) { output(1); } else { output(0); }",
    input: @[], expectedOutput: @[1], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 9, name: "Conditional branch",
    category: "Conditionals", sourceCode: "if (input() > 5) { output(10); } else { output(20); }",
    input: @[7], expectedOutput: @[10], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 10, name: "Simple loop",
    category: "Loops", sourceCode: "int i = 3; while (i > 0) { output(i); i = i - 1; }",
    input: @[], expectedOutput: @[3, 2, 1], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 11, name: "Nested loop",
    category: "Loops", sourceCode: "for (int i = 1; i <= 2; i = i + 1) { for (int j = 1; j <= 2; j = j + 1) { output(i * 10 + j); } }",
    input: @[], expectedOutput: @[11, 12, 21, 22], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 12, name: "Brainfuck program",
    category: "Brainfuck", sourceCode: "+++[>++[>++<-]<-]>>.",
    input: @[], expectedOutput: @[8], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 13, name: "Befunge direction changes",
    category: "Befunge", sourceCode: ">:#,_@",
    input: @[65], expectedOutput: @[65], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 14, name: "Befunge conditional",
    category: "Befunge", sourceCode: "5_@#,_@",
    input: @[], expectedOutput: @[], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 15, name: "BCPL pointer operation",
    category: "BCPL", sourceCode: "int x = 42; int* p = &x; output(*p);",
    input: @[], expectedOutput: @[42], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 16, name: "Mixed BF + BCPL",
    category: "Hybrid", sourceCode: "int x = 10; tape[0] = x; output(tape[0]);",
    input: @[], expectedOutput: @[10], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 17, name: "Mixed Befunge + BF",
    category: "Hybrid", sourceCode: "+++[>+++<-]>.",
    input: @[], expectedOutput: @[9], critical: true
  )

  conformanceSuite.add ConformanceTest(
    id: 18, name: "Full hybrid program",
    category: "Hybrid", sourceCode: "int sum = 0; for (int i = 0; i < 3; i = i + 1) { tape[i] = input(); sum = sum + tape[i]; } output(sum);",
    input: @[1, 2, 3], expectedOutput: @[6], critical: true
  )

  # ─────────────────────────────────────────────────────────────
  # EXTENDED TESTS (beyond core 18)
  # ─────────────────────────────────────────────────────────────

  conformanceSuite.add ConformanceTest(
    id: 19, name: "Empty input handling",
    category: "I/O", sourceCode: "int x = input(); output(x);",
    input: @[], expectedOutput: @[0], critical: false
  )

  conformanceSuite.add ConformanceTest(
    id: 20, name: "Multiple outputs",
    category: "I/O", sourceCode: "output(1); output(2); output(3);",
    input: @[], expectedOutput: @[1, 2, 3], critical: false
  )

  conformanceSuite.add ConformanceTest(
    id: 21, name: "Negative numbers",
    category: "Arithmetic", sourceCode: "output(-5); output(-(-10));",
    input: @[], expectedOutput: @[-5, 10], critical: false
  )

  conformanceSuite.add ConformanceTest(
    id: 22, name: "Operator precedence",
    category: "Arithmetic", sourceCode: "output(2 + 3 * 4 - 5);",
    input: @[], expectedOutput: @[9], critical: false
  )

  conformanceSuite.add ConformanceTest(
    id: 23, name: "Array operations",
    category: "Memory", sourceCode: "int arr[5]; for (int i = 0; i < 5; i = i + 1) { arr[i] = i * i; } for (int i = 0; i < 5; i = i + 1) { output(arr[i]); }",
    input: @[], expectedOutput: @[0, 1, 4, 9, 16], critical: false
  )

  conformanceSuite.add ConformanceTest(
    id: 24, name: "Factorial",
    category: "Algorithms", sourceCode: "int n = input(); int r = 1; for (int i = 2; i <= n; i = i + 1) { r = r * i; } output(r);",
    input: @[5], expectedOutput: @[120], critical: false
  )

  conformanceSuite.add ConformanceTest(
    id: 25, name: "Fibonacci sequence",
    category: "Algorithms", sourceCode: "int a = 0; int b = 1; for (int i = 0; i < 6; i = i + 1) { output(a); int t = a + b; a = b; b = t; }",
    input: @[], expectedOutput: @[0, 1, 1, 2, 3, 5], critical: false
  )

# ─────────────────────────────────────────────────────────────────────────
# TEST EXECUTION
# ─────────────────────────────────────────────────────────────────────────

proc runConformanceTest*(test: ConformanceTest; compileFn: proc(source: string): seq[int]): bool =
  ## Run single conformance test through full pipeline
  try:
    inc results.total

    # Compile through full pipeline
    let compiled = compileFn(test.sourceCode)
    if compiled.len == 0:
      echo "✗ Test ", test.id, ": ", test.name, " [COMPILE ERROR]"
      if test.critical:
        results.critical_failures.add test.name
      inc results.failed
      return false

    # Execute compiled program
    var mem = compiled
    let result = runSubleq(mem, test.input, 1_000_000)

    if result.fault.len > 0:
      echo "✗ Test ", test.id, ": ", test.name, " [RUNTIME FAULT]"
      if test.critical:
        results.critical_failures.add test.name
      inc results.failed
      return false

    if result.output != test.expectedOutput:
      echo "✗ Test ", test.id, ": ", test.name, " [OUTPUT MISMATCH]"
      echo "  Expected: ", test.expectedOutput
      echo "  Got:      ", result.output
      if test.critical:
        results.critical_failures.add test.name
      inc results.failed
      return false

    echo "✓ Test ", test.id, ": ", test.name
    inc results.passed
    return true

  except Exception as e:
    echo "✗ Test ", test.id, ": ", test.name, " [ERROR: ", e.msg, "]"
    if test.critical:
      results.critical_failures.add test.name
    inc results.failed
    return false

# ─────────────────────────────────────────────────────────────────────────
# PLACEHOLDER COMPILER
# ─────────────────────────────────────────────────────────────────────────

proc placeholderCompile*(source: string): seq[int] =
  # To be replaced by actual hybrid compiler
  @[]

# ─────────────────────────────────────────────────────────────────────────
# MAIN CONFORMANCE RUNNER
# ─────────────────────────────────────────────────────────────────────────

proc runFullConformanceSuite* =
  echo "════════════════════════════════════════════════════════════════"
  echo "HYBRID COMPILER CONFORMANCE SUITE (Agent 3 - Block 07)"
  echo "════════════════════════════════════════════════════════════════\n"

  buildConformanceSuite()
  echo "Running ", conformanceSuite.len, " conformance tests...\n"

  for test in conformanceSuite:
    discard runConformanceTest(test, placeholderCompile)

  # Summary
  echo "\n════════════════════════════════════════════════════════════════"
  echo "CONFORMANCE RESULTS"
  echo "════════════════════════════════════════════════════════════════"
  echo "Total:    ", results.total
  echo "Passed:   ", results.passed, " ✓"
  echo "Failed:   ", results.failed, " ✗"

  if results.critical_failures.len > 0:
    echo "\n⚠ CRITICAL FAILURES:"
    for test in results.critical_failures:
      echo "  - ", test
    echo "\nCompiler is not production-ready."
  else:
    echo "\n✓ All critical tests passed. Compiler is conformant."

  echo "════════════════════════════════════════════════════════════════"

  if results.failed > 0:
    quit 1

when isMainModule:
  runFullConformanceSuite()
