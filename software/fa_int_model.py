"""
Bit-exact integer model of the FA_ENGINE hardware (rtl/src/fa_engine.sv).

Number formats
  Q, K, V elements : signed 8-bit Q4.4   (value = int / 16), taken from the low
                     8 bits of each memory word
  logits           : int, value = int / 256   ((q.k) * scale_q(d) >> 8)
  exp(-x)          : Q0.16 (65536 == 1.0), LUT(16 segments) + linear interpolation
  l, o accumulators: wide integers (hardware: 64-bit)
  output O         : value = int / 256   ((o * 16) / l, truncated toward zero)

Tiling: keys are processed in tiles of BC=4; the online-softmax rescale happens
once per tile, so BC is part of the numerical definition of the result.
"""

import math

D_MAX = 16
BR = 4
BC = 4
NEG_INF = -(1 << 30)

EXP_LUT = [int(65536 * 2 ** (-i / 16) + 0.5) for i in range(17)]
SCALE_Q = [0] + [int(256 / math.sqrt(d) + 0.5) for d in range(1, D_MAX + 1)]
LOG2E_Q8 = 369  # round(log2(e) * 256)


def s8(x: int) -> int:
    x &= 0xFF
    return x - 256 if x & 0x80 else x


def exp_neg(delta: int) -> int:
    """exp(-delta/256) in Q0.16 for delta >= 0 (delta in logit units)."""
    assert delta >= 0
    if delta > 4095:
        delta = 4095
    y8 = (delta * LOG2E_Q8) >> 8
    n = y8 >> 8
    f = y8 & 255
    i = f >> 4
    r = f & 15
    t0 = EXP_LUT[i]
    t1 = EXP_LUT[i + 1]
    base = t0 - (((t0 - t1) * r) >> 4)
    return 0 if n >= 16 else base >> n


def trunc_div(n: int, d: int) -> int:
    q = abs(n) // abs(d)
    return -q if (n < 0) != (d < 0) else q


def fa_int(Q, K, V, N: int, d: int):
    """Q, K, V: N x d lists of ints (already int8-valued). Returns N x d ints."""
    assert 1 <= d <= D_MAX and N >= 1
    out = []
    for i in range(N):
        m = NEG_INF
        l = 0
        o = [0] * d
        for j0 in range(0, N, BC):
            keys = list(range(j0, min(j0 + BC, N)))
            logits = []
            for j in keys:
                dot = sum(Q[i][c] * K[j][c] for c in range(d))
                logits.append((dot * SCALE_Q[d]) >> 8)
            m_new = max(m, max(logits))
            alpha = exp_neg(m_new - m)
            l = (l * alpha) >> 16
            o = [(x * alpha) >> 16 for x in o]
            m = m_new
            for jj, j in enumerate(keys):
                p = exp_neg(m - logits[jj])
                l += p
                for c in range(d):
                    o[c] += p * V[j][c]
        out.append([trunc_div(x * 16, l) for x in o])
    return out


def fa_float(Q, K, V, N: int, d: int):
    """Plain floating-point attention on the real values (int / 16)."""
    import numpy as np

    q = np.array(Q, dtype=np.float64) / 16
    k = np.array(K, dtype=np.float64) / 16
    v = np.array(V, dtype=np.float64) / 16
    s = q @ k.T / math.sqrt(d)
    s -= s.max(axis=1, keepdims=True)
    w = np.exp(s)
    w /= w.sum(axis=1, keepdims=True)
    return w @ v
