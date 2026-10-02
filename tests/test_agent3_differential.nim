# BLOCK 03: Differential Verification Tests
# Verify: Reference Semantics == Compiled Execution
# If ANY mismatch, it's a compiler bug

import std/[strutils, tables]
import ../src/subleq_bf

type
  DifferentialTest* = object
    name*: string
    sourceCode*: string
    input*: seq[int]
    description*: string

  DifferentialResult* = object
    passed*: bool
    referenceOutput*: seq[int]
    compiledOutput*: seq[int]
    referenceSteps*: int
    compiledSteps*: int
    mismatchType*: string  # "output", "steps", "memory", "none"

var testCount = 0
var passCount = 0
var failCount = 0

# ─────────────────────────────────────────────────────────────────────────
# PATH 1: Reference Semantics (direct interpreter)
# ─────────────────────────────────────────────────────────────────────────

proc getReferenceExecution*(source: string; input: seq[int]): tuple[output: seq[int], steps: int, fault: string] =
  ## Run program through reference interpreter (Agent 1's semantics)
  ## For now, placeholder. Agent 1 will provide this.
  (output: @[], steps: 0, fault: "Reference interpreter not yet available")

# ─────────────────────────────────────────────────────────────────────────
# PATH 2: Compiled Execution (full pipeline)
# ─────────────────────────────────────────────────────────────────────────

proc getCompiledExecution*(source: string; input: seq[int]): tuple[output: seq[int], steps: int, fault: string] =
  ## Run: SOURCE → AGENT1 → AGENT3 NORMALIZER → AGENT2 → SUBLEQ VM
  ## For now, placeholder. Full pipeline integration once agents commit.
  (output: @[], steps: 0, fault: "Compiled execution pipeline not yet available")

# ─────────────────────────────────────────────────────────────────────────
# DIFFERENTIAL TEST HARNESS
# ─────────────────────────────────────────────────────────────────────────

proc runDifferentialTest*(test: DifferentialTest): DifferentialResult =
  inc testCount

  echo "\n[DIFF-TEST] ", test.name
  echo "  Description: ", test.description

  let (refOut, refSteps, refFault) = getReferenceExecution(test.sourceCode, test.input)
  let (compOut, compSteps, compFault) = getCompiledExecution(test.sourceCode, test.input)

  var result: DifferentialResult
  result.referenceOutput = refOut
  result.compiledOutput = compOut
  result.referenceSteps = refSteps
  result.compiledSteps = compSteps

  # Check for faults
  if refFault.len > 0:
    echo "  ✗ Reference execution failed: ", refFault
    result.passed = false
    result.mismatchType = "reference_fault"
    inc failCount
    return result

  if compFault.len > 0:
    echo "  ✗ Compiled execution failed: ", compFault
    result.passed = false
    result.mismatchType = "compiled_fault"
    inc failCount
    return result

  # Compare outputs
  if refOut != compOut:
    echo "  ✗ OUTPUT MISMATCH"
    echo "    Reference: ", refOut
    echo "    Compiled:  ", compOut
    result.passed = false
    result.mismatchType = "output"
    inc failCount
    return result

  # Compare step counts (may differ due to optimization, but not drastically)
  let stepRatio = if refSteps > 0: float(compSteps) / float(refSteps) else: 1.0
  if stepRatio > 2.0:  # If compiled takes >2x more steps, something is wrong
    echo "  ⚠ STEP COUNT INFLATION"
    echo "    Reference: ", refSteps, " steps"
    echo "    Compiled:  ", compSteps, " steps (", formatFloat(stepRatio, ffDecimal, 2), "x)"
    # Don't fail, but warn

  echo "  ✓ PASS"
  result.passed = true
  result.mismatchType = "none"
  inc passCount
  result

# ─────────────────────────────────────────────────────────────────────────
# DIFFERENTIAL TEST SUITE
# ─────────────────────────────────────────────────────────────────────────

proc runDifferentialTests* =
  echo "════════════════════════════════════════════════════════════"
  echo "Differential Verification (Agent 3 - Block 03)"
  echo "Reference vs Compiled Execution"
  echo "════════════════════════════════════════════════════════════\n"

  var tests: seq[DifferentialTest]

  # Test 1: Simple constant output
  tests.add DifferentialTest(
    name: "Constant output",
    sourceCode: "output(42);",
    input: @[],
    description: "Reference and compiled must both output 42"
  )

  # Test 2: Input echo
  tests.add DifferentialTest(
    name: "Input echo",
    sourceCode: "output(input()); output(input());",
    input: @[10, 20],
    description: "Both must echo input values"
  )

  # Test 3: Arithmetic
  tests.add DifferentialTest(
    name: "Arithmetic operations",
    sourceCode: "output(5 + 3); output(10 - 2); output(4 * 6);",
    input: @[],
    description: "Arithmetic results must match exactly"
  )

  # Test 4: Conditional
  tests.add DifferentialTest(
    name: "Conditional branching",
    sourceCode: "if (input() > 5) { output(1); } else { output(0); }",
    input: @[7],
    description: "Conditional must execute same branch"
  )

  # Test 5: Loop
  tests.add DifferentialTest(
    name: "Loop execution",
    sourceCode: "int i = 3; while (i > 0) { output(i); i = i - 1; }",
    input: @[],
    description: "Loop must execute same number of iterations"
  )

  # Test 6: Memory access
  tests.add DifferentialTest(
    name: "Memory operations",
    sourceCode: "int x = 10; int y = x + 5; output(y);",
    input: @[],
    description: "Memory read/write must be consistent"
  )

  # Test 7: Nested structures
  tests.add DifferentialTest(
    name: "Nested loops",
    sourceCode: "for (int i = 1; i <= 2; i = i + 1) { for (int j = 1; j <= 2; j = j + 1) { output(i * 10 + j); } }",
    input: @[],
    description: "Nested loops must execute in correct order"
  )

  # Test 8: Zero values
  tests.add DifferentialTest(
    name: "Zero handling",
    sourceCode: "int x = 0; output(x); output(x + 0); output(0 - 0);",
    input: @[],
    description: "Zero operations must match"
  )

  # Test 9: Negative numbers
  tests.add DifferentialTest(
    name: "Negative arithmetic",
    sourceCode: "int x = -10; int y = -5; output(x + y); output(x - y);",
    input: @[],
    description: "Negative number operations must match"
  )

  # Test 10: Large values
  tests.add DifferentialTest(
    name: "Large integers",
    sourceCode: "output(1000000); output(999999 + 1);",
    input: @[],
    description: "Large value operations must match"
  )

  echo "Running ", tests.len, " differential tests...\n"

  var mismatches: seq[DifferentialResult]

  for test in tests:
    let result = runDifferentialTest(test)
    if not result.passed:
      mismatches.add result

  # Summary
  echo "\n════════════════════════════════════════════════════════════"
  echo "DIFFERENTIAL VERIFICATION RESULTS"
  echo "────────────────────────────────────────────────────────────"
  echo "Total tests: ", testCount
  echo "Passed:      ", passCount
  echo "Failed:      ", failCount

  if mismatches.len > 0:
    echo "\n⚠ MISMATCHES DETECTED:"
    for mismatch in mismatches:
      echo "  - ", mismatch.mismatchType, ": ", mismatch.referenceOutput, " vs ", mismatch.compiledOutput

  echo "════════════════════════════════════════════════════════════"

  if failCount > 0:
    quit 1

when isMainModule:
  runDifferentialTests()
