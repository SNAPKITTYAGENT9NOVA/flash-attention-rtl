#include "l0_boot.h"

#include <stdlib.h>
#include <string.h>

#include <fcntl.h>
#include <sys/random.h>
#include <unistd.h>

#if defined(__x86_64__) || defined(__i386__)
#include <cpuid.h>
#endif

#include "cs_sha256.h"

cs_status cs_boot_cpu_detect(cs_cpu_info *out)
{
    if (!out) return CS_ERR_ARG;
    memset(out, 0, sizeof *out);
    strcpy(out->vendor, "unknown");
    out->word_bits = (int)(sizeof(void *) * 8);
    {
        const uint16_t probe = 1;
        out->little_endian = *(const uint8_t *)&probe == 1;
    }
#if defined(__x86_64__)
    strcpy(out->arch, "x86_64");
#elif defined(__i386__)
    strcpy(out->arch, "i386");
#elif defined(__aarch64__)
    strcpy(out->arch, "aarch64");
#elif defined(__riscv)
    strcpy(out->arch, "riscv");
#else
    strcpy(out->arch, "other");
#endif

#if defined(__x86_64__) || defined(__i386__)
    unsigned eax, ebx, ecx, edx;
    if (__get_cpuid(0, &eax, &ebx, &ecx, &edx)) {
        unsigned maxleaf = eax;
        memcpy(out->vendor, &ebx, 4);
        memcpy(out->vendor + 4, &edx, 4);
        memcpy(out->vendor + 8, &ecx, 4);
        out->vendor[12] = '\0';
        if (__get_cpuid(1, &eax, &ebx, &ecx, &edx)) {
            if (edx & (1u << 26)) out->features |= CS_CPU_SSE2;
            if (ecx & (1u << 25)) out->features |= CS_CPU_AES;
            if (ecx & (1u << 30)) out->features |= CS_CPU_RDRAND;
        }
        if (maxleaf >= 7 && __get_cpuid_count(7, 0, &eax, &ebx, &ecx, &edx)) {
            if (ebx & (1u << 5))  out->features |= CS_CPU_AVX2;
            if (ebx & (1u << 29)) out->features |= CS_CPU_SHA;
        }
    }
#endif
    return CS_OK;
}

static int os_entropy(void *buf, size_t n)
{
    uint8_t *p = buf;
    while (n > 0) {
        ssize_t r = getrandom(p, n, 0);
        if (r < 0) {
            int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
            if (fd < 0) return -1;
            while (n > 0) {
                ssize_t g = read(fd, p, n);
                if (g <= 0) { close(fd); return -1; }
                p += g; n -= (size_t)g;
            }
            close(fd);
            return 0;
        }
        p += r; n -= (size_t)r;
    }
    return 0;
}

static int health_ok(const uint8_t *s, size_t n)
{
    size_t run = 1;
    int distinct = 0;
    for (size_t i = 1; i < n; i++) {
        run = (s[i] == s[i - 1]) ? run + 1 : 1;
        if (run >= 4) return 0;           /* repetition count test */
        if (s[i] != s[0]) distinct = 1;
    }
    return n > 1 && distinct;             /* not constant */
}

cs_status cs_boot_entropy(cs_entropy_fn fn, uint8_t *out, size_t n)
{
    if (!out || n == 0) return CS_ERR_ARG;
    if (!fn) fn = os_entropy;
    uint8_t probe[64];
    if (fn(probe, sizeof probe) != 0) return CS_ERR_ENTROPY;
    int ok = health_ok(probe, sizeof probe);
    memset(probe, 0, sizeof probe);
    if (!ok) return CS_ERR_ENTROPY;
    if (fn(out, n) != 0) return CS_ERR_ENTROPY;
    if (n >= 16 && !health_ok(out, n)) return CS_ERR_ENTROPY;
    return CS_OK;
}

cs_status cs_memtest_check(volatile const uint64_t *region, size_t words, uint64_t pattern)
{
    for (size_t i = 0; i < words; i++)
        if (region[i] != pattern) return CS_ERR_MEMTEST;
    return CS_OK;
}

static uint64_t unique_word(size_t i)
{
    uint64_t x = (uint64_t)i * 0x9E3779B97F4A7C15ull + 0xD1B54A32D192ED03ull;
    x ^= x >> 29;
    return x * 0xBF58476D1CE4E5B9ull;
}

cs_status cs_memtest_region(volatile uint64_t *region, size_t words)
{
    if (!region || words == 0) return CS_ERR_ARG;
    static const uint64_t pats[] = {0x0ull, ~0ull, 0xAAAAAAAAAAAAAAAAull, 0x5555555555555555ull};
    for (size_t p = 0; p < sizeof pats / sizeof pats[0]; p++) {
        for (size_t i = 0; i < words; i++) region[i] = pats[p];
        if (cs_memtest_check(region, words, pats[p]) != CS_OK) return CS_ERR_MEMTEST;
    }
    for (size_t i = 0; i < words; i++) region[i] = unique_word(i);
    for (size_t i = 0; i < words; i++)
        if (region[i] != unique_word(i)) return CS_ERR_MEMTEST;
    return CS_OK;
}

cs_status cs_boot_memory_verify(size_t mem_bytes)
{
    size_t words = mem_bytes / sizeof(uint64_t);
    if (words == 0) return CS_ERR_ARG;
    uint64_t *r = malloc(words * sizeof *r);
    if (!r) return CS_ERR_NOMEM;
    cs_status s = cs_memtest_region(r, words);
    free(r);
    return s;
}

cs_status cs_boot_run(cs_boot_report *rep, cs_entropy_fn entropy, size_t mem_bytes)
{
    if (!rep) return CS_ERR_ARG;
    memset(rep, 0, sizeof *rep);
    rep->status = CS_ERR_BOOT;

    cs_status s = cs_boot_cpu_detect(&rep->cpu);
    if (s != CS_OK) return s;

    s = cs_boot_entropy(entropy, rep->seed, sizeof rep->seed);
    if (s != CS_OK) { rep->status = s; return s; }

    s = cs_boot_memory_verify(mem_bytes);
    if (s != CS_OK) { rep->status = s; return s; }
    rep->mem_verified_bytes = mem_bytes / sizeof(uint64_t) * sizeof(uint64_t);

    cs_sha256_ctx c;
    cs_sha256_init(&c);
    cs_sha256_update(&c, "cstack-boot-v1", 14);
    cs_sha256_update(&c, rep->seed, sizeof rep->seed);
    cs_sha256_update(&c, rep->cpu.arch, strlen(rep->cpu.arch));
    cs_sha256_update(&c, rep->cpu.vendor, strlen(rep->cpu.vendor));
    cs_sha256_update_u64(&c, rep->cpu.features);
    cs_sha256_final(&c, rep->boot_id);

    rep->status = CS_OK;
    return CS_OK;
}
