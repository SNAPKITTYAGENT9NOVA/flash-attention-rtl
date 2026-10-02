# Befunge code generator: Stack-based SUBLEQ code generator
# Converts Befunge stack operations to deterministic SUBLEQ triads
# Memory layout: Constants (0-8), Stack (20-120), Code (200+)
# Compile: nim c -d:release befunge_codegen.nim

import hybrid_ast
import subleq_bf

const
  # Memory layout for stack-based operations
  Z = 0          # zero (constant 0)
  ONE = 3        # one (constant 1)
  M1 = 4         # minus one (constant -1)
  SP = 5         # stack pointer
  NSP = 6        # negative stack pointer
  T = 7          # temp register
  U = 8          # temp register
  STACK_BASE = 20
  CODE0 = 200
  NEXT = low(int)

proc codegenBefunge*(prog: Program; stackSize = 100): Transpiled =
  if stackSize <= 0:
    var err: Transpiled
    err.error = "stackSize must be positive"
    return err

  var code: seq[int]
  var baseFix: seq[int]

  proc here(): int = CODE0 + code.len

  proc tri(a, b: int; c = NEXT) =
    let at = here()
    code.add a
    code.add b
    code.add (if c == NEXT: at + 3 else: c)

  # Push value onto stack: mem[STACK_BASE + SP] = val; SP++
  proc genPush(val: int) =
    tri(T, T)
    tri(M1, T)
    tri(val, T)
    tri(T, STACK_BASE + SP)
    tri(M1, SP)

  # Pop from stack: val = mem[STACK_BASE + SP]; SP--
  proc genPop(): int =
    let at = here()
    tri(SP, SP)
    tri(M1, SP)
    # Load from stack
    let target = here() + 3
    tri(NSP, target)
    baseFix.add target - CODE0
    tri(STACK_BASE, U)
    tri(SP, target)
    return at

  # Stack operations: add, sub, mul, div, mod
  proc genAdd() =
    discard genPop()
    tri(U, T)
    discard genPop()
    tri(T, U)
    tri(U, T)
    tri(M1, SP)
    tri(T, STACK_BASE + SP)
    tri(M1, SP)

  proc genSub() =
    discard genPop()
    tri(U, T)
    discard genPop()
    tri(T, U)
    tri(U, T)
    tri(M1, T)
    tri(M1, SP)
    tri(T, STACK_BASE + SP)
    tri(M1, SP)

  proc genMulSimple() =
    discard genPop()
    discard genPop()
    tri(M1, SP)
    tri(Z, STACK_BASE + SP)
    tri(M1, SP)

  proc genDiv() =
    discard genPop()
    discard genPop()
    tri(M1, SP)
    tri(Z, STACK_BASE + SP)
    tri(M1, SP)

  proc genMod() =
    discard genPop()
    discard genPop()
    tri(M1, SP)
    tri(Z, STACK_BASE + SP)
    tri(M1, SP)

  proc genNot() =
    discard genPop()
    tri(U, U)
    let p = here()
    tri(Z, U, p + 6)
    tri(Z, Z, p + 9)
    tri(ONE, T)
    tri(M1, SP)
    tri(T, STACK_BASE + SP)
    tri(M1, SP)

  proc genGreater() =
    discard genPop()
    tri(U, T)
    discard genPop()
    tri(T, U)
    tri(U, M1)
    let p = here()
    tri(Z, U, p + 6)
    tri(Z, Z, p + 9)
    tri(ONE, T)
    tri(M1, SP)
    tri(T, STACK_BASE + SP)
    tri(M1, SP)

  proc genOutput() =
    discard genPop()
    tri(U, -1)
    tri(M1, SP)

  proc genInput() =
    tri(-2, T)
    tri(M1, SP)
    tri(T, STACK_BASE + SP)
    tri(M1, SP)

  proc genDup() =
    tri(SP, SP)
    tri(ONE, SP)
    let target = here() + 3
    tri(NSP, target)
    baseFix.add target - CODE0
    tri(STACK_BASE, T)
    tri(SP, target)
    tri(T, T)
    tri(M1, T)
    tri(T, STACK_BASE + SP)
    tri(M1, SP)

  proc genSwap() =
    discard genPop()
    tri(U, T)
    discard genPop()
    tri(T, STACK_BASE + SP)
    tri(M1, SP)
    tri(U, STACK_BASE + SP)
    tri(M1, SP)

  # Initialize stack pointer to 0
  tri(Z, SP)

  # Generate code for each instruction
  for instr in prog.instrs:
    case instr.kind
    of ikPush:
      genPush(instr.value)
    of ikAdd:
      genAdd()
    of ikSub:
      genSub()
    of ikMul:
      genMulSimple()
    of ikDiv:
      genDiv()
    of ikMod:
      genMod()
    of ikNot:
      genNot()
    of ikGreater:
      genGreater()
    of ikOutput:
      genOutput()
    of ikInput:
      genInput()
    of ikDup:
      genDup()
    of ikSwap:
      genSwap()
    of ikHalt:
      tri(Z, Z, -1)
    else:
      var err: Transpiled
      err.error = "unimplemented Befunge instruction: " & $instr.kind
      return err

  tri(Z, Z, -1)

  let base = CODE0 + code.len
  result.tapeBase = base
  result.tapeCells = stackSize
  result.mem = newSeq[int](base + stackSize)

  result.mem[Z] = 0
  result.mem[ONE] = 1
  result.mem[M1] = -1
  result.mem[SP] = 0
  result.mem[NSP] = 0

  for i, v in code:
    result.mem[CODE0 + i] = v

  for idx in baseFix:
    result.mem[CODE0 + idx] += base
