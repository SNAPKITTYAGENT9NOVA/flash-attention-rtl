# SUBLEQ + φ-Born Deterministic Attention

A small, deterministic agent built on **SUBLEQ** (a one-instruction computer) with **φ-Born attention** for action selection, plus a **Brainfuck → SUBLEQ transpiler**.

## What's in it

- **SUBLEQ interpreter** with bounds-checked memory, a step limit, and input/output
- **Brainfuck → SUBLEQ transpiler** that compiles any Brainfuck program to a SUBLEQ memory image
- **Reference Brainfuck interpreter** used to test the transpiler
- **φ-Born attention**: golden-ratio-weighted, multi-head, deterministic action selection
- **Agent loop** that encodes its state, selects an action with φ-Born attention, and runs for a bounded number of cycles

Everything is deterministic: no random numbers, and the same input always produces the same output.

## Quick start

Requires [Nim](https://nim-lang.org/).

```bash
# run the agent (the argument is a Brainfuck program used as its goal)
nim c -d:release consolidated_agent.nim
./consolidated_agent "+++[-]"

# run the test suite
nim c -d:release test_bf_to_subleq_j.nim
./test_bf_to_subleq_j
```

## SUBLEQ

One instruction, `subleq a b c`:

```
mem[b] -= mem[a]
if mem[b] <= 0: goto c   else: goto next instruction
```

Interpreter conventions (`subleq_bf.nim`):

| Condition | Behaviour |
|-----------|-----------|
| `a < 0` | read the next input value (0 at end of input) into `mem[b]` |
| `b < 0` | append `mem[a]` to the output |
| `pc < 0` | halt |
| operand or `pc` outside memory, or step limit reached | stop with a fault message |

## Brainfuck → SUBLEQ

SUBLEQ has no indirect addressing, so reading or writing `tape[ptr]` uses self-modifying code: the operand of the instruction that touches the tape is patched with the pointer, the instruction runs, and the operand is restored.

```
+  :  subleq NP  I+1      ; operand += ptr        (NP holds -ptr)
   I: subleq M1  TAPE     ; tape[ptr] -= -1
      subleq P   I+1      ; operand -= ptr
```

Memory layout of a compiled program:

| Address | Contents |
|---------|----------|
| `0..2` | entry triad (`mem[0]` doubles as the constant zero) |
| `3` / `4` | constants `+1` / `-1` |
| `5` / `6` | pointer `P` / negated pointer `NP` |
| `7` / `8` | scratch cells `T`, `U` |
| `9 ..` | compiled triads, ending in a halt |
| after code | the Brainfuck tape (default 256 cells) |

Operators:

| BF | Compiled to |
|----|-------------|
| `>` `<` | update `P` and `NP` |
| `+` `-` | patched `subleq` on `tape[ptr]` |
| `.` `,` | patched output / input instruction |
| `[` `]` | full `== 0` test using `T = -x`, `U = x` (works for negative cells), then jump |

Semantics: cells are unbounded signed integers (no 8-bit wrap). Moving the pointer outside `[0, tapeCells)` is undefined in the compiled program.

```nim
import subleq_bf

let prog = brainfuckToSubleq("+++[->++<]>.")   # prog.mem, prog.tapeBase, prog.error
var mem = prog.mem
let res = runSubleq(mem)                        # res.output == @[6], res.halted == true
```

## φ-Born attention

```
state ──encodeState──▶ φ-weighted activation vectors (4 heads × 8 dims)
      ──multiheadAttention──▶ one value per head: floor(Σ φ⁻ⁱ · |aᵢ|) mod 256
      ──selectAction──▶ Observe | Plan | Transpile | Run | Halt
```

The weights are powers of the inverse golden ratio, so the result is a pure function of the encoded state.

## Testing

`test_bf_to_subleq_j.nim` compiles each program to SUBLEQ, runs it, and compares output, final tape contents and final pointer with the reference Brainfuck interpreter. It covers:

- hand-written programs: pointer movement, independent cells, negative cells, skipped and nested loops, input/output, Hello World
- unmatched-bracket errors
- identical input compiling to identical memory
- about 2000 deterministic pseudo-random programs

Expected last line: `failed: 0`.

## Repository layout

| Path | Contents |
|------|----------|
| `subleq_bf.nim` | SUBLEQ interpreter, Brainfuck → SUBLEQ transpiler, reference Brainfuck interpreter |
| `consolidated_agent.nim` | φ-Born attention and the agent loop |
| `test_bf_to_subleq_j.nim` | differential test suite |
| `rtl/`, `sim/` | SystemVerilog systolic-array RTL and its simulation testbench |
| `software/` | FlashAttention golden model and test-vector generator |

## License

GNU General Public License v3 or later, with a supplementary term prohibiting use of this code as AI/ML training data. See `LICENSE`.

## References

- SUBLEQ: https://esolangs.org/wiki/Subleq
- Brainfuck: https://esolangs.org/wiki/Brainfuck
- Golden ratio: https://en.wikipedia.org/wiki/Golden_ratio
