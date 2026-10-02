#include "l3_sigma.h"

#include <time.h>

#include "cs_sha256.h"

static uint64_t default_clock(void *ctx)
{
    (void)ctx;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

void sigma_init(sigma_ctx *s, const sigma_limits *lim, sigma_clock_fn clock, void *clock_ctx)
{
    s->lim = *lim;
    s->mem_used = s->mem_peak = s->steps = 0;
    s->clock = clock ? clock : default_clock;
    s->clock_ctx = clock_ctx;
    s->breach = CS_OK;
    s->start_ns = s->clock(s->clock_ctx);
}

static cs_status latch(sigma_ctx *s, cs_status why)
{
    if (s->breach == CS_OK) s->breach = why;
    return s->breach;
}

cs_status sigma_charge_mem(sigma_ctx *s, uint64_t bytes)
{
    if (!s) return CS_ERR_ARG;
    if (s->breach != CS_OK) return s->breach;
    if (bytes > s->lim.max_mem_bytes - (s->mem_used > s->lim.max_mem_bytes ? s->lim.max_mem_bytes : s->mem_used))
        return latch(s, CS_ERR_LIMIT);
    s->mem_used += bytes;
    if (s->mem_used > s->mem_peak) s->mem_peak = s->mem_used;
    return CS_OK;
}

cs_status sigma_release_mem(sigma_ctx *s, uint64_t bytes)
{
    if (!s) return CS_ERR_ARG;
    if (bytes > s->mem_used) return CS_ERR_RANGE;      /* releasing more than was charged */
    s->mem_used -= bytes;
    return CS_OK;
}

cs_status sigma_charge_steps(sigma_ctx *s, uint64_t n)
{
    if (!s) return CS_ERR_ARG;
    if (s->breach != CS_OK) return s->breach;
    if (n > s->lim.max_steps - (s->steps > s->lim.max_steps ? s->lim.max_steps : s->steps))
        return latch(s, CS_ERR_LIMIT);
    s->steps += n;
    return CS_OK;
}

uint64_t sigma_elapsed_ns(const sigma_ctx *s)
{
    uint64_t now = s->clock(s->clock_ctx);
    return now >= s->start_ns ? now - s->start_ns : 0;
}

cs_status sigma_check_time(sigma_ctx *s)
{
    if (!s) return CS_ERR_ARG;
    if (s->breach != CS_OK) return s->breach;
    if (sigma_elapsed_ns(s) > s->lim.max_ns) return latch(s, CS_ERR_LIMIT);
    return CS_OK;
}

cs_status sigma_status(const sigma_ctx *s) { return s ? s->breach : CS_ERR_ARG; }

/* ---- drift ---- */

cs_status sigma_drift_init(sigma_drift *d, int64_t baseline, int64_t tolerance, unsigned shift)
{
    if (!d || tolerance < 0 || shift < 1 || shift > 16) return CS_ERR_ARG;
    if (baseline > INT64_MAX / 4 || baseline < INT64_MIN / 4) return CS_ERR_ARG;
    d->baseline = baseline;
    d->tolerance = tolerance;
    d->ewma = baseline;
    d->shift = shift;
    d->samples = 0;
    d->state = CS_OK;
    return CS_OK;
}

cs_status sigma_drift_update(sigma_drift *d, int64_t sample)
{
    if (!d) return CS_ERR_ARG;
    if (d->state != CS_OK) return d->state;
    if (sample > INT64_MAX / 4 || sample < INT64_MIN / 4) return CS_ERR_ARG;
    d->samples++;
    d->ewma += (sample - d->ewma) / ((int64_t)1 << d->shift);   /* truncates toward zero */
    int64_t dev = d->ewma - d->baseline;
    if (dev < 0) dev = -dev;
    if (dev > d->tolerance) d->state = CS_ERR_DRIFT;
    return d->state;
}

cs_status sigma_state_check(const uint8_t expected[32], const void *state, size_t len)
{
    if (!expected || (!state && len)) return CS_ERR_ARG;
    uint8_t h[32];
    cs_sha256(state ? state : "", len, h);
    return cs_ct_equal(h, expected, 32) ? CS_OK : CS_ERR_DRIFT;
}
