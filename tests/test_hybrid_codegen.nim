# Test suite for hybrid compiler code generator
# Validates compiled SUBLEQ matches reference interpreter output

import hybrid_ast
import hybrid_codegen
import subleq_bf

const TapeCells = 64

var passes = 0
var failures = 0

proc fail(name, msg: string) =
  inc failures
  echo "FAIL ", name, ": ", msg

proc pass(name: string) =
  inc passes
  echo "PASS ", name

proc testCompilation(name, bf: string; expectedOutput: seq[int]) =
  # Parse as Brainfuck
  let prog = Program(
    instrs: @[],
    mode: modeBrainfuck
  )

  # Build program from string manually
  var program = Program(mode: modeBrainfuck)
  for ch in bf:
    case ch
    of '>': program.instrs.add ptrInc()
    of '<': program.instrs.add ptrDec()
    of '+': program.instrs.add cellInc()
    of '-': program.instrs.add cellDec()
    of '.': program.instrs.add cellOut()
    of ',': program.instrs.add cellIn()
    of '[': program.instrs.add loopStart()
    of ']': program.instrs.add loopEnd()
    else: discard
  program.instrs.add halt()

  # Compile with hybrid compiler
  let tr = codegen(program, TapeCells)
  if tr.error.len > 0:
    fail name, "codegen error: " & tr.error
    return

  # Execute compiled code
  var mem = tr.mem
  let result = runSubleq(mem)

  if result.fault.len > 0:
    fail name, "execution fault: " & result.fault
  elif not result.halted:
    fail name, "did not halt"
  elif result.output != expectedOutput:
    fail name, "output mismatch: got " & $result.output & " expected " & $expectedOutput
  else:
    pass name

# Test cases
testCompilation("inc-out", "+++.", @[3])
testCompilation("ptr-moves", ">+>++<<.>.>.", @[0, 1, 2])
testCompilation("zero-skip-loop", "[+++.]+.", @[1])
testCompilation("move-loop", "+++[->++<]>.", @[6])
testCompilation("negative-cell", "-.", @[-1])

# Summary
echo ""
echo "Results: " & $passes & " passed, " & $failures & " failed"
if failures > 0:
  quit 1
