# Hybrid AST for Befunge + Brainfuck unified representation
# Enables both stack-based (Befunge) and tape-based (Brainfuck) operations
# Compile: nim c -d:release hybrid_ast.nim

type
  # Token for lexer output
  Token* = object
    kind*: string
    text*: string
    lexeme*: string
    line*: int
    col*: int

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
