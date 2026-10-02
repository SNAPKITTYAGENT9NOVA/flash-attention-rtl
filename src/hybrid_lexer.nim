# Hybrid Lexer: Tokenize Befunge 2D + Brainfuck + BCPL
#
# Deterministic tokenization from raw input into Token stream.
# Handles:
# - 2D Befunge grids (with row/col position tracking)
# - Brainfuck linear sequences
# - BCPL variable declarations (int x = y; int arr[N];)
# - Comments (#)

import hybrid_ast

# ─────────────────────────────────────────────────────────────────────────────
# Character classification
# ─────────────────────────────────────────────────────────────────────────────

proc isBefungeChar*(c: char): bool =
  c in {
    '>', '<', 'v', '^',     # direction
    '0'..'9',               # digits (push)
    '+', '-', '*', '/', '%',# arithmetic
    '!', '`',               # comparison
    ']', '[',               # stack rotate
    ':', '$', '"',          # stack ops (actually quote for swap)
    'g', 'p',               # grid access
    '&', '.', ',',          # I/O (& for input, . for int output, , for char output)
    '@',                    # exit
    ' '                     # space (nop in Befunge)
  }

proc isBrainfuckChar*(c: char): bool =
  c in {'>', '<', '+', '-', '.', ',', '[', ']'}

proc isAlpha*(c: char): bool =
  (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')

proc isIdentChar*(c: char): bool =
  (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_'

proc isDigit*(c: char): bool =
  c >= '0' and c <= '9'

# ─────────────────────────────────────────────────────────────────────────────
# Lexer implementation
# ─────────────────────────────────────────────────────────────────────────────

proc initLexer*(input: string): Lexer =
  Lexer(input: input, pos: 0, line: 1, col: 1, tokens: @[], error: "")

proc peek*(lex: Lexer; offset: int = 0): char =
  let p = lex.pos + offset
  if p >= 0 and p < lex.input.len: lex.input[p] else: '\0'

proc advance*(lex: var Lexer): char =
  let c = lex.peek()
  if c == '\n':
    inc lex.line
    lex.col = 1
  else:
    inc lex.col
  inc lex.pos
  c

proc skipWhitespace*(lex: var Lexer) =
  while lex.peek() in {' ', '\t', '\n', '\r'}:
    discard lex.advance()

proc skipComment*(lex: var Lexer) =
  if lex.peek() == '#':
    while lex.peek() != '\n' and lex.peek() != '\0':
      discard lex.advance()

proc readNumber*(lex: var Lexer): int =
  var num = 0
  while lex.peek().isDigit():
    num = num * 10 + (lex.peek().ord - '0'.ord)
    discard lex.advance()
  num

proc readIdent*(lex: var Lexer): string =
  var ident = ""
  while lex.peek().isIdentChar():
    ident &= lex.advance()
  ident

# ─────────────────────────────────────────────────────────────────────────────
# Single-token recognition (deterministic, no backtracking)
# ─────────────────────────────────────────────────────────────────────────────

proc nextToken*(lex: var Lexer): Token =
  lex.skipWhitespace()
  lex.skipComment()
  lex.skipWhitespace()

  let startLine = lex.line
  let startCol = lex.col
  let c = lex.peek()

  # End of input
  if c == '\0':
    return Token(kind: tokEOF, lexeme: "", line: startLine, col: startCol)

  # Befunge direction operators
  if c == '>':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: ">", line: startLine, col: startCol, value: 0)
  if c == '<':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: "<", line: startLine, col: startCol, value: 0)
  if c == 'v':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: "v", line: startLine, col: startCol, value: 0)
  if c == '^':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: "^", line: startLine, col: startCol, value: 0)

  # Digit (Befunge push / numeric literal)
  if c.isDigit():
    let digit = lex.readNumber()
    let lexeme = $digit
    return Token(kind: tokNumber, lexeme: lexeme, line: startLine, col: startCol, value: digit)

  # Arithmetic and Befunge/Brainfuck operators
  if c == '+':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: "+", line: startLine, col: startCol)
  if c == '-':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: "-", line: startLine, col: startCol)
  if c == '*':
    discard lex.advance()
    return Token(kind: tokStar, lexeme: "*", line: startLine, col: startCol)
  if c == '/':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: "/", line: startLine, col: startCol)
  if c == '%':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: "%", line: startLine, col: startCol)

  # Stack and grid operations
  if c == '!':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: "!", line: startLine, col: startCol)
  if c == '`':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: "`", line: startLine, col: startCol)
  if c == ':':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: ":", line: startLine, col: startCol)
  if c == '$':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: "$", line: startLine, col: startCol)
  if c == 'g':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: "g", line: startLine, col: startCol)
  if c == 'p':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: "p", line: startLine, col: startCol)

  # I/O operations
  if c == '.':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: ".", line: startLine, col: startCol)
  if c == ',':
    discard lex.advance()
    return Token(kind: tokComma, lexeme: ",", line: startLine, col: startCol)
  if c == '&':
    discard lex.advance()
    return Token(kind: tokAmpersand, lexeme: "&", line: startLine, col: startCol)

  # Exit
  if c == '@':
    discard lex.advance()
    return Token(kind: tokBefungeOp, lexeme: "@", line: startLine, col: startCol)

  # Brainfuck bracket operations
  if c == '[':
    discard lex.advance()
    return Token(kind: tokLBracket, lexeme: "[", line: startLine, col: startCol)
  if c == ']':
    discard lex.advance()
    return Token(kind: tokRBracket, lexeme: "]", line: startLine, col: startCol)

  # BCPL-style syntax
  if c == '(':
    discard lex.advance()
    return Token(kind: tokLParen, lexeme: "(", line: startLine, col: startCol)
  if c == ')':
    discard lex.advance()
    return Token(kind: tokRParen, lexeme: ")", line: startLine, col: startCol)
  if c == '{':
    discard lex.advance()
    return Token(kind: tokLBrace, lexeme: "{", line: startLine, col: startCol)
  if c == '}':
    discard lex.advance()
    return Token(kind: tokRBrace, lexeme: "}", line: startLine, col: startCol)
  if c == ';':
    discard lex.advance()
    return Token(kind: tokSemicolon, lexeme: ";", line: startLine, col: startCol)
  if c == '=':
    discard lex.advance()
    return Token(kind: tokAssign, lexeme: "=", line: startLine, col: startCol)

  # Identifiers and keywords
  if c.isAlpha() or c == '_':
    let ident = lex.readIdent()
    let kind = case ident
      of "int": tokVarDecl
      of "if": tokIf
      of "else": tokElse
      of "while": tokWhile
      of "fn": tokFn
      of "return": tokReturn
      of "__fa_trap": tokFATrap
      else: tokIdent
    return Token(kind: kind, lexeme: ident, line: startLine, col: startCol)

  # Unknown character
  discard lex.advance()
  return Token(kind: tokError, lexeme: $c & " (unexpected)", line: startLine, col: startCol)

# ─────────────────────────────────────────────────────────────────────────────
# Full tokenization (driver)
# ─────────────────────────────────────────────────────────────────────────────

proc tokenize*(input: string): (seq[Token], string) =
  var lex = initLexer(input)
  var tokens: seq[Token]
  var errorMsg = ""

  while true:
    let tok = lex.nextToken()
    if tok.kind == tokError:
      errorMsg = "line " & $tok.line & " col " & $tok.col & ": " & tok.lexeme
      break
    tokens.add tok
    if tok.kind == tokEOF:
      break

  (tokens, errorMsg)

# ─────────────────────────────────────────────────────────────────────────────
# 2D Befunge grid tokenization (separate path for grid-based parsing)
# ─────────────────────────────────────────────────────────────────────────────

proc tokenize2DGrid*(input: string): (BefungeGrid, string) =
  var grid = BefungeGrid(
    ops: @[],
    width: 0,
    height: 0,
    startRow: 0,
    startCol: 0
  )
  var errorMsg = ""
  var currentRow: seq[BefungeOp] = @[]
  var rowNum = 0
  var maxCol = 0

  var i = 0
  while i < input.len:
    let c = input[i]

    case c
    of '\n':
      if currentRow.len > 0:
        grid.ops.add currentRow
        if currentRow.len > maxCol:
          maxCol = currentRow.len
      currentRow = @[]
      rowNum += 1
      i += 1

    of ' ':
      currentRow.add BfNop
      i += 1

    of '>', '<', 'v', '^':
      let op = case c
        of '>': BfRight
        of '<': BfLeft
        of 'v': BfDown
        of '^': BfUp
        else: BfNop
      currentRow.add op
      i += 1

    of '0'..'9':
      let digit = c.ord - '0'.ord
      currentRow.add case digit
        of 0: BfPush
        of 1: BfPush
        of 2: BfPush
        of 3: BfPush
        of 4: BfPush
        of 5: BfPush
        of 6: BfPush
        of 7: BfPush
        of 8: BfPush
        of 9: BfPush
        else: BfNop
      i += 1

    of '+', '-', '*', '/', '%', '!', '`', ':', '$', 'g', 'p', '.', ',', '&', '@':
      let op = case c
        of '+': BfAdd
        of '-': BfSub
        of '*': BfMul
        of '/': BfDiv
        of '%': BfMod
        of '!': BfNot
        of '`': BfCmpGt
        of ':': BfDup
        of '$': BfPop
        of 'g': BfMGet
        of 'p': BfMPut
        of '.': BfOutput
        of ',': BfOutputAscii
        of '&': BfInput
        of '@': BfExit
        else: BfNop
      currentRow.add op
      i += 1

    of '#':
      # Skip comment line
      while i < input.len and input[i] != '\n':
        i += 1

    else:
      errorMsg = "unexpected character in grid: " & c
      break

  if currentRow.len > 0:
    grid.ops.add currentRow
    if currentRow.len > maxCol:
      maxCol = currentRow.len

  grid.width = maxCol
  grid.height = grid.ops.len

  (grid, errorMsg)
