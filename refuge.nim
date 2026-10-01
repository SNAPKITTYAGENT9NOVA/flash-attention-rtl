# Refuge – deterministic offline computational sanctuary
# Built only on SUBLEQ + φ-Born attention
# BF→SUBLEQ-J: Brainfuck to SUBLEQ using J array semantics
# Compile: nim c -d:release -r refuge.nim

import std/[sequtils, math, random, strutils, os, times, strformat, tables]

const
  MEM_SIZE     = 256
  PHI          = 1.6180339887
  PHI_INV      = 1.0 / PHI
  MAX_STEPS    = 2000
  N_HEADS      = 4
  HEAD_DIM     = 8
  MAX_CYCLES   = 128
  BF_MEM       = 30000
  CHECKPOINT   = "refuge.chk"

type
  Mem = seq[int]
  Action = enum
    ActObserve, ActPlan, ActWrite, ActEdit, ActRun,
    ActTest, ActReflect, ActHalt,
    ActEmitBF, ActRunBF, ActOptimiseSUBLEQ,
    ActTranspileSUBLEQtoBF, ActTranspileBFtoSUBLEQJ, ActEnterRefuge, ActRecover

  AgentState = object
    goal: string
    code: string
    lastOutput: string
    lastError: string
    history: seq[string]
    cycle: int
    done: bool
    score: float
    bfTape: seq[int]
    lastSUBLEQ: seq[int]
    inRefuge: bool
    recovered: bool

# ═══════════════════════════════════════════════════════════════
# SUBLEQ core (deterministic, pure)
# ═══════════════════════════════════════════════════════════════

proc subleqStep(instr: array[3, int], pc: int, mem: var Mem): tuple[mem: Mem, pc: int] =
  let a = instr[0]
  let b = instr[1]
  let c = instr[2]
  if a == -1: return (mem, pc + 3)
  elif b == -1: return (mem, -1)
  else:
    let val = mem[b] - mem[a]
    mem[b] = val
    let npc = if val <= 0: c else: pc + 3
    return (mem, npc)

proc subleqRun(maxSteps: int, mem: var Mem): tuple[output: seq[int], mem: Mem] =
  var pc = 0
  var output: seq[int] = @[]
  for _ in 0 ..< maxSteps:
    if pc < 0 or pc >= mem.len: break
    let a = mem[pc]
    let b = mem[pc+1]
    let c = mem[pc+2]
    if a == -1:
      output.add mem[b]
      pc += 3
    elif b == -1: break
    else:
      let (newMem, newPc) = subleqStep([a, b, c], pc, mem)
      mem = newMem
      pc = newPc
  (output, mem)

proc activationsToTriads(activations: seq[float]): seq[int] =
  var addrs = activations.mapIt(max(1, min(255, int(256.0 * abs(it)))))
  let n = 3 * (addrs.len div 3)
  addrs = addrs[0 ..< n]
  result = @[]
  for i in countup(0, n-1, 3):
    result.add addrs[i]
    result.add addrs[i+1]
    result.add addrs[i+2]

proc phiWeights(n: int): seq[float] =
  result = newSeq[float](n)
  for i in 0 ..< n:
    result[i] = pow(PHI_INV, float(i))

proc bornCollapse(v: seq[float]): int =
  let w = phiWeights(v.len)
  var s = 0.0
  for i in 0 ..< v.len:
    s += w[i] * v[i]
  int(floor(s)) mod 256

proc attentionHead(activations: seq[float]): seq[int] =
  let triads = activationsToTriads(activations)
  var mem = newSeq[int](MEM_SIZE)
  for i, t in triads:
    if i < MEM_SIZE: mem[i] = t
  let haltPos = min(triads.len, MEM_SIZE-3)
  mem[haltPos] = -1
  mem[haltPos+1] = -1
  mem[haltPos+2] = -1
  for i in 0 ..< (min(128, 192-128)):
    if i < activations.len:
      mem[128+i] = int(1000.0 * activations[i])
  let res = subleqRun(MAX_STEPS, mem)
  res.output

proc multiheadAttention(heads: seq[seq[float]]): seq[int] =
  result = @[]
  for head in heads:
    let attOut = attentionHead(head)
    if attOut.len > 0:
      result.add bornCollapse(attOut.mapIt(float(it)))

# ═══════════════════════════════════════════════════════════════
# Brainfuck interpreter
# ═══════════════════════════════════════════════════════════════

proc runBrainfuck(code: string, input = ""): tuple[output: string, tape: seq[int]] =
  var tape = newSeq[int](BF_MEM)
  var tapePtr, ip, inpIdx = 0
  var outStr = ""
  var loopStack: seq[int] = @[]
  while ip < code.len:
    case code[ip]
    of '>': tapePtr = (tapePtr+1) mod BF_MEM
    of '<': tapePtr = (tapePtr-1+BF_MEM) mod BF_MEM
    of '+': tape[tapePtr] = (tape[tapePtr]+1) and 0xFF
    of '-': tape[tapePtr] = (tape[tapePtr]-1) and 0xFF
    of '.': outStr.add char(tape[tapePtr])
    of ',':
      if inpIdx < input.len:
        tape[tapePtr] = ord(input[inpIdx]); inc inpIdx
      else: tape[tapePtr] = 0
    of '[':
      if tape[tapePtr] == 0:
        var depth = 1
        while depth > 0 and ip < code.len-1:
          inc ip
          if code[ip]=='[': inc depth
          elif code[ip]==']': dec depth
      else: loopStack.add ip
    of ']':
      if tape[tapePtr] != 0 and loopStack.len > 0: ip = loopStack[^1]
      elif loopStack.len > 0: discard loopStack.pop()
    else: discard
    inc ip
  (outStr, tape)

const HelloBF = "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++."

# ═══════════════════════════════════════════════════════════════
# BF → SUBLEQ-J (J array semantics)
# ═══════════════════════════════════════════════════════════════
# Strategy: Treat BF tape as a J-style array
# - Memory cells indexed by pointer
# - SUBLEQ operations on array elements
# - Pointer arithmetic via array indexing
#
# Memory layout for compiled code:
#   [0..N-1]    : array (BF tape)
#   [N]         : pointer cell
#   [N+1]       : increment -1 (for dec)
#   [N+2]       : decrement 1  (for inc)
#   [N+3]       : zero register
#   [N+4..]     : SUBLEQ code

type
  BFCompileCtx = object
    code: seq[int]          # compiled SUBLEQ triads
    arraySize: int
    ptrCell: int
    negOneCell: int
    oneCell: int
    zeroCell: int
    codeStart: int
    loopStack: seq[int]     # stack of loop start positions in SUBLEQ code
    labels: Table[string, int]

proc bfToSubleqJ(bfCode: string, arraySize = 256): tuple[mem: seq[int], labels: Table[string, int], error: string] =
  ## Compile Brainfuck to SUBLEQ using J array semantics
  ## arraySize: BF tape size (J array dimension)
  ## Returns: compiled SUBLEQ memory + label table

  var ctx = BFCompileCtx(
    arraySize: arraySize,
    ptrCell: arraySize,
    negOneCell: arraySize + 1,
    oneCell: arraySize + 2,
    zeroCell: arraySize + 3,
    codeStart: arraySize + 4,
    code: @[],
    loopStack: @[],
    labels: initTable[string, int]()
  )

  # Helper: emit a SUBLEQ triad
  proc emit(a, b, c: int) =
    ctx.code.add a
    ctx.code.add b
    ctx.code.add c

  # Helper: emit current PC label
  proc label(name: string): int =
    let pc = ctx.codeStart + ctx.code.len
    ctx.labels[name] = pc
    pc

  # Helper: indirect access - read/write array[ptr]
  # In SUBLEQ: we can't do indirect indexing natively,
  # so we compile it as: move ptr to a temp, then use as address
  # For now, we keep it simple by expanding loops over possible indices

  proc emitIncArray(): seq[int] =
    ## tape[ptr]++ → subleq -1 tape[ptr] NEXT
    ## We'll emit a simple increment of array element
    @[ctx.negOneCell, 0, ctx.codeStart + ctx.code.len + 3]

  proc emitDecArray(): seq[int] =
    ## tape[ptr]-- → subleq 1 tape[ptr] NEXT
    @[ctx.oneCell, 0, ctx.codeStart + ctx.code.len + 3]

  # Parse and compile BF
  var i = 0
  while i < bfCode.len:
    case bfCode[i]
    of '>':
      # ptr++ → subleq -1 ptrCell NEXT
      emit(ctx.negOneCell, ctx.ptrCell, ctx.codeStart + ctx.code.len + 3)
      inc i

    of '<':
      # ptr-- → subleq 1 ptrCell NEXT
      emit(ctx.oneCell, ctx.ptrCell, ctx.codeStart + ctx.code.len + 3)
      inc i

    of '+':
      # tape[ptr]++ (simplified: affect a fixed cell)
      # Full BF would need dynamic indexing; we simplify here
      emit(ctx.negOneCell, 0, ctx.codeStart + ctx.code.len + 3)  # increment cell 0
      inc i

    of '-':
      # tape[ptr]-- (simplified)
      emit(ctx.oneCell, 0, ctx.codeStart + ctx.code.len + 3)     # decrement cell 0
      inc i

    of '.':
      # output tape[ptr] → subleq -1 0 NEXT (output marker)
      emit(-1, 0, ctx.codeStart + ctx.code.len + 3)
      inc i

    of ',':
      # input tape[ptr] (stub for now)
      inc i

    of '[':
      # loop start: if tape[ptr]==0, skip to matching ]
      let loopStart = ctx.codeStart + ctx.code.len
      ctx.loopStack.add loopStart
      # Placeholder: will patch when we find ]
      emit(0, 0, 0)  # to be patched
      inc i

    of ']':
      # loop end: if tape[ptr]!=0, jump back to [
      if ctx.loopStack.len == 0:
        return (@[], initTable[string, int](), "unmatched ]")
      let loopStart = ctx.loopStack.pop()
      let loopEnd = ctx.codeStart + ctx.code.len
      # Jump back to loop start
      emit(0, 0, loopStart)
      # Patch the [ instruction's skip-target
      ctx.code[loopStart - ctx.codeStart + 2] = loopEnd + 3
      inc i

    else:
      inc i

  # Halt
  emit(-1, -1, -1)

  # Build final memory: [array][ptr][−1][1][0][code]
  var mem = newSeq[int](ctx.codeStart + ctx.code.len)
  # Initialize array and special cells
  for j in 0 ..< ctx.ptrCell: mem[j] = 0
  mem[ctx.ptrCell] = 0      # pointer = 0
  mem[ctx.negOneCell] = -1
  mem[ctx.oneCell] = 1
  mem[ctx.zeroCell] = 0
  # Append code
  for j, v in ctx.code: mem[ctx.codeStart + j] = v

  (mem, ctx.labels, "")

# ═══════════════════════════════════════════════════════════════
# Transpilers
# ═══════════════════════════════════════════════════════════════

proc movePtr(fromPos, toPos: int): string =
  let d = toPos - fromPos
  if d > 0: ">".repeat(d)
  elif d < 0: "<".repeat(-d)
  else: ""

proc bfClear(cell: int): string =
  movePtr(0, cell) & "[-]" & movePtr(cell, 0)

proc transpileSUBLEQtoBF(triads: seq[int], z = 15): string =
  result = ""
  var i = 0
  while i+2 < triads.len:
    let a = triads[i]
    let b = triads[i+1]
    let c = triads[i+2]
    if a == -1 and b == -1:
      result &= "# HALT\n"; break
    if a == b and a >= 0:
      result &= bfClear(a) & " # clear\n"; i += 3; continue
    if a == -1 and b >= 0:
      result &= movePtr(0,b) & "+" & movePtr(b,0) & " # inc\n"; i += 3; continue
    result &= "# sub " & $a & " " & $b & "\n"
    result &= movePtr(0,a) & "[" & movePtr(a,b) & "-" & movePtr(b,a) & "-]" & movePtr(a,0) & "\n"
    i += 3
  result &= movePtr(0,0)

# ═══════════════════════════════════════════════════════════════
# Checkpoint / recovery (Refuge resilience)
# ═══════════════════════════════════════════════════════════════

proc saveCheckpoint(s: AgentState) =
  var lines: seq[string] = @[]
  lines.add "cycle=" & $s.cycle
  lines.add "score=" & $s.score
  lines.add "done=" & $s.done
  lines.add "inRefuge=" & $s.inRefuge
  lines.add "goal=" & s.goal.replace("\n","\\n")
  lines.add "code=" & s.code.replace("\n","\\n")
  lines.add "lastOutput=" & s.lastOutput.replace("\n","\\n")
  lines.add "history=" & s.history.join("|").replace("\n","\\n")
  try:
    writeFile(CHECKPOINT, lines.join("\n"))
  except:
    discard

proc loadCheckpoint(): AgentState =
  result = AgentState(bfTape: newSeq[int](BF_MEM), history: @[], lastSUBLEQ: @[])
  if not fileExists(CHECKPOINT): return
  try:
    let lines = readFile(CHECKPOINT).splitLines()
    for line in lines:
      let parts = line.split('=', 1)
      if parts.len < 2: continue
      case parts[0]
      of "cycle":     result.cycle = parseInt(parts[1])
      of "score":     result.score = parseFloat(parts[1])
      of "done":      result.done = parts[1] == "true"
      of "inRefuge":  result.inRefuge = parts[1] == "true"
      of "goal":      result.goal = parts[1].replace("\\n","\n")
      of "code":      result.code = parts[1].replace("\\n","\n")
      of "lastOutput":result.lastOutput = parts[1].replace("\\n","\n")
      of "history":   result.history = parts[1].replace("\\n","\n").split('|')
      else: discard
    result.recovered = true
  except:
    result.recovered = false

# ═══════════════════════════════════════════════════════════════
# Encoding & action selection
# ═══════════════════════════════════════════════════════════════

proc encodeState(s: AgentState): seq[seq[float]] =
  result = newSeq[seq[float]](N_HEADS)
  let seed = float(s.cycle)*PHI + float(s.goal.len)*0.01 + float(s.code.len)*0.001
  for h in 0..<N_HEADS:
    var vec = newSeq[float](HEAD_DIM)
    for i in 0..<HEAD_DIM:
      let phase = seed + float(h*17 + i*31)*PHI_INV
      vec[i] = abs(sin(phase)) * (0.3 + 0.7*float((s.history.len+i) mod 5)/5.0)
      if s.lastError.len > 0: vec[i] = min(1.0, vec[i]+0.25)
      if s.score > 0.7: vec[i] = max(0.0, vec[i]-0.15)
      if s.inRefuge: vec[i] = vec[i] * 0.85
    result[h] = vec

proc collapseToAction(collapsed: seq[int], inRefuge: bool): Action =
  if collapsed.len == 0: return ActHalt
  let v = collapsed[0] mod (if inRefuge: 8 else: 14)
  if inRefuge:
    case v
    of 0: ActObserve
    of 1: ActReflect
    of 2: ActRun
    of 3: ActTest
    of 4: ActRecover
    of 5: ActEmitBF
    of 6: ActRunBF
    else: ActHalt
  else:
    case v
    of 0: ActObserve
    of 1: ActPlan
    of 2: ActWrite
    of 3: ActEdit
    of 4: ActRun
    of 5: ActTest
    of 6: ActReflect
    of 7: ActEmitBF
    of 8: ActRunBF
    of 9: ActOptimiseSUBLEQ
    of 10: ActTranspileSUBLEQtoBF
    of 11: ActTranspileBFtoSUBLEQJ
    of 12: ActEnterRefuge
    else: ActHalt

# ═══════════════════════════════════════════════════════════════
# Agent actions
# ═══════════════════════════════════════════════════════════════

proc actObserve(s: var AgentState) =
  s.history.add "OBS " & $s.cycle
  echo "[OBS] cycle=", s.cycle, " refuge=", s.inRefuge

proc actPlan(s: var AgentState) =
  s.history.add "PLAN"
  echo "[PLAN]"

proc actWrite(s: var AgentState) =
  s.lastSUBLEQ = @[0,0,3, 1,15,6, 15,2,9, 15,15,12, -1,-1,-1]
  s.code = "SUBLEQ " & $s.lastSUBLEQ
  echo "[WRITE]"

proc actEdit(s: var AgentState) =
  if s.lastSUBLEQ.len == 0: actWrite(s)
  else:
    if s.lastSUBLEQ[^3] != -1:
      s.lastSUBLEQ.add(-1); s.lastSUBLEQ.add(-1); s.lastSUBLEQ.add(-1)
    s.code = "SUBLEQ-edited " & $s.lastSUBLEQ
  echo "[EDIT]"

proc actRun(s: var AgentState) =
  s.lastOutput = "run@" & $s.cycle
  s.score = min(1.0, s.score + 0.08)
  echo "[RUN]"

proc actTest(s: var AgentState) =
  if s.code.len > 4:
    s.score = min(1.0, s.score + 0.12)
    s.lastError = ""
    echo "[TEST] pass"
  else:
    s.lastError = "short"
    s.score = max(0.0, s.score - 0.08)
    echo "[TEST] fail"

proc actReflect(s: var AgentState) =
  echo "[REFLECT] score=", s.score, " history=", s.history.len
  s.history.add "REFLECT"

proc actHalt(s: var AgentState) =
  s.done = true
  echo "[HALT]"

proc actEmitBF(s: var AgentState) =
  s.code = HelloBF
  echo "[EMIT-BF]"

proc actRunBF(s: var AgentState) =
  if not (s.code.contains("+") or s.code.contains("[")):
    actEmitBF(s)
  let (bfOut, tape) = runBrainfuck(s.code)
  s.lastOutput = bfOut
  s.bfTape = tape
  s.score = min(1.0, s.score + 0.25)
  echo "[RUN-BF] → \"", bfOut, "\""

proc actOptimiseSUBLEQ(s: var AgentState) =
  if s.lastSUBLEQ.len == 0: actWrite(s)
  s.score = min(1.0, s.score + 0.15)
  echo "[OPTIMISE]"

proc actTranspileSUBLEQtoBF(s: var AgentState) =
  if s.lastSUBLEQ.len == 0: actWrite(s)
  s.code = transpileSUBLEQtoBF(s.lastSUBLEQ)
  s.score = min(1.0, s.score + 0.20)
  echo "[TRANSPILE SUBLEQ→BF] ", s.code.len, " chars"

proc actTranspileBFtoSUBLEQJ(s: var AgentState) =
  ## BF → SUBLEQ using J array semantics
  if s.code.len == 0:
    actEmitBF(s)
  let (mem, labels, err) = bfToSubleqJ(s.code)
  if err.len > 0:
    s.lastError = err
    echo "[TRANSPILE BF→SUBLEQ-J] ERROR: ", err
    return
  s.lastSUBLEQ = mem
  s.score = min(1.0, s.score + 0.25)
  echo "[TRANSPILE BF→SUBLEQ-J] ", mem.len, " words, ", labels.len, " labels"

proc actEnterRefuge(s: var AgentState) =
  s.inRefuge = true
  s.history.add "ENTERED REFUGE"
  echo """
╔════════════════════════════════════════╗
║          R E F U G E                   ║
║  deterministic • offline • minimal     ║
║  SUBLEQ core + φ-Born + J-array only   ║
╚════════════════════════════════════════╝"""
  saveCheckpoint(s)

proc actRecover(s: var AgentState) =
  echo "[RECOVER] restoring calm state"
  s.lastError = ""
  s.score = max(s.score, 0.4)
  s.history.add "RECOVERED"
  saveCheckpoint(s)

# ═══════════════════════════════════════════════════════════════
# Main Refuge loop
# ═══════════════════════════════════════════════════════════════

proc runRefuge(goal: string) =
  randomize()
  var state = loadCheckpoint()
  if state.recovered:
    echo "† Resumed from checkpoint (cycle ", state.cycle, ")"
  else:
    state.goal = goal
    state.bfTape = newSeq[int](BF_MEM)

  echo "=== REFUGE ==="
  echo "Goal: ", state.goal
  echo "Mode: ", if state.inRefuge: "INSIDE REFUGE (restricted)" else: "OPEN"
  echo "Engines: SUBLEQ | Brainfuck | φ-Born Attention | J-array"
  echo "=============="

  while not state.done and state.cycle < MAX_CYCLES:
    inc state.cycle
    echo "\n--- cycle ", state.cycle, " ---"

    let heads = encodeState(state)
    let collapsed = multiheadAttention(heads)
    let action = collapseToAction(collapsed, state.inRefuge)
    echo "attention → ", action

    case action
    of ActObserve:             actObserve(state)
    of ActPlan:                actPlan(state)
    of ActWrite:               actWrite(state)
    of ActEdit:                actEdit(state)
    of ActRun:                 actRun(state)
    of ActTest:                actTest(state)
    of ActReflect:             actReflect(state)
    of ActHalt:                actHalt(state)
    of ActEmitBF:              actEmitBF(state)
    of ActRunBF:               actRunBF(state)
    of ActOptimiseSUBLEQ:      actOptimiseSUBLEQ(state)
    of ActTranspileSUBLEQtoBF: actTranspileSUBLEQtoBF(state)
    of ActTranspileBFtoSUBLEQJ:actTranspileBFtoSUBLEQJ(state)
    of ActEnterRefuge:         actEnterRefuge(state)
    of ActRecover:             actRecover(state)

    if state.cycle mod 7 == 0:
      saveCheckpoint(state)

    if state.score >= 0.93:
      echo "\n*** Refuge goal satisfied ***"
      state.done = true

  saveCheckpoint(state)
  echo "\n=== Refuge final ==="
  echo "Cycles : ", state.cycle
  echo "Score  : ", state.score
  echo "In refuge: ", state.inRefuge
  if state.lastOutput.len > 0:
    echo "Last output: ", state.lastOutput
  echo "Checkpoint written to ", CHECKPOINT

when isMainModule:
  let g = if paramCount() > 0: paramStr(1)
          else: "Maintain a stable offline computational refuge"
  runRefuge(g)
