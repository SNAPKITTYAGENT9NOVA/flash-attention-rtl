#ifndef CSTACK_H
#define CSTACK_H

/* The C stack: ten layers, each depending only on the ones below it.
 *
 *   L0 Boot              CPU detection, health-tested entropy, memory verification
 *   L1 UAC               Goldilocks field, matrices, tensors (the compute substrate)
 *   L2 ALP boundary      proof availability, sorry manifest
 *   L3 Sigma kernel      resource limits, drift detection
 *   L4 Dissonance        contradiction detection, violation trapping
 *   L5 Triple-lock       Guardian -> Examiner -> Publisher
 *   L6 Execution         approved work only
 *   L7 Unified witness   cryptographic evidence per execution
 *   L8 WORM ledger       append-only hash chain of seals
 *   L9 Observability     metrics and audit
 *
 * cstack_submit runs one job through every layer in order. The first layer that refuses stops the
 * job; nothing below it runs. Single-threaded. */

#include <stddef.h>
#include <stdint.h>

#include "cs_status.h"
#include "l0_boot.h"
#include "l1_goldilocks.h"
#include "l1_pmat.h"
#include "l1_tensor.h"
#include "l2_alp.h"
#include "l3_sigma.h"
#include "l4_dissonance.h"
#include "l5_gateway.h"
#include "l6_exec.h"
#include "l7_witness.h"
#include "l8_worm.h"
#include "l9_obs.h"

typedef struct cstack_config {
    cs_entropy_fn  entropy;             /* NULL = OS entropy */
    size_t         mem_verify_bytes;    /* 0 = 1 MiB */
    gw_policy      policy;
    sigma_limits   limits;              /* applied to every job */
    sigma_clock_fn clock;               /* NULL = CLOCK_MONOTONIC */
    void          *clock_ctx;
    const char    *ledger_path;         /* NULL = in-memory ledger */
    int            drift_enabled;       /* watch steps-per-job with the Sigma drift detector */
    int64_t        drift_baseline_steps;
    int64_t        drift_tolerance;
    unsigned       drift_shift;         /* EWMA window, 1..16 */
} cstack_config;

typedef struct cstack {
    int             initialized;
    cstack_config   cfg;
    cs_boot_report  boot;
    alp_registry    alp;
    dis_engine      dis;
    gateway         gw;
    exec_rt         exec;
    worm_ledger     worm;
    obs_ctx         obs;
    sigma_drift     drift;
    uint8_t         witness_key[32];
    uint8_t         config_digest[32];
} cstack;

typedef struct cstack_job {
    uint64_t           id;
    uint32_t           kind;            /* 0..31, checked against the policy */
    const void        *payload;
    size_t             payload_len;
    const char *const *requires;        /* ALP claims that must be proven */
    size_t             nrequires;
    exec_work_fn       work;
    void              *work_ctx;
} cstack_job;

typedef struct cstack_result {
    cs_status   status;
    int         failed_layer;           /* -1 if the job was accepted and executed; 6 if the work failed */
    exec_result exec;
    int         sealed;                 /* 1 if a witness was recorded in the ledger */
    wit_record  witness;
    worm_seal   seal;
} cstack_result;

/* Runs layers 0, 1 (self-test), 8 (ledger open) and wires the rest. */
cs_status cstack_init(cstack *cs, const cstack_config *cfg);
cs_status cstack_submit(cstack *cs, const cstack_job *job, cstack_result *out);
/* Operator action: clears a dissonance trap (logged). The cause must have been fixed. */
cs_status cstack_reset_trap(cstack *cs);
/* Verifies the ledger chain and the audit chain. */
cs_status cstack_verify(const cstack *cs);
void      cstack_shutdown(cstack *cs);

#endif
