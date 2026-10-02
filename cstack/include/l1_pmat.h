#ifndef L1_PMAT_H
#define L1_PMAT_H

/* Layer 1 - UAC: dense matrices over F_p (PMat). Row-major. */

#include <stddef.h>

#include "l1_goldilocks.h"

typedef struct pmat {
    size_t rows, cols;
    gl_t  *d;
} pmat;

cs_status pmat_new(pmat *m, size_t rows, size_t cols);     /* zero-filled */
void      pmat_free(pmat *m);
cs_status pmat_identity(pmat *m, size_t n);
gl_t      pmat_get(const pmat *m, size_t r, size_t c);     /* caller guarantees in range */
void      pmat_set(pmat *m, size_t r, size_t c, gl_t v);
int       pmat_equal(const pmat *a, const pmat *b);

cs_status pmat_add(const pmat *a, const pmat *b, pmat *out);
cs_status pmat_sub(const pmat *a, const pmat *b, pmat *out);
cs_status pmat_scale(const pmat *a, gl_t k, pmat *out);
cs_status pmat_mul(const pmat *a, const pmat *b, pmat *out);
cs_status pmat_transpose(const pmat *a, pmat *out);
cs_status pmat_det(const pmat *a, gl_t *det);               /* square only */
cs_status pmat_inverse(const pmat *a, pmat *out);           /* CS_ERR_SINGULAR if det = 0 */

#endif
