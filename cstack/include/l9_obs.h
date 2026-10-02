#ifndef L9_OBS_H
#define L9_OBS_H

/* Layer 9 - Observability: metrics and a tamper-evident audit log.
 *
 * Metrics: counters, gauges and summaries (count/sum/min/max), exported as text.
 * Audit: a ring of events, each chained to the previous one by SHA-256, so any edit to a retained
 * event is detected by obs_audit_verify(). Observability never feeds back into the layers below. */

#include <stddef.h>
#include <stdint.h>

#include "cs_status.h"
#include "l3_sigma.h"      /* sigma_clock_fn */

#define OBS_NAME_MAX    48
#define OBS_MAX_METRICS 64
#define OBS_AUDIT_CAP   128
#define OBS_MSG_MAX     96

typedef enum obs_kind { OBS_COUNTER = 0, OBS_GAUGE, OBS_SUMMARY } obs_kind;

typedef struct obs_metric {
    char     name[OBS_NAME_MAX];
    obs_kind kind;
    int64_t  value;                  /* counter / gauge value, summary sum */
    uint64_t count;                  /* summary only */
    int64_t  min, max;               /* summary only */
} obs_metric;

typedef struct obs_event {
    uint64_t  seq;
    uint64_t  ts_ns;
    int       layer;                 /* 0..9 */
    cs_status status;
    char      msg[OBS_MSG_MAX];
    uint8_t   chain[32];             /* SHA-256(prev chain || event fields) */
} obs_event;

typedef struct obs_ctx {
    obs_metric     metrics[OBS_MAX_METRICS];
    size_t         nmetrics;
    obs_event      ring[OBS_AUDIT_CAP];
    uint64_t       total_events;
    uint8_t        base_chain[32];   /* chain value preceding the oldest retained event */
    sigma_clock_fn clock;
    void          *clock_ctx;
} obs_ctx;

void      obs_init(obs_ctx *o, sigma_clock_fn clock, void *clock_ctx);   /* NULL = CLOCK_MONOTONIC */

cs_status obs_counter_add(obs_ctx *o, const char *name, uint64_t delta);
cs_status obs_gauge_set(obs_ctx *o, const char *name, int64_t value);
cs_status obs_observe(obs_ctx *o, const char *name, int64_t value);
/* 1 if the metric exists (value written to *out), else 0 */
int       obs_get(const obs_ctx *o, const char *name, obs_metric *out);

cs_status obs_audit(obs_ctx *o, int layer, cs_status status, const char *msg);
uint64_t  obs_audit_total(const obs_ctx *o);
const obs_event *obs_audit_at(const obs_ctx *o, size_t i);               /* 0 = oldest retained */
cs_status obs_audit_verify(const obs_ctx *o);                            /* CS_ERR_TAMPER on mismatch */

/* snprintf-style exports; return the length that would be written. */
size_t    obs_export_metrics(const obs_ctx *o, char *buf, size_t cap);
size_t    obs_export_audit(const obs_ctx *o, char *buf, size_t cap);

#endif
