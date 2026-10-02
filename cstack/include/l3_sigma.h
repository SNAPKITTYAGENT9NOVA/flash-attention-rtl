#ifndef L3_SIGMA_H
#define L3_SIGMA_H

/* Layer 3 - Sigma kernel: resource limits and drift detection. */

#include <stddef.h>
#include <stdint.h>

#include "cs_status.h"

/* ---- resource limits ---- */

typedef uint64_t (*sigma_clock_fn)(void *ctx);     /* monotonic nanoseconds */

typedef struct sigma_limits {
    uint64_t max_mem_bytes;
    uint64_t max_steps;
    uint64_t max_ns;
} sigma_limits;

typedef struct sigma_ctx {
    sigma_limits   lim;
    uint64_t       mem_used, mem_peak, steps, start_ns;
    sigma_clock_fn clock;
    void          *clock_ctx;
    cs_status      breach;                         /* latched first breach, CS_OK if none */
} sigma_ctx;

/* clock NULL = CLOCK_MONOTONIC. A limit of 0 means "none allowed" (not "unlimited"). */
void      sigma_init(sigma_ctx *s, const sigma_limits *lim, sigma_clock_fn clock, void *clock_ctx);
cs_status sigma_charge_mem(sigma_ctx *s, uint64_t bytes);
cs_status sigma_release_mem(sigma_ctx *s, uint64_t bytes);
cs_status sigma_charge_steps(sigma_ctx *s, uint64_t n);
cs_status sigma_check_time(sigma_ctx *s);
cs_status sigma_status(const sigma_ctx *s);
uint64_t  sigma_elapsed_ns(const sigma_ctx *s);

/* ---- drift detection ---- */

/* Integer EWMA drift detector: ewma += (sample - ewma) / 2^shift, drift when
 * |ewma - baseline| > tolerance. Latches on first drift. Deterministic (no floating point). */
typedef struct sigma_drift {
    int64_t   baseline, tolerance, ewma;
    unsigned  shift;
    uint64_t  samples;
    cs_status state;
} sigma_drift;

cs_status sigma_drift_init(sigma_drift *d, int64_t baseline, int64_t tolerance, unsigned shift);
cs_status sigma_drift_update(sigma_drift *d, int64_t sample);

/* State drift: SHA-256 of a state blob must equal the recorded baseline digest. */
cs_status sigma_state_check(const uint8_t expected[32], const void *state, size_t len);

#endif
