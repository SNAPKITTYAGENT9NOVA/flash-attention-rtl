#include "l7_witness.h"

#include <string.h>

#include "cs_sha256.h"

static void compute_digest(const wit_record *w, uint8_t out[32])
{
    cs_sha256_ctx c;
    cs_sha256_init(&c);
    cs_sha256_update(&c, "cstack-witness-v1", 17);
    cs_sha256_update_u64(&c, w->seq);
    cs_sha256_update_u64(&c, w->request_id);
    cs_sha256_update(&c, w->boot_id, 32);
    cs_sha256_update(&c, w->request_digest, 32);
    cs_sha256_update(&c, w->approval_mac, 32);
    cs_sha256_update(&c, w->result_digest, 32);
    cs_sha256_update_u64(&c, w->steps);
    cs_sha256_update_u64(&c, w->mem_peak);
    cs_sha256_update_u64(&c, w->exec_status);
    cs_sha256_final(&c, out);
}

cs_status wit_seal(wit_record *w, const uint8_t key[32], const uint8_t boot_id[32],
                   const gw_request *req, const gw_approval *appr, const exec_result *res)
{
    if (!w || !key || !boot_id || !req || !appr || !res) return CS_ERR_ARG;
    if (!cs_ct_equal(req->digest, appr->request_digest, 32)) return CS_ERR_ARG;
    memset(w, 0, sizeof *w);
    w->seq = appr->seq;
    w->request_id = req->id;
    memcpy(w->boot_id, boot_id, 32);
    memcpy(w->request_digest, req->digest, 32);
    memcpy(w->approval_mac, appr->mac, 32);
    memcpy(w->result_digest, res->result_digest, 32);
    w->steps = res->steps;
    w->mem_peak = res->mem_peak;
    w->exec_status = (uint32_t)res->status;
    compute_digest(w, w->digest);
    cs_hmac_sha256(key, 32, w->digest, 32, w->sig);
    return CS_OK;
}

cs_status wit_verify(const wit_record *w, const uint8_t key[32])
{
    if (!w || !key) return CS_ERR_ARG;
    uint8_t d[32], sig[32];
    compute_digest(w, d);
    cs_hmac_sha256(key, 32, w->digest, 32, sig);
    int ok = cs_ct_equal(d, w->digest, 32) & cs_ct_equal(sig, w->sig, 32);
    return ok ? CS_OK : CS_ERR_TAMPER;
}
