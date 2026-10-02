#ifndef L6_EXEC_H
#define L6_EXEC_H

/* Layer 6 - Execution runtime: runs approved work only.
 *
 * exec_run is the only way to execute a job. It verifies the gateway approval for exactly this
 * request, consumes it (approvals are single use and must be presented in issue order), then runs
 * the work under Sigma resource limits. */

#include <stdint.h>

#include "cs_status.h"
#include "l3_sigma.h"
#include "l5_gateway.h"

/* The work reports a SHA-256 digest of its result and charges resources to sigma. Returns CS_OK
 * on success. */
typedef cs_status (*exec_work_fn)(void *ctx, sigma_ctx *sigma, uint8_t result_digest[32]);

typedef struct exec_rt {
    uint64_t last_seq;           /* highest approval sequence consumed */
    uint64_t executed;
} exec_rt;

typedef struct exec_result {
    cs_status status;            /* status of the work (or of the limit that stopped it) */
    uint8_t   result_digest[32]; /* zero if the work produced none */
    uint64_t  steps;
    uint64_t  mem_peak;
    uint64_t  elapsed_ns;        /* informational, not deterministic */
} exec_result;

void exec_init(exec_rt *rt);

/* Returns CS_OK if the work ran and succeeded. If the approval is rejected nothing runs and out
 * is untouched (CS_ERR_DENIED / CS_ERR_REPLAY). Once the approval is accepted it is consumed even
 * if the work fails; out->status then carries the outcome and the return value equals it. */
cs_status exec_run(exec_rt *rt, const gateway *g, const gw_request *req, const gw_approval *appr,
                   exec_work_fn work, void *work_ctx, const sigma_limits *limits,
                   sigma_clock_fn clock, void *clock_ctx, exec_result *out);

#endif
