# Test program: Brainfuck → SUBLEQ-J compiler
# Demonstrates J-array semantics for BF compilation

import std/[sequtils, strutils]

# Include the BF→SUBLEQ-J compiler from refuge.nim
include "refuge.nim"

proc main() =
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║  BF → SUBLEQ-J Compiler Test (J Array Semantics)           ║"
  echo "╚════════════════════════════════════════════════════════════╝"

  # Test 1: Simple increment
  echo "\n[Test 1] Simple Brainfuck: '+' (increment tape[0])"
  let bfTest1 = "+"
  let (mem1, labels1, err1) = bfToSubleqJ(bfTest1)
  if err1.len > 0:
    echo "ERROR: ", err1
  else:
    echo "  Compiled to ", mem1.len, " words"
    echo "  Labels: ", labels1.len
    echo "  Memory (first 20 words): ", mem1[0..min(19, mem1.len-1)]

  # Test 2: Loop structure
  echo "\n[Test 2] Brainfuck loop: '[' and ']'"
  let bfTest2 = "+[>+<-]"
  let (mem2, labels2, err2) = bfToSubleqJ(bfTest2)
  if err2.len > 0:
    echo "ERROR: ", err2
  else:
    echo "  Compiled to ", mem2.len, " words"
    echo "  Labels: ", labels2.len

  # Test 3: Hello World (simplified)
  echo "\n[Test 3] Brainfuck: '+++' (three increments)"
  let bfTest3 = "+++"
  let (mem3, labels3, err3) = bfToSubleqJ(bfTest3)
  if err3.len > 0:
    echo "ERROR: ", err3
  else:
    echo "  Compiled to ", mem3.len, " words"
    echo "  Key cells:"
    echo "    Array cells [0..", bfTest3.len, "]: ", mem3[0..min(5, mem3.len-1)]
    echo "    Special registers: ptr=", mem3[256], " -1=", mem3[257], " +1=", mem3[258]

  # Test 4: Full Hello World (truncated for demo)
  echo "\n[Test 4] Hello World (original BF code)"
  let bfHello = HelloBF[0..50]  # First 50 chars
  let (memH, labelsH, errH) = bfToSubleqJ(bfHello)
  if errH.len > 0:
    echo "ERROR: ", errH
  else:
    echo "  BF code length: ", bfHello.len
    echo "  Compiled to: ", memH.len, " SUBLEQ words"
    let cap = if memH.len > 256: memH[256] else: 0
    echo "  Array capacity: ", cap

  # Test 5: Verify round-trip consistency
  echo "\n[Test 5] Consistency check - multiple compilations"
  let bfCode = "++[>++<-]"
  let (m1, l1, e1) = bfToSubleqJ(bfCode)
  let (m2, l2, e2) = bfToSubleqJ(bfCode)
  if m1 == m2 and e1 == e2:
    echo "  ✓ Deterministic: multiple compilations produce identical output"
  else:
    echo "  ✗ Non-deterministic compilation detected!"

  echo "\n╔════════════════════════════════════════════════════════════╗"
  echo "║  All tests completed                                       ║"
  echo "╚════════════════════════════════════════════════════════════╝"

when isMainModule:
  main()
