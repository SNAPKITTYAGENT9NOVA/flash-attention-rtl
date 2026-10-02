#include "l1_goldilocks.h"

#define EPSILON 0xFFFFFFFFull   /* 2^32 - 1 = 2^64 mod p */

__extension__ typedef unsigned __int128 u128;

gl_t gl_reduce(uint64_t x) { return x >= GL_P ? x - GL_P : x; }

gl_t gl_add(gl_t a, gl_t b)
{
    uint64_t s = a + b;
    int carry = s < a;
    if (carry) s += EPSILON;          /* wrapped by 2^64 == EPSILON (mod p); cannot wrap twice */
    return gl_reduce(s);
}

gl_t gl_sub(gl_t a, gl_t b)
{
    uint64_t d = a - b;
    if (a < b) d -= EPSILON;          /* borrowed 2^64 == EPSILON (mod p) */
    return gl_reduce(d);
}

gl_t gl_neg(gl_t a) { return a == 0 ? 0 : GL_P - a; }

gl_t gl_mul(gl_t a, gl_t b)
{
    u128 prod = (u128)a * b;
    uint64_t lo = (uint64_t)prod;
    uint64_t hi = (uint64_t)(prod >> 64);
    uint64_t hi_hi = hi >> 32;
    uint64_t hi_lo = hi & EPSILON;
    /* 2^64 = 2^32 - 1, 2^96 = -1 (mod p) */
    uint64_t t0 = lo - hi_hi;
    if (lo < hi_hi) t0 -= EPSILON;
    uint64_t t1 = hi_lo * EPSILON;
    uint64_t t2 = t0 + t1;
    if (t2 < t0) t2 += EPSILON;
    return gl_reduce(t2);
}

gl_t gl_pow(gl_t a, uint64_t e)
{
    gl_t r = 1;
    while (e) {
        if (e & 1) r = gl_mul(r, a);
        a = gl_mul(a, a);
        e >>= 1;
    }
    return r;
}

cs_status gl_inv(gl_t a, gl_t *out)
{
    if (!out) return CS_ERR_ARG;
    if (a == 0) return CS_ERR_SINGULAR;
    *out = gl_pow(a, GL_P - 2);       /* Fermat */
    return CS_OK;
}

cs_status gl_div(gl_t a, gl_t b, gl_t *out)
{
    gl_t inv;
    if (!out) return CS_ERR_ARG;
    cs_status s = gl_inv(b, &inv);
    if (s != CS_OK) return s;
    *out = gl_mul(a, inv);
    return CS_OK;
}

cs_status gl_selftest(void)
{
    const gl_t m1 = GL_P - 1;
    if (gl_add(m1, 1) != 0) return CS_ERR_BOOT;
    if (gl_sub(0, 1) != m1) return CS_ERR_BOOT;
    if (gl_mul(m1, m1) != 1) return CS_ERR_BOOT;                       /* (-1)^2 = 1 */
    if (gl_mul(0xFFFFFFFFull, 0x100000001ull) != 0xFFFFFFFEull) return CS_ERR_BOOT;   /* 2^64-1 mod p */
    if (gl_pow(7, GL_P - 1) != 1) return CS_ERR_BOOT;                  /* Fermat */
    if (gl_pow(2, 192) != 1) return CS_ERR_BOOT;                       /* 2^96 = -1 => 2^192 = 1 */
    if (gl_pow(2, 96) != m1) return CS_ERR_BOOT;
    gl_t inv;
    if (gl_inv(123456789, &inv) != CS_OK || gl_mul(inv, 123456789) != 1) return CS_ERR_BOOT;
    return CS_OK;
}
