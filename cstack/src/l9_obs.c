#include "l9_obs.h"

#include <stdio.h>
#include <string.h>
#include <time.h>

#include "cs_sha256.h"

static uint64_t default_clock(void *ctx)
{
    (void)ctx;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

void obs_init(obs_ctx *o, sigma_clock_fn clock, void *clock_ctx)
{
    memset(o, 0, sizeof *o);
    o->clock = clock ? clock : default_clock;
    o->clock_ctx = clock_ctx;
    cs_sha256("cstack-audit-genesis-v1", 23, o->base_chain);
}

static obs_metric *lookup(obs_ctx *o, const char *name, obs_kind kind, cs_status *st)
{
    *st = CS_OK;
    if (!o || !name || name[0] == '\0' || strlen(name) >= OBS_NAME_MAX) { *st = CS_ERR_ARG; return NULL; }
    for (size_t i = 0; i < o->nmetrics; i++)
        if (strcmp(o->metrics[i].name, name) == 0) {
            if (o->metrics[i].kind != kind) { *st = CS_ERR_STATE; return NULL; }
            return &o->metrics[i];
        }
    if (o->nmetrics == OBS_MAX_METRICS) { *st = CS_ERR_NOMEM; return NULL; }
    obs_metric *m = &o->metrics[o->nmetrics++];
    memset(m, 0, sizeof *m);
    strcpy(m->name, name);
    m->kind = kind;
    return m;
}

cs_status obs_counter_add(obs_ctx *o, const char *name, uint64_t delta)
{
    cs_status st;
    obs_metric *m = lookup(o, name, OBS_COUNTER, &st);
    if (!m) return st;
    if (delta > (uint64_t)INT64_MAX - (uint64_t)m->value) return CS_ERR_RANGE;
    m->value += (int64_t)delta;
    return CS_OK;
}

cs_status obs_gauge_set(obs_ctx *o, const char *name, int64_t value)
{
    cs_status st;
    obs_metric *m = lookup(o, name, OBS_GAUGE, &st);
    if (!m) return st;
    m->value = value;
    return CS_OK;
}

cs_status obs_observe(obs_ctx *o, const char *name, int64_t value)
{
    cs_status st;
    obs_metric *m = lookup(o, name, OBS_SUMMARY, &st);
    if (!m) return st;
    if (m->count == 0 || value < m->min) m->min = value;
    if (m->count == 0 || value > m->max) m->max = value;
    if ((value > 0 && m->value > INT64_MAX - value) || (value < 0 && m->value < INT64_MIN - value))
        return CS_ERR_RANGE;
    m->value += value;
    m->count++;
    return CS_OK;
}

int obs_get(const obs_ctx *o, const char *name, obs_metric *out)
{
    if (!o || !name) return 0;
    for (size_t i = 0; i < o->nmetrics; i++)
        if (strcmp(o->metrics[i].name, name) == 0) {
            if (out) *out = o->metrics[i];
            return 1;
        }
    return 0;
}

static void event_chain(const uint8_t prev[32], const obs_event *e, uint8_t out[32])
{
    cs_sha256_ctx c;
    cs_sha256_init(&c);
    cs_sha256_update(&c, prev, 32);
    cs_sha256_update_u64(&c, e->seq);
    cs_sha256_update_u64(&c, e->ts_ns);
    cs_sha256_update_u64(&c, (uint64_t)e->layer);
    cs_sha256_update_u64(&c, (uint64_t)e->status);
    cs_sha256_update(&c, e->msg, strlen(e->msg));
    cs_sha256_final(&c, out);
}

cs_status obs_audit(obs_ctx *o, int layer, cs_status status, const char *msg)
{
    if (!o || layer < 0 || layer > 9) return CS_ERR_ARG;
    obs_event *slot = &o->ring[o->total_events % OBS_AUDIT_CAP];
    const uint8_t *prev;
    uint8_t prev_copy[32];
    if (o->total_events == 0) prev = o->base_chain;
    else {
        memcpy(prev_copy, o->ring[(o->total_events - 1) % OBS_AUDIT_CAP].chain, 32);
        prev = prev_copy;
    }
    if (o->total_events >= OBS_AUDIT_CAP)       /* the overwritten event's chain becomes the new base */
        memcpy(o->base_chain, slot->chain, 32);
    obs_event e;
    memset(&e, 0, sizeof e);
    e.seq = o->total_events + 1;
    e.ts_ns = o->clock(o->clock_ctx);
    e.layer = layer;
    e.status = status;
    snprintf(e.msg, sizeof e.msg, "%s", msg ? msg : "");
    event_chain(prev, &e, e.chain);
    *slot = e;
    o->total_events++;
    return CS_OK;
}

uint64_t obs_audit_total(const obs_ctx *o) { return o ? o->total_events : 0; }

static size_t retained(const obs_ctx *o)
{
    return o->total_events < OBS_AUDIT_CAP ? (size_t)o->total_events : OBS_AUDIT_CAP;
}

const obs_event *obs_audit_at(const obs_ctx *o, size_t i)
{
    if (!o || i >= retained(o)) return NULL;
    uint64_t first = o->total_events - retained(o);
    return &o->ring[(first + i) % OBS_AUDIT_CAP];
}

cs_status obs_audit_verify(const obs_ctx *o)
{
    if (!o) return CS_ERR_ARG;
    uint8_t prev[32];
    memcpy(prev, o->base_chain, 32);
    uint64_t first_seq = o->total_events - retained(o) + 1;
    for (size_t i = 0; i < retained(o); i++) {
        const obs_event *e = obs_audit_at(o, i);
        uint8_t want[32];
        if (e->seq != first_seq + i) return CS_ERR_TAMPER;
        event_chain(prev, e, want);
        if (!cs_ct_equal(want, e->chain, 32)) return CS_ERR_TAMPER;
        memcpy(prev, e->chain, 32);
    }
    return CS_OK;
}

/* append helper for snprintf-style output */
typedef struct sink { char *buf; size_t cap, total; } sink;
static void emit(sink *s, const char *fmt_line, size_t n)
{
    if (s->cap > 0 && s->total < s->cap) {
        size_t room = s->cap - s->total - 1;
        size_t w = n < room ? n : room;
        memcpy(s->buf + s->total, fmt_line, w);
        s->buf[s->total + w] = '\0';
    }
    s->total += n;
}

size_t obs_export_metrics(const obs_ctx *o, char *buf, size_t cap)
{
    sink s = {buf, cap, 0};
    char line[160];
    if (cap > 0) buf[0] = '\0';
    for (size_t i = 0; i < o->nmetrics; i++) {
        const obs_metric *m = &o->metrics[i];
        int n;
        switch (m->kind) {
        case OBS_SUMMARY:
            n = snprintf(line, sizeof line, "%s_count %llu\n%s_sum %lld\n%s_min %lld\n%s_max %lld\n",
                         m->name, (unsigned long long)m->count, m->name, (long long)m->value,
                         m->name, (long long)m->min, m->name, (long long)m->max);
            break;
        default:
            n = snprintf(line, sizeof line, "%s %lld\n", m->name, (long long)m->value);
        }
        emit(&s, line, (size_t)n);
    }
    return s.total;
}

size_t obs_export_audit(const obs_ctx *o, char *buf, size_t cap)
{
    sink s = {buf, cap, 0};
    char line[256], hex[17];
    if (cap > 0) buf[0] = '\0';
    for (size_t i = 0; i < retained(o); i++) {
        const obs_event *e = obs_audit_at(o, i);
        cs_hex(e->chain, 8, hex);
        int n = snprintf(line, sizeof line, "%llu %llu L%d %s %s chain=%s\n",
                         (unsigned long long)e->seq, (unsigned long long)e->ts_ns, e->layer,
                         cs_status_str(e->status), e->msg, hex);
        emit(&s, line, (size_t)n);
    }
    return s.total;
}
