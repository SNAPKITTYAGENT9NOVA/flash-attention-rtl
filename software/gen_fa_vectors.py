"""
Generate test vectors for the FA_ENGINE: sim/fa/vectors/fa_vectors.txt

File format (whitespace separated decimal integers):
  <num_cases>
  per case:  N d  Q[N*d]  K[N*d]  V[N*d]  O[N*d]      (row-major)

Also checks the integer model against floating-point attention and fails if the
error is out of tolerance.

Usage: python3 software/gen_fa_vectors.py
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from fa_int_model import D_MAX, exp_neg, fa_float, fa_int

TOLERANCE = 0.08  # absolute error on output values (value units, not ints)


def rand_mat(rng, n, d, lo=-128, hi=127):
    return [[rng.randint(lo, hi) for _ in range(d)] for _ in range(n)]


def build_cases():
    rng = random.Random(12345)
    cases = []
    # every head dimension, several sequence lengths (incl. non multiples of the tile size)
    for d in range(1, D_MAX + 1):
        for n in (1, 3, 4, 5, 9):
            cases.append((n, d, rand_mat(rng, n, d, -40, 40), rand_mat(rng, n, d, -40, 40),
                          rand_mat(rng, n, d)))
    # long sequences
    for n, d in ((13, 8), (17, 4), (24, 16)):
        cases.append((n, d, rand_mat(rng, n, d, -30, 30), rand_mat(rng, n, d, -30, 30), rand_mat(rng, n, d)))
    # full-range operands: very peaked softmax, exercises alpha -> 0
    for n, d in ((6, 8), (11, 16)):
        cases.append((n, d, rand_mat(rng, n, d), rand_mat(rng, n, d), rand_mat(rng, n, d)))
    # extremes
    cases.append((5, 8, [[127] * 8] * 5, [[127] * 8] * 5, [[-128] * 8] * 5))
    cases.append((5, 8, [[-128] * 8] * 5, [[127] * 8] * 5, [[127] * 8] * 5))
    cases.append((7, 4, [[0] * 4] * 7, [[0] * 4] * 7, rand_mat(rng, 7, 4)))  # uniform attention
    return cases


def main():
    cases = build_cases()
    worst = 0.0
    lines = [str(len(cases))]
    for (n, d, Q, K, V) in cases:
        O = fa_int(Q, K, V, n, d)
        ref = fa_float(Q, K, V, n, d)
        err = np.max(np.abs(np.array(O) / 256.0 - ref))
        worst = max(worst, err)
        flat = lambda M: [str(x) for row in M for x in row]
        lines.append(f"{n} {d}")
        lines.append(" ".join(flat(Q)))
        lines.append(" ".join(flat(K)))
        lines.append(" ".join(flat(V)))
        lines.append(" ".join(flat(O)))
    out_dir = os.path.join(os.path.dirname(__file__), "..", "sim", "fa", "vectors")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "fa_vectors.txt")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    # exp_neg table for the EXP_APPROX unit test
    exp_err = 0.0
    with open(os.path.join(out_dir, "exp_vectors.txt"), "w") as f:
        for delta in range(0, 4200):
            r = exp_neg(delta)
            f.write(f"{delta} {r}\n")
            exp_err = max(exp_err, abs(r / 65536.0 - math.exp(-delta / 256.0)))
    print(f"max |exp_neg - exp| = {exp_err:.6f}")
    if exp_err > 0.003:
        sys.exit("exp approximation out of tolerance")
    print(f"{len(cases)} cases written to {os.path.normpath(path)}")
    print(f"max |integer model - float attention| = {worst:.5f} (tolerance {TOLERANCE})")
    if worst > TOLERANCE:
        sys.exit("integer model deviates from float attention beyond tolerance")


if __name__ == "__main__":
    main()
