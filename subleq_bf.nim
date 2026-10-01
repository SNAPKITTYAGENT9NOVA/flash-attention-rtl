# SUBLEQ interpreter + Brainfuck -> SUBLEQ transpiler (self-modifying, J-style
# indexed tape access) + a reference Brainfuck interpreter for testing.
#
# SUBLEQ has no indirect addressing, so tape[ptr] is reached by patching the
# operand field of the instruction that touches the tape:
#   operand += ptr   ->   execute   ->   operand -= ptr
#
# Semantics (cells are unbounded signed ints, no 8-bit wrap):
#   a < 0          : read next input value (0 on EOF) into mem[b]; pc += 3
#   b < 0          : append mem[a] to output; pc += 3
#   otherwise      : mem[b] -= mem[a]; pc = (mem[b] <= 0) ? c : pc + 3
#   pc < 0         : halt
# BF pointer outside [0, tapeCells) is undefined in the compiled program
# (the reference interpreter reports it as an error).

type
  RunResult* = object
    output*: seq[int]
    steps*: int
    halted*: bool
    fault*: string

proc runSubleq*(mem: var seq[int]; input: seq[int] = @[]; maxSteps = 1_000_000): RunResult =
  var pc = 0
  var inPos = 0
  while true:
    if pc < 0:
      result.halted = true
      return
    if pc + 2 >= mem.len:
      result.fault = "pc " & $pc & " out of range"
      return
    if result.steps >= maxSteps:
      result.fault = "step limit reached"
      return
    inc result.steps
    let a = mem[pc]
    let b = mem[pc + 1]
    let c = mem[pc + 2]
    if a < 0:
      if b < 0 or b >= mem.len:
        result.fault = "bad input target " & $b & " at pc " & $pc
        return
      mem[b] = if inPos < input.len: input[inPos] else: 0
      inc inPos
      pc += 3
    elif b < 0:
      if a >= mem.len:
        result.fault = "bad output source " & $a & " at pc " & $pc
        return
      result.output.add mem[a]
      pc += 3
    else:
      if a >= mem.len or b >= mem.len:
        result.fault = "operand out of range at pc " & $pc
        return
      mem[b] -= mem[a]
      pc = if mem[b] <= 0: c else: pc + 3

# ─────────────────────────────────────────────────────────────────────────
# Transpiler
#
# Memory layout:
#   0..2   [0, 0, CODE0]  entry triad (also makes mem[0] the zero cell Z)
#   3 ONE=1   4 M1=-1   5 P=ptr   6 NP=-ptr   7 T (scratch)   8 U (scratch)
#   CODE0=9 .. codeEnd    compiled triads (last one halts)
#   tapeBase ..           BF tape, tapeCells cells
# ─────────────────────────────────────────────────────────────────────────

const
  Z = 0
  ONE = 3
  M1 = 4
  P = 5
  NP = 6
  T = 7
  U = 8
  CODE0 = 9
  NEXT = low(int)

type
  Transpiled* = object
    mem*: seq[int]
    tapeBase*: int
    tapeCells*: int
    error*: string

const
  PtrCell* = P
  NegPtrCell* = NP

proc brainfuckToSubleq*(bf: string; tapeCells = 256): Transpiled =
  if tapeCells <= 0:
    result.error = "tapeCells must be positive"
    return

  var code: seq[int]
  var baseFix: seq[int]
  var loops: seq[tuple[patch, body: int]]

  proc here(): int = CODE0 + code.len

  proc tri(a, b: int; c = NEXT) =
    let at = here()
    code.add a
    code.add b
    code.add (if c == NEXT: at + 3 else: c)

  # Emit: patch operand += ptr; instruction; operand -= ptr.
  # field 0 = a is indirect, field 1 = b is indirect (that operand is a 0 placeholder
  # that later receives tapeBase).
  proc viaPtr(a, b, field: int) =
    let target = here() + 3 + field
    tri(NP, target)
    baseFix.add target - CODE0
    tri(a, b)
    tri(P, target)

  # T := -tape[ptr]; U := tape[ptr]
  proc loadTest() =
    tri(T, T)
    viaPtr(0, T, 0)
    tri(U, U)
    tri(T, U)

  for i, ch in bf:
    case ch
    of '>':
      tri(M1, P)
      tri(ONE, NP)
    of '<':
      tri(ONE, P)
      tri(M1, NP)
    of '+': viaPtr(M1, 0, 1)
    of '-': viaPtr(ONE, 0, 1)
    of '.': viaPtr(0, -1, 0)
    of ',': viaPtr(-1, 0, 1)
    of '[':
      # zero test: x < 0 -> body, x == 0 -> past matching ']', x > 0 -> body
      loadTest()
      let p = here()
      tri(Z, T, p + 6)
      tri(Z, Z, p + 9)
      tri(Z, U, 0)
      loops.add (patch: p + 6 + 2 - CODE0, body: p + 9)
    of ']':
      if loops.len == 0:
        result.error = "unmatched ']' at index " & $i
        return
      let lp = loops.pop()
      loadTest()
      let p = here()
      tri(Z, T, p + 6)
      tri(Z, Z, lp.body)
      tri(Z, U, p + 12)
      tri(Z, Z, lp.body)
      code[lp.patch] = p + 12
    else: discard

  if loops.len > 0:
    result.error = "unmatched '[' (" & $loops.len & " unclosed)"
    return

  tri(Z, Z, -1)

  let base = CODE0 + code.len
  result.tapeBase = base
  result.tapeCells = tapeCells
  result.mem = newSeq[int](base + tapeCells)
  result.mem[2] = CODE0
  result.mem[ONE] = 1
  result.mem[M1] = -1
  for i, v in code:
    result.mem[CODE0 + i] = v
  for idx in baseFix:
    result.mem[CODE0 + idx] += base

# ─────────────────────────────────────────────────────────────────────────
# Reference Brainfuck interpreter (same cell semantics as the transpiler)
# ─────────────────────────────────────────────────────────────────────────

type
  BFResult* = object
    output*: seq[int]
    tape*: seq[int]
    ptrPos*: int
    steps*: int
    error*: string

proc runBF*(bf: string; input: seq[int] = @[]; tapeCells = 256; maxSteps = 1_000_000): BFResult =
  var jump = newSeq[int](bf.len)
  var stack: seq[int]
  for i, ch in bf:
    if ch == '[':
      stack.add i
    elif ch == ']':
      if stack.len == 0:
        result.error = "unmatched ']' at index " & $i
        return
      let j = stack.pop()
      jump[i] = j
      jump[j] = i
  if stack.len > 0:
    result.error = "unmatched '[' (" & $stack.len & " unclosed)"
    return

  result.tape = newSeq[int](tapeCells)
  var ip = 0
  var inPos = 0
  while ip < bf.len:
    if result.steps >= maxSteps:
      result.error = "step limit reached"
      return
    inc result.steps
    case bf[ip]
    of '>':
      inc result.ptrPos
      if result.ptrPos >= tapeCells:
        result.error = "pointer out of range"
        return
    of '<':
      dec result.ptrPos
      if result.ptrPos < 0:
        result.error = "pointer out of range"
        return
    of '+': inc result.tape[result.ptrPos]
    of '-': dec result.tape[result.ptrPos]
    of '.': result.output.add result.tape[result.ptrPos]
    of ',':
      result.tape[result.ptrPos] = if inPos < input.len: input[inPos] else: 0
      inc inPos
    of '[':
      if result.tape[result.ptrPos] == 0: ip = jump[ip]
    of ']':
      if result.tape[result.ptrPos] != 0: ip = jump[ip]
    else: discard
    inc ip
