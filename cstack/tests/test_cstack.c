/* Integration tests: a job goes through all ten layers, and each layer's refusal stops it. */
#include "cs_test.h"
#include "cs_sha256.h"
#include "cstack.h"
#include <stdio.h>
#include <string.h>

static uint64_t fake_now;
static uint64_t fake_clock(void *ctx) { (void)ctx; return fake_now; }

static int fixed_entropy(void *buf, size_t n)
{
    uint8_t *p = buf;
    for (size_t i = 0; i < n; i++) p[i] = (uint8_t)(i * 29u + 5u);
    return 0;
}
static int bad_entropy(void *buf, size_t n) { memset(buf, 0, n); return 0; }

/* UAC-backed work: C = A*B over F_p for n x n matrices derived from a seed; result digest = H(C). */
typedef struct { size_t n; uint64_t seed; int runs; } matmul_job;

static cs_status matmul_work(void *vctx, sigma_ctx *sg, uint8_t digest[32])
{
    matmul_job *j = vctx;
    j->runs++;
    size_t n = j->n;
    cs_status s = sigma_charge_mem(sg, 3 * n * n * sizeof(gl_t));
    if (s == CS_OK) s = sigma_charge_steps(sg, n * n * n);
    if (s != CS_OK) return s;
    pmat a, b, c;
    if (pmat_new(&a, n, n) != CS_OK) return CS_ERR_NOMEM;
    if (pmat_new(&b, n, n) != CS_OK) { pmat_free(&a); return CS_ERR_NOMEM; }
    uint64_t x = j->seed | 1;
    for (size_t i = 0; i < n * n; i++) {
        x ^= x << 13; x ^= x >> 7; x ^= x << 17; a.d[i] = gl_reduce(x);
        x ^= x << 13; x ^= x >> 7; x ^= x << 17; b.d[i] = gl_reduce(x);
    }
    s = pmat_mul(&a, &b, &c);
    if (s == CS_OK) { cs_sha256(c.d, n * n * sizeof(gl_t), digest); pmat_free(&c); }
    pmat_free(&a); pmat_free(&b);
    return s;
}

static cs_status failing_work(void *ctx, sigma_ctx *sg, uint8_t digest[32])
{
    (void)ctx; (void)sg; (void)digest;
    return CS_ERR_WORK;
}

static cstack_config base_config(void)
{
    cstack_config c;
    memset(&c, 0, sizeof c);
    c.entropy = fixed_entropy;
    c.mem_verify_bytes = 1 << 16;
    c.policy.allowed_kinds = (1u << 1) | (1u << 2);
    c.policy.max_payload = 128;
    c.limits.max_mem_bytes = 1 << 20;
    c.limits.max_steps = 100000;
    c.limits.max_ns = 1000000000ull;
    c.clock = fake_clock;
    return c;
}

static cstack_job mk(uint64_t id, uint32_t kind, const char *payload, matmul_job *w,
                     const char *const *req, size_t nreq)
{
    cstack_job j;
    memset(&j, 0, sizeof j);
    j.id = id; j.kind = kind;
    j.payload = payload; j.payload_len = strlen(payload);
    j.requires = req; j.nrequires = nreq;
    j.work = matmul_work; j.work_ctx = w;
    return j;
}

static const char *proven_claim[] = {"gl_mul_correct"};
static const char *sorry_claim[] = {"fa_bound"};

static void setup_claims(cstack *cs)
{
    const char *good = "theorem gl_mul_correct : True := trivial\n";
    const char *bad = "theorem fa_bound : True := by sorry\n";
    alp_attach_proof(&cs->alp, "gl_mul_correct", good, strlen(good));
    alp_attach_proof(&cs->alp, "fa_bound", bad, strlen(bad));
}

TEST_MAIN_BEGIN("cstack integration")
    cstack cs;
    cstack_config cfg = base_config();
    cstack_result r;
    matmul_job w = {.n = 4, .seed = 7};

    /* ---- boot failures stop the stack before anything exists ---- */
    cstack_config bad = cfg;
    bad.entropy = bad_entropy;
    CHECK_EQ_STATUS(cstack_init(&cs, &bad), CS_ERR_ENTROPY);
    cstack_job j0 = mk(1, 1, "x", &w, NULL, 0);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j0, &r), CS_ERR_STATE);
    CHECK(r.failed_layer == 0 && w.runs == 0);
    CHECK_EQ_STATUS(cstack_init(NULL, &cfg), CS_ERR_ARG);

    /* ---- happy path through all layers ---- */
    CHECK_EQ_STATUS(cstack_init(&cs, &cfg), CS_OK);
    setup_claims(&cs);
    CHECK(worm_count(&cs.worm) == 1);                                    /* seal_0 */
    memset(cs.boot.seed, 0, 0);                                          /* seed was wiped at init: */
    {
        uint8_t zero[32] = {0};
        CHECK(memcmp(cs.boot.seed, zero, 32) == 0);
    }

    cstack_job j1 = mk(100, 1, "matmul 4x4", &w, proven_claim, 1);
    fake_now = 1000;
    CHECK_EQ_STATUS(cstack_submit(&cs, &j1, &r), CS_OK);
    CHECK(r.failed_layer == -1 && r.sealed && w.runs == 1);
    CHECK(r.exec.steps == 1 + 64 && r.exec.mem_peak == 3 * 16 * sizeof(gl_t));
    CHECK(r.seal.index == 1 && worm_count(&cs.worm) == 2);
    CHECK_EQ_STATUS(wit_verify(&r.witness, cs.witness_key), CS_OK);
    CHECK(memcmp(r.witness.boot_id, cs.boot.boot_id, 32) == 0);
    CHECK(memcmp(r.seal.witness_digest, r.witness.digest, 32) == 0);
    CHECK_EQ_STATUS(cstack_verify(&cs), CS_OK);

    /* the result digest equals an independent computation with the UAC layer */
    {
        pmat a, b, c;
        pmat_new(&a, 4, 4); pmat_new(&b, 4, 4);
        uint64_t x = 7 | 1;
        for (size_t i = 0; i < 16; i++) {
            x ^= x << 13; x ^= x >> 7; x ^= x << 17; a.d[i] = gl_reduce(x);
            x ^= x << 13; x ^= x >> 7; x ^= x << 17; b.d[i] = gl_reduce(x);
        }
        pmat_mul(&a, &b, &c);
        uint8_t want[32];
        cs_sha256(c.d, 16 * sizeof(gl_t), want);
        CHECK(memcmp(r.exec.result_digest, want, 32) == 0);
        pmat_free(&a); pmat_free(&b); pmat_free(&c);
    }

    /* ---- L2: a claim with sorry (or no proof) refuses the job; the work never runs ---- */
    int runs = w.runs;
    cstack_job j2 = mk(101, 1, "needs fa_bound", &w, sorry_claim, 1);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j2, &r), CS_ERR_UNPROVEN);
    CHECK(r.failed_layer == 2 && !r.sealed && w.runs == runs && worm_count(&cs.worm) == 2);
    const char *missing[] = {"never_declared"};
    cstack_job j2b = mk(102, 1, "x", &w, missing, 1);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j2b, &r), CS_ERR_UNPROVEN);
    const char *both[] = {"gl_mul_correct", "fa_bound"};
    cstack_job j2c = mk(103, 1, "x", &w, both, 2);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j2c, &r), CS_ERR_UNPROVEN);       /* one bad claim is enough */
    CHECK(w.runs == runs);

    /* ---- L5: policy (kind / size) refuses at the Examiner ---- */
    cstack_job j5 = mk(104, 7, "kind 7 is not allowed", &w, NULL, 0);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j5, &r), CS_ERR_DENIED);
    CHECK(r.failed_layer == 5 && w.runs == runs);
    char big[200];
    memset(big, 'p', sizeof big - 1);
    big[sizeof big - 1] = '\0';
    cstack_job j5b = mk(105, 1, big, &w, NULL, 0);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j5b, &r), CS_ERR_DENIED);
    CHECK(r.failed_layer == 5);
    cstack_job j5c = mk(106, 40, "kind out of range", &w, NULL, 0);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j5c, &r), CS_ERR_ARG);
    CHECK(w.runs == runs && worm_count(&cs.worm) == 2);

    /* ---- L6/L7/L8: failing work and limit breaches are still witnessed and sealed ---- */
    cstack_job jf = mk(110, 1, "will fail", &w, NULL, 0);
    jf.work = failing_work;
    CHECK_EQ_STATUS(cstack_submit(&cs, &jf, &r), CS_ERR_WORK);
    CHECK(r.failed_layer == 6 && r.sealed && r.witness.exec_status == CS_ERR_WORK);
    CHECK(worm_count(&cs.worm) == 3);
    matmul_job huge = {.n = 100, .seed = 1};                              /* 1e6 steps > 1e5 limit */
    cstack_job jl = mk(111, 1, "too much", &huge, NULL, 0);
    CHECK_EQ_STATUS(cstack_submit(&cs, &jl, &r), CS_ERR_LIMIT);
    CHECK(r.sealed && r.witness.exec_status == CS_ERR_LIMIT && huge.runs == 1);
    CHECK(worm_count(&cs.worm) == 4);
    CHECK_EQ_STATUS(cstack_verify(&cs), CS_OK);

    /* ---- L4: a contradiction traps the stack; no job runs until the operator resets ---- */
    CHECK_EQ_STATUS(dis_add_implication(&cs.dis, "claims_ok", "ledger_ok"), CS_OK);
    CHECK_EQ_STATUS(dis_assert(&cs.dis, "claims_ok", 1), CS_OK);
    CHECK_EQ_STATUS(dis_assert(&cs.dis, "ledger_ok", 0), CS_ERR_CONTRADICTION);
    CHECK(dis_is_trapped(&cs.dis));
    runs = w.runs;
    cstack_job j4 = mk(120, 1, "after trap", &w, NULL, 0);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j4, &r), CS_ERR_TRAPPED);
    CHECK(r.failed_layer == 4 && w.runs == runs);
    CHECK_EQ_STATUS(cstack_reset_trap(&cs), CS_OK);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j4, &r), CS_OK);
    CHECK(w.runs == runs + 1);

    /* ---- L3: in-memory tampering with the policy is detected as drift and traps ---- */
    uint32_t saved_kinds = cs.gw.policy.allowed_kinds;
    cs.gw.policy.allowed_kinds = 0xFFFFFFFFu;                             /* attacker widens the policy */
    runs = w.runs;
    cstack_job j3 = mk(130, 9, "kind 9 would now pass the examiner", &w, NULL, 0);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j3, &r), CS_ERR_DRIFT);
    CHECK(r.failed_layer == 3 && w.runs == runs && dis_is_trapped(&cs.dis));
    CHECK_EQ_STATUS(cstack_reset_trap(&cs), CS_OK);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j3, &r), CS_ERR_DRIFT);           /* still drifted after reset */
    cs.gw.policy.allowed_kinds = saved_kinds;
    cstack_reset_trap(&cs);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j4, &r), CS_OK);                  /* restored: accepted again */
    /* payload larger than the memory budget */
    cstack_config tight = cfg;
    tight.limits.max_mem_bytes = 4;
    cstack cs_tight;
    CHECK_EQ_STATUS(cstack_init(&cs_tight, &tight), CS_OK);
    cstack_job jt = mk(1, 1, "longer than four bytes", &w, NULL, 0);
    CHECK_EQ_STATUS(cstack_submit(&cs_tight, &jt, &r), CS_ERR_LIMIT);
    CHECK(r.failed_layer == 3);
    cstack_shutdown(&cs_tight);

    /* ---- L8: tampering with the ledger is caught by the L4 invariant ---- */
    size_t before = worm_count(&cs.worm);
    cs.worm.seals[1].witness_digest[0] ^= 1;
    CHECK_EQ_STATUS(cstack_verify(&cs), CS_ERR_TAMPER);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j4, &r), CS_ERR_CONTRADICTION);
    CHECK(r.failed_layer == 4 && dis_is_trapped(&cs.dis) && worm_count(&cs.worm) == before);
    cs.worm.seals[1].witness_digest[0] ^= 1;
    cstack_reset_trap(&cs);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j4, &r), CS_OK);

    /* ---- L4 cross-layer invariant: the runtime cannot have consumed approvals never issued ---- */
    uint64_t saved_seq = cs.exec.last_seq;
    cs.exec.last_seq = cs.gw.next_seq + 5;
    CHECK_EQ_STATUS(cstack_submit(&cs, &j4, &r), CS_ERR_CONTRADICTION);
    CHECK(r.failed_layer == 4 && dis_is_trapped(&cs.dis));
    cs.exec.last_seq = saved_seq;
    cstack_reset_trap(&cs);
    CHECK_EQ_STATUS(cstack_submit(&cs, &j4, &r), CS_OK);

    /* ---- L9: metrics and audit reflect what happened ---- */
    obs_metric m;
    CHECK(obs_get(&cs.obs, "jobs_ok", &m) && m.value >= 4);
    CHECK(obs_get(&cs.obs, "refused_l2", &m) && m.value == 3);
    CHECK(obs_get(&cs.obs, "refused_l5", &m) && m.value == 3);
    CHECK(obs_get(&cs.obs, "refused_l3", &m) && m.value >= 2);
    CHECK(obs_get(&cs.obs, "jobs_work_failed", &m) && m.value == 2);
    CHECK(obs_get(&cs.obs, "traps_total", &m) && m.value >= 3);
    CHECK(obs_get(&cs.obs, "ledger_length", &m) && m.value == (int64_t)worm_count(&cs.worm));
    CHECK(obs_get(&cs.obs, "job_steps", &m) && m.count >= 4);
    CHECK_EQ_STATUS(obs_audit_verify(&cs.obs), CS_OK);
    CHECK_EQ_STATUS(cstack_verify(&cs), CS_OK);
    char alog[1 << 15];
    obs_export_audit(&cs.obs, alog, sizeof alog);
    CHECK(strstr(alog, "claim 'fa_bound' is not proven") != NULL);
    CHECK(strstr(alog, "operator reset of dissonance trap") != NULL);
    cstack_shutdown(&cs);

    /* ---- determinism: same entropy + same jobs => identical ledger heads ---- */
    uint8_t head[2][32];
    for (int run = 0; run < 2; run++) {
        cstack d;
        cstack_config dc = base_config();
        CHECK_EQ_STATUS(cstack_init(&d, &dc), CS_OK);
        setup_claims(&d);
        for (uint64_t id = 1; id <= 5; id++) {
            matmul_job mj = {.n = 3 + id, .seed = id * 77};
            cstack_job jj = mk(id, 1, "deterministic", &mj, proven_claim, 1);
            fake_now = 123456 + id * (uint64_t)run;                       /* wall time differs between runs */
            CHECK_EQ_STATUS(cstack_submit(&d, &jj, &r), CS_OK);
        }
        memcpy(head[run], worm_head(&d.worm)->seal, 32);
        cstack_shutdown(&d);
    }
    CHECK(memcmp(head[0], head[1], 32) == 0);
    {
        cstack d;
        cstack_config dc = base_config();
        dc.entropy = NULL;                                                /* real entropy: different boot id */
        CHECK_EQ_STATUS(cstack_init(&d, &dc), CS_OK);
        setup_claims(&d);
        matmul_job mj = {.n = 4, .seed = 77};
        cstack_job jj = mk(1, 1, "deterministic", &mj, proven_claim, 1);
        cstack_submit(&d, &jj, &r);
        CHECK(memcmp(worm_head(&d.worm)->seal, head[0], 32) != 0);
        cstack_shutdown(&d);
    }

    /* ---- persistence: the chain survives restart; file tampering refuses to start ---- */
    const char *path = "build/cstack_test.ledger";
    remove(path);
    cstack_config pc = base_config();
    pc.ledger_path = path;
    {
        cstack p;
        CHECK_EQ_STATUS(cstack_init(&p, &pc), CS_OK);
        setup_claims(&p);
        cstack_job jp = mk(1, 1, "persist", &w, proven_claim, 1);
        CHECK_EQ_STATUS(cstack_submit(&p, &jp, &r), CS_OK);
        CHECK_EQ_STATUS(cstack_submit(&p, &jp, &r), CS_OK);                /* same job again: fresh approval */
        cstack_shutdown(&p);
    }
    {
        cstack p;
        CHECK_EQ_STATUS(cstack_init(&p, &pc), CS_OK);
        CHECK(worm_count(&p.worm) == 3);                                   /* genesis + 2 jobs from before */
        setup_claims(&p);
        cstack_job jp = mk(2, 1, "persist", &w, proven_claim, 1);
        CHECK_EQ_STATUS(cstack_submit(&p, &jp, &r), CS_OK);
        CHECK(r.seal.index == 3);
        CHECK_EQ_STATUS(cstack_verify(&p), CS_OK);
        cstack_shutdown(&p);
    }
    {
        FILE *f = fopen(path, "r+b");
        CHECK(f != NULL);
        if (f) { fseek(f, 5, SEEK_SET); fputc('Z', f); fclose(f); }
        cstack p;
        CHECK_EQ_STATUS(cstack_init(&p, &pc), CS_ERR_TAMPER);
        CHECK(!p.initialized);
    }
    remove(path);

    /* ---- Sigma drift detector watching steps per job ---- */
    {
        cstack d;
        cstack_config dc = base_config();
        dc.drift_enabled = 1;
        dc.drift_baseline_steps = 65;
        dc.drift_tolerance = 20;
        dc.drift_shift = 1;
        CHECK_EQ_STATUS(cstack_init(&d, &dc), CS_OK);
        matmul_job small = {.n = 4, .seed = 3};                           /* 65 steps: on baseline */
        cstack_job js = mk(1, 1, "steady", &small, NULL, 0);
        for (int i = 0; i < 5; i++) CHECK_EQ_STATUS(cstack_submit(&d, &js, &r), CS_OK);
        matmul_job larger = {.n = 10, .seed = 3};                         /* 1001 steps: far off baseline */
        cstack_job jb = mk(2, 1, "drifting", &larger, NULL, 0);
        CHECK_EQ_STATUS(cstack_submit(&d, &jb, &r), CS_OK);               /* the job itself completes... */
        CHECK(dis_is_trapped(&d.dis));                                    /* ...and the drift traps the stack */
        CHECK_EQ_STATUS(cstack_submit(&d, &js, &r), CS_ERR_DRIFT);        /* drift stays latched */
        CHECK(r.failed_layer == 3);
        cstack_reset_trap(&d);
        CHECK_EQ_STATUS(cstack_submit(&d, &js, &r), CS_ERR_DRIFT);
        cstack_shutdown(&d);
    }

    /* argument checks */
    CHECK_EQ_STATUS(cstack_submit(&cs, &j4, &r), CS_ERR_STATE);           /* after shutdown */
    CHECK_EQ_STATUS(cstack_submit(NULL, &j4, &r), CS_ERR_ARG);
    CHECK_EQ_STATUS(cstack_verify(NULL), CS_ERR_ARG);
TEST_MAIN_END
