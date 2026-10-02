#ifndef L1_TENSOR_H
#define L1_TENSOR_H

/* Layer 1 - UAC: dense tensors over F_p, rank 1..CS_TENSOR_MAX_RANK, row-major. */

#include <stddef.h>

#include "l1_goldilocks.h"
#include "l1_pmat.h"

#define CS_TENSOR_MAX_RANK 4

typedef struct tensor {
    size_t rank;
    size_t shape[CS_TENSOR_MAX_RANK];
    gl_t  *d;
    size_t size;
} tensor;

cs_status tensor_new(tensor *t, size_t rank, const size_t *shape);   /* zero-filled */
void      tensor_free(tensor *t);
cs_status tensor_get(const tensor *t, const size_t *idx, gl_t *out);
cs_status tensor_set(tensor *t, const size_t *idx, gl_t v);

cs_status tensor_add(const tensor *a, const tensor *b, tensor *out);
cs_status tensor_hadamard(const tensor *a, const tensor *b, tensor *out);
/* out[i..., j...] = a[i...] * b[j...]; rank(a) + rank(b) <= CS_TENSOR_MAX_RANK */
cs_status tensor_outer(const tensor *a, const tensor *b, tensor *out);
/* Sum over a's axis_a and b's axis_b (extents must match). Result rank = ra + rb - 2 (>= 1). */
cs_status tensor_contract(const tensor *a, size_t axis_a, const tensor *b, size_t axis_b, tensor *out);

cs_status tensor_from_pmat(const pmat *m, tensor *t);
cs_status tensor_to_pmat(const tensor *t, pmat *m);                  /* rank 2 only */

#endif
