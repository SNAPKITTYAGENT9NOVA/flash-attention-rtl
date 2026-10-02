#include "cstack.h"

#include <stdio.h>
#include <string.h>

#include "cs_sha256.h"

#define DEFAULT_MEM_VERIFY (1u << 20)

static void wipe(void *p, size_t n)
{
    volatile uint8_t *v = p;
    while (n--) *v++ = 0;
}

/* digest of everything the layers rely on staying constant */
static void config_digest(const cstack *cs, uint8_t out[32])
{
    cs_sha256_ctx c;
    cs_sha256_init(&c);
    cs_sha256_update(&c, "cstack-config-v1", 16);
    cs_sha256_update_u64(&c, cs->gw.policy.allowed_kinds);
    cs_sha256_update_u64(&c, cs->gw.policy.max_payload);
    cs_sha256_update_u64(&c, cs->cfg.limits.max_mem_bytes);
    cs_sha256_update_u64(&c, cs->cfg.limits.max_steps);
    cs_sha256_update_u64(&c, cs->cfg.limits.max_ns);
    cs_sha256_final(&c, out);
}

static int inv_ledger(void *ctx) { return worm_verify(&((cstack *)ctx)->worm) == CS_OK; }
static int inv_audit(void *ctx)  { return obs_audit_verify(&((cstack *)ctx)->obs) == CS_OK; }
/* cross-layer: the runtime can never have consumed an approval the gateway has not issued */
static int inv_sequence(void *ctx)
{
    const cstack *cs = ctx;
    return cs->exec.last_seq < cs->gw.next_seq;
}

static void on_trap(const dis_violation *v, void *ctx)
{
    cstack *cs = ctx;
    obs_counter_add(&cs->obs, "traps_total", 1);
    obs_audit(&cs->obs, 4, v->code, v->msg);
}

cs_status cstack_init(cstack *cs, const cstack_config *cfg)
{
    if (!cs || !cfg) return CS_ERR_ARG;
    memset(cs, 0, sizeof *cs);
    cs->cfg = *cfg;
    obs_init(&cs->obs, cfg->clock, cfg->clock_ctx);

    /* Layer 0 */
    size_t mem = cfg->mem_verify_bytes ? cfg->mem_verify_bytes : DEFAULT_MEM_VERIFY;
    cs_status s = cs_boot_run(&cs->boot, cfg->entropy, mem);
    if (s != CS_OK) { obs_audit(&cs->obs, 0, s, "boot failed"); return s; }
    obs_audit(&cs->obs, 0, CS_OK, "boot ok");

    /* Layer 1: the field must satisfy its known answers before anything is built on it */
    s = gl_selftest();
    if (s != CS_OK) { obs_audit(&cs->obs, 1, s, "uac self-test failed"); return s; }

    /* keys come from the health-tested seed, which is then wiped */
    cs_hmac_sha256(cs->boot.seed, sizeof cs->boot.seed, "cstack-witness", 14, cs->witness_key);
    s = gw_init(&cs->gw, cs->boot.seed, &cfg->policy);
    wipe(cs->boot.seed, sizeof cs->boot.seed);
    if (s != CS_OK) return s;

    alp_init(&cs->alp);
    exec_init(&cs->exec);

    if (cfg->drift_enabled) {
        s = sigma_drift_init(&cs->drift, cfg->drift_baseline_steps, cfg->drift_tolerance, cfg->drift_shift);
        if (s != CS_OK) return s;
    }
    config_digest(cs, cs->config_digest);

    /* Layer 8 first, because the dissonance invariants watch the ledger */
    s = worm_open(&cs->worm, cfg->ledger_path);
    if (s != CS_OK) { obs_audit(&cs->obs, 8, s, "ledger open failed"); return s; }

    /* Layer 4 */
    dis_init(&cs->dis);
    dis_set_trap_handler(&cs->dis, on_trap, cs);
    dis_add_invariant(&cs->dis, "ledger-chain-valid", inv_ledger, cs);
    dis_add_invariant(&cs->dis, "audit-chain-valid", inv_audit, cs);
    dis_add_invariant(&cs->dis, "approvals-consumed<=issued", inv_sequence, cs);

    char msg[OBS_MSG_MAX];
    snprintf(msg, sizeof msg, "stack ready, ledger length %zu", worm_count(&cs->worm));
    obs_audit(&cs->obs, 9, CS_OK, msg);
    obs_gauge_set(&cs->obs, "ledger_length", (int64_t)worm_count(&cs->worm));
    cs->initialized = 1;
    return CS_OK;
}

static cs_status refuse(cstack *cs, cstack_result *out, int layer, cs_status st, const char *msg)
{
    char name[32];
    snprintf(name, sizeof name, "refused_l%d", layer);
    obs_counter_add(&cs->obs, name, 1);
    obs_audit(&cs->obs, layer, st, msg);
    out->status = st;
    out->failed_layer = layer;
    return st;
}

cs_status cstack_submit(cstack *cs, const cstack_job *job, cstack_result *out)
{
    if (!cs || !job || !out || !job->work) return CS_ERR_ARG;
    memset(out, 0, sizeof *out);
    out->failed_layer = -1;
    if (!cs->initialized) { out->status = CS_ERR_STATE; out->failed_layer = 0; return CS_ERR_STATE; }
    obs_counter_add(&cs->obs, "jobs_submitted", 1);
    char msg[OBS_MSG_MAX];

    /* L0: the boot report must still say ok */
    if (cs->boot.status != CS_OK) return refuse(cs, out, 0, CS_ERR_BOOT, "boot report not ok");

    /* L1: the substrate re-proves its known answers before each job */
    if (gl_selftest() != CS_OK) {
        dis_trap(&cs->dis, CS_ERR_BOOT, "uac self-test failed");
        return refuse(cs, out, 1, CS_ERR_BOOT, "uac self-test failed");
    }

    /* L2: every claim the job relies on must be proven (no sorry) */
    for (size_t i = 0; i < job->nrequires; i++) {
        if (alp_require(&cs->alp, job->requires[i]) != CS_OK) {
            snprintf(msg, sizeof msg, "job %llu: claim '%.40s' is not proven",
                     (unsigned long long)job->id, job->requires[i]);
            return refuse(cs, out, 2, CS_ERR_UNPROVEN, msg);
        }
    }

    /* L3: configuration must not have drifted; payload must fit the memory budget */
    uint8_t now[32];
    config_digest(cs, now);
    if (!cs_ct_equal(now, cs->config_digest, 32)) {
        dis_trap(&cs->dis, CS_ERR_DRIFT, "policy/limits changed since init");
        return refuse(cs, out, 3, CS_ERR_DRIFT, "policy/limits changed since init");
    }
    if (cs->cfg.drift_enabled && cs->drift.state != CS_OK)
        return refuse(cs, out, 3, CS_ERR_DRIFT, "steps-per-job drift latched");
    if (job->payload_len > cs->cfg.limits.max_mem_bytes)
        return refuse(cs, out, 3, CS_ERR_LIMIT, "payload exceeds the memory limit");

    /* L4: no job runs while trapped or while an invariant is violated */
    if (dis_is_trapped(&cs->dis)) return refuse(cs, out, 4, CS_ERR_TRAPPED, "dissonance engine is trapped");
    if (dis_check_invariants(&cs->dis) != CS_OK) return refuse(cs, out, 4, CS_ERR_CONTRADICTION, "invariant violated");

    /* L5: Guardian -> Examiner -> Publisher */
    gw_request req;
    cs_status s = gw_request_init(&req, job->id, job->kind, job->payload, job->payload_len);
    gw_approval appr;
    if (s == CS_OK) {
        gw_health h = {.boot_ok = 1, .alp_ok = 1, .sigma_ok = 1, .dissonance_clear = !dis_is_trapped(&cs->dis)};
        s = gw_approve(&cs->gw, &req, &h, &appr);
    }
    if (s != CS_OK) {
        snprintf(msg, sizeof msg, "job %llu: gateway refused (%s)", (unsigned long long)job->id, cs_status_str(s));
        return refuse(cs, out, 5, s == CS_ERR_ARG ? CS_ERR_ARG : CS_ERR_DENIED, msg);
    }

    /* L6: run the approved work under the resource limits */
    s = exec_run(&cs->exec, &cs->gw, &req, &appr, job->work, job->work_ctx, &cs->cfg.limits,
                 cs->cfg.clock, cs->cfg.clock_ctx, &out->exec);
    if (s == CS_ERR_DENIED || s == CS_ERR_REPLAY || s == CS_ERR_ARG)
        return refuse(cs, out, 6, s, "execution runtime rejected the approval");

    /* L7: evidence */
    s = wit_seal(&out->witness, cs->witness_key, cs->boot.boot_id, &req, &appr, &out->exec);
    if (s == CS_OK) s = wit_verify(&out->witness, cs->witness_key);
    if (s != CS_OK) return refuse(cs, out, 7, s, "witness could not be sealed");

    /* L8: seal it */
    s = worm_append(&cs->worm, out->witness.digest, &out->seal);
    if (s != CS_OK) {
        dis_trap(&cs->dis, s, "ledger append failed");
        return refuse(cs, out, 8, s, "ledger append failed");
    }
    out->sealed = 1;

    /* L9: observe */
    obs_counter_add(&cs->obs, out->exec.status == CS_OK ? "jobs_ok" : "jobs_work_failed", 1);
    obs_observe(&cs->obs, "job_steps", (int64_t)out->exec.steps);
    obs_observe(&cs->obs, "job_mem_peak", (int64_t)out->exec.mem_peak);
    obs_gauge_set(&cs->obs, "ledger_length", (int64_t)worm_count(&cs->worm));
    char hex[17];
    cs_hex(out->seal.seal, 8, hex);
    snprintf(msg, sizeof msg, "job %llu %s, seal_%llu=%s...", (unsigned long long)job->id,
             out->exec.status == CS_OK ? "sealed" : "failed+sealed", (unsigned long long)out->seal.index, hex);
    obs_audit(&cs->obs, 9, out->exec.status, msg);

    if (cs->cfg.drift_enabled && sigma_drift_update(&cs->drift, (int64_t)out->exec.steps) == CS_ERR_DRIFT)
        dis_trap(&cs->dis, CS_ERR_DRIFT, "steps-per-job drifted from baseline");

    out->status = out->exec.status;
    out->failed_layer = out->exec.status == CS_OK ? -1 : 6;
    return out->status;
}

cs_status cstack_reset_trap(cstack *cs)
{
    if (!cs || !cs->initialized) return CS_ERR_ARG;
    obs_audit(&cs->obs, 4, CS_OK, "operator reset of dissonance trap");
    return dis_reset_trap(&cs->dis);
}

cs_status cstack_verify(const cstack *cs)
{
    if (!cs || !cs->initialized) return CS_ERR_ARG;
    cs_status s = worm_verify(&cs->worm);
    if (s != CS_OK) return s;
    return obs_audit_verify(&cs->obs);
}

void cstack_shutdown(cstack *cs)
{
    if (!cs) return;
    worm_close(&cs->worm);
    wipe(cs->witness_key, sizeof cs->witness_key);
    cs->initialized = 0;
}
