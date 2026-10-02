# Normalized Intermediate Representation (IR)
# Contract between Agent 1 (Parser) and Agent 2 (Codegen)
# Stable, deterministic, supports hybrid BCPL/Befunge semantics

import std/[tables, sets, hashes, algorithm]

type
  # ─────────────────────────────────────────────────────────────
  # IR Node Types
  # ─────────────────────────────────────────────────────────────

  Literal* = object
    value*: int

  Variable* = object
    name*: string
    index*: int  # Unique ID for register allocation

  BinaryOp* = enum
    opAdd = "+"
    opSub = "-"
    opMul = "*"
    opDiv = "/"
    opMod = "%"
    opGt = ">"
    opLt = "<"
    opEq = "=="
    opNe = "!="
    opGe = ">="
    opLe = "<="
    opLogicalAnd = "&&"
    opLogicalOr = "||"

  UnaryOp* = enum
    opNot = "!"
    opNeg = "-"

  IRExprKind* = enum
    irLit, irVar, irBinOp, irUnOp, irCall, irIndex

  IRExpr* = ref object
    case kind*: IRExprKind
    of irLit:
      litValue*: int
    of irVar:
      varName*: string
      varId*: int
    of irBinOp:
      binOp*: BinaryOp
      left*: IRExpr
      right*: IRExpr
    of irUnOp:
      unOp*: UnaryOp
      operand*: IRExpr
    of irCall:
      funcName*: string
      args*: seq[IRExpr]
    of irIndex:
      arrayExpr*: IRExpr
      indexExpr*: IRExpr

  IRStmtKind* = enum
    irAssign, irOutput, irInput, irIf, irWhile, irFor, irMemSet, irPtrMove, irBreak, irContinue

  IRStmt* = ref object
    case kind*: IRStmtKind
    of irAssign:
      assignTarget*: string
      assignValue*: IRExpr
    of irOutput:
      outputExpr*: IRExpr
    of irInput:
      inputTarget*: string
    of irIf:
      condition*: IRExpr
      thenBranch*: seq[IRStmt]
      elseBranch*: seq[IRStmt]
    of irWhile:
      whileCondition*: IRExpr
      whileBody*: seq[IRStmt]
    of irFor:
      forVar*: string
      forStart*: IRExpr
      forEnd*: IRExpr
      forBody*: seq[IRStmt]
    of irMemSet:
      memAddr*: IRExpr
      memValue*: IRExpr
      memSize*: IRExpr
    of irPtrMove:
      pointerDelta*: int
    of irBreak, irContinue:
      discard

  IRFunction* = object
    name*: string
    params*: seq[string]
    locals*: seq[string]
    body*: seq[IRStmt]

  IRProgram* = object
    functions*: seq[IRFunction]
    globals*: seq[string]
    main*: seq[IRStmt]
    typeInfo*: Table[string, string]  # variable name -> type

  # ─────────────────────────────────────────────────────────────
  # Compilation result
  # ─────────────────────────────────────────────────────────────

  CompileResult* = object
    program*: IRProgram
    errors*: seq[string]
    warnings*: seq[string]

  # ─────────────────────────────────────────────────────────────
  # Execution trace for differential testing
  # ─────────────────────────────────────────────────────────────

  ExecutionTrace* = object
    statements*: seq[string]
    output*: seq[int]
    memoryState*: Table[int, int]
    halted*: bool
    faultMessage*: string

# ─────────────────────────────────────────────────────────────
# Constructors for easy IR building
# ─────────────────────────────────────────────────────────────

proc intLit*(v: int): IRExpr =
  var e: IRExpr
  new e
  e.kind = irLit
  e.litValue = v
  e

proc varRef*(name: string; id: int = 0): IRExpr =
  var e: IRExpr
  new e
  e.kind = irVar
  e.varName = name
  e.varId = id
  e

proc binOp*(op: BinaryOp; l: IRExpr; r: IRExpr): IRExpr =
  var e: IRExpr
  new e
  e.kind = irBinOp
  e.binOp = op
  e.left = l
  e.right = r
  e

proc unOp*(op: UnaryOp; operand: IRExpr): IRExpr =
  var e: IRExpr
  new e
  e.kind = irUnOp
  e.unOp = op
  e.operand = operand
  e

proc assign*(target: string; value: IRExpr): IRStmt =
  var s: IRStmt
  new s
  s.kind = irAssign
  s.assignTarget = target
  s.assignValue = value
  s

proc outputStmt*(expr: IRExpr): IRStmt =
  var s: IRStmt
  new s
  s.kind = irOutput
  s.outputExpr = expr
  s

proc inputStmt*(target: string): IRStmt =
  var s: IRStmt
  new s
  s.kind = irInput
  s.inputTarget = target
  s

proc ifStmt*(cond: IRExpr; thenBr: seq[IRStmt]; elseBr: seq[IRStmt] = @[]): IRStmt =
  var s: IRStmt
  new s
  s.kind = irIf
  s.condition = cond
  s.thenBranch = thenBr
  s.elseBranch = elseBr
  s

proc whileStmt*(cond: IRExpr; body: seq[IRStmt]): IRStmt =
  var s: IRStmt
  new s
  s.kind = irWhile
  s.whileCondition = cond
  s.whileBody = body
  s

# ─────────────────────────────────────────────────────────────
# IR Validation and normalization
# ─────────────────────────────────────────────────────────────

proc validateProgram*(prog: IRProgram): seq[string] =
  var errors: seq[string]
  var seenVars = initHashSet[string]()

  for v in prog.globals:
    if v in seenVars:
      errors.add("Duplicate global variable: " & v)
    seenVars.incl v

  # Validate main body references only declared variables
  # (simplified; full validator goes in Agent 3)

  errors

proc normalizeProgram*(prog: IRProgram): IRProgram =
  # Deterministic normalization: stable ordering, deduplication
  var normalized = prog
  # Sort globals and locals for deterministic compilation
  normalized.globals.sort()
  for fn in normalized.functions.mitems:
    fn.params.sort()
    fn.locals.sort()
  normalized
