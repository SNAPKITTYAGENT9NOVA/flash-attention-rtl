#include "cs_test.h"
#include "cs_sha256.h"
#include "l8_worm.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void witness(uint8_t out[32], int n) { cs_sha256(&n, sizeof n, out); }

static char *slurp(const char *path, size_t *len)
{
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    static char buf[1 << 16];
    *len = fread(buf, 1, sizeof buf - 1, f);
    fclose(f);
    buf[*len] = '\0';
    return buf;
}
static void spit(const char *path, const char *data, size_t len)
{
    FILE *f = fopen(path, "wb");
    fwrite(data, 1, len, f);
    fclose(f);
}

TEST_MAIN_BEGIN("l8 worm")
    uint8_t w[32];
    worm_ledger l;

    /* in-memory chain */
    CHECK_EQ_STATUS(worm_open(&l, NULL), CS_OK);
    CHECK(worm_count(&l) == 1);
    const worm_seal genesis_copy = *worm_at(&l, 0);       /* by value: appends may reallocate */
    const worm_seal *g = &genesis_copy;
    uint8_t expect_genesis[32];
    cs_sha256("cstack-worm-genesis-v1", 22, expect_genesis);
    CHECK(g->index == 0 && memcmp(g->seal, expect_genesis, 32) == 0);
    CHECK_EQ_STATUS(worm_verify(&l), CS_OK);
    for (int i = 1; i <= 100; i++) {
        witness(w, i);
        worm_seal s;
        CHECK_EQ_STATUS(worm_append(&l, w, &s), CS_OK);
        CHECK(s.index == (uint64_t)i);
    }
    CHECK(worm_count(&l) == 101 && worm_head(&l)->index == 100);
    CHECK_EQ_STATUS(worm_verify(&l), CS_OK);
    CHECK(worm_at(&l, 101) == NULL);

    /* seal_i really chains seal_{i-1}: recompute independently */
    {
        cs_sha256_ctx c;
        uint8_t want[32];
        witness(w, 1);
        cs_sha256_init(&c);
        cs_sha256_update(&c, "cstack-worm-seal-v1", 19);
        cs_sha256_update_u64(&c, 1);
        cs_sha256_update(&c, g->seal, 32);
        cs_sha256_update(&c, w, 32);
        cs_sha256_final(&c, want);
        CHECK(memcmp(worm_at(&l, 1)->seal, want, 32) == 0);
    }

    /* tamper detection on the chain: every kind of edit is caught */
    worm_seal copy[101];
    int caught = 0, tries = 0;
    for (size_t i = 0; i < 101; i++) {
        for (int field = 0; field < 3; field++) {
            memcpy(copy, l.seals, sizeof copy);
            if (field == 0) copy[i].index ^= 1;
            else if (field == 1) copy[i].witness_digest[7] ^= 0x10;
            else copy[i].seal[31] ^= 1;
            tries++;
            if (worm_verify_chain(copy, 101) == CS_ERR_TAMPER) caught++;
        }
    }
    CHECK(caught == tries);
    memcpy(copy, l.seals, sizeof copy);                                   /* reordering */
    worm_seal tmp = copy[5]; copy[5] = copy[6]; copy[6] = tmp;
    CHECK_EQ_STATUS(worm_verify_chain(copy, 101), CS_ERR_TAMPER);
    memcpy(copy, l.seals, sizeof copy);                                   /* deleting a middle entry */
    memmove(&copy[50], &copy[51], 50 * sizeof copy[0]);
    CHECK_EQ_STATUS(worm_verify_chain(copy, 100), CS_ERR_TAMPER);
    CHECK_EQ_STATUS(worm_verify_chain(l.seals + 1, 100), CS_ERR_TAMPER);  /* no genesis */
    CHECK_EQ_STATUS(worm_verify_chain(l.seals, 50), CS_OK);               /* a prefix is a valid chain */
    CHECK_EQ_STATUS(worm_verify_chain(NULL, 0), CS_ERR_TAMPER);
    worm_close(&l);
    CHECK(worm_count(&l) == 0);

    /* file-backed ledger: persistence across open/close */
    const char *path = "build/worm_test.ledger";
    remove(path);
    CHECK_EQ_STATUS(worm_open(&l, path), CS_OK);
    for (int i = 1; i <= 5; i++) { witness(w, i); CHECK_EQ_STATUS(worm_append(&l, w, NULL), CS_OK); }
    uint8_t head[32];
    memcpy(head, worm_head(&l)->seal, 32);
    worm_close(&l);

    CHECK_EQ_STATUS(worm_open(&l, path), CS_OK);
    CHECK(worm_count(&l) == 6 && memcmp(worm_head(&l)->seal, head, 32) == 0);
    witness(w, 6);
    CHECK_EQ_STATUS(worm_append(&l, w, NULL), CS_OK);                     /* continues the same chain */
    worm_close(&l);
    CHECK_EQ_STATUS(worm_open(&l, path), CS_OK);
    CHECK(worm_count(&l) == 7);
    worm_close(&l);

    size_t len = 0;
    char *orig = slurp(path, &len);
    char saved[1 << 12];
    CHECK(orig != NULL && len < sizeof saved);
    memcpy(saved, orig, len + 1);
    size_t saved_len = len;

    /* edit a witness digest on disk */
    char mod[1 << 12];
    memcpy(mod, saved, saved_len + 1);
    char *p = strchr(mod, '\n');                                          /* start of line 1 */
    p += 1 + 2 + 1;                                                       /* "1 " then first hex digit */
    *p = (*p == '0') ? '1' : '0';
    spit(path, mod, saved_len);
    CHECK_EQ_STATUS(worm_open(&l, path), CS_ERR_TAMPER);

    /* delete a middle line */
    {
        char *s1 = strchr(saved, '\n') + 1, *s2 = strchr(s1, '\n') + 1, *s3 = strchr(s2, '\n') + 1;
        memcpy(mod, saved, (size_t)(s2 - saved));
        memcpy(mod + (s2 - saved), s3, saved_len - (size_t)(s3 - saved));
        spit(path, mod, saved_len - (size_t)(s3 - s2));
        CHECK_EQ_STATUS(worm_open(&l, path), CS_ERR_TAMPER);
    }
    /* truncated last line (crash mid-write) */
    spit(path, saved, saved_len - 10);
    CHECK_EQ_STATUS(worm_open(&l, path), CS_ERR_TAMPER);
    /* truncation at a line boundary yields a shorter but valid chain (documented limit: pair with an external head) */
    {
        char *last = saved + saved_len - 1;
        while (last > saved && *(last - 1) != '\n') last--;
        spit(path, saved, (size_t)(last - saved));
        CHECK_EQ_STATUS(worm_open(&l, path), CS_OK);
        CHECK(worm_count(&l) == 6);
        worm_close(&l);
    }
    /* garbage */
    spit(path, "not a ledger\n", 13);
    CHECK_EQ_STATUS(worm_open(&l, path), CS_ERR_TAMPER);
    /* a file that does not start at genesis */
    {
        char *s1 = strchr(saved, '\n') + 1;
        spit(path, s1, saved_len - (size_t)(s1 - saved));
        CHECK_EQ_STATUS(worm_open(&l, path), CS_ERR_TAMPER);
    }
    remove(path);

    CHECK_EQ_STATUS(worm_open(&l, "build/no_such_dir/x.ledger"), CS_ERR_IO);
    CHECK_EQ_STATUS(worm_open(NULL, NULL), CS_ERR_ARG);
    worm_ledger z;
    memset(&z, 0, sizeof z);
    witness(w, 1);
    CHECK_EQ_STATUS(worm_append(&z, w, NULL), CS_ERR_ARG);                /* not opened */
TEST_MAIN_END
