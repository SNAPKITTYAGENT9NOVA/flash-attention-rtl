#include "l1_tensor.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

cs_status tensor_new(tensor *t, size_t rank, const size_t *shape)
{
    if (!t || !shape || rank == 0 || rank > CS_TENSOR_MAX_RANK) return CS_ERR_ARG;
    size_t size = 1;
    for (size_t i = 0; i < rank; i++) {
        if (shape[i] == 0) return CS_ERR_ARG;
        if (size > SIZE_MAX / shape[i]) return CS_ERR_NOMEM;
        size *= shape[i];
    }
    if (size > SIZE_MAX / sizeof(gl_t)) return CS_ERR_NOMEM;
    gl_t *d = calloc(size, sizeof(gl_t));
    if (!d) return CS_ERR_NOMEM;
    memset(t, 0, sizeof *t);
    t->rank = rank;
    memcpy(t->shape, shape, rank * sizeof(size_t));
    t->d = d;
    t->size = size;
    return CS_OK;
}

void tensor_free(tensor *t)
{
    if (!t) return;
    free(t->d);
    memset(t, 0, sizeof *t);
}

static int offset_of(const tensor *t, const size_t *idx, size_t *off)
{
    size_t o = 0;
    for (size_t i = 0; i < t->rank; i++) {
        if (idx[i] >= t->shape[i]) return 0;
        o = o * t->shape[i] + idx[i];
    }
    *off = o;
    return 1;
}

cs_status tensor_get(const tensor *t, const size_t *idx, gl_t *out)
{
    size_t o;
    if (!t || !idx || !out || !t->d) return CS_ERR_ARG;
    if (!offset_of(t, idx, &o)) return CS_ERR_RANGE;
    *out = t->d[o];
    return CS_OK;
}

cs_status tensor_set(tensor *t, const size_t *idx, gl_t v)
{
    size_t o;
    if (!t || !idx || !t->d) return CS_ERR_ARG;
    if (!offset_of(t, idx, &o)) return CS_ERR_RANGE;
    t->d[o] = gl_reduce(v);
    return CS_OK;
}

static int same_shape(const tensor *a, const tensor *b)
{
    return a->rank == b->rank && memcmp(a->shape, b->shape, a->rank * sizeof(size_t)) == 0;
}

static cs_status pointwise(const tensor *a, const tensor *b, tensor *out, int mul)
{
    if (!a || !b || !out || !a->d || !b->d) return CS_ERR_ARG;
    if (!same_shape(a, b)) return CS_ERR_RANGE;
    tensor r;
    cs_status s = tensor_new(&r, a->rank, a->shape);
    if (s != CS_OK) return s;
    for (size_t i = 0; i < r.size; i++)
        r.d[i] = mul ? gl_mul(a->d[i], b->d[i]) : gl_add(a->d[i], b->d[i]);
    *out = r;
    return CS_OK;
}

cs_status tensor_add(const tensor *a, const tensor *b, tensor *out) { return pointwise(a, b, out, 0); }
cs_status tensor_hadamard(const tensor *a, const tensor *b, tensor *out) { return pointwise(a, b, out, 1); }

cs_status tensor_outer(const tensor *a, const tensor *b, tensor *out)
{
    if (!a || !b || !out || !a->d || !b->d) return CS_ERR_ARG;
    if (a->rank + b->rank > CS_TENSOR_MAX_RANK) return CS_ERR_RANGE;
    size_t shape[CS_TENSOR_MAX_RANK];
    memcpy(shape, a->shape, a->rank * sizeof(size_t));
    memcpy(shape + a->rank, b->shape, b->rank * sizeof(size_t));
    tensor r;
    cs_status s = tensor_new(&r, a->rank + b->rank, shape);
    if (s != CS_OK) return s;
    for (size_t i = 0; i < a->size; i++)
        for (size_t j = 0; j < b->size; j++) r.d[i * b->size + j] = gl_mul(a->d[i], b->d[j]);
    *out = r;
    return CS_OK;
}

cs_status tensor_contract(const tensor *a, size_t axis_a, const tensor *b, size_t axis_b, tensor *out)
{
    if (!a || !b || !out || !a->d || !b->d) return CS_ERR_ARG;
    if (axis_a >= a->rank || axis_b >= b->rank) return CS_ERR_RANGE;
    if (a->shape[axis_a] != b->shape[axis_b]) return CS_ERR_RANGE;
    size_t rr = a->rank + b->rank - 2;
    if (rr == 0 || rr > CS_TENSOR_MAX_RANK) return CS_ERR_RANGE;

    size_t shape[CS_TENSOR_MAX_RANK], n = 0;
    for (size_t i = 0; i < a->rank; i++) if (i != axis_a) shape[n++] = a->shape[i];
    for (size_t i = 0; i < b->rank; i++) if (i != axis_b) shape[n++] = b->shape[i];
    tensor r;
    cs_status s = tensor_new(&r, rr, shape);
    if (s != CS_OK) return s;

    size_t ext = a->shape[axis_a];
    size_t ia[CS_TENSOR_MAX_RANK], ib[CS_TENSOR_MAX_RANK], ir[CS_TENSOR_MAX_RANK] = {0};
    for (size_t o = 0; o < r.size; o++) {
        /* decode o into the free indices of a then b */
        size_t rem = o;
        for (size_t i = rr; i-- > 0;) { ir[i] = rem % r.shape[i]; rem /= r.shape[i]; }
        size_t p = 0;
        for (size_t i = 0; i < a->rank; i++) if (i != axis_a) ia[i] = ir[p++];
        for (size_t i = 0; i < b->rank; i++) if (i != axis_b) ib[i] = ir[p++];
        gl_t acc = 0;
        for (size_t k = 0; k < ext; k++) {
            ia[axis_a] = k;
            ib[axis_b] = k;
            size_t oa = 0, ob = 0;
            if (!offset_of(a, ia, &oa) || !offset_of(b, ib, &ob)) {
                tensor_free(&r);
                return CS_ERR_RANGE;
            }
            acc = gl_add(acc, gl_mul(a->d[oa], b->d[ob]));
        }
        r.d[o] = acc;
    }
    *out = r;
    return CS_OK;
}

cs_status tensor_from_pmat(const pmat *m, tensor *t)
{
    if (!m || !t || !m->d) return CS_ERR_ARG;
    size_t shape[2] = {m->rows, m->cols};
    cs_status s = tensor_new(t, 2, shape);
    if (s != CS_OK) return s;
    memcpy(t->d, m->d, t->size * sizeof(gl_t));
    return CS_OK;
}

cs_status tensor_to_pmat(const tensor *t, pmat *m)
{
    if (!t || !m || !t->d) return CS_ERR_ARG;
    if (t->rank != 2) return CS_ERR_RANGE;
    cs_status s = pmat_new(m, t->shape[0], t->shape[1]);
    if (s != CS_OK) return s;
    memcpy(m->d, t->d, t->size * sizeof(gl_t));
    return CS_OK;
}
