# Integer FlashAttention model: bit-exact twin of rtl/src/fa_engine.sv and
# software/fa_int_model.py (see the latter for the number formats).
#
# Q, K, V : n*d row-major arrays of words; only the low 8 bits (signed, Q4.4) are used.
# Result  : n*d signed integers with 8 fractional bits.

import std/math

const
  FaDMax* = 16
  FaBC = 4
  FaNegInf = -(1 shl 30)
  FaMaxN* = 1_048_576
  ExpLut = [65536, 62757, 60097, 57549, 55109, 52773, 50535, 48393, 46341,
            44376, 42495, 40693, 38968, 37316, 35734, 34219, 32768]
  ScaleQ = [0, 256, 181, 148, 128, 114, 105, 97, 91, 85, 81, 77, 74, 71, 68, 66, 64]

proc s8(x: int): int =
  let v = x and 0xFF
  if v >= 128: v - 256 else: v

proc asr(x, n: int): int = floorDiv(x, 1 shl n)

proc expNeg*(delta: int): int =
  ## exp(-delta/256) in Q0.16, delta >= 0
  let dl = min(delta, 4095)
  let y8 = (dl * 369) shr 8
  let n = y8 shr 8
  let f = y8 and 255
  let i = f shr 4
  let r = f and 15
  let t0 = ExpLut[i]
  let t1 = ExpLut[i + 1]
  let base = t0 - (((t0 - t1) * r) shr 4)
  if n >= 16: 0 else: base shr n

proc faAttention*(q, k, v: seq[int]; n, d: int): seq[int] =
  doAssert n >= 1 and d >= 1 and d <= FaDMax
  result = newSeq[int](n * d)
  for i in 0 ..< n:
    var m = FaNegInf
    var l = 0
    var o = newSeq[int](d)
    var j0 = 0
    while j0 < n:
      let keys = min(FaBC, n - j0)
      var logits = newSeq[int](keys)
      for jj in 0 ..< keys:
        var dot = 0
        for c in 0 ..< d:
          dot += s8(q[i * d + c]) * s8(k[(j0 + jj) * d + c])
        logits[jj] = asr(dot * ScaleQ[d], 8)
      var tileMax = logits[0]
      for x in logits: tileMax = max(tileMax, x)
      let mNew = max(m, tileMax)
      let alpha = expNeg(mNew - m)
      l = (l * alpha) shr 16
      for c in 0 ..< d: o[c] = asr(o[c] * alpha, 16)
      m = mNew
      for jj in 0 ..< keys:
        let p = expNeg(m - logits[jj])
        l += p
        for c in 0 ..< d: o[c] += p * s8(v[(j0 + jj) * d + c])
      j0 += FaBC
    for c in 0 ..< d:
      result[i * d + c] = (o[c] * 16) div l      # div truncates toward zero
