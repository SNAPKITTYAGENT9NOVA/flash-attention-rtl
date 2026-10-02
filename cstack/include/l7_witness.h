#ifndef L7_WITNESS_H
#define L7_WITNESS_H

/* Layer 7 - Unified witness: one cryptographic evidence record per execution, binding the boot
 * identity, the request, the approval, the result and the deterministic resource usage. The record
 * digest is a SHA-256 over a canonical big-endian serialization; sig = HMAC(witness key, digest). */

#include <stdint.h>

#include "cs_status.h"
#include "l5_gateway.h"
#include "l6_exec.h"

typedef struct wit_record {
    uint64_t seq;                 /* approval sequence */
    uint64_t request_id;
    uint8_t  boot_id[32];
    uint8_t  request_digest[32];
    uint8_t  approval_mac[32];
    uint8_t  result_digest[32];
    uint64_t steps;
    uint64_t mem_peak;
    uint32_t exec_status;         /* cs_status of the execution */
    uint8_t  digest[32];
    uint8_t  sig[32];
} wit_record;

cs_status wit_seal(wit_record *w, const uint8_t key[32], const uint8_t boot_id[32],
                   const gw_request *req, const gw_approval *appr, const exec_result *res);

/* Recomputes the digest and checks the signature; CS_ERR_TAMPER on any mismatch. */
cs_status wit_verify(const wit_record *w, const uint8_t key[32]);

#endif
