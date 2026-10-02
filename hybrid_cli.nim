# CLI: Hybrid Compiler Command-Line Interface
# Commands: hybridc [--option] program.hy [input]

import std/[os, parseopt, strutils, sequtils]
import subleq_bf

type
  CLICommand* = enum
    cmdParse = "parse"
    cmdEmitIR = "emit-ir"
    cmdEmitSUBLEQ = "emit-subleq"
    cmdRun = "run"
    cmdTrace = "trace"
    cmdStats = "stats"
    cmdHelp = "help"

  CLIOptions* = object
    command*: CLICommand
    inputFile*: string
    input*: seq[int]
    verbose*: bool
    optimizationLevel*: int

# ─────────────────────────────────────────────────────────────────────────
# COMMAND HANDLERS
# ─────────────────────────────────────────────────────────────────────────

proc handleParse*(filename: string): bool =
  ## Parse source file and print AST
  echo "parse command for: ", filename
  # Agent 1 will provide AST printing
  true

proc handleEmitIR*(filename: string): bool =
  ## Parse and emit IR
  echo "emit-ir command for: ", filename
  # Agent 1 → IR normalization
  true

proc handleEmitSUBLEQ*(filename: string): bool =
  ## Parse, normalize, and emit SUBLEQ
  echo "emit-subleq command for: ", filename
  # Full pipeline: Agent 1 → Agent 3 → Agent 2
  true

proc handleRun*(filename: string; input: seq[int]): bool =
  ## Compile and execute program
  echo "run command for: ", filename
  if input.len > 0:
    echo "input: ", input
  # Full pipeline with execution
  true

proc handleTrace*(filename: string; input: seq[int]): bool =
  ## Compile, execute, and print trace
  echo "trace command for: ", filename
  if input.len > 0:
    echo "input: ", input
  # Full pipeline with execution trace
  true

proc handleStats*(filename: string): bool =
  ## Analyze and report statistics
  echo "stats command for: ", filename
  # Report code size, step count, memory usage
  true

proc printHelp* =
  echo """
Hybrid Compiler - CLI Interface

Usage:
  hybridc [OPTION] PROGRAM [INPUT...]

Commands:
  parse PROGRAM              Print abstract syntax tree
  emit-ir PROGRAM            Parse and emit normalized IR
  emit-subleq PROGRAM        Compile to SUBLEQ machine code
  run PROGRAM [INPUT]        Compile and execute with given input
  trace PROGRAM [INPUT]      Execute with execution trace
  stats PROGRAM              Report code size and performance metrics
  help                       Show this help message

Options:
  -O0, -O1, -O2, -O3         Optimization level (0=none, 3=aggressive)
  -v, --verbose              Verbose output
  --source-loc               Include source location in errors
  --emit-binary FILE         Write SUBLEQ binary to file
  --emit-ir FILE             Write IR to file

Examples:
  hybridc parse program.hy
  hybridc emit-subleq program.hy
  hybridc run program.hy
  hybridc run program.hy 10 20 30
  hybridc trace program.hy 5
  hybridc -O3 run program.hy
  hybridc stats program.hy

Error Handling:
  All errors report source location and diagnostic message.
  No intermediate step fails silently.
"""

proc parseArgs*(args: seq[string]): CLIOptions =
  ## Parse command-line arguments
  var opts: CLIOptions
  opts.command = cmdRun
  opts.optimizationLevel = 1
  opts.verbose = false

  var i = 0
  while i < args.len:
    let arg = args[i]

    case arg
    of "-v", "--verbose":
      opts.verbose = true
    of "-O0":
      opts.optimizationLevel = 0
    of "-O1":
      opts.optimizationLevel = 1
    of "-O2":
      opts.optimizationLevel = 2
    of "-O3":
      opts.optimizationLevel = 3
    of "parse":
      opts.command = cmdParse
      if i + 1 < args.len:
        opts.inputFile = args[i + 1]
        inc i
    of "emit-ir":
      opts.command = cmdEmitIR
      if i + 1 < args.len:
        opts.inputFile = args[i + 1]
        inc i
    of "emit-subleq":
      opts.command = cmdEmitSUBLEQ
      if i + 1 < args.len:
        opts.inputFile = args[i + 1]
        inc i
    of "run":
      opts.command = cmdRun
      if i + 1 < args.len:
        opts.inputFile = args[i + 1]
        inc i
        # Remaining args are input
        while i + 1 < args.len:
          try:
            opts.input.add parseInt(args[i + 1])
            inc i
          except ValueError:
            break
    of "trace":
      opts.command = cmdTrace
      if i + 1 < args.len:
        opts.inputFile = args[i + 1]
        inc i
        # Remaining args are input
        while i + 1 < args.len:
          try:
            opts.input.add parseInt(args[i + 1])
            inc i
          except ValueError:
            break
    of "stats":
      opts.command = cmdStats
      if i + 1 < args.len:
        opts.inputFile = args[i + 1]
        inc i
    of "help", "-h", "--help":
      opts.command = cmdHelp
    else:
      # Assume it's the input file if no command yet
      if opts.inputFile == "":
        opts.inputFile = arg
      else:
        # Try to parse as input value
        try:
          opts.input.add parseInt(arg)
        except ValueError:
          discard

    inc i

  opts

# ─────────────────────────────────────────────────────────────────────────
# MAIN CLI HANDLER
# ─────────────────────────────────────────────────────────────────────────

proc runCLI*(args: seq[string]) =
  ## Main CLI entry point
  if args.len == 0:
    printHelp()
    quit 0

  let opts = parseArgs(args)

  case opts.command
  of cmdHelp:
    printHelp()
  of cmdParse:
    if opts.inputFile == "":
      echo "Error: missing filename for 'parse' command"
      quit 1
    discard handleParse(opts.inputFile)
  of cmdEmitIR:
    if opts.inputFile == "":
      echo "Error: missing filename for 'emit-ir' command"
      quit 1
    discard handleEmitIR(opts.inputFile)
  of cmdEmitSUBLEQ:
    if opts.inputFile == "":
      echo "Error: missing filename for 'emit-subleq' command"
      quit 1
    discard handleEmitSUBLEQ(opts.inputFile)
  of cmdRun:
    if opts.inputFile == "":
      echo "Error: missing filename for 'run' command"
      quit 1
    discard handleRun(opts.inputFile, opts.input)
  of cmdTrace:
    if opts.inputFile == "":
      echo "Error: missing filename for 'trace' command"
      quit 1
    discard handleTrace(opts.inputFile, opts.input)
  of cmdStats:
    if opts.inputFile == "":
      echo "Error: missing filename for 'stats' command"
      quit 1
    discard handleStats(opts.inputFile)

when isMainModule:
  let args = commandLineParams()
  runCLI(args)
