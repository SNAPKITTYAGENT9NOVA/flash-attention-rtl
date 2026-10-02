#include "l1_pmat.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

cs_status pmat_new(pmat *m, size_t rows, size_t cols)
{
    if (!m || rows == 0 || cols == 0) return CS_ERR_ARG;
    if (rows > SIZE_MAX / cols || rows * cols > SIZE_MAX / sizeof(gl_t)) return CS_ERR_NOMEM;
    m->d = calloc(rows * cols, sizeof(gl_t));
    if (!m->d) return CS_ERR_NOMEM;
    m->rows = rows;
    m->cols = cols;
    return CS_OK;
}

void pmat_free(pmat *m)
{
    if (!m) return;
    free(m->d);
    m->d = NULL;
    m->rows = m->cols = 0;
}

cs_status pmat_identity(pmat *m, size_t n)
{
    cs_status s = pmat_new(m, n, n);
    if (s != CS_OK) return s;
    for (size_t i = 0; i < n; i++) m->d[i * n + i] = 1;
    return CS_OK;
}

gl_t pmat_get(const pmat *m, size_t r, size_t c) { return m->d[r * m->cols + c]; }
void pmat_set(pmat *m, size_t r, size_t c, gl_t v) { m->d[r * m->cols + c] = gl_reduce(v); }

int pmat_equal(const pmat *a, const pmat *b)
{
    return a->rows == b->rows && a->cols == b->cols &&
           memcmp(a->d, b->d, a->rows * a->cols * sizeof(gl_t)) == 0;
}

static cs_status elementwise(const pmat *a, const pmat *b, pmat *out, int sub)
{
    if (!a || !b || !out || !a->d || !b->d) return CS_ERR_ARG;
    if (a->rows != b->rows || a->cols != b->cols) return CS_ERR_RANGE;
    pmat r;
    cs_status s = pmat_new(&r, a->rows, a->cols);
    if (s != CS_OK) return s;
    for (size_t i = 0; i < a->rows * a->cols; i++)
        r.d[i] = sub ? gl_sub(a->d[i], b->d[i]) : gl_add(a->d[i], b->d[i]);
    *out = r;
    return CS_OK;
}

cs_status pmat_add(const pmat *a, const pmat *b, pmat *out) { return elementwise(a, b, out, 0); }
cs_status pmat_sub(const pmat *a, const pmat *b, pmat *out) { return elementwise(a, b, out, 1); }

cs_status pmat_scale(const pmat *a, gl_t k, pmat *out)
{
    if (!a || !out || !a->d) return CS_ERR_ARG;
    pmat r;
    cs_status s = pmat_new(&r, a->rows, a->cols);
    if (s != CS_OK) return s;
    k = gl_reduce(k);
    for (size_t i = 0; i < a->rows * a->cols; i++) r.d[i] = gl_mul(a->d[i], k);
    *out = r;
    return CS_OK;
}

cs_status pmat_mul(const pmat *a, const pmat *b, pmat *out)
{
    if (!a || !b || !out || !a->d || !b->d) return CS_ERR_ARG;
    if (a->cols != b->rows) return CS_ERR_RANGE;
    pmat r;
    cs_status s = pmat_new(&r, a->rows, b->cols);
    if (s != CS_OK) return s;
    for (size_t i = 0; i < a->rows; i++)
        for (size_t k = 0; k < a->cols; k++) {
            gl_t aik = a->d[i * a->cols + k];
            for (size_t j = 0; j < b->cols; j++)
                r.d[i * r.cols + j] = gl_add(r.d[i * r.cols + j], gl_mul(aik, b->d[k * b->cols + j]));
        }
    *out = r;
    return CS_OK;
}

cs_status pmat_transpose(const pmat *a, pmat *out)
{
    if (!a || !out || !a->d) return CS_ERR_ARG;
    pmat r;
    cs_status s = pmat_new(&r, a->cols, a->rows);
    if (s != CS_OK) return s;
    for (size_t i = 0; i < a->rows; i++)
        for (size_t j = 0; j < a->cols; j++) r.d[j * r.cols + i] = a->d[i * a->cols + j];
    *out = r;
    return CS_OK;
}

/* Gauss-Jordan on [A | I]; accumulates the determinant. */
static cs_status eliminate(const pmat *a, pmat *inv_out, gl_t *det_out)
{
    if (!a || !a->d) return CS_ERR_ARG;
    if (a->rows != a->cols) return CS_ERR_RANGE;
    size_t n = a->rows;
    pmat w, id;
    cs_status s = pmat_new(&w, n, n);
    if (s != CS_OK) return s;
    memcpy(w.d, a->d, n * n * sizeof(gl_t));
    s = pmat_identity(&id, n);
    if (s != CS_OK) { pmat_free(&w); return s; }

    gl_t det = 1;
    for (size_t col = 0; col < n; col++) {
        size_t piv = col;
        while (piv < n && w.d[piv * n + col] == 0) piv++;
        if (piv == n) { det = 0; pmat_free(&w); pmat_free(&id); if (det_out) *det_out = 0; return CS_ERR_SINGULAR; }
        if (piv != col) {
            for (size_t j = 0; j < n; j++) {
                gl_t t = w.d[piv * n + j]; w.d[piv * n + j] = w.d[col * n + j]; w.d[col * n + j] = t;
                t = id.d[piv * n + j]; id.d[piv * n + j] = id.d[col * n + j]; id.d[col * n + j] = t;
            }
            det = gl_neg(det);
        }
        gl_t pv = w.d[col * n + col], pinv;
        det = gl_mul(det, pv);
        (void)gl_inv(pv, &pinv);
        for (size_t j = 0; j < n; j++) {
            w.d[col * n + j] = gl_mul(w.d[col * n + j], pinv);
            id.d[col * n + j] = gl_mul(id.d[col * n + j], pinv);
        }
        for (size_t r = 0; r < n; r++) {
            if (r == col) continue;
            gl_t f = w.d[r * n + col];
            if (f == 0) continue;
            for (size_t j = 0; j < n; j++) {
                w.d[r * n + j] = gl_sub(w.d[r * n + j], gl_mul(f, w.d[col * n + j]));
                id.d[r * n + j] = gl_sub(id.d[r * n + j], gl_mul(f, id.d[col * n + j]));
            }
        }
    }
    if (det_out) *det_out = det;
    pmat_free(&w);
    if (inv_out) *inv_out = id; else pmat_free(&id);
    return CS_OK;
}

cs_status pmat_det(const pmat *a, gl_t *det)
{
    if (!det) return CS_ERR_ARG;
    cs_status s = eliminate(a, NULL, det);
    if (s == CS_ERR_SINGULAR) return CS_OK;     /* det of a singular matrix is 0 */
    return s;
}

cs_status pmat_inverse(const pmat *a, pmat *out)
{
    if (!out) return CS_ERR_ARG;
    return eliminate(a, out, NULL);
}
