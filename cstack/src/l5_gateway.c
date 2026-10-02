#include "l5_gateway.h"

#include <string.h>

#include "cs_sha256.h"

cs_status gw_request_init(gw_request *r, uint64_t id, uint32_t kind, const void *payload, size_t len)
{
    if (!r || (!payload && len) || kind > 31) return CS_ERR_ARG;
    r->id = id;
    r->kind = kind;
    r->payload = payload;
    r->len = len;
    cs_sha256_ctx c;
    cs_sha256_init(&c);
    cs_sha256_update(&c, "cstack-req-v1", 13);
    cs_sha256_update_u64(&c, id);
    cs_sha256_update_u64(&c, kind);
    cs_sha256_update_u64(&c, len);
    if (len) cs_sha256_update(&c, payload, len);
    cs_sha256_final(&c, r->digest);
    return CS_OK;
}

static void derive(const uint8_t root[32], const char *label, uint8_t out[32])
{
    cs_hmac_sha256(root, 32, label, strlen(label), out);
}

cs_status gw_init(gateway *g, const uint8_t root_key[32], const gw_policy *policy)
{
    if (!g || !root_key || !policy) return CS_ERR_ARG;
    derive(root_key, "cstack-gw-guardian", g->k_guardian);
    derive(root_key, "cstack-gw-examiner", g->k_examiner);
    derive(root_key, "cstack-gw-publisher", g->k_publisher);
    g->policy = *policy;
    g->next_seq = 1;
    return CS_OK;
}

static void mac2(const uint8_t key[32], const void *a, size_t alen, const void *b, size_t blen,
                 uint8_t out[32])
{
    uint8_t buf[128];
    memcpy(buf, a, alen);
    memcpy(buf + alen, b, blen);
    cs_hmac_sha256(key, 32, buf, alen + blen, out);
}

static void guardian_mac(const gateway *g, const gw_request *r, uint8_t out[32])
{
    mac2(g->k_guardian, "G", 1, r->digest, GW_DIGEST_LEN, out);
}

static void examiner_mac(const gateway *g, const gw_request *r, const gw_token *gt, uint8_t out[32])
{
    uint8_t in[GW_DIGEST_LEN * 2];
    memcpy(in, r->digest, GW_DIGEST_LEN);
    memcpy(in + GW_DIGEST_LEN, gt->mac, GW_DIGEST_LEN);
    mac2(g->k_examiner, "E", 1, in, sizeof in, out);
}

static void publisher_mac(const gateway *g, const uint8_t digest[32], uint64_t seq, uint8_t out[32])
{
    uint8_t in[GW_DIGEST_LEN + 8];
    memcpy(in, digest, GW_DIGEST_LEN);
    for (int i = 0; i < 8; i++) in[GW_DIGEST_LEN + i] = (uint8_t)(seq >> (56 - 8 * i));
    mac2(g->k_publisher, "P", 1, in, sizeof in, out);
}

cs_status gw_guardian(const gateway *g, const gw_request *r, const gw_health *h, gw_token *out)
{
    if (!g || !r || !h || !out) return CS_ERR_ARG;
    if (!h->boot_ok || !h->alp_ok || !h->sigma_ok || !h->dissonance_clear) return CS_ERR_DENIED;
    guardian_mac(g, r, out->mac);
    return CS_OK;
}

cs_status gw_examiner(const gateway *g, const gw_request *r, const gw_token *guardian, gw_token *out)
{
    if (!g || !r || !guardian || !out) return CS_ERR_ARG;
    uint8_t expect[32];
    guardian_mac(g, r, expect);
    if (!cs_ct_equal(expect, guardian->mac, 32)) return CS_ERR_DENIED;   /* did not pass the Guardian */

    /* independent re-derivation: the payload must still match the digest it was bound to */
    gw_request fresh;
    if (gw_request_init(&fresh, r->id, r->kind, r->payload, r->len) != CS_OK) return CS_ERR_DENIED;
    if (!cs_ct_equal(fresh.digest, r->digest, 32)) return CS_ERR_DENIED;

    if (!(g->policy.allowed_kinds & (1u << r->kind))) return CS_ERR_DENIED;
    if (r->len > g->policy.max_payload) return CS_ERR_DENIED;
    examiner_mac(g, r, guardian, out->mac);
    return CS_OK;
}

cs_status gw_publisher(gateway *g, const gw_request *r, const gw_token *guardian,
                       const gw_token *examiner, gw_approval *out)
{
    if (!g || !r || !guardian || !examiner || !out) return CS_ERR_ARG;
    uint8_t expect[32];
    guardian_mac(g, r, expect);
    if (!cs_ct_equal(expect, guardian->mac, 32)) return CS_ERR_DENIED;
    examiner_mac(g, r, guardian, expect);
    if (!cs_ct_equal(expect, examiner->mac, 32)) return CS_ERR_DENIED;   /* did not pass the Examiner */
    if (g->next_seq == UINT64_MAX) return CS_ERR_STATE;
    memcpy(out->request_digest, r->digest, GW_DIGEST_LEN);
    out->seq = g->next_seq++;
    publisher_mac(g, out->request_digest, out->seq, out->mac);
    return CS_OK;
}

cs_status gw_approve(gateway *g, const gw_request *r, const gw_health *h, gw_approval *out)
{
    gw_token gt, et;
    cs_status s = gw_guardian(g, r, h, &gt);
    if (s != CS_OK) return s;
    s = gw_examiner(g, r, &gt, &et);
    if (s != CS_OK) return s;
    return gw_publisher(g, r, &gt, &et, out);
}

cs_status gw_verify_approval(const gateway *g, const gw_request *r, const gw_approval *a)
{
    if (!g || !r || !a) return CS_ERR_ARG;
    if (!cs_ct_equal(a->request_digest, r->digest, GW_DIGEST_LEN)) return CS_ERR_DENIED;
    uint8_t expect[32];
    publisher_mac(g, a->request_digest, a->seq, expect);
    return cs_ct_equal(expect, a->mac, 32) ? CS_OK : CS_ERR_DENIED;
}
