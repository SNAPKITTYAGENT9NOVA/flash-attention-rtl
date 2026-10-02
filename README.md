# SUBLEQ + φ-Born Deterministic Attention

A small, deterministic agent built on **SUBLEQ** (a one-instruction computer) with **φ-Born attention** for action selection, plus a **Brainfuck → SUBLEQ transpiler**.

## What's in it

- **SUBLEQ interpreter** with bounds-checked memory, a step limit, and input/output
- **Brainfuck → SUBLEQ transpiler** that compiles any Brainfuck program to a SUBLEQ memory image
- **Reference Brainfuck interpreter** used to test the transpiler
- **FlashAttention opcode**: a SUBLEQ instruction that hands a whole attention computation to a hardware engine (`FA_ENGINE`), then resumes
- **φ-Born attention**: golden-ratio-weighted, multi-head, deterministic action selection
- **SUBLEQ CPU + FA_ENGINE + RAM** in SystemVerilog, verified in simulation against the Nim interpreter and a bit-exact Python model
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
| `a == -1` | read the next input value (0 at end of input) into `mem[b]` |
| `a == -2` | FlashAttention trap (see below); continue at `c` |
| `a < -2` | fault |
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

## FlashAttention opcode and FA_ENGINE

Billions of SUBLEQ steps would be needed to express attention, so the CPU has one extended instruction. A triad whose `a` operand is `-2` is the **FA trap**:

```
SUBLEQ program ──▶ normal subtract/branch ──▶ FA trap (a = -2)
                                                  │
                                    FlashAttention hardware (FA_ENGINE)
                                                  │
                                         result written to memory
                                                  │
                                       SUBLEQ resumes at c
```

`subleq a=-2, b=DESC, c=NEXT` — `b` is the address of a 6-word descriptor (`FA_BEGIN`):

| Word | Field | Meaning |
|------|-------|---------|
| `DESC+0` | `Q_ptr` | address of Q (`N × d`, row-major) |
| `DESC+1` | `K_ptr` | address of K |
| `DESC+2` | `V_ptr` | address of V |
| `DESC+3` | `O_ptr` | address where O (`N × d`) is written |
| `DESC+4` | `sequence_length` | `N`, 1 … 1,048,576 |
| `DESC+5` | `head_dimension` | `d`, 1 … 16 |

An invalid descriptor, or any address outside memory, faults the CPU. The engine never writes memory for an invalid descriptor.

```
SUBLEQ CPU ── instruction decoder ─┬─ SUBLEQ path: subtract / branch
                                   └─ FA path ──▶ FA_ENGINE
FA_ENGINE
├── Q_TILE_SRAM, K_TILE_SRAM, V_TILE_SRAM      (fa_tile_sram)
├── QK_DOT_PRODUCT — MAC array                 (fa_qk_mac)
├── ROW_MAX                                    (fa_row_max)
├── EXP_APPROX                                 (fa_exp_approx)
├── ONLINE_SOFTMAX — running m and l           (fa_online_softmax)
├── PV_ACCUMULATOR                             (fa_pv_accum)
├── OUTPUT_NORMALIZER                          (fa_output_normalizer, fa_divider)
└── DMA / MEMORY_INTERFACE                     (fa_dma)
```

Algorithm (per query row, key tiles of `BC = 4`): scores `Q·K` on the MAC array → tile max → `m_new = max(m, tile_max)`, `alpha = exp(m − m_new)` → `l`, `o` rescaled by `alpha` → `p = exp(score − m_new)`, `l += p`, `o += p·V` → after the last tile `O = o / l`.

Number formats (defined bit-exactly by `software/fa_int_model.py`):

| Quantity | Format |
|----------|--------|
| Q, K, V elements | signed 8-bit Q4.4 in the low 8 bits of each word |
| logits | integer, 8 fractional bits, scaled by `round(256/√d)` |
| `exp(−x)` | Q0.16, 16-segment table with linear interpolation (≤ 0.3 % absolute error) |
| `l`, `o` accumulators | 64-bit |
| O elements | signed integer, 8 fractional bits (`(o·16)/l`, truncated toward zero) |

RTL words are 32-bit. `BC = 4` is part of the numerical definition of the result (the softmax rescale happens once per key tile). The engine processes one operation at a time and is not pipelined across keys.

The Nim interpreter implements the same opcode (`fa_model.nim`), so a SUBLEQ program behaves identically in software and on the RTL CPU.

## φ-Born attention

```
state ──encodeState──▶ φ-weighted activation vectors (4 heads × 8 dims)
      ──multiheadAttention──▶ one value per head: floor(Σ φ⁻ⁱ · |aᵢ|) mod 256
      ──selectAction──▶ Observe | Plan | Transpile | Run | Halt
```

The weights are powers of the inverse golden ratio, so the result is a pure function of the encoded state.

## Testing

```bash
# Brainfuck transpiler (Nim only)
nim c -d:release test_bf_to_subleq_j.nim && ./test_bf_to_subleq_j

# FlashAttention opcode and hardware (needs python3 + numpy, nim, verilator)
sim/fa/run_all.sh
```

`test_bf_to_subleq_j.nim` compiles each program to SUBLEQ, runs it, and compares output, final tape contents and final pointer with the reference Brainfuck interpreter: hand-written programs (pointer movement, negative cells, nested loops, I/O, Hello World), unmatched-bracket errors, deterministic output, and about 2000 pseudo-random programs.

`sim/fa/run_all.sh` runs the whole FlashAttention flow:

1. `software/gen_fa_vectors.py` — the Python integer model produces 88 test cases (every head dimension 1–16, sequence lengths that are and are not multiples of the tile size, full-range and extreme operands) and checks the model against floating-point attention.
2. `test_fa_opcode.nim` — each case runs as a real SUBLEQ program in the Nim interpreter (subtract/branch loop, FA trap, then more SUBLEQ that prints the result) and must match the Python output; it also writes memory images.
3. Verilator testbenches:
   - `tb_fa_units` — `fa_exp_approx` bit-exact over 4200 inputs, `fa_divider` against SystemVerilog division, `fa_qk_mac`, `fa_row_max`
   - `tb_fa_engine` — `FA_ENGINE` against all 88 cases, bit-exact; inputs and surrounding memory untouched; invalid descriptors rejected; out-of-range access flagged
   - `tb_subleq_soc` — the RTL CPU + FA_ENGINE + RAM runs all 88 FA programs and four transpiled Brainfuck programs (including Hello World), compared with the Nim/Python outputs

## Repository layout

| Path | Contents |
|------|----------|
| `subleq_bf.nim` | SUBLEQ interpreter, Brainfuck → SUBLEQ transpiler, reference Brainfuck interpreter |
| `fa_model.nim` | integer FlashAttention model used by the interpreter's FA opcode |
| `consolidated_agent.nim` | φ-Born attention and the agent loop |
| `test_bf_to_subleq_j.nim` | transpiler differential tests |
| `test_fa_opcode.nim` | FA opcode tests; writes memory images for the RTL SoC test |
| `rtl/src/fa_*.sv`, `subleq_cpu.sv`, `subleq_fa_soc.sv`, `subleq_ram.sv` | FA_ENGINE blocks, SUBLEQ CPU, SoC and RAM |
| `sim/fa/` | Verilator testbenches, test vectors and `run_all.sh` |
| `software/fa_int_model.py`, `gen_fa_vectors.py` | bit-exact integer model and test-vector generator |
| `rtl/src/processing_element.sv`, `systolic_array.sv`, `sim/test_systolic_array.py` | systolic-array RTL and its testbench |
| `software/` | FlashAttention golden model and test-vector generator |

## License

GNU General Public License v3 or later, with a supplementary term prohibiting use of this code as AI/ML training data. See `LICENSE`.

## References

- SUBLEQ: https://esolangs.org/wiki/Subleq
- Brainfuck: https://esolangs.org/wiki/Brainfuck
- Golden ratio: https://en.wikipedia.org/wiki/Golden_ratio
