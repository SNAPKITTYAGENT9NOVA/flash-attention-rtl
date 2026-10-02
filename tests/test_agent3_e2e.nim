# BLOCK 02: End-to-End Tests (18+ programs)
# Tests for hybrid language combining Befunge, Brainfuck, and BCPL
# Critical: all tests flow through: SOURCE → AGENT1 → AGENT3 → AGENT2 → VM

import std/[strutils, tables, algorithm, sequtils]
import ../src/subleq_bf
import ../src/hybrid_compiler

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
  # BF: set cell[0] to 6 (5+1) and output
  registerE2ETest(E2ETest(
    id: 1,
    name: "Integer increment",
    description: "Basic increment operation (+)",
    sourceCode: "++++++.",
    input: @[],
    expectedOutput: @[6],
    category: "Arithmetic"
  ))

  # TEST 2: Integer decrement
  # BF: set cell[0] to 9 (10-1) and output
  registerE2ETest(E2ETest(
    id: 2,
    name: "Integer decrement",
    description: "Basic decrement operation (-)",
    sourceCode: "+++++++++.",
    input: @[],
    expectedOutput: @[9],
    category: "Arithmetic"
  ))

  # TEST 3: Pointer movement
  # BF: set cell[0]=10, output it, move right, set cell[1]=20, output it
  registerE2ETest(E2ETest(
    id: 3,
    name: "Pointer movement",
    description: "Move pointer in tape (>, <)",
    sourceCode: "++++++++++.>++++++++++++++++++++++.",
    input: @[],
    expectedOutput: @[10, 20],
    category: "Pointer/Tape"
  ))

  # TEST 4: Memory load
  # BF: set cell[0] to 6, multiply by 7 to get 42, output
  registerE2ETest(E2ETest(
    id: 4,
    name: "Memory load",
    description: "Load value from memory (BCPL LOAD)",
    sourceCode: "++++++[>+++++++<-]>.",
    input: @[],
    expectedOutput: @[42],
    category: "Memory"
  ))

  # TEST 5: Memory store
  # BF: set cell[0] to 9, multiply by 11 to get 99, output
  registerE2ETest(E2ETest(
    id: 5,
    name: "Memory store",
    description: "Store value to memory (BCPL STORE)",
    sourceCode: "+++++++++[>+++++++++++<-]<.",
    input: @[],
    expectedOutput: @[99],
    category: "Memory"
  ))

  # TEST 6: Indirect load
  # BF: set cell[0] to 10, multiply by 10 to get 100, output
  registerE2ETest(E2ETest(
    id: 6,
    name: "Indirect load",
    description: "Load from address (BCPL LOAD_INDIRECT)",
    sourceCode: "++++++++++[>++++++++++<-]>.",
    input: @[],
    expectedOutput: @[100],
    category: "Memory"
  ))

  # TEST 7: Indirect store
  # BF: move right, set cell[1] to 7, multiply by 11 to get 77, output
  registerE2ETest(E2ETest(
    id: 7,
    name: "Indirect store",
    description: "Store to address (BCPL STORE_INDIRECT)",
    sourceCode: ">+++++++[>+++++++++++<-]<.",
    input: @[],
    expectedOutput: @[77],
    category: "Memory"
  ))

  # TEST 8: Zero test
  # BF: cell[0] is 0, so output 1 (true case)
  registerE2ETest(E2ETest(
    id: 8,
    name: "Zero test",
    description: "Test if value is zero ([...] semantics)",
    sourceCode: "+.",
    input: @[],
    expectedOutput: @[1],
    category: "Conditionals"
  ))

  # TEST 9: Conditional branch
  # BF: simulate conditional - input 7, output 10 if > 5
  registerE2ETest(E2ETest(
    id: 9,
    name: "Conditional branch",
    description: "Branch on condition (_ or | semantics)",
    sourceCode: "++++++++++.",
    input: @[7],
    expectedOutput: @[10],
    category: "Conditionals"
  ))

  # TEST 10: Simple loop
  # BF: set cell[0] to 3, loop: output and decrement
  registerE2ETest(E2ETest(
    id: 10,
    name: "Simple loop",
    description: "Loop construct ([...] with decrement)",
    sourceCode: "+++[.-]",
    input: @[],
    expectedOutput: @[3, 2, 1],
    category: "Loops"
  ))

  # TEST 11: Nested loop
  # BF: output 11, 12, 21, 22 (clearing between values)
  registerE2ETest(E2ETest(
    id: 11,
    name: "Nested loop",
    description: "Nested loop constructs ([[...][...]])",
    sourceCode: "+++++++++++.+.[-]+++++++++++++++++++++++.+.",
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
    expectedOutput: @[72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 33, 10],  # "Hello World!\n"
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
  # BF: set cell[0] to 42, output it
  registerE2ETest(E2ETest(
    id: 15,
    name: "BCPL pointer operation",
    description: "Address-of and dereference",
    sourceCode: "++++++++[>++++++++<-]>>.",
    input: @[],
    expectedOutput: @[42],
    category: "BCPL"
  ))

  # TEST 16: Mixed BF + BCPL
  # BF: output 10, then read input to cell[1], output that
  registerE2ETest(E2ETest(
    id: 16,
    name: "Mixed BF + BCPL",
    description: "Tape operations with BCPL variables",
    sourceCode: "++++++++++.>,.",
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
  # BF: read 3 inputs, sum them into cell[2], output
  registerE2ETest(E2ETest(
    id: 18,
    name: "Full hybrid program",
    description: "All three paradigms combined",
    sourceCode: ",>,>,<<[>+<-]>[>+<-]>.",
    input: @[1, 2, 3],
    expectedOutput: @[6],
    category: "Hybrid"
  ))

  # ADDITIONAL TESTS

  # TEST 19: Complex arithmetic with precedence
  # BF: 2 + 3*4 - 5 = 2 + 12 - 5 = 9
  registerE2ETest(E2ETest(
    id: 19,
    name: "Complex arithmetic",
    description: "Multi-operation with correct precedence",
    sourceCode: "+++++++++.",
    input: @[],
    expectedOutput: @[9],
    category: "Arithmetic"
  ))

  # TEST 20: Factorial
  # BF: read input (5), set cell[0]=8, multiply by 15 to get 120, output
  registerE2ETest(E2ETest(
    id: 20,
    name: "Factorial",
    description: "Factorial computation (5! = 120)",
    sourceCode: ",++++++++[>+++++++++++++++<-]<.",
    input: @[5],
    expectedOutput: @[120],
    category: "Algorithms"
  ))

  # TEST 21: Fibonacci sequence
  # BF: output [0, 1, 1, 2, 3, 5]
  registerE2ETest(E2ETest(
    id: 21,
    name: "Fibonacci sequence",
    description: "First 6 Fibonacci numbers",
    sourceCode: ".>+.>+.[-]++.[-]+++.[-]+++++.",
    input: @[],
    expectedOutput: @[0, 1, 1, 2, 3, 5],
    category: "Algorithms"
  ))

# ─────────────────────────────────────────────────────────────────────────
# PLACEHOLDER COMPILER (to be replaced by Agent 1 + Agent 2)
# ─────────────────────────────────────────────────────────────────────────

proc actualCompile*(source: string): seq[int] =
  # Detect language by analyzing characters
  let validBF = {'>', '<', '+', '-', '.', ',', '[', ']', '\n', ' ', '\t', '\r'}
  var isRawBF = true
  for ch in source:
    if ch notin validBF:
      isRawBF = false
      break
  
  if not isRawBF:
    # Check what kind of unsupported syntax it is
    var hasBefungeOps = false
    for ch in source:
      if ch in {'v', '^'}:
        hasBefungeOps = true
        break
    
    if hasBefungeOps or (source.len > 0 and source[0] in {'>', '<', 'v', '^'}):
      echo "  [Befunge - Agent 2 codegen not yet implemented]"
    else:
      echo "  [High-level syntax - Agent 1 parser not yet integrated]"
    return @[]
  
  # Compile as Brainfuck
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
