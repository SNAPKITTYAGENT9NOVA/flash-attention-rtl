# FA opcode tests.
#   1. Every case in sim/fa/vectors/fa_vectors.txt is run as a real SUBLEQ program in the Nim
#      interpreter (normal subtract/branch code, FA trap, then more SUBLEQ that prints the result)
#      and compared with the Python integer model's expected output.
#   2. The same programs, plus transpiled Brainfuck programs, are written as memory images to
#      sim/fa/work_img/ so the RTL SoC testbench can run them and compare against the same
#      expected outputs (see sim/fa/run_all.sh).
# Run from the repository root.

import std/[os, strutils]
import ../src/subleq_bf

const
  VecFile = "sim/fa/vectors/fa_vectors.txt"
  ImgDir = "sim/fa/work_img"
  Data = 2048
  ZeroC = Data
  OneC = Data + 1
  ResC = Data + 2
  TwoC = Data + 3
  CntC = Data + 4
  Desc = Data + 8
  Qa = Data + 32

var failures = 0
var passes = 0

proc fail(name, msg: string) =
  inc failures
  echo "FAIL ", name, ": ", msg

proc writeLines(path: string; xs: seq[int]) =
  var s = ""
  for x in xs: s.add $x & "\n"
  writeFile(path, s)

proc buildProgram(q, k, v: seq[int]; n, d: int): tuple[mem: seq[int], expected: seq[int]] =
  ## SUBLEQ program: RES = 10 - 2; loop CNT 3 -> 0 printing CNT; FA trap; print RES; print O.
  let nd = n * d
  let ka = Qa + nd + 4
  let va = ka + nd + 4
  let oa = va + nd + 4
  var mem = newSeq[int](oa + nd + 4)
  var code: seq[int]
  proc tri(a, b, c: int) =
    code.add a
    code.add b
    code.add c
  tri(TwoC, ResC, 3)                  # RES -= 2
  tri(OneC, CntC, 12)                 # 3: CNT -= 1; CNT <= 0 -> leave loop
  tri(CntC, -1, 9)                    # 6: print CNT
  tri(ZeroC, ZeroC, 3)                # 9: loop
  tri(-2, Desc, 15)                   # 12: FA trap
  var here = 15
  tri(ResC, -1, here + 3); here += 3  # print RES (proves state survived the trap)
  for i in 0 ..< nd:
    tri(oa + i, -1, here + 3); here += 3
  tri(ZeroC, ZeroC, -1)               # halt
  for i, w in code: mem[i] = w
  doAssert code.len < Data
  mem[OneC] = 1
  mem[ResC] = 10
  mem[TwoC] = 2
  mem[CntC] = 3
  mem[Desc] = Qa; mem[Desc + 1] = ka; mem[Desc + 2] = va; mem[Desc + 3] = oa
  mem[Desc + 4] = n; mem[Desc + 5] = d
  for i in 0 ..< nd:
    mem[Qa + i] = q[i]; mem[ka + i] = k[i]; mem[va + i] = v[i]
  (mem, @[2, 1, 8])

createDir ImgDir
let tokens = readFile(VecFile).splitWhitespace()
var pos = 0
proc nextInt(): int =
  result = parseInt(tokens[pos])
  inc pos

let ncases = nextInt()
for cs in 0 ..< ncases:
  let n = nextInt()
  let d = nextInt()
  var q, k, v, o: seq[int]
  for _ in 0 ..< n * d: q.add nextInt()
  for _ in 0 ..< n * d: k.add nextInt()
  for _ in 0 ..< n * d: v.add nextInt()
  for _ in 0 ..< n * d: o.add nextInt()
  let name = "fa_case_" & align($cs, 3, '0')
  var (mem, expected) = buildProgram(q, k, v, n, d)
  expected.add o
  writeLines(ImgDir / (name & ".img"), mem)
  writeLines(ImgDir / (name & ".exp"), expected)
  let res = runSubleq(mem, @[], 1_000_000)
  if res.fault.len > 0: fail name, "fault: " & res.fault
  elif not res.halted: fail name, "did not halt"
  elif res.output != expected: fail name, "output differs from the Python model"
  else: inc passes

# FA error handling: invalid descriptors fault
for (n, d) in [(0, 4), (4, 0), (4, 17)]:
  var (mem, _) = buildProgram(@[0], @[0], @[0], 1, 1)
  mem[Desc + 4] = n
  mem[Desc + 5] = d
  let res = runSubleq(mem, @[], 100_000)
  if res.fault.len == 0: fail "invalid-desc", "expected a fault for N=" & $n & " d=" & $d
  else: inc passes

# Brainfuck programs for the RTL CPU (word semantics are identical)
const HelloBF = "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++."
for (name, bf, input) in [("bf_hello", HelloBF, newSeq[int]()),
                          ("bf_nested", "++[>++[>++<-]<-]>>.", newSeq[int]()),
                          ("bf_negative", "---[+]>-.", newSeq[int]()),
                          ("bf_cat", ",[.,]", @[104, 105, 33])]:
  let tr = brainfuckToSubleq(bf, 64)
  let ref0 = runBF(bf, input, 64)
  doAssert tr.error.len == 0 and ref0.error.len == 0
  writeLines(ImgDir / (name & ".img"), tr.mem)
  writeLines(ImgDir / (name & ".exp"), ref0.output)
  writeLines(ImgDir / (name & ".in"), input)
  var mem = tr.mem
  let res = runSubleq(mem, input, 5_000_000)
  if res.output != ref0.output or not res.halted: fail name, "transpiled program differs from reference"
  else: inc passes

echo "passed: ", passes, "  failed: ", failures
if failures > 0: quit 1
