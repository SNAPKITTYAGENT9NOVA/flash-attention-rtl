#ifndef L0_BOOT_H
#define L0_BOOT_H

/* Layer 0 - Boot: CPU detection, entropy source, memory verification. */

#include <stddef.h>
#include <stdint.h>

#include "cs_status.h"

#define CS_BOOT_SEED_LEN 32

enum {
    CS_CPU_SSE2   = 1u << 0,
    CS_CPU_AVX2   = 1u << 1,
    CS_CPU_AES    = 1u << 2,
    CS_CPU_RDRAND = 1u << 3,
    CS_CPU_SHA    = 1u << 4
};

typedef struct cs_cpu_info {
    char     arch[16];     /* "x86_64", "aarch64", ... */
    char     vendor[16];   /* cpuid vendor string on x86, else "unknown" */
    uint32_t features;     /* CS_CPU_* bits (x86 only) */
    int      little_endian;
    int      word_bits;
} cs_cpu_info;

/* Entropy source: fills buf with n bytes, returns 0 on success. NULL selects the OS source. */
typedef int (*cs_entropy_fn)(void *buf, size_t n);

typedef struct cs_boot_report {
    cs_cpu_info cpu;
    uint8_t     seed[CS_BOOT_SEED_LEN];     /* health-tested entropy */
    uint8_t     boot_id[CS_BOOT_SEED_LEN];  /* SHA-256(seed || cpu description) */
    size_t      mem_verified_bytes;
    cs_status   status;
} cs_boot_report;

cs_status cs_boot_cpu_detect(cs_cpu_info *out);

/* Draws 64 test bytes then n output bytes; fails if the stream is constant, contains a run of
 * 4 identical bytes, or the source itself fails. */
cs_status cs_boot_entropy(cs_entropy_fn fn, uint8_t *out, size_t n);

/* Pattern verification of a caller-supplied region: all-zero, all-one, 0xAA.., 0x55.., and a
 * unique value per word. Returns CS_ERR_MEMTEST on the first mismatch. */
cs_status cs_memtest_region(volatile uint64_t *region, size_t words);
/* Single pattern fill + verify; exposed so fault detection itself can be tested. */
cs_status cs_memtest_check(volatile const uint64_t *region, size_t words, uint64_t pattern);

/* Allocates and verifies mem_bytes (rounded down to whole words). */
cs_status cs_boot_memory_verify(size_t mem_bytes);

/* Runs the whole layer. entropy NULL = OS source. */
cs_status cs_boot_run(cs_boot_report *rep, cs_entropy_fn entropy, size_t mem_bytes);

#endif
