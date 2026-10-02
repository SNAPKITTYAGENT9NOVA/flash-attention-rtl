# Hybrid AST: Befunge + Brainfuck + BCPL → SUBLEQ
# Type definitions for the abstract syntax tree, memory layout, and control flow.
#
# Semantics: All values are unbounded signed integers. No floating point.
# Memory is addressable by index. Befunge 2D grid maps to a flat code region.
# BCPL variables reserve cells in a static layout.
# Brainfuck tape is dynamically addressable via pointer register.

type
  # ───────────────────────────────────────────────────────────────────────────
  # Befunge operations: 2D, deterministic, no randomness
  # ───────────────────────────────────────────────────────────────────────────

  BefungeOp* = enum
    BfNop      = "nop"       # no operation
    BfRight    = ">"         # direction: right (east)
    BfLeft     = "<"         # direction: left (west)
    BfDown     = "v"         # direction: down (south)
    BfUp       = "^"         # direction: up (north)
    BfPush     = "0"         # push digit onto stack
    BfAdd      = "+"         # pop b, a → push a + b
    BfSub      = "-"         # pop b, a → push a - b
    BfMul      = "*"         # pop b, a → push a * b
    BfDiv      = "/"         # pop b, a → push a / b (trap if b == 0)
    BfMod      = "%"         # pop b, a → push a % b (trap if b == 0)
    BfNot      = "!"         # pop a → push (a == 0 ? 1 : 0)
    BfCmpGt    = "`"         # pop b, a → push (a > b ? 1 : 0)
    BfHRotate  = "]"         # rotate stack right
    BfHRotateL = "["         # rotate stack left
    BfDup      = ":"         # duplicate top of stack
    BfPop      = "$"         # discard top of stack
    BfSwap     = "\""        # swap top two stack values (quote)
    BfMGet     = "g"         # pop y, x → push cell[x, y]
    BfMPut     = "p"         # pop y, x, v → set cell[x, y] = v
    BfInput    = "&"         # read integer from input
    BfOutput   = "."         # pop a → output integer
    BfOutputAscii = ","      # pop a → output char (a as ASCII)
    BfExit     = "@"         # terminate

  # ───────────────────────────────────────────────────────────────────────────
  # Brainfuck operations: tape-based pointer, memory indirect operations
  # ───────────────────────────────────────────────────────────────────────────

  BrainfuckOp* = enum
    BfcPtrInc  = ">"        # ++ptr (invariant: 0 <= ptr < tapeCells)
    BfcPtrDec  = "<"        # --ptr
    BfcCellInc = "+"        # ++tape[ptr]
    BfcCellDec = "-"        # --tape[ptr]
    BfcOutput  = "."        # output tape[ptr]
    BfcInput   = ","        # tape[ptr] := read input
    BfcLoopBeg = "["        # if tape[ptr] == 0: jump to matching ]
    BfcLoopEnd = "]"        # if tape[ptr] != 0: jump to matching [

  # ───────────────────────────────────────────────────────────────────────────
  # BCPL variable declarations (static storage allocation)
  # ───────────────────────────────────────────────────────────────────────────

  VarDecl* = object
    name*: string            # variable identifier
    cellAddr*: int           # assigned memory address (>= 0)
    initialValue*: int       # cell initialized to this value (default 0)
    isArray*: bool           # array vs. scalar
    arraySize*: int          # if isArray: number of cells (>= 1)
    isConst*: bool           # const vs. mutable

  # ───────────────────────────────────────────────────────────────────────────
  # AST Node: Any operation in the hybrid language
  # ───────────────────────────────────────────────────────────────────────────

  ASTNodeKind* = enum
    astBefunge           # Befunge operation
    astBrainfuck         # Brainfuck operation
    astSeq               # sequence: execute children in order
    astIf                # conditional: guard, thenBranch, elseBranch (2D control flow)
    astLoop              # loop: condition, body (Befunge or Brainfuck)
    astCall              # function call (subroutine)
    astVarRef            # reference a variable
    astLit               # integer literal
    astFATrap            # FlashAttention trap (descriptor address in immediate)
    astComment           # documentation; no code gen

  ASTNode* = ref object
    case kind*: ASTNodeKind
    of astBefunge:
      befOp*: BefungeOp
      befVal*: int         # immediate value (for digit push)
    of astBrainfuck:
      bfcOp*: BrainfuckOp
    of astSeq:
      children*: seq[ASTNode]
    of astIf:
      condition*: ASTNode
      thenBranch*: ASTNode
      elseBranch*: ASTNode
    of astLoop:
      loopCond*: ASTNode   # re-evaluated each iteration
      loopBody*: ASTNode
    of astCall:
      funcName*: string
      args*: seq[ASTNode]
    of astVarRef:
      varName*: string
      isDeref*: bool       # *name for indirect addressing
    of astLit:
      litValue*: int
    of astFATrap:
      descAddr*: int       # descriptor address (must be valid)
      nextPc*: int         # resume PC after trap
    of astComment:
      text*: string

  # ───────────────────────────────────────────────────────────────────────────
  # Befunge 2D grid: sparse representation (row, col) → operation
  # ───────────────────────────────────────────────────────────────────────────

  BefungeGrid* = object
    ops*: seq[seq[BefungeOp]]  # ops[y][x]
    width*: int                # max column + 1
    height*: int               # max row + 1
    startRow*: int             # entry point row (default 0)
    startCol*: int             # entry point column (default 0)

  # ───────────────────────────────────────────────────────────────────────────
  # Brainfuck program: flat sequence
  # ───────────────────────────────────────────────────────────────────────────

  BrainfuckProg* = object
    ops*: seq[BrainfuckOp]
    tapeCells*: int            # tape size (>= 1)

  # ───────────────────────────────────────────────────────────────────────────
  # Memory layout (determined by BCPL declarations + Befunge/Brainfuck needs)
  # ───────────────────────────────────────────────────────────────────────────

  MemoryLayout* = object
    subleqOverhead*: int              # cells 0..N used by SUBLEQ runtime (entry, scratch, consts)
    variables*: seq[VarDecl]          # BCPL variable declarations
    varMap*: seq[(string, int)]       # name → cellAddr for fast lookup
    befungeCodeBase*: int             # where Befunge 2D grid bytecode starts
    befungeCodeSize*: int             # total code cells
    brainfuckTapeBase*: int           # where Brainfuck tape starts
    brainfuckTapeCells*: int          # tape size
    totalCells*: int                  # total memory required

  # ───────────────────────────────────────────────────────────────────────────
  # Hybrid program: all three components bound together
  # ───────────────────────────────────────────────────────────────────────────

  HybridProgram* = object
    ast*: ASTNode                     # unified AST
    befungeGrid*: BefungeGrid         # 2D Befunge grid (if present)
    brainfuckProg*: BrainfuckProg     # Brainfuck sequence (if present)
    variables*: seq[VarDecl]          # BCPL declarations
    memoryLayout*: MemoryLayout       # computed memory map
    entryPoint*: int                  # starting PC
    error*: string                    # error message (if parsing failed)

  # ───────────────────────────────────────────────────────────────────────────
  # Token: output of lexer, input to parser
  # ───────────────────────────────────────────────────────────────────────────

  TokenKind* = enum
    tokBefungeOp          # one of >, <, v, ^, 0-9, +, -, etc.
    tokBrainfuckOp        # one of >, <, +, -, ., ,, [, ]
    tokVarDecl            # int name = value;  or  int name[N];
    tokIdent              # identifier (variable name, function name)
    tokNumber             # integer literal
    tokLParen             # (
    tokRParen             # )
    tokLBrace             # {
    tokRBrace             # }
    tokLBracket           # [
    tokRBracket           # ]
    tokSemicolon           # ;
    tokComma              # ,
    tokAssign             # =
    tokStar               # * (dereference, multiply)
    tokAmpersand          # & (address-of)
    tokIf                 # if keyword
    tokElse               # else keyword
    tokWhile              # while keyword
    tokFn                 # fn keyword (function definition)
    tokFATrap             # __fa_trap
    tokReturn             # return keyword
    tokEOF                # end of input
    tokError              # lexical error

  Token* = object
    kind*: TokenKind
    lexeme*: string        # raw text (e.g., "+", "varName", "42")
    line*: int             # 1-indexed
    col*: int              # 1-indexed (or position in 2D grid)
    row*: int              # for Befunge 2D: grid row
    value*: int            # for tokNumber: the integer value

  # ───────────────────────────────────────────────────────────────────────────
  # Parser state machine: tracks position, lookahead, symbol table
  # ───────────────────────────────────────────────────────────────────────────

  Parser* = object
    tokens*: seq[Token]
    pos*: int              # current token index
    symbols*: seq[(string, VarDecl)]  # symbol table for scoping
    memCounter*: int       # next available memory address
    error*: string         # accumulated error messages
    errors*: seq[string]   # all errors encountered

  # ───────────────────────────────────────────────────────────────────────────
  # Lexer state machine: tokenizes the input
  # ───────────────────────────────────────────────────────────────────────────

  Lexer* = object
    input*: string
    pos*: int              # current character index
    line*: int             # 1-indexed line number
    col*: int              # 1-indexed column number
    tokens*: seq[Token]    # output buffer
    error*: string

# ───────────────────────────────────────────────────────────────────────────
# Smart constructors for AST nodes (enforce invariants)
# ───────────────────────────────────────────────────────────────────────────

proc newSeqNode*(children: seq[ASTNode]): ASTNode =
  new result
  result.kind = astSeq
  result.children = children

proc newBefungeNode*(op: BefungeOp, val: int = 0): ASTNode =
  new result
  result.kind = astBefunge
  result.befOp = op
  result.befVal = val

proc newBrainfuckNode*(op: BrainfuckOp): ASTNode =
  new result
  result.kind = astBrainfuck
  result.bfcOp = op

proc newLitNode*(val: int): ASTNode =
  new result
  result.kind = astLit
  result.litValue = val

proc newVarRefNode*(name: string, deref: bool = false): ASTNode =
  new result
  result.kind = astVarRef
  result.varName = name
  result.isDeref = deref

proc newFATrapNode*(desc: int, next: int): ASTNode =
  new result
  result.kind = astFATrap
  result.descAddr = desc
  result.nextPc = next

proc newCommentNode*(text: string): ASTNode =
  new result
  result.kind = astComment
  result.text = text

proc newIfNode*(cond, thenB, elseB: ASTNode): ASTNode =
  new result
  result.kind = astIf
  result.condition = cond
  result.thenBranch = thenB
  result.elseBranch = elseB

proc newLoopNode*(cond, body: ASTNode): ASTNode =
  new result
  result.kind = astLoop
  result.loopCond = cond
  result.loopBody = body

proc newCallNode*(name: string, args: seq[ASTNode]): ASTNode =
  new result
  result.kind = astCall
  result.funcName = name
  result.args = args

# ───────────────────────────────────────────────────────────────────────────
# Predicates for robustness
# ───────────────────────────────────────────────────────────────────────────

proc isBefungeOp*(op: BefungeOp): bool = true
proc isBrainfuckOp*(op: BrainfuckOp): bool = true

proc isControlFlow*(node: ASTNode): bool =
  node.kind in {astIf, astLoop, astCall}

proc isTerminal*(node: ASTNode): bool =
  node.kind in {astBefunge, astBrainfuck, astLit, astVarRef}

proc isTerminating*(op: BefungeOp): bool =
  op == BfExit

# ───────────────────────────────────────────────────────────────────────────
# Validation helpers
# ───────────────────────────────────────────────────────────────────────────

proc validateMemoryLayout*(layout: MemoryLayout): string =
  if layout.subleqOverhead < 9:
    return "SUBLEQ overhead must be >= 9"
  if layout.totalCells < layout.subleqOverhead:
    return "total cells must accommodate SUBLEQ overhead"
  if layout.befungeCodeSize > 0 and layout.befungeCodeBase < layout.subleqOverhead:
    return "Befunge code must come after SUBLEQ overhead"
  if layout.brainfuckTapeCells < 1:
    return "Brainfuck tape must have >= 1 cell"
  for v in layout.variables:
    if v.cellAddr < layout.subleqOverhead or v.cellAddr >= layout.totalCells:
      return "variable " & v.name & " at " & $v.cellAddr & " out of bounds"
    if v.isArray and v.arraySize < 1:
      return "array " & v.name & " must have size >= 1"
  return ""

proc validateVarDecl*(v: VarDecl): string =
  if v.name.len == 0:
    return "variable name cannot be empty"
  if v.cellAddr < 0:
    return "cell address must be >= 0"
  if v.isArray and v.arraySize < 1:
    return "array size must be >= 1"
  return ""
