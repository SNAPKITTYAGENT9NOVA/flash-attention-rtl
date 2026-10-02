# Hybrid Parser: Build AST from tokens, trace control flow, allocate memory
#
# Deterministic parsing of Befunge 2D grids, Brainfuck sequences, and BCPL
# variable declarations. Produces a unified AST and memory layout.
#
# Invariants:
# - All variables have unique names
# - All memory addresses are assigned deterministically
# - All jumps and loops are resolved (no forward references)
# - Control flow is acyclic for Brainfuck (loops are recognized)

import hybrid_ast
import hybrid_lexer
import sequtils
import strutils

# ─────────────────────────────────────────────────────────────────────────────
# Parser initialization
# ─────────────────────────────────────────────────────────────────────────────

proc initParser*(tokens: seq[Token]): Parser =
  Parser(
    tokens: tokens,
    pos: 0,
    symbols: @[],
    memCounter: 9,  # Start after SUBLEQ overhead
    error: "",
    errors: @[]
  )

# ─────────────────────────────────────────────────────────────────────────────
# Token stream navigation
# ─────────────────────────────────────────────────────────────────────────────

proc peek*(p: Parser; offset: int = 0): Token =
  let idx = p.pos + offset
  if idx >= 0 and idx < p.tokens.len: p.tokens[idx] else: Token(kind: tokEOF)

proc advance*(p: var Parser): Token =
  let tok = p.peek()
  if p.pos < p.tokens.len:
    inc p.pos
  tok

proc expect*(p: var Parser; kind: TokenKind): bool =
  if p.peek().kind == kind:
    discard p.advance()
    true
  else:
    false

proc errorAt*(p: var Parser; msg: string) =
  let tok = p.peek()
  let err = "line " & $tok.line & " col " & $tok.col & ": " & msg
  p.errors.add err
  p.error = err

proc addSymbol*(p: var Parser; v: VarDecl): bool =
  # Check for duplicate
  for item in p.symbols:
    if item[0] == v.name:
      p.errorAt("duplicate variable: " & v.name)
      return false
  p.symbols.add (v.name, v)
  true

proc lookupSymbol*(p: Parser; name: string): VarDecl =
  for item in p.symbols:
    if item[0] == name:
      return item[1]
  VarDecl()  # null/zero value for not found

# ─────────────────────────────────────────────────────────────────────────────
# Brainfuck bracket matching (pre-pass)
# ─────────────────────────────────────────────────────────────────────────────

proc matchBrackets*(tokens: seq[Token]): (seq[int], string) =
  # Build a jump map: bracket position → matching bracket position
  var jumpMap = newSeq[int](tokens.len)
  var stack: seq[int]
  var errorMsg = ""

  for i, tok in tokens:
    if tok.kind == tokLBracket:
      stack.add i
    elif tok.kind == tokRBracket:
      if stack.len == 0:
        errorMsg = "unmatched ']' at token " & $i
        break
      let j = stack.pop()
      jumpMap[i] = j
      jumpMap[j] = i

  if stack.len > 0 and errorMsg == "":
    errorMsg = "unmatched '['"

  (jumpMap, errorMsg)

# ─────────────────────────────────────────────────────────────────────────────
# Parse variable declarations (BCPL-style)
# ─────────────────────────────────────────────────────────────────────────────

proc parseVarDecl*(p: var Parser): VarDecl =
  var v = VarDecl(cellAddr: p.memCounter, initialValue: 0, isArray: false)

  # Expect: int name [= initialValue] [;]
  if not p.expect(tokVarDecl):
    p.errorAt("expected 'int'")
    return v

  let nameTok = p.peek()
  if nameTok.kind != tokIdent:
    p.errorAt("expected identifier after 'int'")
    return v
  v.name = nameTok.lexeme
  discard p.advance()

  # Optional array size: [N]
  if p.peek().kind == tokLBracket:
    discard p.advance()
    let sizeTok = p.peek()
    if sizeTok.kind != tokNumber:
      p.errorAt("expected array size")
      return v
    v.arraySize = sizeTok.value
    v.isArray = true
    discard p.advance()
    if not p.expect(tokRBracket):
      p.errorAt("expected ']'")
      return v

  # Optional initializer: = value
  if p.peek().kind == tokAssign:
    discard p.advance()
    let valTok = p.peek()
    if valTok.kind != tokNumber:
      p.errorAt("expected number in initializer")
      return v
    v.initialValue = valTok.value
    discard p.advance()

  # Consume semicolon
  if not p.expect(tokSemicolon):
    p.errorAt("expected ';' after variable declaration")

  # Allocate memory
  v.cellAddr = p.memCounter
  if v.isArray:
    p.memCounter += v.arraySize
  else:
    p.memCounter += 1

  v

# ─────────────────────────────────────────────────────────────────────────────
# Parse Brainfuck sequence
# ─────────────────────────────────────────────────────────────────────────────

proc parseBrainfuckSeq*(p: var Parser): ASTNode =
  var children: seq[ASTNode]
  let bracketResult = matchBrackets(p.tokens[p.pos ..< p.tokens.len])
  let jumpMap = bracketResult[0]
  let errMsg = bracketResult[1]
  if errMsg != "":
    p.errorAt(errMsg)
    return newSeqNode(@[])

  while p.peek().kind != tokEOF:
    let tok = p.peek()
    case tok.kind
    of tokBefungeOp:
      # Brainfuck-specific operations (>, <, +, -, ., ,, [, ])
      let op = case tok.lexeme
        of ">": BfcPtrInc
        of "<": BfcPtrDec
        of "+": BfcCellInc
        of "-": BfcCellDec
        of ".": BfcOutput
        of ",": BfcInput
        else:
          p.errorAt("invalid brainfuck op: " & tok.lexeme)
          discard p.advance()
          continue
      children.add newBrainfuckNode(op)
      discard p.advance()

    of tokLBracket:
      # Match and parse loop body
      let openIdx = p.pos
      discard p.advance()
      let closeIdx = jumpMap[openIdx]

      # Parse loop body
      var bodyChildren: seq[ASTNode]
      while p.pos < closeIdx and p.peek().kind != tokEOF:
        let bodyTok = p.peek()
        case bodyTok.kind
        of tokBefungeOp:
          let op = case bodyTok.lexeme
            of ">": BfcPtrInc
            of "<": BfcPtrDec
            of "+": BfcCellInc
            of "-": BfcCellDec
            of ".": BfcOutput
            of ",": BfcInput
            else:
              p.errorAt("invalid brainfuck op: " & bodyTok.lexeme)
              discard p.advance()
              continue
          bodyChildren.add newBrainfuckNode(op)
          discard p.advance()
        of tokRBracket:
          break
        else:
          discard p.advance()

      if not p.expect(tokRBracket):
        p.errorAt("expected matching ']'")

      # Loop condition: test if tape[ptr] == 0
      let cond = newBrainfuckNode(BfcCellDec)  # dummy; real test is runtime
      let body = if bodyChildren.len == 0:
        newSeqNode(@[])
      elif bodyChildren.len == 1:
        bodyChildren[0]
      else:
        newSeqNode(bodyChildren)
      children.add newLoopNode(cond, body)

    of tokRBracket:
      p.errorAt("unmatched ']'")
      discard p.advance()

    else:
      discard p.advance()

  if children.len == 0:
    newSeqNode(@[])
  elif children.len == 1:
    children[0]
  else:
    newSeqNode(children)

# ─────────────────────────────────────────────────────────────────────────────
# Parse 2D Befunge grid
# ─────────────────────────────────────────────────────────────────────────────

proc parse2DBerungeGrid*(grid: BefungeGrid): ASTNode =
  # Build a linear AST from the 2D grid (row-major traversal)
  var children: seq[ASTNode]

  for row in 0 ..< grid.height:
    for col in 0 ..< grid.width:
      if col < grid.ops[row].len:
        let op = grid.ops[row][col]
        case op
        of BfNop:
          discard
        of BfPush:
          # Push needs a digit argument; we'll use 0 as placeholder
          children.add newBefungeNode(BfPush, 0)
        of BfRight, BfLeft, BfDown, BfUp:
          children.add newBefungeNode(op)
        of BfAdd, BfSub, BfMul, BfDiv, BfMod:
          children.add newBefungeNode(op)
        of BfNot, BfCmpGt:
          children.add newBefungeNode(op)
        of BfHRotate, BfHRotateL:
          children.add newBefungeNode(op)
        of BfDup, BfPop, BfSwap:
          children.add newBefungeNode(op)
        of BfMGet, BfMPut:
          children.add newBefungeNode(op)
        of BfInput, BfOutput, BfOutputAscii:
          children.add newBefungeNode(op)
        of BfExit:
          children.add newBefungeNode(BfExit)
          break

  if children.len == 0:
    newSeqNode(@[])
  elif children.len == 1:
    children[0]
  else:
    newSeqNode(children)

# ─────────────────────────────────────────────────────────────────────────────
# Parse primary expression
# ─────────────────────────────────────────────────────────────────────────────

proc parseExpr*(p: var Parser): ASTNode =
  let tok = p.peek()
  case tok.kind
  of tokNumber:
    let val = tok.value
    discard p.advance()
    return newLitNode(val)
  of tokIdent:
    let name = tok.lexeme
    discard p.advance()
    return newVarRefNode(name)
  of tokAmpersand:
    discard p.advance()
    let name = p.peek().lexeme
    if p.peek().kind != tokIdent:
      p.errorAt("expected identifier after '&'")
      return newLitNode(0)
    discard p.advance()
    return newVarRefNode(name, false)
  of tokStar:
    discard p.advance()
    let name = p.peek().lexeme
    if p.peek().kind != tokIdent:
      p.errorAt("expected identifier after '*'")
      return newLitNode(0)
    discard p.advance()
    return newVarRefNode(name, true)
  else:
    p.errorAt("unexpected token in expression: " & tok.lexeme)
    discard p.advance()
    return newLitNode(0)

# ─────────────────────────────────────────────────────────────────────────────
# Parse statement (top-level production)
# ─────────────────────────────────────────────────────────────────────────────

proc parseStatement*(p: var Parser): ASTNode =
  let tok = p.peek()
  case tok.kind
  of tokVarDecl:
    let v = p.parseVarDecl()
    if p.addSymbol(v):
      # Successful declaration; return comment node (no code generation)
      return newCommentNode("declare " & v.name)
    else:
      return newSeqNode(@[])

  of tokIf:
    discard p.advance()
    if not p.expect(tokLParen):
      p.errorAt("expected '(' after 'if'")
      return newSeqNode(@[])
    let cond = p.parseExpr()
    if not p.expect(tokRParen):
      p.errorAt("expected ')' after condition")
    if not p.expect(tokLBrace):
      p.errorAt("expected '{' before then-branch")
      return newSeqNode(@[])
    var thenChildren: seq[ASTNode]
    while p.peek().kind != tokRBrace and p.peek().kind != tokEOF:
      thenChildren.add p.parseStatement()
    if not p.expect(tokRBrace):
      p.errorAt("expected '}'")
    let thenBranch = if thenChildren.len == 0:
      newSeqNode(@[])
    elif thenChildren.len == 1:
      thenChildren[0]
    else:
      newSeqNode(thenChildren)

    var elseBranch = newSeqNode(@[])
    if p.peek().kind == tokElse:
      discard p.advance()
      if not p.expect(tokLBrace):
        p.errorAt("expected '{'")
        return newSeqNode(@[])
      var elseChildren: seq[ASTNode]
      while p.peek().kind != tokRBrace and p.peek().kind != tokEOF:
        elseChildren.add p.parseStatement()
      if not p.expect(tokRBrace):
        p.errorAt("expected '}'")
      elseBranch = if elseChildren.len == 0:
        newSeqNode(@[])
      elif elseChildren.len == 1:
        elseChildren[0]
      else:
        newSeqNode(elseChildren)

    return newIfNode(cond, thenBranch, elseBranch)

  of tokWhile:
    discard p.advance()
    if not p.expect(tokLParen):
      p.errorAt("expected '(' after 'while'")
      return newSeqNode(@[])
    let cond = p.parseExpr()
    if not p.expect(tokRParen):
      p.errorAt("expected ')' after condition")
    if not p.expect(tokLBrace):
      p.errorAt("expected '{' before loop body")
      return newSeqNode(@[])
    var bodyChildren: seq[ASTNode]
    while p.peek().kind != tokRBrace and p.peek().kind != tokEOF:
      bodyChildren.add p.parseStatement()
    if not p.expect(tokRBrace):
      p.errorAt("expected '}'")
    let body = if bodyChildren.len == 0:
      newSeqNode(@[])
    elif bodyChildren.len == 1:
      bodyChildren[0]
    else:
      newSeqNode(bodyChildren)
    return newLoopNode(cond, body)

  of tokBefungeOp:
    let op = case tok.lexeme
      of ">": BfRight
      of "<": BfLeft
      of "v": BfDown
      of "^": BfUp
      of "+": BfAdd
      of "-": BfSub
      of "*": BfMul
      of "/": BfDiv
      of "%": BfMod
      of "!": BfNot
      of "`": BfCmpGt
      of ":": BfDup
      of "$": BfPop
      of "g": BfMGet
      of "p": BfMPut
      of ".": BfOutput
      of ",": BfOutputAscii
      of "&": BfInput
      of "@": BfExit
      else:
        p.errorAt("unknown befunge op: " & tok.lexeme)
        discard p.advance()
        return newSeqNode(@[])
    discard p.advance()
    return newBefungeNode(op)

  of tokFATrap:
    discard p.advance()
    if not p.expect(tokLParen):
      p.errorAt("expected '(' after __fa_trap")
      return newSeqNode(@[])
    let descTok = p.peek()
    if descTok.kind != tokNumber:
      p.errorAt("expected address in __fa_trap")
      return newSeqNode(@[])
    let desc = descTok.value
    discard p.advance()
    if not p.expect(tokRParen):
      p.errorAt("expected ')'")
    return newFATrapNode(desc, 0)  # nextPc will be assigned during code gen

  else:
    p.errorAt("unexpected token: " & tok.lexeme)
    discard p.advance()
    return newSeqNode(@[])

# ─────────────────────────────────────────────────────────────────────────────
# Compute memory layout
# ─────────────────────────────────────────────────────────────────────────────

proc computeMemoryLayout*(p: Parser; befungeCodeSize: int = 0; brainfuckTapeCells: int = 256): MemoryLayout =
  var layout = MemoryLayout(
    subleqOverhead: 9,
    variables: p.symbols.mapIt(it[1]),
    varMap: p.symbols.mapIt((it[0], it[1].cellAddr)),
    befungeCodeBase: p.memCounter,
    befungeCodeSize: befungeCodeSize,
    brainfuckTapeBase: p.memCounter + befungeCodeSize,
    brainfuckTapeCells: brainfuckTapeCells,
    totalCells: p.memCounter + befungeCodeSize + brainfuckTapeCells
  )
  layout

# ─────────────────────────────────────────────────────────────────────────────
# Main parsing function: build HybridProgram from input
# ─────────────────────────────────────────────────────────────────────────────

proc parseHybrid*(input: string): HybridProgram =
  var prog = HybridProgram(
    ast: newSeqNode(@[]),
    befungeGrid: BefungeGrid(),
    brainfuckProg: BrainfuckProg(tapeCells: 256),
    variables: @[],
    memoryLayout: MemoryLayout(),
    entryPoint: 9,
    error: ""
  )

  # Try 2D Befunge grid first
  let gridResult = tokenize2DGrid(input)
  let grid = gridResult[0]
  let gridErr = gridResult[1]
  if gridErr == "" and grid.height > 0:
    prog.befungeGrid = grid
    prog.ast = parse2DBerungeGrid(grid)
    prog.memoryLayout = computeMemoryLayout(Parser(), grid.width * grid.height, 256)
    return prog

  # Otherwise, tokenize as BCPL + Brainfuck
  let tokResult = tokenize(input)
  let tokens = tokResult[0]
  let lexErr = tokResult[1]
  if lexErr != "":
    prog.error = lexErr
    return prog

  var p = initParser(tokens)

  # Parse declarations and statements
  while p.peek().kind != tokEOF:
    discard p.parseStatement()
    # (comment nodes are just for declarations; skip them)

  if p.errors.len > 0:
    prog.error = p.errors.join("; ")
    return prog

  prog.variables = p.symbols.mapIt(it[1])
  prog.memoryLayout = p.computeMemoryLayout()
  prog.entryPoint = 9

  prog
