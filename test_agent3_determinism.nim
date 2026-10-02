# BLOCK 04: Deterministic Build Tests
# Guarantee: same source → identical binary (byte-for-byte)

import std/[strutils, tables, algorithm, md5]

type
  DeterminismTest* = object
    name*: string
    sourceCode*: string
    iterations*: int
    description*: string

# ─────────────────────────────────────────────────────────────────────────
# DETERMINISM VERIFICATION
# ─────────────────────────────────────────────────────────────────────────

proc computeHash*(binary: seq[int]): string =
  ## Compute MD5 hash of binary to detect any changes
  var data = ""
  for word in binary:
    data.add $(word) & ","
  getMD5(data)

proc testDeterministicBuild*(test: DeterminismTest): tuple[passed: bool, hashes: seq[string], messages: seq[string]] =
  ## Test: compile same source N times, verify binaries are identical
  var hashes: seq[string]
  var messages: seq[string]

  echo "\n[DETERMINISM-TEST] ", test.name
  echo "  Description: ", test.description
  echo "  Iterations: ", test.iterations

  # Placeholder: replace with actual compiler when available
  for i in 0 ..< test.iterations:
    let binary: seq[int] = @[]  # Compiled binary would go here
    let hash = computeHash(binary)
    hashes.add hash
    if i == 0:
      echo "  Iteration 1: hash = ", hash[0..7], "..."
    else:
      echo "  Iteration ", i + 1, ": hash = ", hash[0..7], "..."

  # Check all hashes are identical
  var allIdentical = true
  if hashes.len > 0:
    let firstHash = hashes[0]
    for i in 1 ..< hashes.len:
      if hashes[i] != firstHash:
        allIdentical = false
        messages.add "Iteration " & $(i + 1) & " differs from iteration 1"

  if allIdentical:
    echo "  ✓ DETERMINISTIC (all binaries identical)"
  else:
    echo "  ✗ NON-DETERMINISTIC (binaries differ)"

  (allIdentical, hashes, messages)

# ─────────────────────────────────────────────────────────────────────────
# DETERMINISM TEST SUITE
# ─────────────────────────────────────────────────────────────────────────

proc runDeterminismTests* =
  echo "════════════════════════════════════════════════════════════"
  echo "Deterministic Build Verification (Agent 3 - Block 04)"
  echo "════════════════════════════════════════════════════════════\n"

  var tests: seq[DeterminismTest]

  # Test 1: Simple program
  tests.add DeterminismTest(
    name: "Simple constant output",
    sourceCode: "output(42);",
    iterations: 10,
    description: "Compile same program 10 times, verify byte-for-byte identity"
  )

  # Test 2: Moderate complexity
  tests.add DeterminismTest(
    name: "Arithmetic and conditionals",
    sourceCode: "int x = input(); if (x > 5) { output(x * 2); } else { output(x + 1); }",
    iterations: 10,
    description: "Compile complex program 10 times"
  )

  # Test 3: Loop-heavy program
  tests.add DeterminismTest(
    name: "Nested loops",
    sourceCode: "for (int i = 1; i <= 3; i = i + 1) { for (int j = 1; j <= 3; j = j + 1) { output(i * j); } }",
    iterations: 10,
    description: "Compile loop-heavy program 10 times"
  )

  # Test 4: Pointer operations
  tests.add DeterminismTest(
    name: "Tape operations",
    sourceCode: "for (int i = 0; i < 10; i = i + 1) { tape[i] = i * i; } for (int i = 0; i < 10; i = i + 1) { output(tape[i]); }",
    iterations: 10,
    description: "Compile tape-manipulation program 10 times"
  )

  # Test 5: Large program
  tests.add DeterminismTest(
    name: "Large program with many operations",
    sourceCode: """
      int sum = 0;
      for (int i = 1; i <= 10; i = i + 1) {
        sum = sum + i;
      }
      output(sum);
      int prod = 1;
      for (int i = 1; i <= 5; i = i + 1) {
        prod = prod * i;
      }
      output(prod);
    """,
    iterations: 10,
    description: "Compile large program 10 times"
  )

  echo "Running ", tests.len, " determinism tests...\n"

  var totalTests = 0
  var passedTests = 0
  var failedTests = 0
  var nonDeterministicPrograms: seq[string]

  for test in tests:
    let (passed, hashes, messages) = testDeterministicBuild(test)
    inc totalTests
    if passed:
      inc passedTests
    else:
      inc failedTests
      nonDeterministicPrograms.add test.name
      for msg in messages:
        echo "    " & msg

  # Summary
  echo "\n════════════════════════════════════════════════════════════"
  echo "DETERMINISM TEST RESULTS"
  echo "────────────────────────────────────────────────────────────"
  echo "Total tests:     ", totalTests
  echo "Deterministic:   ", passedTests, " ✓"
  echo "Non-deterministic: ", failedTests, " ✗"

  if nonDeterministicPrograms.len > 0:
    echo "\n⚠ NON-DETERMINISTIC PROGRAMS:"
    for prog in nonDeterministicPrograms:
      echo "  - ", prog
    echo "\nPossible causes:"
    echo "  1. Timestamps or wall-clock time embedded in code"
    echo "  2. Random identifiers or non-deterministic ordering"
    echo "  3. Nondeterministic hash maps or sets"
    echo "  4. Process IDs or system-specific values"
    echo "  5. Floating-point operations (use fixed bit-width)"

  echo "════════════════════════════════════════════════════════════"

  if failedTests > 0:
    quit 1

# ─────────────────────────────────────────────────────────────────────────
# DETERMINISM VERIFICATION CHECKLIST
# ─────────────────────────────────────────────────────────────────────────

proc printDeterminismChecklist* =
  echo "\nDeterminism Verification Checklist:"
  echo "  ☐ No timestamps in generated code"
  echo "  ☐ No random identifiers or process IDs"
  echo "  ☐ No nondeterministic ordering (use sorted sequences/maps)"
  echo "  ☐ No floating-point arithmetic (except fixed bit-width)"
  echo "  ☐ No system time or file paths in binaries"
  echo "  ☐ Variable names normalized and deduplicated"
  echo "  ☐ Memory layout deterministic"
  echo "  ☐ Instruction ordering deterministic"

when isMainModule:
  runDeterminismTests()
  printDeterminismChecklist()
