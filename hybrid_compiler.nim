# Hybrid compiler: orchestrator for lexer → parser → codegen
# Unified pipeline for Befunge and Brainfuck languages
# Compile: nim c -d:release hybrid_compiler.nim

import hybrid_ast
import hybrid_codegen
import subleq_bf

type
  ParserError* = object
    msg*: string
    position*: int

  Language* = enum langBrainfuck, langBefunge, langHybrid

  Parser* = object
    code*: string
    pos*: int
    error*: ParserError
    program*: Program

proc initParser*(code: string): Parser =
  result.code = code
  result.pos = 0
  result.program = Program()

proc peekChar(p: Parser): char =
  if p.pos < p.code.len: p.code[p.pos] else: '\0'

proc nextChar(p: var Parser): char =
  if p.pos < p.code.len:
    result = p.code[p.pos]
    inc p.pos
  else:
    result = '\0'

proc parseError(p: var Parser; msg: string) =
  p.error = ParserError(msg: msg, position: p.pos)

proc parseBrainfuckProgram(p: var Parser): Program =
  result = Program()
  var loopStack: seq[int]

  while p.pos < p.code.len:
    let ch = nextChar(p)
    case ch
    of '>':
      result.instrs.add ptrInc()
    of '<':
      result.instrs.add ptrDec()
    of '+':
      result.instrs.add cellInc()
    of '-':
      result.instrs.add cellDec()
    of '.':
      result.instrs.add cellOut()
    of ',':
      result.instrs.add cellIn()
    of '[':
      result.instrs.add loopStart()
      loopStack.add result.instrs.len - 1
    of ']':
      if loopStack.len == 0:
        parseError(p, "unmatched ']' at position " & $p.pos)
        return result
      discard loopStack.pop()
      result.instrs.add loopEnd()
    else:
      discard

  if loopStack.len > 0:
    parseError(p, "unmatched '[' at position " & $p.pos)

  result.instrs.add halt()
  result.mode = modeBrainfuck

proc parseBefungeProgram(p: var Parser): Program =
  result = Program()

  while p.pos < p.code.len:
    let ch = nextChar(p)
    case ch
    of '0'..'9':
      result.instrs.add push(int(ch) - int('0'))
    of '+':
      result.instrs.add add()
    of '-':
      result.instrs.add sub()
    of '*':
      result.instrs.add mul()
    of '/':
      result.instrs.add divOp()
    of '%':
      result.instrs.add modOp()
    of '!':
      result.instrs.add notOp()
    of '`':
      result.instrs.add greaterOp()
    of '@':
      result.instrs.add halt()
      return result
    of '.':
      result.instrs.add output()
    of ',':
      result.instrs.add input()
    else:
      discard

  result.instrs.add halt()
  result.mode = modeBefunge

proc detectLanguage*(code: string): Language =
  let befungeChars = {'>', '<', 'v', '^', '0'..'9', '+', '-', '*', '/', '%', '!', '`', '@', '.', ',', '"', '#'}
  let brainfuckChars = {'>', '<', '+', '-', '.', ',', '[', ']'}

  var hasBeads = false
  var hasOther = false

  for ch in code:
    if ch in befungeChars and ch notin brainfuckChars:
      hasBeads = true
    elif ch in brainfuckChars and ch notin befungeChars:
      hasOther = true

  if hasBeads and hasOther:
    langHybrid
  elif hasBeads:
    langBefunge
  else:
    langBrainfuck

proc parseProgram*(code: string): tuple[program: Program, error: string] =
  var p = initParser(code)
  let lang = detectLanguage(code)

  let prog = case lang
  of langBrainfuck:
    parseBrainfuckProgram(p)
  of langBefunge:
    parseBefungeProgram(p)
  of langHybrid:
    parseBrainfuckProgram(p)

  if p.error.msg.len > 0:
    return (prog, p.error.msg)
  return (prog, "")

proc compileToSubleq*(sourceCode: string; tapeCells = 256): tuple[result: Transpiled, error: string] =
  let (prog, parseErr) = parseProgram(sourceCode)
  if parseErr.len > 0:
    return (Transpiled(error: parseErr), parseErr)

  let tr = codegen(prog, tapeCells)
  return (tr, tr.error)

when isMainModule:
  let bfCode = "+++."
  let (tr, err) = compileToSubleq(bfCode, 64)

  if err.len > 0:
    echo "Compilation error: " & err
    quit 1

  var mem = tr.mem
  let result = runSubleq(mem)

  echo "Output: " & $result.output
  if result.halted:
    echo "Halted successfully"
  else:
    echo "Fault: " & result.fault
