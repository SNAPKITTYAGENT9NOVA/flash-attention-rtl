#include "cs_test.h"
#include "l1_goldilocks.h"
#include "l1_pmat.h"
#include "l1_tensor.h"
#include <string.h>

__extension__ typedef unsigned __int128 u128;

static uint64_t rng_state = 0x123456789abcdef1ull;
static uint64_t rnd(void)
{
    rng_state ^= rng_state << 13; rng_state ^= rng_state >> 7; rng_state ^= rng_state << 17;
    return rng_state;
}
static gl_t rnd_gl(void) { return gl_reduce(rnd()); }

static void fill(pmat *m) { for (size_t i = 0; i < m->rows * m->cols; i++) m->d[i] = rnd_gl(); }

TEST_MAIN_BEGIN("l1 uac")
    CHECK_EQ_STATUS(gl_selftest(), CS_OK);

    /* edge values vs a __int128 reference */
    const gl_t edges[] = {0, 1, 2, 0xFFFFFFFFull, 0x100000000ull, 0x100000001ull,
                          GL_P - 2, GL_P - 1, GL_P / 2, GL_P / 2 + 1, 0xFFFFFFFE00000001ull};
    for (size_t i = 0; i < sizeof edges / sizeof edges[0]; i++)
        for (size_t j = 0; j < sizeof edges / sizeof edges[0]; j++) {
            gl_t a = edges[i], b = edges[j];
            CHECK(gl_mul(a, b) == (gl_t)(((u128)a * b) % GL_P));
            CHECK(gl_add(a, b) == (gl_t)(((u128)a + b) % GL_P));
            CHECK(gl_sub(a, b) == (gl_t)(((u128)a + GL_P - b) % GL_P));
        }
    /* random vs reference */
    int bad = 0;
    for (int i = 0; i < 200000; i++) {
        gl_t a = rnd_gl(), b = rnd_gl();
        if (gl_mul(a, b) != (gl_t)(((u128)a * b) % GL_P)) bad++;
        if (gl_add(a, b) != (gl_t)(((u128)a + b) % GL_P)) bad++;
        if (gl_sub(a, b) != (gl_t)(((u128)a + GL_P - b) % GL_P)) bad++;
        if (gl_add(a, gl_neg(a)) != 0) bad++;
    }
    CHECK(bad == 0);
    /* field axioms on random triples */
    bad = 0;
    for (int i = 0; i < 20000; i++) {
        gl_t a = rnd_gl(), b = rnd_gl(), c = rnd_gl();
        if (gl_mul(a, gl_add(b, c)) != gl_add(gl_mul(a, b), gl_mul(a, c))) bad++;   /* distributive */
        if (gl_mul(gl_mul(a, b), c) != gl_mul(a, gl_mul(b, c))) bad++;              /* associative */
        gl_t inv;
        if (a != 0 && (gl_inv(a, &inv) != CS_OK || gl_mul(a, inv) != 1)) bad++;
    }
    CHECK(bad == 0);
    gl_t q;
    CHECK_EQ_STATUS(gl_inv(0, &q), CS_ERR_SINGULAR);
    CHECK_EQ_STATUS(gl_div(5, 0, &q), CS_ERR_SINGULAR);
    CHECK_EQ_STATUS(gl_div(10, 2, &q), CS_OK);
    CHECK(q == 5);
    CHECK(gl_pow(3, 0) == 1 && gl_pow(0, 5) == 0 && gl_pow(GL_P - 1, 3) == GL_P - 1);

    /* matrices */
    pmat a, b, c, d, id;
    CHECK_EQ_STATUS(pmat_new(&a, 0, 3), CS_ERR_ARG);
    CHECK_EQ_STATUS(pmat_new(&a, (size_t)-1, 8), CS_ERR_NOMEM);
    CHECK_EQ_STATUS(pmat_new(&a, 3, 4), CS_OK);
    CHECK_EQ_STATUS(pmat_new(&b, 4, 2), CS_OK);
    fill(&a); fill(&b);
    CHECK_EQ_STATUS(pmat_mul(&a, &a, &c), CS_ERR_RANGE);        /* 3x4 * 3x4 */
    CHECK_EQ_STATUS(pmat_mul(&a, &b, &c), CS_OK);
    CHECK(c.rows == 3 && c.cols == 2);
    gl_t ref = 0;
    for (size_t k = 0; k < 4; k++) ref = gl_add(ref, gl_mul(pmat_get(&a, 1, k), pmat_get(&b, k, 1)));
    CHECK(pmat_get(&c, 1, 1) == ref);
    /* (AB)^T = B^T A^T */
    pmat abt, at, bt, btat;
    CHECK_EQ_STATUS(pmat_transpose(&c, &abt), CS_OK);
    CHECK_EQ_STATUS(pmat_transpose(&a, &at), CS_OK);
    CHECK_EQ_STATUS(pmat_transpose(&b, &bt), CS_OK);
    CHECK_EQ_STATUS(pmat_mul(&bt, &at, &btat), CS_OK);
    CHECK(pmat_equal(&abt, &btat));
    pmat_free(&abt); pmat_free(&at); pmat_free(&bt); pmat_free(&btat);
    /* add / sub / scale */
    pmat a2, s1, s2;
    CHECK_EQ_STATUS(pmat_add(&a, &a, &a2), CS_OK);
    CHECK_EQ_STATUS(pmat_scale(&a, 2, &s1), CS_OK);
    CHECK(pmat_equal(&a2, &s1));
    CHECK_EQ_STATUS(pmat_sub(&a2, &a, &s2), CS_OK);
    CHECK(pmat_equal(&s2, &a));
    CHECK_EQ_STATUS(pmat_add(&a, &b, &d), CS_ERR_RANGE);
    pmat_free(&a2); pmat_free(&s1); pmat_free(&s2);
    pmat_free(&a); pmat_free(&b); pmat_free(&c);

    /* inverse / determinant */
    int inv_bad = 0, det_bad = 0;
    for (int trial = 0; trial < 40; trial++) {
        size_t n = 1 + (size_t)(rnd() % 6);
        pmat m, mi, prod, m2, prod2;
        pmat_new(&m, n, n);
        fill(&m);
        gl_t det;
        CHECK_EQ_STATUS(pmat_det(&m, &det), CS_OK);
        if (pmat_inverse(&m, &mi) == CS_OK) {
            pmat_mul(&m, &mi, &prod);
            pmat_identity(&id, n);
            if (!pmat_equal(&prod, &id)) inv_bad++;
            pmat_mul(&mi, &m, &prod2);
            if (!pmat_equal(&prod2, &id)) inv_bad++;
            /* det(A) * det(A^-1) = 1 */
            gl_t det_i;
            pmat_det(&mi, &det_i);
            if (gl_mul(det, det_i) != 1) det_bad++;
            pmat_free(&mi); pmat_free(&prod); pmat_free(&prod2); pmat_free(&id);
        }
        /* det(A^T) = det(A) */
        pmat_transpose(&m, &m2);
        gl_t det_t;
        pmat_det(&m2, &det_t);
        if (det_t != det) det_bad++;
        pmat_free(&m); pmat_free(&m2);
    }
    CHECK(inv_bad == 0 && det_bad == 0);
    /* known 2x2: [[1,2],[3,4]] det = -2, inverse = [[-2,1],[3/2,-1/2]] */
    pmat k, ki;
    pmat_new(&k, 2, 2);
    pmat_set(&k, 0, 0, 1); pmat_set(&k, 0, 1, 2); pmat_set(&k, 1, 0, 3); pmat_set(&k, 1, 1, 4);
    gl_t kd;
    CHECK_EQ_STATUS(pmat_det(&k, &kd), CS_OK);
    CHECK(kd == gl_neg(2));
    CHECK_EQ_STATUS(pmat_inverse(&k, &ki), CS_OK);
    gl_t half;
    gl_inv(2, &half);
    CHECK(pmat_get(&ki, 0, 0) == gl_neg(2) && pmat_get(&ki, 0, 1) == 1);
    CHECK(pmat_get(&ki, 1, 0) == gl_mul(3, half) && pmat_get(&ki, 1, 1) == gl_neg(half));
    pmat_free(&ki);
    /* singular: second row = 2 * first row */
    pmat_set(&k, 1, 0, 2); pmat_set(&k, 1, 1, 4);
    CHECK_EQ_STATUS(pmat_inverse(&k, &ki), CS_ERR_SINGULAR);
    CHECK_EQ_STATUS(pmat_det(&k, &kd), CS_OK);
    CHECK(kd == 0);
    pmat_free(&k);
    pmat rect;
    pmat_new(&rect, 2, 3);
    CHECK_EQ_STATUS(pmat_inverse(&rect, &ki), CS_ERR_RANGE);
    pmat_free(&rect);

    /* tensors */
    size_t sh2[2] = {3, 4}, sh3[3] = {2, 3, 4};
    tensor t;
    CHECK_EQ_STATUS(tensor_new(&t, 0, sh2), CS_ERR_ARG);
    CHECK_EQ_STATUS(tensor_new(&t, CS_TENSOR_MAX_RANK + 1, sh3), CS_ERR_ARG);
    size_t zero_shape[2] = {3, 0};
    CHECK_EQ_STATUS(tensor_new(&t, 2, zero_shape), CS_ERR_ARG);
    CHECK_EQ_STATUS(tensor_new(&t, 3, sh3), CS_OK);
    size_t idx[3] = {1, 2, 3};
    CHECK_EQ_STATUS(tensor_set(&t, idx, GL_P + 5), CS_OK);       /* reduced on set */
    gl_t v;
    CHECK_EQ_STATUS(tensor_get(&t, idx, &v), CS_OK);
    CHECK(v == 5);
    CHECK(t.d[1 * 12 + 2 * 4 + 3] == 5);                         /* row-major layout */
    idx[1] = 3;
    CHECK_EQ_STATUS(tensor_get(&t, idx, &v), CS_ERR_RANGE);
    tensor_free(&t);

    /* contraction of rank-2 tensors == matrix multiplication */
    pmat ma, mb, mc, mc2;
    pmat_new(&ma, 3, 5); pmat_new(&mb, 5, 2);
    fill(&ma); fill(&mb);
    tensor ta, tb, tc;
    tensor_from_pmat(&ma, &ta);
    tensor_from_pmat(&mb, &tb);
    CHECK_EQ_STATUS(tensor_contract(&ta, 1, &tb, 0, &tc), CS_OK);
    CHECK_EQ_STATUS(tensor_to_pmat(&tc, &mc), CS_OK);
    CHECK_EQ_STATUS(pmat_mul(&ma, &mb, &mc2), CS_OK);
    CHECK(pmat_equal(&mc, &mc2));
    CHECK_EQ_STATUS(tensor_contract(&ta, 0, &tb, 0, &tc), CS_ERR_RANGE);   /* 3 != 5 */
    CHECK_EQ_STATUS(tensor_contract(&ta, 2, &tb, 0, &tc), CS_ERR_RANGE);   /* bad axis */
    tensor_free(&tc);
    /* contracting over a different axis pair = multiplication by a transpose */
    pmat mat_t;
    pmat_transpose(&mb, &mat_t);                                           /* 2x5 */
    tensor tbt;
    tensor_from_pmat(&mat_t, &tbt);
    CHECK_EQ_STATUS(tensor_contract(&ta, 1, &tbt, 1, &tc), CS_OK);
    pmat mc3;
    tensor_to_pmat(&tc, &mc3);
    CHECK(pmat_equal(&mc3, &mc2));
    pmat_free(&mc3); pmat_free(&mat_t); tensor_free(&tbt); tensor_free(&tc);

    /* outer product, hadamard, add */
    size_t len3[1] = {3}, len2[1] = {2};
    tensor x, y, o;
    tensor_new(&x, 1, len3); tensor_new(&y, 1, len2);
    for (size_t i = 0; i < 3; i++) x.d[i] = rnd_gl();
    for (size_t i = 0; i < 2; i++) y.d[i] = rnd_gl();
    CHECK_EQ_STATUS(tensor_outer(&x, &y, &o), CS_OK);
    CHECK(o.rank == 2 && o.shape[0] == 3 && o.shape[1] == 2);
    size_t oi[2] = {2, 1};
    tensor_get(&o, oi, &v);
    CHECK(v == gl_mul(x.d[2], y.d[1]));
    /* contracting an outer product with a vector recovers a scaled vector */
    tensor w, z;
    tensor_new(&w, 1, len2);
    w.d[0] = 1; w.d[1] = 0;
    CHECK_EQ_STATUS(tensor_contract(&o, 1, &w, 0, &z), CS_OK);
    CHECK(z.rank == 1 && z.d[0] == gl_mul(x.d[0], y.d[0]) && z.d[2] == gl_mul(x.d[2], y.d[0]));
    CHECK_EQ_STATUS(tensor_hadamard(&x, &y, &z), CS_ERR_RANGE);
    tensor x2, h;
    CHECK_EQ_STATUS(tensor_add(&x, &x, &x2), CS_OK);
    CHECK_EQ_STATUS(tensor_hadamard(&x, &x, &h), CS_OK);
    CHECK(x2.d[1] == gl_add(x.d[1], x.d[1]) && h.d[1] == gl_mul(x.d[1], x.d[1]));
    tensor big_a, big_b, big_o;
    size_t s22[2] = {1, 1}, s222[3] = {1, 1, 1};
    tensor_new(&big_a, 2, s22); tensor_new(&big_b, 3, s222);
    CHECK_EQ_STATUS(tensor_outer(&big_a, &big_b, &big_o), CS_ERR_RANGE);   /* rank 5 > max */
    tensor_free(&big_a); tensor_free(&big_b);
    tensor_free(&x); tensor_free(&y); tensor_free(&o); tensor_free(&w); tensor_free(&z);
    tensor_free(&x2); tensor_free(&h);
    tensor_free(&ta); tensor_free(&tb);
    pmat_free(&ma); pmat_free(&mb); pmat_free(&mc); pmat_free(&mc2);
TEST_MAIN_END
