#include "cs_test.h"
#include "l0_boot.h"
#include <string.h>

static int fixed_good(void *buf, size_t n)
{
    uint8_t *p = buf;
    for (size_t i = 0; i < n; i++) p[i] = (uint8_t)(i * 37u + 11u);
    return 0;
}
static int fixed_zero(void *buf, size_t n) { memset(buf, 0, n); return 0; }
static int fixed_run(void *buf, size_t n)
{
    uint8_t *p = buf;
    for (size_t i = 0; i < n; i++) p[i] = (uint8_t)(i * 37u + 11u);
    if (n > 8) memset(p + 2, 0x5a, 4);   /* run of 4 identical bytes */
    return 0;
}
static int failing(void *buf, size_t n) { (void)buf; (void)n; return -1; }

TEST_MAIN_BEGIN("l0 boot")
    cs_cpu_info cpu;
    CHECK_EQ_STATUS(cs_boot_cpu_detect(&cpu), CS_OK);
    CHECK(cpu.arch[0] != '\0');
    CHECK(cpu.word_bits == 32 || cpu.word_bits == 64);
    CHECK(cpu.little_endian == 1);
    CHECK_EQ_STATUS(cs_boot_cpu_detect(NULL), CS_ERR_ARG);
#if defined(__x86_64__)
    CHECK(strcmp(cpu.arch, "x86_64") == 0);
    CHECK(strlen(cpu.vendor) == 12);
    CHECK(cpu.features & CS_CPU_SSE2);   /* mandatory on x86_64 */
#endif

    uint8_t buf[32], buf2[32];
    CHECK_EQ_STATUS(cs_boot_entropy(NULL, buf, sizeof buf), CS_OK);
    CHECK_EQ_STATUS(cs_boot_entropy(NULL, buf2, sizeof buf2), CS_OK);
    CHECK(memcmp(buf, buf2, sizeof buf) != 0);
    CHECK_EQ_STATUS(cs_boot_entropy(fixed_good, buf, sizeof buf), CS_OK);
    CHECK_EQ_STATUS(cs_boot_entropy(fixed_zero, buf, sizeof buf), CS_ERR_ENTROPY);
    CHECK_EQ_STATUS(cs_boot_entropy(failing, buf, sizeof buf), CS_ERR_ENTROPY);
    CHECK_EQ_STATUS(cs_boot_entropy(NULL, NULL, 8), CS_ERR_ARG);

    uint64_t region[256];
    CHECK_EQ_STATUS(cs_memtest_region(region, 256), CS_OK);
    CHECK_EQ_STATUS(cs_memtest_region(region, 0), CS_ERR_ARG);
    /* fault detection: a flipped bit must be found by the verifier */
    for (size_t i = 0; i < 256; i++) region[i] = 0xAAAAAAAAAAAAAAAAull;
    CHECK_EQ_STATUS(cs_memtest_check(region, 256, 0xAAAAAAAAAAAAAAAAull), CS_OK);
    region[200] ^= 1ull << 17;
    CHECK_EQ_STATUS(cs_memtest_check(region, 256, 0xAAAAAAAAAAAAAAAAull), CS_ERR_MEMTEST);
    CHECK_EQ_STATUS(cs_boot_memory_verify(1 << 20), CS_OK);
    CHECK_EQ_STATUS(cs_boot_memory_verify(3), CS_ERR_ARG);

    cs_boot_report a, b, c;
    CHECK_EQ_STATUS(cs_boot_run(&a, fixed_good, 1 << 16), CS_OK);
    CHECK_EQ_STATUS(cs_boot_run(&b, fixed_good, 1 << 16), CS_OK);
    CHECK(memcmp(a.boot_id, b.boot_id, 32) == 0);          /* deterministic given the same entropy */
    CHECK(a.mem_verified_bytes == (1u << 16));
    CHECK_EQ_STATUS(cs_boot_run(&c, NULL, 1 << 16), CS_OK);
    CHECK(memcmp(a.boot_id, c.boot_id, 32) != 0);
    CHECK_EQ_STATUS(cs_boot_run(&c, fixed_zero, 1 << 16), CS_ERR_ENTROPY);
    CHECK(c.status == CS_ERR_ENTROPY);
    CHECK_EQ_STATUS(cs_boot_run(&c, fixed_run, 1 << 16), CS_ERR_ENTROPY);
    CHECK_EQ_STATUS(cs_boot_run(NULL, NULL, 1 << 16), CS_ERR_ARG);
TEST_MAIN_END
