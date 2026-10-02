# BLOCK 06: Benchmarking & Analysis Framework
# Profile compiled programs: code size, step count, execution time

import std/[strutils, times, tables]

type
  ExecutionStats* = object
    sourceFile*: string
    codeSize*: int          # triads (SUBLEQ instructions)
    dataSize*: int          # words (constants, stack, tape)
    totalMemory*: int       # code + data
    stepsExecuted*: int
    outputWords*: int
    cyclesPerInstruction*: float
    executionTimeMs*: int
    optimizationLevel*: int
    beforeOptimSize*: int   # for reporting delta
    afterOptimSize*: int

  BenchmarkReport* = object
    program*: string
    stats*: ExecutionStats
    performance*: tuple[
      codeSize: int,
      stepCount: int,
      memoryUsage: int
    ]

# ─────────────────────────────────────────────────────────────────────────
# STATISTICS GATHERING
# ─────────────────────────────────────────────────────────────────────────

proc gatherStats*(sourceFile: string; compiledMem: seq[int]; executionSteps: int;
                   outputSize: int; optimLevel: int = 1;
                   beforeOptim: int = 0; afterOptim: int = 0): ExecutionStats =
  ## Gather execution statistics for a compiled program

  # Code size (SUBLEQ triads are 3 words each)
  let codeSize = compiledMem.len
  let triads = codeSize div 3

  # Data size estimation (rough; final data is embedded in memory after code)
  let dataSize = 0  # To be determined during compilation

  # CPI (cycles per instruction)
  let cpi = if compiledMem.len > 0: float(executionSteps) / float(compiledMem.len) else: 0.0

  ExecutionStats(
    sourceFile: sourceFile,
    codeSize: triads,
    dataSize: dataSize,
    totalMemory: codeSize,
    stepsExecuted: executionSteps,
    outputWords: outputSize,
    cyclesPerInstruction: cpi,
    executionTimeMs: 0,  # Would measure wall-clock time
    optimizationLevel: optimLevel,
    beforeOptimSize: beforeOptim,
    afterOptimSize: afterOptim
  )

# ─────────────────────────────────────────────────────────────────────────
# REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────

proc reportStats*(stats: ExecutionStats) =
  echo "\n" & repeat("═", 60)
  echo "EXECUTION STATISTICS: ", stats.sourceFile
  echo repeat("═", 60)

  echo "\nMemory Layout:"
  echo "  Code:       ", stats.codeSize, " triads (", stats.codeSize * 3, " words)"
  echo "  Data:       ", stats.dataSize, " words"
  echo "  Total:      ", stats.totalMemory, " words"

  echo "\nExecution Profile:"
  echo "  Steps executed: ", stats.stepsExecuted
  echo "  Output words:   ", stats.outputWords
  echo "  CPI (cycles/instr): ", formatFloat(stats.cyclesPerInstruction, ffDecimal, 2)

  if stats.beforeOptimSize > 0:
    let delta = stats.beforeOptimSize - stats.afterOptimSize
    let percent = float(delta) / float(stats.beforeOptimSize) * 100.0
    echo "\nOptimization Impact (Level ", stats.optimizationLevel, "):"
    echo "  Before:   ", stats.beforeOptimSize, " words"
    echo "  After:    ", stats.afterOptimSize, " words"
    echo "  Savings:  ", delta, " words (", formatFloat(percent, ffDecimal, 1), "%)"

  if stats.executionTimeMs > 0:
    echo "\nTiming:"
    echo "  Execution: ", stats.executionTimeMs, " ms"
    echo "  Steps/ms:  ", stats.stepsExecuted div max(1, stats.executionTimeMs)

  echo repeat("═", 60)

proc compareBenchmarks*(stats1: ExecutionStats; stats2: ExecutionStats) =
  ## Compare two execution profiles
  echo "\n" & repeat("─", 60)
  echo "BENCHMARK COMPARISON"
  echo repeat("─", 60)

  echo "\n", stats1.sourceFile, " vs ", stats2.sourceFile
  echo "\nCode Size:"
  echo "  Program 1: ", stats1.codeSize, " triads"
  echo "  Program 2: ", stats2.codeSize, " triads"
  if stats1.codeSize != stats2.codeSize:
    let diff = if stats1.codeSize > stats2.codeSize:
                 (stats1.codeSize - stats2.codeSize, "Program 1 is larger")
               else:
                 (stats2.codeSize - stats1.codeSize, "Program 2 is larger")
    echo "  Difference: ", diff[0], " triads (", diff[1], ")"

  echo "\nExecution Steps:"
  echo "  Program 1: ", stats1.stepsExecuted, " steps"
  echo "  Program 2: ", stats2.stepsExecuted, " steps"
  if stats1.stepsExecuted != stats2.stepsExecuted:
    let diff = if stats1.stepsExecuted > stats2.stepsExecuted:
                 (stats1.stepsExecuted - stats2.stepsExecuted, "Program 1 takes more steps")
               else:
                 (stats2.stepsExecuted - stats1.stepsExecuted, "Program 2 takes more steps")
    echo "  Difference: ", diff[0], " steps (", diff[1], ")"

  echo "\nCPI:"
  echo "  Program 1: ", formatFloat(stats1.cyclesPerInstruction, ffDecimal, 2)
  echo "  Program 2: ", formatFloat(stats2.cyclesPerInstruction, ffDecimal, 2)

  echo repeat("─", 60)

# ─────────────────────────────────────────────────────────────────────────
# PERFORMANCE ANALYSIS
# ─────────────────────────────────────────────────────────────────────────

proc analyzePerformance*(stats: ExecutionStats): tuple[efficiency: string, recommendations: seq[string]] =
  ## Analyze performance characteristics and suggest optimizations
  var recommendations: seq[string]
  var efficiency = "Good"

  # Check CPI
  if stats.cyclesPerInstruction > 3.0:
    efficiency = "Poor"
    recommendations.add "High CPI: consider optimizing hot loops"
  elif stats.cyclesPerInstruction > 2.0:
    efficiency = "Fair"
    recommendations.add "Moderate CPI: some optimization potential"

  # Check memory usage
  if stats.totalMemory > 10000:
    recommendations.add "Large memory footprint: consider reducing data size"

  # Check output ratio
  let outputRatio = float(stats.outputWords) / float(stats.stepsExecuted)
  if outputRatio < 0.001:
    recommendations.add "Low output ratio: most computation is internal"

  (efficiency, recommendations)

# ─────────────────────────────────────────────────────────────────────────
# BENCHMARK SUITE
# ─────────────────────────────────────────────────────────────────────────

proc runBenchmarkSuite*(programs: seq[tuple[name: string, mem: seq[int], steps: int, output: int]]) =
  echo "\n" & repeat("═", 60)
  echo "BENCHMARK SUITE"
  echo repeat("═", 60)

  var allStats: seq[ExecutionStats]

  for (name, mem, steps, output) in programs:
    let stats = gatherStats(name, mem, steps, output)
    allStats.add stats
    reportStats(stats)

    let (efficiency, recommendations) = analyzePerformance(stats)
    if recommendations.len > 0:
      echo "\n⚠ Performance Analysis for ", name
      echo "  Efficiency: ", efficiency
      for rec in recommendations:
        echo "  → ", rec

  # Summary table
  echo "\n" & repeat("═", 60)
  echo "SUMMARY TABLE"
  echo repeat("─", 60)
  echo "Program             Code Size  Steps      CPI      Memory"
  echo repeat("─", 60)

  for stats in allStats:
    let cpi = formatFloat(stats.cyclesPerInstruction, ffDecimal, 2)
    echo alignLeft(stats.sourceFile, 20) & " " &
         alignRight($stats.codeSize, 10) & " " &
         alignRight($stats.stepsExecuted, 10) & " " &
         alignRight(cpi, 8) & " " &
         alignRight($stats.totalMemory, 8)

  echo repeat("═", 60)

# ─────────────────────────────────────────────────────────────────────────
# PROFILING HELPERS
# ─────────────────────────────────────────────────────────────────────────

proc profileMemoryLayout*(mem: seq[int]): tuple[code: int, data: int, total: int] =
  ## Estimate memory layout breakdown
  ## SUBLEQ layout typically:
  ## [0..2] entry
  ## [3..8] constants and scratch
  ## [9..codeEnd] compiled code
  ## [codeEnd..] data and tape

  let codeEnd = 100  # Placeholder
  let code = min(codeEnd, mem.len)
  let data = max(0, mem.len - codeEnd)
  (code, data, mem.len)
