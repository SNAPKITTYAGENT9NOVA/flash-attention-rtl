# Test suite for hybrid frontend: lexer, parser, AST
# Verifies correctness and determinism of tokenization and parsing.

import ../src/hybrid_ast
import ../src/hybrid_lexer
import ../src/hybrid_parser
import strutils
import sequtils

# ─────────────────────────────────────────────────────────────────────────────
# Test: Lexer basic tokens
# ─────────────────────────────────────────────────────────────────────────────

proc testLexerBasic*(): string =
  let input = "+ - > < . , [ ]"
  let tokResult = tokenize(input)
  let tokens = tokResult[0]
  let err = tokResult[1]
  if err != "":
    return "FAIL: lexer error: " & err
  if tokens.len < 8:
    return "FAIL: expected >= 8 tokens, got " & $tokens.len
  if tokens[0].lexeme != "+":
    return "FAIL: first token should be '+', got " & tokens[0].lexeme
  "PASS: lexer_basic"

# ─────────────────────────────────────────────────────────────────────────────
# Test: Lexer variable declarations
# ─────────────────────────────────────────────────────────────────────────────

proc testLexerVarDecl*(): string =
  let input = "int x = 42; int arr[10];"
  let tokResult = tokenize(input)
  let tokens = tokResult[0]
  let err = tokResult[1]
  if err != "":
    return "FAIL: lexer error: " & err
  # Should have: int, x, =, 42, ;, int, arr, [, 10, ], ;, EOF
  var hasInt = false
  var hasIdent = false
  var hasNumber = false
  for tok in tokens:
    if tok.kind == tokVarDecl: hasInt = true
    if tok.kind == tokIdent: hasIdent = true
    if tok.kind == tokNumber and tok.value == 42: hasNumber = true
  if not hasInt or not hasIdent or not hasNumber:
    return "FAIL: missing expected tokens in var decl"
  "PASS: lexer_var_decl"

# ─────────────────────────────────────────────────────────────────────────────
# Test: Lexer numbers
# ─────────────────────────────────────────────────────────────────────────────

proc testLexerNumbers*(): string =
  let input = "123 456 0 999"
  let tokResult = tokenize(input)
  let tokens = tokResult[0]
  let err = tokResult[1]
  if err != "":
    return "FAIL: lexer error: " & err
  var values = newSeq[int]()
  for tok in tokens:
    if tok.kind == tokNumber:
      values.add tok.value
  if values.len != 4:
    return "FAIL: expected 4 numbers, got " & $values.len
  if values[0] != 123 or values[1] != 456 or values[2] != 0 or values[3] != 999:
    return "FAIL: number values incorrect: " & values.mapIt($it).join(", ")
  "PASS: lexer_numbers"

# ─────────────────────────────────────────────────────────────────────────────
# Test: 2D Befunge grid tokenization
# ─────────────────────────────────────────────────────────────────────────────

proc testLexer2DGrid*(): string =
  let input = "v\n>\n@"
  let gridResult = tokenize2DGrid(input)
  let grid = gridResult[0]
  let err = gridResult[1]
  if err != "":
    return "FAIL: 2D tokenizer error: " & err
  if grid.height != 3:
    return "FAIL: expected height 3, got " & $grid.height
  if grid.width < 1:
    return "FAIL: expected width >= 1, got " & $grid.width
  "PASS: lexer_2d_grid"

# ─────────────────────────────────────────────────────────────────────────────
# Test: Parser variable declarations
# ─────────────────────────────────────────────────────────────────────────────

proc testParserVarDecl*(): string =
  let prog = parseHybrid("int x = 5; int y;")
  if prog.error != "":
    return "FAIL: parser error: " & prog.error
  if prog.variables.len != 2:
    return "FAIL: expected 2 variables, got " & $prog.variables.len
  if prog.variables[0].name != "x" or prog.variables[0].initialValue != 5:
    return "FAIL: first variable incorrect"
  if prog.variables[1].name != "y":
    return "FAIL: second variable incorrect"
  "PASS: parser_var_decl"

# ─────────────────────────────────────────────────────────────────────────────
# Test: Parser array declarations
# ─────────────────────────────────────────────────────────────────────────────

proc testParserArrayDecl*(): string =
  let prog = parseHybrid("int buf[256];")
  if prog.error != "":
    return "FAIL: parser error: " & prog.error
  if prog.variables.len != 1:
    return "FAIL: expected 1 variable, got " & $prog.variables.len
  let v = prog.variables[0]
  if v.name != "buf" or not v.isArray or v.arraySize != 256:
    return "FAIL: array declaration incorrect"
  "PASS: parser_array_decl"

# ─────────────────────────────────────────────────────────────────────────────
# Test: Parser memory layout
# ─────────────────────────────────────────────────────────────────────────────

proc testParserMemLayout*(): string =
  let prog = parseHybrid("int x; int y; int z;")
  if prog.error != "":
    return "FAIL: parser error: " & prog.error
  let layout = prog.memoryLayout
  if layout.subleqOverhead != 9:
    return "FAIL: SUBLEQ overhead should be 9, got " & $layout.subleqOverhead
  if layout.totalCells < layout.subleqOverhead + 3:
    return "FAIL: total cells too small"
  # Variables should be at addresses 9, 10, 11 (after overhead)
  if prog.variables.len > 0 and prog.variables[0].cellAddr != 9:
    return "FAIL: first var should be at 9, got " & $prog.variables[0].cellAddr
  "PASS: parser_mem_layout"

# ─────────────────────────────────────────────────────────────────────────────
# Test: AST node construction
# ─────────────────────────────────────────────────────────────────────────────

proc testASTConstruction*(): string =
  let lit = newLitNode(42)
  if lit.kind != astLit or lit.litValue != 42:
    return "FAIL: lit node construction"

  let varRef = newVarRefNode("foo")
  if varRef.kind != astVarRef or varRef.varName != "foo":
    return "FAIL: var ref node construction"

  let seq = newSeqNode(@[lit, varRef])
  if seq.kind != astSeq or seq.children.len != 2:
    return "FAIL: seq node construction"

  "PASS: ast_construction"

# ─────────────────────────────────────────────────────────────────────────────
# Test: Befunge grid parsing (2D)
# ─────────────────────────────────────────────────────────────────────────────

proc testBefungeGridParsing*(): string =
  let grid2d = "v\n>\n<\n^"
  let prog = parseHybrid(grid2d)
  if prog.befungeGrid.height <= 0:
    return "FAIL: Befunge grid not detected"
  "PASS: befunge_grid_parsing"

# ─────────────────────────────────────────────────────────────────────────────
# Test: Brainfuck loop matching
# ─────────────────────────────────────────────────────────────────────────────

proc testBrainfuckLoopMatching*(): string =
  let input = "+++[>++<-]"
  let tokResult = tokenize(input)
  let tokens = tokResult[0]
  let err = tokResult[1]
  if err != "":
    return "FAIL: lexer error: " & err
  let bracketResult = matchBrackets(tokens)
  let jumpMap = bracketResult[0]
  let matchErr = bracketResult[1]
  if matchErr != "":
    return "FAIL: bracket matching error: " & matchErr
  # Should have matched [ and ]
  var hasMatch = false
  for j in jumpMap:
    if j > 0:
      hasMatch = true
      break
  if not hasMatch:
    return "FAIL: brackets not matched"
  "PASS: brainfuck_loop_matching"

# ─────────────────────────────────────────────────────────────────────────────
# Test: Parser error handling (unmatched bracket)
# ─────────────────────────────────────────────────────────────────────────────

proc testParserErrorHandling*(): string =
  let input = "+++[+++"  # unmatched [
  let tokResult = tokenize(input)
  let tokens = tokResult[0]
  let err = tokResult[1]
  if err != "":
    return "SKIP: lexer error (expected): " & err
  let bracketResult = matchBrackets(tokens)
  let jumpMap = bracketResult[0]
  let matchErr = bracketResult[1]
  if matchErr == "":
    return "FAIL: should detect unmatched bracket"
  "PASS: parser_error_handling"

# ─────────────────────────────────────────────────────────────────────────────
# Test: Variable name uniqueness
# ─────────────────────────────────────────────────────────────────────────────

proc testVarUniqueness*(): string =
  let prog = parseHybrid("int x; int x;")
  if prog.error == "":
    return "FAIL: should detect duplicate variable"
  "PASS: var_uniqueness"

# ─────────────────────────────────────────────────────────────────────────────
# Test: Memory layout validation
# ─────────────────────────────────────────────────────────────────────────────

proc testMemLayoutValidation*(): string =
  let prog = parseHybrid("int x = 1;")
  let validErr = validateMemoryLayout(prog.memoryLayout)
  if validErr != "":
    return "FAIL: valid layout rejected: " & validErr
  "PASS: mem_layout_validation"

# ─────────────────────────────────────────────────────────────────────────────
# Test: Variable declaration validation
# ─────────────────────────────────────────────────────────────────────────────

proc testVarDeclValidation*(): string =
  var v = VarDecl(name: "x", cellAddr: 0, isArray: false)
  let err = validateVarDecl(v)
  if err != "":
    return "FAIL: valid var decl rejected: " & err

  var v2 = VarDecl(name: "", cellAddr: 0)
  let err2 = validateVarDecl(v2)
  if err2 == "":
    return "FAIL: empty name should be invalid"

  "PASS: var_decl_validation"

# ─────────────────────────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────────────────────────

proc runTests*() =
  let tests = @[
    testLexerBasic,
    testLexerVarDecl,
    testLexerNumbers,
    testLexer2DGrid,
    testParserVarDecl,
    testParserArrayDecl,
    testParserMemLayout,
    testASTConstruction,
    testBefungeGridParsing,
    testBrainfuckLoopMatching,
    testParserErrorHandling,
    testVarUniqueness,
    testMemLayoutValidation,
    testVarDeclValidation,
  ]

  var passed = 0
  var failed = 0
  var skipped = 0

  for test in tests:
    let result = test()
    echo result
    if result.startsWith("PASS"):
      inc passed
    elif result.startsWith("FAIL"):
      inc failed
    elif result.startsWith("SKIP"):
      inc skipped

  echo ""
  echo "Results: " & $passed & " passed, " & $failed & " failed, " & $skipped & " skipped"
  if failed > 0:
    quit(1)

when isMainModule:
  runTests()
