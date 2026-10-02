#ifndef L2_ALP_H
#define L2_ALP_H

/* Layer 2 - ALP boundary: which claims have machine-checked proofs available, and a manifest of
 * every `sorry` (unproven placeholder) in the proof sources. A claim may only be relied on by the
 * layers above when its proof is available and contains no sorry. */

#include <stddef.h>
#include <stdint.h>

#include "cs_status.h"

#define ALP_MAX_CLAIMS 64
#define ALP_NAME_MAX   64

typedef enum alp_state {
    ALP_MISSING = 0,   /* declared, no proof attached */
    ALP_PROVEN,        /* proof attached, zero sorry */
    ALP_SORRY          /* proof attached but contains sorry */
} alp_state;

typedef struct alp_claim {
    char      name[ALP_NAME_MAX];
    alp_state state;
    size_t    sorries;
    size_t    proof_len;
    uint8_t   proof_hash[32];
} alp_claim;

typedef struct alp_registry {
    alp_claim claims[ALP_MAX_CLAIMS];
    size_t    count;
} alp_registry;

/* Counts `sorry` tokens in Lean-style source, ignoring line comments (-- ...), nested block
 * comments (/- ... -/) and string literals. */
size_t alp_scan_sorries(const char *text, size_t len);

void      alp_init(alp_registry *r);
cs_status alp_declare(alp_registry *r, const char *name);
cs_status alp_attach_proof(alp_registry *r, const char *name, const char *text, size_t len);
cs_status alp_attach_file(alp_registry *r, const char *name, const char *path);

alp_state alp_state_of(const alp_registry *r, const char *name);   /* undeclared -> ALP_MISSING */
int       alp_proof_available(const alp_registry *r, const char *name);
cs_status alp_require(const alp_registry *r, const char *name);    /* CS_ERR_UNPROVEN unless proven */
/* Re-checks a proof text against the recorded hash (detects a changed proof source). */
cs_status alp_verify_proof(const alp_registry *r, const char *name, const char *text, size_t len);
size_t    alp_total_sorries(const alp_registry *r);

/* Deterministic text manifest, snprintf-style: returns the length that would be written. */
size_t    alp_manifest(const alp_registry *r, char *buf, size_t cap);

#endif
