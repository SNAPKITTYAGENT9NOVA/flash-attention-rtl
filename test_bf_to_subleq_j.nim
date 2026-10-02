# Differential tests: compiled SUBLEQ must match the reference BF interpreter
# on output, final tape contents and final pointer.

import std/strutils
import subleq_bf

const TapeCells = 64
const HelloBF = "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++."

var failures = 0
var passes = 0

proc fail(name, msg: string) =
  inc failures
  echo "FAIL ", name, ": ", msg

proc compare(name, bf: string; input: seq[int] = @[]): bool =
  ## returns true if the program was comparable (reference finished cleanly)
  let ref0 = runBF(bf, input, TapeCells, 3000)
  if ref0.error.len > 0: return false
  let tr = brainfuckToSubleq(bf, TapeCells)
  if tr.error.len > 0:
    fail name, "transpile error: " & tr.error
    return true
  var mem = tr.mem
  let res = runSubleq(mem, input, 16 * ref0.steps + 100)
  if res.fault.len > 0:
    fail name, "subleq fault: " & res.fault
  elif not res.halted:
    fail name, "did not halt"
  elif res.output != ref0.output:
    fail name, "output " & $res.output & " != reference " & $ref0.output
  elif mem[tr.tapeBase ..< tr.tapeBase + TapeCells] != ref0.tape:
    fail name, "final tape differs"
  elif mem[PtrCell] != ref0.ptrPos or mem[NegPtrCell] != -ref0.ptrPos:
    fail name, "final pointer differs"
  else:
    inc passes
  true

proc expectOutput(name, bf: string; expected: seq[int]; input: seq[int] = @[]) =
  let tr = brainfuckToSubleq(bf, TapeCells)
  var mem = tr.mem
  let res = runSubleq(mem, input, 1_000_000)
  if tr.error.len > 0 or res.fault.len > 0 or res.output != expected:
    fail name, "got " & $res.output & " (err '" & tr.error & res.fault & "') want " & $expected
  else:
    inc passes

proc expectError(name, bf: string) =
  if brainfuckToSubleq(bf, TapeCells).error.len == 0: fail name, "expected transpile error"
  else: inc passes

proc ords(s: string): seq[int] =
  for ch in s: result.add ord(ch)

# ── hand-written programs (also prove the tape pointer is actually honoured) ──
expectOutput "inc-out", "+++.", @[3]
expectOutput "ptr-moves", ">+>++<<.>.>.", @[0, 1, 2]
expectOutput "ptr-independent-cells", "+>++>+++<<.>.>.", @[1, 2, 3]
expectOutput "negative-cell", "-.", @[-1]
expectOutput "zero-skip-loop", "[+++.]+.", @[1]
expectOutput "negative-loop", "---[+]>.", @[0]
expectOutput "move-loop", "+++[->++<]>.", @[6]
expectOutput "nested", "++[>++[>++<-]<-]>>.", @[8]
expectOutput "cat", ",[.,]", ords("abc"), ords("abc")
expectOutput "hello", HelloBF, ords("Hello World!\n")
expectError "unmatched-close", "+]"
expectError "unmatched-open", "[+"

# determinism
block:
  let a = brainfuckToSubleq(HelloBF, TapeCells)
  let b = brainfuckToSubleq(HelloBF, TapeCells)
  if a.mem != b.mem or a.tapeBase != b.tapeBase: fail "determinism", "compiles differ"
  else: inc passes

# differential comparisons on the hand-written set
for bf in ["", "+", ">>+<<", "+++[>+++[>+<-]<-]", ",>,<[->+<]>.", "+[>+]", ">+++[<+++>-]<."]:
  discard compare("diff:" & bf, bf, @[7, 9])

# deterministic fuzz of balanced programs
var seed: uint64 = 0x9E3779B97F4A7C15'u64
proc rnd(n: int): int =
  seed = seed * 6364136223846793005'u64 + 1442695040888963407'u64
  int((seed shr 33) mod uint64(n))

var compared = 0
const alphabet = "+++---<<>>>[.,"
for iter in 0 ..< 6000:
  var prog = ""
  var depth = 0
  for k in 0 ..< 3 + rnd(40):
    var ch = alphabet[rnd(alphabet.len)]
    if ch == '[':
      inc depth
    elif ch == ']':
      ch = '+'
    prog.add ch
    if depth > 0 and rnd(6) == 0:
      prog.add ']'
      dec depth
  prog.add ']'.repeat(depth)
  if compare("fuzz#" & $iter & ":" & prog, prog, @[3, 1, 4, 1, 5]):
    inc compared

if compared < 500:
  fail "fuzz-coverage", "only " & $compared & " fuzz programs were comparable"

echo "passed: ", passes, "  failed: ", failures, "  fuzz comparable: ", compared
if failures > 0: quit 1
