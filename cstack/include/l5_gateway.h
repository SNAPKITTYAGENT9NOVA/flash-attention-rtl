#ifndef L5_GATEWAY_H
#define L5_GATEWAY_H

/* Layer 5 - Triple-lock gateway: Guardian -> Examiner -> Publisher.
 *
 * The order is enforced cryptographically, not by convention: every stage has its own key (derived
 * from the boot seed), the Examiner only accepts a token minted by the Guardian, and the Publisher
 * only accepts a token minted by the Examiner. Only the Publisher can issue an approval, so no
 * work reaches the execution layer without having passed all three locks. */

#include <stddef.h>
#include <stdint.h>

#include "cs_status.h"

#define GW_DIGEST_LEN 32

typedef struct gw_request {
    uint64_t    id;
    uint32_t    kind;           /* 0..31 */
    const void *payload;
    size_t      len;
    uint8_t     digest[GW_DIGEST_LEN];
} gw_request;

/* Binds id, kind and payload into digest. */
cs_status gw_request_init(gw_request *r, uint64_t id, uint32_t kind, const void *payload, size_t len);

/* Inputs the Guardian takes from the layers below. */
typedef struct gw_health {
    int boot_ok;
    int alp_ok;
    int sigma_ok;
    int dissonance_clear;
} gw_health;

typedef struct gw_policy {
    uint32_t allowed_kinds;     /* bit k set = kind k allowed */
    size_t   max_payload;
} gw_policy;

typedef struct gw_token { uint8_t mac[GW_DIGEST_LEN]; } gw_token;

typedef struct gw_approval {
    uint8_t  request_digest[GW_DIGEST_LEN];
    uint64_t seq;               /* strictly increasing, starts at 1 */
    uint8_t  mac[GW_DIGEST_LEN];
} gw_approval;

typedef struct gateway {
    uint8_t   k_guardian[32], k_examiner[32], k_publisher[32];
    gw_policy policy;
    uint64_t  next_seq;
} gateway;

cs_status gw_init(gateway *g, const uint8_t root_key[32], const gw_policy *policy);

cs_status gw_guardian(const gateway *g, const gw_request *r, const gw_health *h, gw_token *out);
cs_status gw_examiner(const gateway *g, const gw_request *r, const gw_token *guardian, gw_token *out);
/* Verifies both earlier tokens before issuing the approval. */
cs_status gw_publisher(gateway *g, const gw_request *r, const gw_token *guardian,
                       const gw_token *examiner, gw_approval *out);

/* Runs the three locks in order. */
cs_status gw_approve(gateway *g, const gw_request *r, const gw_health *h, gw_approval *out);

/* CS_OK only for an approval issued by this gateway for exactly this request. */
cs_status gw_verify_approval(const gateway *g, const gw_request *r, const gw_approval *a);

#endif
