#ifndef CS_SHA256_H
#define CS_SHA256_H

#include <stddef.h>
#include <stdint.h>

#define CS_SHA256_LEN 32

typedef struct cs_sha256_ctx {
    uint32_t h[8];
    uint64_t total;
    uint8_t  buf[64];
    size_t   n;
} cs_sha256_ctx;

void cs_sha256_init(cs_sha256_ctx *c);
void cs_sha256_update(cs_sha256_ctx *c, const void *data, size_t len);
void cs_sha256_final(cs_sha256_ctx *c, uint8_t out[CS_SHA256_LEN]);
void cs_sha256(const void *data, size_t len, uint8_t out[CS_SHA256_LEN]);

void cs_hmac_sha256(const void *key, size_t klen, const void *msg, size_t mlen,
                    uint8_t out[CS_SHA256_LEN]);

/* big-endian helpers for canonical serialization */
void cs_sha256_update_u64(cs_sha256_ctx *c, uint64_t v);

/* constant-time comparison; returns 1 if equal */
int  cs_ct_equal(const void *a, const void *b, size_t n);
/* out must hold 2*n+1 bytes */
void cs_hex(const uint8_t *in, size_t n, char *out);
/* returns 0 on success; hex must be exactly 2*n digits */
int  cs_unhex(const char *hex, uint8_t *out, size_t n);

#endif
