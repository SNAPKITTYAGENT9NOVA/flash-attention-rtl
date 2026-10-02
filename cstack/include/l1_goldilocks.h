#ifndef L1_GOLDILOCKS_H
#define L1_GOLDILOCKS_H

/* Layer 1 - UAC: arithmetic in the Goldilocks field F_p, p = 2^64 - 2^32 + 1.
 * Elements are canonical: always in [0, p). */

#include <stdint.h>

#include "cs_status.h"

#define GL_P 0xFFFFFFFF00000001ull

typedef uint64_t gl_t;

gl_t gl_reduce(uint64_t x);                 /* any uint64 -> canonical */
gl_t gl_add(gl_t a, gl_t b);
gl_t gl_sub(gl_t a, gl_t b);
gl_t gl_neg(gl_t a);
gl_t gl_mul(gl_t a, gl_t b);
gl_t gl_pow(gl_t a, uint64_t e);
cs_status gl_inv(gl_t a, gl_t *out);        /* CS_ERR_SINGULAR for 0 */
cs_status gl_div(gl_t a, gl_t b, gl_t *out);

/* Known-answer self test (field axioms on fixed vectors); used at stack init. */
cs_status gl_selftest(void);

#endif
