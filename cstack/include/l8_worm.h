#ifndef L8_WORM_H
#define L8_WORM_H

/* Layer 8 - WORM ledger: an append-only hash chain of seals.
 *
 *   seal_0 = SHA-256("cstack-worm-genesis-v1")
 *   seal_i = SHA-256("cstack-worm-seal-v1" || be64(i) || seal_{i-1} || witness_digest_i)
 *
 * There is no API to modify or remove an entry. A file-backed ledger is opened O_APPEND, one line
 * per seal ("index witness_hex seal_hex"), and is fully re-verified when opened: any edit,
 * deletion, reordering or truncated line is reported as CS_ERR_TAMPER. */

#include <stddef.h>
#include <stdint.h>

#include "cs_status.h"

typedef struct worm_seal {
    uint64_t index;
    uint8_t  witness_digest[32];     /* all zero for seal_0 */
    uint8_t  seal[32];
} worm_seal;

typedef struct worm_ledger {
    worm_seal *seals;
    size_t     count, cap;
    int        fd;                   /* -1 when memory only */
} worm_ledger;

/* path NULL = memory only. An existing file is loaded and verified; a new one gets seal_0. */
cs_status worm_open(worm_ledger *l, const char *path);
cs_status worm_append(worm_ledger *l, const uint8_t witness_digest[32], worm_seal *out);
void      worm_close(worm_ledger *l);

/* Pointers returned by worm_at / worm_head are valid only until the next worm_append. */
size_t           worm_count(const worm_ledger *l);
const worm_seal *worm_at(const worm_ledger *l, size_t i);
const worm_seal *worm_head(const worm_ledger *l);

/* Re-derives the whole chain; CS_ERR_TAMPER on any inconsistency. */
cs_status worm_verify(const worm_ledger *l);
cs_status worm_verify_chain(const worm_seal *seals, size_t n);

#endif
