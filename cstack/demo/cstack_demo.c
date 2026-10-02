/* Walks jobs through the ten layers and shows where each refusal happens. */
#include <stdio.h>
#include <string.h>

#include "cs_sha256.h"
#include "cstack.h"

static cs_status matmul_work(void *ctx, sigma_ctx *sg, uint8_t digest[32])
{
    size_t n = *(size_t *)ctx;
    cs_status s = sigma_charge_mem(sg, 3 * n * n * sizeof(gl_t));
    if (s == CS_OK) s = sigma_charge_steps(sg, n * n * n);
    if (s != CS_OK) return s;

    pmat a, b, c;
    if (pmat_new(&a, n, n) != CS_OK || pmat_new(&b, n, n) != CS_OK) return CS_ERR_NOMEM;
    for (size_t i = 0; i < n * n; i++) {
        a.d[i] = gl_reduce(i * 2654435761u + 1);
        b.d[i] = gl_reduce(i * 40503u + 7);
    }
    s = pmat_mul(&a, &b, &c);
    if (s == CS_OK) {
        cs_sha256(c.d, n * n * sizeof(gl_t), digest);
        pmat_free(&c);
    }
    pmat_free(&a);
    pmat_free(&b);
    return s;
}

static void show(const char *what, cs_status s, const cstack_result *r)
{
    printf("  %-34s -> %-24s", what, cs_status_str(s));
    if (r->failed_layer >= 0) printf(" (stopped at layer %d)", r->failed_layer);
    if (r->sealed) printf(" sealed as seal_%llu", (unsigned long long)r->seal.index);
    printf("\n");
}

int main(void)
{
    cstack cs;
    cstack_config cfg;
    memset(&cfg, 0, sizeof cfg);
    cfg.policy.allowed_kinds = 1u << 1;
    cfg.policy.max_payload = 256;
    cfg.limits.max_mem_bytes = 1u << 20;
    cfg.limits.max_steps = 1000000;
    cfg.limits.max_ns = 5ull * 1000000000ull;

    cs_status s = cstack_init(&cs, &cfg);
    if (s != CS_OK) { printf("init failed: %s\n", cs_status_str(s)); return 1; }

    printf("L0 boot       cpu=%s/%s  features=0x%x  boot_id=", cs.boot.cpu.arch, cs.boot.cpu.vendor, cs.boot.cpu.features);
    for (int i = 0; i < 8; i++) printf("%02x", cs.boot.boot_id[i]);
    printf("...  memory verified: %zu bytes\n", cs.boot.mem_verified_bytes);
    printf("L1 uac        Goldilocks p = 2^64 - 2^32 + 1, self-test %s\n", gl_selftest() == CS_OK ? "ok" : "FAILED");

    const char *proof_ok = "theorem gl_mul_comm (a b : GL) : a * b = b * a := by ring\n";
    const char *proof_sorry = "theorem fa_bound : x <= y := by\n  sorry\n";
    alp_attach_proof(&cs.alp, "gl_mul_comm", proof_ok, strlen(proof_ok));
    alp_attach_proof(&cs.alp, "fa_bound", proof_sorry, strlen(proof_sorry));
    char manifest[512];
    alp_manifest(&cs.alp, manifest, sizeof manifest);
    printf("L2 alp        manifest:\n");
    for (char *line = strtok(manifest, "\n"); line; line = strtok(NULL, "\n")) printf("                %s\n", line);

    printf("L3-L9         jobs:\n");
    size_t n = 8;
    const char *needs_ok[] = {"gl_mul_comm"};
    const char *needs_sorry[] = {"fa_bound"};
    cstack_result r;

    cstack_job j1 = {.id = 1, .kind = 1, .payload = "matmul 8x8", .payload_len = 10,
                     .requires = needs_ok, .nrequires = 1, .work = matmul_work, .work_ctx = &n};
    show("job 1: 8x8 matmul, proven claim", cstack_submit(&cs, &j1, &r), &r);

    cstack_job j2 = {.id = 2, .kind = 1, .payload = "needs fa_bound", .payload_len = 14,
                     .requires = needs_sorry, .nrequires = 1, .work = matmul_work, .work_ctx = &n};
    show("job 2: relies on a sorry claim", cstack_submit(&cs, &j2, &r), &r);

    cstack_job j3 = {.id = 3, .kind = 9, .payload = "kind not allowed", .payload_len = 16,
                     .work = matmul_work, .work_ctx = &n};
    show("job 3: kind refused by Examiner", cstack_submit(&cs, &j3, &r), &r);

    size_t huge = 200;                                    /* 8e6 steps > 1e6 limit */
    cstack_job j4 = {.id = 4, .kind = 1, .payload = "too big", .payload_len = 7,
                     .work = matmul_work, .work_ctx = &huge};
    show("job 4: exceeds the step limit", cstack_submit(&cs, &j4, &r), &r);

    n = 16;
    cstack_job j5 = {.id = 5, .kind = 1, .payload = "matmul 16x16", .payload_len = 12,
                     .requires = needs_ok, .nrequires = 1, .work = matmul_work, .work_ctx = &n};
    show("job 5: 16x16 matmul, proven claim", cstack_submit(&cs, &j5, &r), &r);

    printf("L8 ledger     %zu seals, chain %s\n", worm_count(&cs.worm), worm_verify(&cs.worm) == CS_OK ? "valid" : "BROKEN");
    for (size_t i = 0; i < worm_count(&cs.worm); i++) {
        char hex[17];
        cs_hex(worm_at(&cs.worm, i)->seal, 8, hex);
        printf("                seal_%zu = %s...\n", i, hex);
    }

    cs.worm.seals[1].witness_digest[0] ^= 1;              /* simulate tampering with a past entry */
    printf("              after altering one bit of seal_1's witness: %s\n",
           cs_status_str(worm_verify(&cs.worm)));
    cs.worm.seals[1].witness_digest[0] ^= 1;

    char metrics[1024];
    obs_export_metrics(&cs.obs, metrics, sizeof metrics);
    printf("L9 metrics\n");
    for (char *line = strtok(metrics, "\n"); line; line = strtok(NULL, "\n")) printf("                %s\n", line);
    printf("   audit      %llu events, chain %s\n", (unsigned long long)obs_audit_total(&cs.obs),
           obs_audit_verify(&cs.obs) == CS_OK ? "valid" : "BROKEN");

    cstack_shutdown(&cs);
    return 0;
}
