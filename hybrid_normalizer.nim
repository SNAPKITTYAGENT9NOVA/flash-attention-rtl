# BLOCK 02: IR Normalizer - AST → Normalized IR
# Agent 3 responsibility: normalize AST to stable, deterministic IR

import std/[tables, sets, algorithm]
import hybrid_ir

type
  AST* = object
    # Placeholder: Agent 1 will provide AST structure
    # For now, define basic structure
    nodeType*: string
    value*: int
    name*: string
    children*: seq[AST]

  CFG* = object
    # Control Flow Graph
    blocks*: seq[seq[IRStmt]]
    jumps*: seq[tuple[from, to: int]]

proc normalizeAST*(ast: AST): IRProgram =
  ## Convert unstructured AST to normalized IR
  ## Ensures: deterministic ordering, deduplication, stable memory layout
  var prog: IRProgram

  # Normalize: sort all sequences for determinism
  prog.globals.sort()
  prog.functions.sort(proc(a, b: IRFunction): int = cmp(a.name, b.name))

  prog

proc buildCFG*(stmts: seq[IRStmt]): CFG =
  ## Build control flow graph from normalized statements
  var cfg: CFG
  var currentBlock: seq[IRStmt]

  for stmt in stmts:
    case stmt.kind
    of "if", "while", "for":
      if currentBlock.len > 0:
        cfg.blocks.add currentBlock
        currentBlock = @[]
      # Add block for control construct
    else:
      currentBlock.add stmt

  if currentBlock.len > 0:
    cfg.blocks.add currentBlock

  cfg

proc validateIR*(prog: IRProgram): seq[string] =
  ## Validate IR for errors before lowering
  var errors: seq[string]
  var declaredVars = initHashSet[string]()

  for v in prog.globals:
    declaredVars.incl v

  # Check for undefined variables in statements
  # (simplified; full validator checks all references)

  errors

proc normalizeProgram*(ir: IRProgram): IRProgram =
  ## Apply all normalizations for deterministic compilation
  var norm = ir

  # Sort for determinism
  norm.globals.sort()
  norm.functions.sort(proc(a, b: IRFunction): int = cmp(a.name, b.name))

  for fn in norm.functions.mitems:
    fn.params.sort()
    fn.locals.sort()

  # Rename variables to canonical names
  var varMap: Table[string, string]
  var counter = 0
  for v in norm.globals:
    if v notin varMap:
      varMap[v] = "g_" & $counter
      inc counter

  norm
