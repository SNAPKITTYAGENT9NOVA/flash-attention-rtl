# Hybrid AST for Befunge + Brainfuck unified representation
# Enables both stack-based (Befunge) and tape-based (Brainfuck) operations
# Compile: nim c -d:release hybrid_ast.nim

type
  # Token type kind (string constant)
  TokenKind* = string

  # Token for lexer output
  Token* = object
    kind*: TokenKind
    text*: string
    lexeme*: string
    value*: int
    line*: int
    col*: int

  # Variable declaration for BCPL-style vars
  VarDecl* = object
    name*: string
    cellAddr*: int
    initialValue*: int
    isArray*: bool
    arraySize*: int

  # Parser state
  Parser* = object
    tokens*: seq[Token]
    pos*: int
    symbols*: seq[tuple[name: string, decl: VarDecl]]
    memCounter*: int
    error*: string
    errors*: seq[string]

  # Memory layout descriptor
  MemoryLayout* = object
    subleqOverhead*: int
    variables*: seq[VarDecl]
    varMap*: seq[tuple[name: string, address: int]]
    befungeCodeBase*: int
    befungeCodeSize*: int
    brainfuckTapeBase*: int
    brainfuckTapeCells*: int
    totalCells*: int

  # Brainfuck program descriptor
  BrainfuckProg* = object
    tapeCells*: int

  # Hybrid program combining all components
  HybridProgram* = object
    ast*: ASTNode
    befungeGrid*: BefungeGrid
    brainfuckProg*: BrainfuckProg
    variables*: seq[VarDecl]
    memoryLayout*: MemoryLayout
    entryPoint*: int
    error*: string

  # Brainfuck AST operations
  BrainfuckOp* = enum
    BfcPtrInc, BfcPtrDec, BfcCellInc, BfcCellDec, BfcOutput, BfcInput, BfcLoopStart, BfcLoopEnd

  # AST node kind discriminator
  ASTNodeKind* = enum
    ankSeq, ankBrainfuck, ankBefunge

  # AST node type (variant)
  ASTNode* = object
    case kind*: ASTNodeKind
    of ankSeq:
      children*: seq[ASTNode]
    of ankBrainfuck:
      bfOp*: BrainfuckOp
    of ankBefunge:
      bfOpEnum*: BefungeOp
      bfValue*: int

  # Lexer state
  Lexer* = object
    input*: string
    pos*: int
    line*: int
    col*: int
    tokens*: seq[Token]
    error*: string

  # Instruction type covering both Befunge and Brainfuck ops
  InstrKind* = enum
    # Befunge stack operations
    ikPush,        # push value onto stack
    ikPop,         # pop from stack
    ikDup,         # duplicate top
    ikSwap,        # swap top two
    ikAdd,         # pop b, pop a, push a+b
    ikSub,         # pop b, pop a, push a-b
    ikMul,         # pop b, pop a, push a*b
    ikDiv,         # pop b, pop a, push a/b
    ikMod,         # pop b, pop a, push a mod b
    ikNot,         # pop a, push (a==0 ? 1 : 0)
    ikGreater,     # pop b, pop a, push (a>b ? 1 : 0)
    ikOutput,      # pop and output
    ikInput,       # read input and push
    ikRandom,      # push random value
    ikTurnRight,   # change direction right
    ikTurnLeft,    # change direction left
    ikHorizontal,  # pop; if 0 go right, else go left
    ikVertical,    # pop; if 0 go down, else go up
    ikStringMode,  # toggle string mode
    ikTraceOn,     # start tracing
    ikTraceOff,    # stop tracing

    # Brainfuck-style operations
    ikPtrInc,      # increment pointer (>)
    ikPtrDec,      # decrement pointer (<)
    ikCellInc,     # increment cell value (+)
    ikCellDec,     # decrement cell value (-)
    ikCellOut,     # output cell value (.)
    ikCellIn,      # input to cell (,)
    ikLoopStart,   # loop start ([)
    ikLoopEnd,     # loop end (])

    # Control flow
    ikLoop,        # unconditional loop
    ikCondBranch,  # conditional branch
    ikJump,        # unconditional jump to label
    ikLabel,       # label definition
    ikHalt,        # halt execution

    # Meta
    ikNop,         # no operation
    ikComment,     # documentation/comment

  Instr* = object
    kind*: InstrKind
    value*: int        # for push/label references
    label*: string     # for labels, branches, jumps

  ExecutionMode* = enum modeHybrid, modeBefunge, modeBrainfuck

  # Befunge 2D grid operations
  BefungeOp* = enum
    BfNop, BfRight, BfLeft, BfDown, BfUp,
    BfPush, BfAdd, BfSub, BfMul, BfDiv, BfMod, BfNot, BfCmpGt,
    BfDup, BfPop, BfSwap, BfHRotate, BfHRotateL,
    BfMGet, BfMPut, BfOutput, BfOutputAscii,
    BfInput, BfExit

  BefungeGrid* = object
    ops*: seq[seq[BefungeOp]]
    width*: int
    height*: int
    startRow*: int
    startCol*: int

  # High-level program representation
  Program* = object
    instrs*: seq[Instr]
    labels*: seq[tuple[name: string, index: int]]
    mode*: ExecutionMode

# Helper constructors
proc push*(val: int): Instr = Instr(kind: ikPush, value: val)
proc pop*(): Instr = Instr(kind: ikPop)
proc dup*(): Instr = Instr(kind: ikDup)
proc swap*(): Instr = Instr(kind: ikSwap)
proc add*(): Instr = Instr(kind: ikAdd)
proc sub*(): Instr = Instr(kind: ikSub)
proc mul*(): Instr = Instr(kind: ikMul)
proc divOp*(): Instr = Instr(kind: ikDiv)
proc modOp*(): Instr = Instr(kind: ikMod)
proc notOp*(): Instr = Instr(kind: ikNot)
proc greaterOp*(): Instr = Instr(kind: ikGreater)
proc output*(): Instr = Instr(kind: ikOutput)
proc input*(): Instr = Instr(kind: ikInput)
proc random*(): Instr = Instr(kind: ikRandom)
proc ptrInc*(): Instr = Instr(kind: ikPtrInc)
proc ptrDec*(): Instr = Instr(kind: ikPtrDec)
proc cellInc*(): Instr = Instr(kind: ikCellInc)
proc cellDec*(): Instr = Instr(kind: ikCellDec)
proc cellOut*(): Instr = Instr(kind: ikCellOut)
proc cellIn*(): Instr = Instr(kind: ikCellIn)
proc loopStart*(): Instr = Instr(kind: ikLoopStart)
proc loopEnd*(): Instr = Instr(kind: ikLoopEnd)
proc label*(name: string): Instr = Instr(kind: ikLabel, label: name)
proc jump*(name: string): Instr = Instr(kind: ikJump, label: name)
proc condBranch*(trueLabel, falseLabel: string): Instr =
  Instr(kind: ikCondBranch, label: trueLabel & "," & falseLabel)
proc halt*(): Instr = Instr(kind: ikHalt)
proc nop*(): Instr = Instr(kind: ikNop)

proc `$`*(i: Instr): string =
  case i.kind
  of ikPush: "push(" & $i.value & ")"
  of ikLabel: "label(" & i.label & ")"
  of ikJump: "jump(" & i.label & ")"
  of ikCondBranch: "condBranch(" & i.label & ")"
  else: $i.kind

# AST node constructors
proc newSeqNode*(children: seq[ASTNode]): ASTNode =
  ASTNode(kind: ankSeq, children: children)

proc newBrainfuckNode*(op: BrainfuckOp): ASTNode =
  ASTNode(kind: ankBrainfuck, bfOp: op)

proc newBefungeNode*(op: BefungeOp; value: int = 0): ASTNode =
  ASTNode(kind: ankBefunge, bfOpEnum: op, bfValue: value)

proc newLoopNode*(cond: ASTNode; body: ASTNode): ASTNode =
  ASTNode(kind: ankSeq, children: @[cond, body])

proc newLitNode*(val: int): ASTNode =
  newBefungeNode(BfPush, val)

proc newVarRefNode*(name: string; isRef: bool = true): ASTNode =
  newSeqNode(@[])

proc newCommentNode*(text: string): ASTNode =
  newSeqNode(@[])

proc newIfNode*(cond: ASTNode; thenBranch: ASTNode; elseBranch: ASTNode): ASTNode =
  ASTNode(kind: ankSeq, children: @[cond, thenBranch, elseBranch])

proc newFATrapNode*(desc: int; nextPc: int): ASTNode =
  newSeqNode(@[])

# Token type constants
const
  tokEOF* = "EOF"
  tokError* = "ERROR"
  tokNumber* = "NUMBER"
  tokIdent* = "IDENT"
  tokBefungeOp* = "BEFUNGE_OP"
  tokVarDecl* = "VAR_DECL"
  tokFn* = "FN"
  tokIf* = "IF"
  tokElse* = "ELSE"
  tokWhile* = "WHILE"
  tokReturn* = "RETURN"
  tokSemicolon* = "SEMICOLON"
  tokLParen* = "LPAREN"
  tokRParen* = "RPAREN"
  tokLBrace* = "LBRACE"
  tokRBrace* = "RBRACE"
  tokLBracket* = "LBRACKET"
  tokRBracket* = "RBRACKET"
  tokAssign* = "ASSIGN"
  tokStar* = "STAR"
  tokAmpersand* = "AMPERSAND"
  tokComma* = "COMMA"
  tokFATrap* = "FA_TRAP"
