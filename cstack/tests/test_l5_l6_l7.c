#include "cs_test.h"
#include "cs_sha256.h"
#include "l5_gateway.h"
#include "l6_exec.h"
#include "l7_witness.h"
#include <stddef.h>
#include <string.h>

static uint64_t fake_now;
static uint64_t fake_clock(void *ctx) { (void)ctx; return fake_now; }

static int work_runs;
static cs_status work_ok(void *ctx, sigma_ctx *s, uint8_t digest[32])
{
    work_runs++;
    cs_status st = sigma_charge_steps(s, 10);
    if (st == CS_OK) st = sigma_charge_mem(s, 64);
    if (st != CS_OK) return st;
    cs_sha256(ctx, strlen(ctx), digest);
    return CS_OK;
}
static cs_status work_fails(void *ctx, sigma_ctx *s, uint8_t digest[32])
{
    (void)ctx; (void)s;
    memset(digest, 0xee, 32);
    return CS_ERR_WORK;
}
static cs_status work_hog(void *ctx, sigma_ctx *s, uint8_t digest[32])
{
    (void)ctx; (void)digest;
    return sigma_charge_steps(s, 1000000);
}
static cs_status work_slow(void *ctx, sigma_ctx *s, uint8_t digest[32])
{
    (void)ctx; (void)s; (void)digest;
    fake_now += 1000000;                      /* "takes" 1 ms but ignores the check itself */
    return CS_OK;
}

static const gw_health healthy = {1, 1, 1, 1};

TEST_MAIN_BEGIN("l5 l6 l7")
    uint8_t root[32];
    for (int i = 0; i < 32; i++) root[i] = (uint8_t)(i * 7 + 3);
    gw_policy pol = {.allowed_kinds = (1u << 1) | (1u << 5), .max_payload = 64};
    gateway g;
    CHECK_EQ_STATUS(gw_init(&g, root, &pol), CS_OK);

    const char *payload = "multiply matrices";
    gw_request req;
    CHECK_EQ_STATUS(gw_request_init(&req, 42, 1, payload, strlen(payload)), CS_OK);
    CHECK_EQ_STATUS(gw_request_init(&req, 42, 32, payload, 1), CS_ERR_ARG);      /* kind out of range */
    CHECK_EQ_STATUS(gw_request_init(&req, 42, 1, NULL, 3), CS_ERR_ARG);
    gw_request req2;
    gw_request_init(&req, 42, 1, payload, strlen(payload));
    gw_request_init(&req2, 43, 1, payload, strlen(payload));
    CHECK(memcmp(req.digest, req2.digest, 32) != 0);                               /* id is bound */
    gw_request_init(&req2, 42, 5, payload, strlen(payload));
    CHECK(memcmp(req.digest, req2.digest, 32) != 0);                               /* kind is bound */
    gw_request_init(&req2, 42, 1, "multiply matrices!", 18);
    CHECK(memcmp(req.digest, req2.digest, 32) != 0);                               /* payload is bound */
    gw_request_init(&req2, 42, 1, payload, strlen(payload));
    CHECK(memcmp(req.digest, req2.digest, 32) == 0);                               /* deterministic */

    /* three locks in order */
    gw_token gt, et;
    gw_approval ap;
    CHECK_EQ_STATUS(gw_guardian(&g, &req, &healthy, &gt), CS_OK);
    CHECK_EQ_STATUS(gw_examiner(&g, &req, &gt, &et), CS_OK);
    CHECK_EQ_STATUS(gw_publisher(&g, &req, &gt, &et, &ap), CS_OK);
    CHECK(ap.seq == 1);
    CHECK_EQ_STATUS(gw_verify_approval(&g, &req, &ap), CS_OK);

    /* Guardian: any unhealthy layer denies */
    gw_health bad;
    for (int i = 0; i < 4; i++) {
        bad = healthy;
        int *f[4] = {&bad.boot_ok, &bad.alp_ok, &bad.sigma_ok, &bad.dissonance_clear};
        *f[i] = 0;
        CHECK_EQ_STATUS(gw_guardian(&g, &req, &bad, &gt), CS_ERR_DENIED);
    }
    /* Examiner: forged / missing guardian token */
    gw_token forged;
    memset(&forged, 0x11, sizeof forged);
    CHECK_EQ_STATUS(gw_examiner(&g, &req, &forged, &et), CS_ERR_DENIED);
    gw_guardian(&g, &req, &healthy, &gt);
    /* Examiner: a guardian token for another request does not carry over */
    gw_token gt_other;
    gw_guardian(&g, &req2, &healthy, &gt_other);                                   /* req2 == req content */
    gw_request req3;
    gw_request_init(&req3, 99, 1, payload, strlen(payload));
    CHECK_EQ_STATUS(gw_examiner(&g, &req3, &gt, &et), CS_ERR_DENIED);
    /* Examiner policy: kind and size */
    gw_request bad_kind, too_big;
    gw_request_init(&bad_kind, 1, 2, "x", 1);
    gw_guardian(&g, &bad_kind, &healthy, &gt);
    CHECK_EQ_STATUS(gw_examiner(&g, &bad_kind, &gt, &et), CS_ERR_DENIED);
    char big[65];
    memset(big, 'a', sizeof big);
    gw_request_init(&too_big, 2, 1, big, sizeof big);
    gw_guardian(&g, &too_big, &healthy, &gt);
    CHECK_EQ_STATUS(gw_examiner(&g, &too_big, &gt, &et), CS_ERR_DENIED);
    /* Examiner: payload mutated after the digest was bound */
    char mutable_payload[] = "do the thing";
    gw_request tampered;
    gw_request_init(&tampered, 7, 1, mutable_payload, strlen(mutable_payload));
    gw_guardian(&g, &tampered, &healthy, &gt);
    mutable_payload[3] = 'X';
    CHECK_EQ_STATUS(gw_examiner(&g, &tampered, &gt, &et), CS_ERR_DENIED);
    /* Publisher: cannot be reached by skipping the Examiner or forging its token */
    gw_request ok2;
    gw_request_init(&ok2, 8, 1, "ok", 2);
    gw_guardian(&g, &ok2, &healthy, &gt);
    gw_approval ap2;
    CHECK_EQ_STATUS(gw_publisher(&g, &ok2, &gt, &forged, &ap2), CS_ERR_DENIED);
    CHECK_EQ_STATUS(gw_publisher(&g, &ok2, &forged, &forged, &ap2), CS_ERR_DENIED);
    CHECK_EQ_STATUS(gw_publisher(&g, &ok2, &gt, &gt, &ap2), CS_ERR_DENIED);       /* guardian token is not an examiner token */
    CHECK(g.next_seq == 2);                                                        /* nothing was issued */
    /* convenience path = same locks */
    CHECK_EQ_STATUS(gw_approve(&g, &ok2, &healthy, &ap2), CS_OK);
    CHECK(ap2.seq == 2);
    bad = healthy; bad.alp_ok = 0;
    CHECK_EQ_STATUS(gw_approve(&g, &ok2, &bad, &ap2), CS_ERR_DENIED);
    CHECK(g.next_seq == 3);

    /* approval verification */
    gw_approval forged_ap = ap;
    forged_ap.seq = 99;
    CHECK_EQ_STATUS(gw_verify_approval(&g, &req, &forged_ap), CS_ERR_DENIED);     /* seq is MACed */
    CHECK_EQ_STATUS(gw_verify_approval(&g, &ok2, &ap), CS_ERR_DENIED);            /* wrong request */
    forged_ap = ap;
    forged_ap.mac[0] ^= 1;
    CHECK_EQ_STATUS(gw_verify_approval(&g, &req, &forged_ap), CS_ERR_DENIED);
    gateway other;
    uint8_t root2[32];
    memset(root2, 9, 32);
    gw_init(&other, root2, &pol);
    CHECK_EQ_STATUS(gw_verify_approval(&other, &req, &ap), CS_ERR_DENIED);        /* different boot key */

    /* ---- layer 6: execution ---- */
    exec_rt rt;
    exec_init(&rt);
    sigma_limits lim = {.max_mem_bytes = 1024, .max_steps = 100, .max_ns = 1000000};
    exec_result res;

    gw_init(&g, root, &pol);                       /* fresh sequence */
    gw_request job;
    char jp[] = "job-A";
    gw_request_init(&job, 1, 1, jp, strlen(jp));
    gw_approval a1;
    CHECK_EQ_STATUS(gw_approve(&g, &job, &healthy, &a1), CS_OK);
    char wctx[] = "result-A";
    CHECK_EQ_STATUS(exec_run(&rt, &g, &job, &a1, work_ok, wctx, &lim, fake_clock, NULL, &res), CS_OK);
    CHECK(work_runs == 1 && res.status == CS_OK);
    CHECK(res.steps == 11 && res.mem_peak == 64);                                  /* 1 dispatch + 10 */
    uint8_t want[32];
    cs_sha256("result-A", 8, want);
    CHECK(memcmp(res.result_digest, want, 32) == 0);

    /* replay, wrong request, forged approval: work never runs again */
    CHECK_EQ_STATUS(exec_run(&rt, &g, &job, &a1, work_ok, wctx, &lim, fake_clock, NULL, &res), CS_ERR_REPLAY);
    gw_request other_job;
    gw_request_init(&other_job, 2, 1, "job-B", 5);
    gw_approval a2;
    gw_approve(&g, &other_job, &healthy, &a2);
    CHECK_EQ_STATUS(exec_run(&rt, &g, &job, &a2, work_ok, wctx, &lim, fake_clock, NULL, &res), CS_ERR_DENIED);
    gw_approval fake = a2;
    fake.mac[5] ^= 0x80;
    CHECK_EQ_STATUS(exec_run(&rt, &g, &other_job, &fake, work_ok, wctx, &lim, fake_clock, NULL, &res), CS_ERR_DENIED);
    CHECK(work_runs == 1);
    CHECK_EQ_STATUS(exec_run(&rt, &g, &other_job, &a2, work_ok, wctx, &lim, fake_clock, NULL, &res), CS_OK);
    CHECK(work_runs == 2);

    /* out-of-order approvals: seq 3 consumed first makes seq 4... fine, but an older one is refused */
    gw_request j3, j4;
    gw_request_init(&j3, 3, 1, "j3", 2);
    gw_request_init(&j4, 4, 1, "j4", 2);
    gw_approval a3, a4;
    gw_approve(&g, &j3, &healthy, &a3);
    gw_approve(&g, &j4, &healthy, &a4);
    CHECK_EQ_STATUS(exec_run(&rt, &g, &j4, &a4, work_ok, wctx, &lim, fake_clock, NULL, &res), CS_OK);
    CHECK_EQ_STATUS(exec_run(&rt, &g, &j3, &a3, work_ok, wctx, &lim, fake_clock, NULL, &res), CS_ERR_REPLAY);

    /* failing work: approval consumed, outcome reported, digest zeroed */
    gw_request jf;
    gw_request_init(&jf, 5, 1, "jf", 2);
    gw_approval af;
    gw_approve(&g, &jf, &healthy, &af);
    CHECK_EQ_STATUS(exec_run(&rt, &g, &jf, &af, work_fails, NULL, &lim, fake_clock, NULL, &res), CS_ERR_WORK);
    CHECK(res.status == CS_ERR_WORK);
    uint8_t zero[32] = {0};
    CHECK(memcmp(res.result_digest, zero, 32) == 0);
    CHECK_EQ_STATUS(exec_run(&rt, &g, &jf, &af, work_fails, NULL, &lim, fake_clock, NULL, &res), CS_ERR_REPLAY);

    /* resource limits stop the work */
    gw_request jh;
    gw_request_init(&jh, 6, 1, "jh", 2);
    gw_approval ah;
    gw_approve(&g, &jh, &healthy, &ah);
    CHECK_EQ_STATUS(exec_run(&rt, &g, &jh, &ah, work_hog, NULL, &lim, fake_clock, NULL, &res), CS_ERR_LIMIT);
    CHECK(res.status == CS_ERR_LIMIT);
    /* wall-time limit is enforced even if the work never checks */
    gw_request js;
    gw_request_init(&js, 7, 1, "js", 2);
    gw_approval as;
    gw_approve(&g, &js, &healthy, &as);
    fake_now = 0;
    CHECK_EQ_STATUS(exec_run(&rt, &g, &js, &as, work_slow, NULL, &lim, fake_clock, NULL, &res), CS_OK);
    gw_request js2;
    gw_request_init(&js2, 8, 1, "js2", 3);
    gw_approve(&g, &js2, &healthy, &as);
    sigma_limits tight = {1024, 100, 500000};
    CHECK_EQ_STATUS(exec_run(&rt, &g, &js2, &as, work_slow, NULL, &tight, fake_clock, NULL, &res), CS_ERR_LIMIT);
    CHECK_EQ_STATUS(exec_run(NULL, &g, &js2, &as, work_ok, NULL, &lim, NULL, NULL, &res), CS_ERR_ARG);

    /* ---- layer 7: witness ---- */
    uint8_t wkey[32], boot[32];
    memset(wkey, 0x5a, 32);
    memset(boot, 0xb0, 32);
    gw_init(&g, root, &pol);
    exec_init(&rt);
    gw_request_init(&job, 11, 1, jp, strlen(jp));
    gw_approve(&g, &job, &healthy, &a1);
    exec_run(&rt, &g, &job, &a1, work_ok, wctx, &lim, fake_clock, NULL, &res);
    wit_record w;
    CHECK_EQ_STATUS(wit_seal(&w, wkey, boot, &job, &a1, &res), CS_OK);
    CHECK(w.seq == 1 && w.request_id == 11 && w.steps == 11 && w.exec_status == CS_OK);
    CHECK_EQ_STATUS(wit_verify(&w, wkey), CS_OK);
    wit_record w2;
    wit_seal(&w2, wkey, boot, &job, &a1, &res);
    CHECK(memcmp(&w, &w2, sizeof w) == 0);                                         /* deterministic */

    uint8_t other_key[32];
    memset(other_key, 0x5b, 32);
    CHECK_EQ_STATUS(wit_verify(&w, other_key), CS_ERR_TAMPER);                     /* wrong key */
    /* flipping any single field breaks verification */
    wit_record t;
    int detected = 0, total = 0;
    for (size_t i = 0; i < offsetof(wit_record, digest); i++) {                 /* every field covered by the digest */
        t = w;
        ((uint8_t *)&t)[i] ^= 1;
        total++;
        if (wit_verify(&t, wkey) == CS_ERR_TAMPER) detected++;
    }
    CHECK(detected == total);
    t = w; t.digest[0] ^= 1;
    CHECK_EQ_STATUS(wit_verify(&t, wkey), CS_ERR_TAMPER);
    t = w; t.sig[31] ^= 1;
    CHECK_EQ_STATUS(wit_verify(&t, wkey), CS_ERR_TAMPER);
    /* a re-computed digest alone is not enough without the key */
    t = w; t.steps = 5;
    CHECK_EQ_STATUS(wit_verify(&t, wkey), CS_ERR_TAMPER);
    CHECK_EQ_STATUS(wit_seal(&w, wkey, boot, &req2, &a1, &res), CS_ERR_ARG);       /* approval is for another request */
TEST_MAIN_END
