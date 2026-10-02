# Hybrid code generator: AST → SUBLEQ machine code
# Converts unified Befunge/Brainfuck AST to deterministic SUBLEQ triads
# Compile: nim c -d:release hybrid_codegen.nim

import hybrid_ast
import subleq_bf

const
  # Memory layout: fixed zones (matches subleq_bf.nim)
  Z = 0          # zero (constant 0)
  ONE = 3        # one (constant 1)
  M1 = 4         # minus one (constant -1)
  P = 5          # BF pointer
  NP = 6         # negative pointer (-P)
  T = 7          # temp
  U = 8          # temp
  CODE0 = 9
  NEXT = low(int)

proc codegenBrainfuck*(prog: Program; tapeCells = 256): Transpiled =
  if tapeCells <= 0:
    var err: Transpiled
    err.error = "tapeCells must be positive"
    return err

  var code: seq[int]
  var baseFix: seq[int]
  var loops: seq[tuple[patch, body: int]]

  proc here(): int = CODE0 + code.len

  proc tri(a, b: int; c = NEXT) =
    let at = here()
    code.add a
    code.add b
    code.add (if c == NEXT: at + 3 else: c)

  proc viaPtr(a, b, field: int) =
    let target = here() + 3 + field
    tri(NP, target)
    baseFix.add target - CODE0
    tri(a, b)
    tri(P, target)

  proc loadTest() =
    tri(T, T)
    viaPtr(0, T, 0)
    tri(U, U)
    tri(T, U)

  # Generate code for each instruction
  for i, instr in prog.instrs:
    case instr.kind
    of ikPtrInc:
      tri(M1, P)
      tri(ONE, NP)
    of ikPtrDec:
      tri(ONE, P)
      tri(M1, NP)
    of ikCellInc:
      viaPtr(M1, 0, 1)
    of ikCellDec:
      viaPtr(ONE, 0, 1)
    of ikCellOut:
      viaPtr(0, -1, 0)
    of ikCellIn:
      viaPtr(-1, 0, 1)
    of ikLoopStart:
      loadTest()
      let p = here()
      tri(Z, T, p + 6)
      tri(Z, Z, p + 9)
      tri(Z, U, 0)
      loops.add (patch: p + 6 + 2 - CODE0, body: p + 9)
    of ikLoopEnd:
      if loops.len == 0:
        var err: Transpiled
        err.error = "unmatched loop end"
        return err
      let lp = loops.pop()
      loadTest()
      let p = here()
      tri(Z, T, p + 6)
      tri(Z, Z, lp.body)
      tri(Z, U, p + 12)
      tri(Z, Z, lp.body)
      code[lp.patch] = p + 12
    of ikHalt:
      tri(Z, Z, -1)
    else:
      var err: Transpiled
      err.error = "unimplemented instruction: " & $instr.kind
      return err

  if prog.instrs.len == 0 or prog.instrs[prog.instrs.len - 1].kind != ikHalt:
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

proc codegen*(prog: Program; tapeCells = 256): Transpiled =
  case prog.mode
  of modeBrainfuck:
    codegenBrainfuck(prog, tapeCells)
  of modeBefunge:
    var err: Transpiled
    err.error = "Befunge code generation not yet implemented"
    return err
  of modeHybrid:
    codegenBrainfuck(prog, tapeCells)
