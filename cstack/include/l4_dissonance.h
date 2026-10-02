#ifndef L4_DISSONANCE_H
#define L4_DISSONANCE_H

/* Layer 4 - Dissonance engine: contradiction detection and violation trapping.
 *
 * Facts are named propositions (true / false / unknown). Implication rules (a => b) and exclusion
 * rules (not both) are propagated by modus ponens and modus tollens. An assertion is applied
 * atomically: if it would create a contradiction nothing changes, the violation is recorded and
 * the engine traps. A trapped engine refuses further assertions until dis_reset_trap(). */

#include <stddef.h>
#include <stdint.h>

#include "cs_status.h"

#define DIS_NAME_MAX       48
#define DIS_MAX_FACTS      64
#define DIS_MAX_RULES      64
#define DIS_MAX_INVARIANTS 16
#define DIS_MAX_VIOLATIONS 16
#define DIS_MSG_MAX        96

typedef struct dis_violation {
    uint64_t  seq;
    cs_status code;
    char      msg[DIS_MSG_MAX];
} dis_violation;

typedef int (*dis_invariant_fn)(void *ctx);                           /* nonzero = holds */
typedef void (*dis_trap_fn)(const dis_violation *v, void *ctx);

typedef struct dis_engine {
    char     fact_name[DIS_MAX_FACTS][DIS_NAME_MAX];
    int8_t   fact_value[DIS_MAX_FACTS];                               /* 1 true, 0 false, -1 unknown */
    size_t   nfacts;

    struct { size_t a, b; } impl[DIS_MAX_RULES];
    size_t   nimpl;
    struct { size_t a, b; } excl[DIS_MAX_RULES];
    size_t   nexcl;

    struct { char name[DIS_NAME_MAX]; dis_invariant_fn fn; void *ctx; } inv[DIS_MAX_INVARIANTS];
    size_t   ninv;

    dis_violation log[DIS_MAX_VIOLATIONS];                            /* ring */
    size_t   nviolations;                                             /* total ever recorded */
    uint64_t seq;
    int      trapped;
    dis_trap_fn on_trap;
    void       *trap_ctx;
} dis_engine;

void      dis_init(dis_engine *e);
void      dis_set_trap_handler(dis_engine *e, dis_trap_fn fn, void *ctx);

cs_status dis_add_implication(dis_engine *e, const char *a, const char *b);
cs_status dis_add_exclusion(dis_engine *e, const char *a, const char *b);
cs_status dis_assert(dis_engine *e, const char *name, int value);
int       dis_value(const dis_engine *e, const char *name);           /* 1 / 0 / -1 */

cs_status dis_add_invariant(dis_engine *e, const char *name, dis_invariant_fn fn, void *ctx);
cs_status dis_check_invariants(dis_engine *e);

/* Explicit violation trap (used by other layers). Always sets the trapped flag. */
cs_status dis_trap(dis_engine *e, cs_status code, const char *msg);
int       dis_is_trapped(const dis_engine *e);
cs_status dis_reset_trap(dis_engine *e);                              /* keeps facts and the log */
size_t    dis_violation_count(const dis_engine *e);                   /* total recorded */
/* i = 0 is the oldest retained violation; NULL if out of range. */
const dis_violation *dis_violation_at(const dis_engine *e, size_t i);

#endif
