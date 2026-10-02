#include "l4_dissonance.h"

#include <stdio.h>
#include <string.h>

void dis_init(dis_engine *e)
{
    memset(e, 0, sizeof *e);
}

void dis_set_trap_handler(dis_engine *e, dis_trap_fn fn, void *ctx)
{
    e->on_trap = fn;
    e->trap_ctx = ctx;
}

static int name_ok(const char *n)
{
    return n && n[0] != '\0' && strlen(n) < DIS_NAME_MAX;
}

static int find_fact(const dis_engine *e, const char *name)
{
    for (size_t i = 0; i < e->nfacts; i++)
        if (strcmp(e->fact_name[i], name) == 0) return (int)i;
    return -1;
}

static int intern(dis_engine *e, const char *name)
{
    int i = find_fact(e, name);
    if (i >= 0) return i;
    if (e->nfacts == DIS_MAX_FACTS) return -1;
    strcpy(e->fact_name[e->nfacts], name);
    e->fact_value[e->nfacts] = -1;
    return (int)e->nfacts++;
}

cs_status dis_trap(dis_engine *e, cs_status code, const char *msg)
{
    if (!e) return CS_ERR_ARG;
    dis_violation *v = &e->log[e->nviolations % DIS_MAX_VIOLATIONS];
    v->seq = ++e->seq;
    v->code = code;
    snprintf(v->msg, sizeof v->msg, "%s", msg ? msg : "");
    e->nviolations++;
    e->trapped = 1;
    if (e->on_trap) e->on_trap(v, e->trap_ctx);
    return code;
}

/* Propagates over a scratch copy of the values. Returns the index of a fact involved in a
 * contradiction, or -1 if consistent. */
static int propagate(const dis_engine *e, int8_t *val)
{
    int changed = 1;
    while (changed) {
        changed = 0;
        for (size_t r = 0; r < e->nimpl; r++) {
            size_t a = e->impl[r].a, b = e->impl[r].b;
            if (val[a] == 1) {
                if (val[b] == 0) return (int)b;
                if (val[b] == -1) { val[b] = 1; changed = 1; }
            }
            if (val[b] == 0) {                                   /* modus tollens */
                if (val[a] == 1) return (int)a;
                if (val[a] == -1) { val[a] = 0; changed = 1; }
            }
        }
        for (size_t r = 0; r < e->nexcl; r++) {
            size_t a = e->excl[r].a, b = e->excl[r].b;
            if (val[a] == 1) {
                if (val[b] == 1) return (int)b;
                if (val[b] == -1) { val[b] = 0; changed = 1; }
            }
            if (val[b] == 1) {
                if (val[a] == 1) return (int)a;
                if (val[a] == -1) { val[a] = 0; changed = 1; }
            }
        }
    }
    return -1;
}

static cs_status contradiction(dis_engine *e, int fact, const char *what)
{
    char msg[DIS_MSG_MAX];
    snprintf(msg, sizeof msg, "contradiction on '%s': %s", e->fact_name[fact], what);
    return dis_trap(e, CS_ERR_CONTRADICTION, msg);
}

cs_status dis_assert(dis_engine *e, const char *name, int value)
{
    if (!e || !name_ok(name) || (value != 0 && value != 1)) return CS_ERR_ARG;
    if (e->trapped) return CS_ERR_TRAPPED;
    int f = intern(e, name);
    if (f < 0) return CS_ERR_NOMEM;
    if (e->fact_value[f] == (int8_t)(1 - value)) return contradiction(e, f, "opposite value already established");

    int8_t scratch[DIS_MAX_FACTS];
    memcpy(scratch, e->fact_value, sizeof scratch);
    scratch[f] = (int8_t)value;
    int bad = propagate(e, scratch);
    if (bad >= 0) return contradiction(e, bad, "derived from rules");
    memcpy(e->fact_value, scratch, sizeof scratch);               /* commit atomically */
    return CS_OK;
}

int dis_value(const dis_engine *e, const char *name)
{
    int f = (e && name) ? find_fact(e, name) : -1;
    return f < 0 ? -1 : e->fact_value[f];
}

static cs_status add_rule(dis_engine *e, const char *a, const char *b, int exclusion)
{
    if (!e || !name_ok(a) || !name_ok(b)) return CS_ERR_ARG;
    if (e->trapped) return CS_ERR_TRAPPED;
    size_t *n = exclusion ? &e->nexcl : &e->nimpl;
    if (*n == DIS_MAX_RULES) return CS_ERR_NOMEM;
    int ia = intern(e, a), ib = intern(e, b);
    if (ia < 0 || ib < 0) return CS_ERR_NOMEM;
    if (exclusion) { e->excl[*n].a = (size_t)ia; e->excl[*n].b = (size_t)ib; }
    else           { e->impl[*n].a = (size_t)ia; e->impl[*n].b = (size_t)ib; }
    (*n)++;

    /* the new rule must be consistent with what is already established */
    int8_t scratch[DIS_MAX_FACTS];
    memcpy(scratch, e->fact_value, sizeof scratch);
    int bad = propagate(e, scratch);
    if (bad >= 0) {
        (*n)--;                                                    /* reject the rule */
        return contradiction(e, bad, "new rule conflicts with established facts");
    }
    memcpy(e->fact_value, scratch, sizeof scratch);
    return CS_OK;
}

cs_status dis_add_implication(dis_engine *e, const char *a, const char *b) { return add_rule(e, a, b, 0); }
cs_status dis_add_exclusion(dis_engine *e, const char *a, const char *b) { return add_rule(e, a, b, 1); }

cs_status dis_add_invariant(dis_engine *e, const char *name, dis_invariant_fn fn, void *ctx)
{
    if (!e || !name_ok(name) || !fn) return CS_ERR_ARG;
    if (e->ninv == DIS_MAX_INVARIANTS) return CS_ERR_NOMEM;
    strcpy(e->inv[e->ninv].name, name);
    e->inv[e->ninv].fn = fn;
    e->inv[e->ninv].ctx = ctx;
    e->ninv++;
    return CS_OK;
}

cs_status dis_check_invariants(dis_engine *e)
{
    if (!e) return CS_ERR_ARG;
    if (e->trapped) return CS_ERR_TRAPPED;
    for (size_t i = 0; i < e->ninv; i++) {
        if (!e->inv[i].fn(e->inv[i].ctx)) {
            char msg[DIS_MSG_MAX];
            snprintf(msg, sizeof msg, "invariant '%s' violated", e->inv[i].name);
            return dis_trap(e, CS_ERR_CONTRADICTION, msg);
        }
    }
    return CS_OK;
}

int dis_is_trapped(const dis_engine *e) { return e ? e->trapped : 1; }

cs_status dis_reset_trap(dis_engine *e)
{
    if (!e) return CS_ERR_ARG;
    e->trapped = 0;
    return CS_OK;
}

size_t dis_violation_count(const dis_engine *e) { return e ? e->nviolations : 0; }

const dis_violation *dis_violation_at(const dis_engine *e, size_t i)
{
    if (!e) return NULL;
    size_t retained = e->nviolations < DIS_MAX_VIOLATIONS ? e->nviolations : DIS_MAX_VIOLATIONS;
    if (i >= retained) return NULL;
    size_t first = e->nviolations - retained;
    return &e->log[(first + i) % DIS_MAX_VIOLATIONS];
}
