#include "cs_test.h"
#include "cs_sha256.h"
#include <string.h>

static int hex_eq(const uint8_t *d, const char *want)
{
    char h[65];
    cs_hex(d, 32, h);
    return strcmp(h, want) == 0;
}

TEST_MAIN_BEGIN("sha256/hmac")
    uint8_t d[32];

    /* FIPS 180-4 examples */
    cs_sha256("", 0, d);
    CHECK(hex_eq(d, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"));
    cs_sha256("abc", 3, d);
    CHECK(hex_eq(d, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
    const char *two = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    cs_sha256(two, strlen(two), d);
    CHECK(hex_eq(d, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"));

    /* one million 'a', fed in odd-sized chunks */
    cs_sha256_ctx c;
    cs_sha256_init(&c);
    char chunk[977];
    memset(chunk, 'a', sizeof chunk);
    size_t left = 1000000;
    while (left) {
        size_t n = left < sizeof chunk ? left : sizeof chunk;
        cs_sha256_update(&c, chunk, n);
        left -= n;
    }
    cs_sha256_final(&c, d);
    CHECK(hex_eq(d, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"));

    /* RFC 4231 test cases 1, 2 and 6 (key longer than the block size) */
    uint8_t key1[20];
    memset(key1, 0x0b, sizeof key1);
    cs_hmac_sha256(key1, 20, "Hi There", 8, d);
    CHECK(hex_eq(d, "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"));
    cs_hmac_sha256("Jefe", 4, "what do ya want for nothing?", 28, d);
    CHECK(hex_eq(d, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"));
    uint8_t key6[131];
    memset(key6, 0xaa, sizeof key6);
    const char *m6 = "Test Using Larger Than Block-Size Key - Hash Key First";
    cs_hmac_sha256(key6, sizeof key6, m6, strlen(m6), d);
    CHECK(hex_eq(d, "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"));

    /* helpers */
    uint8_t a[4] = {1, 2, 3, 4}, b[4] = {1, 2, 3, 4};
    CHECK(cs_ct_equal(a, b, 4));
    b[3] = 5;
    CHECK(!cs_ct_equal(a, b, 4));
    char h[9];
    cs_hex(a, 4, h);
    CHECK(strcmp(h, "01020304") == 0);
    uint8_t back[4];
    CHECK(cs_unhex(h, back, 4) == 0 && memcmp(back, a, 4) == 0);
    CHECK(cs_unhex("0102zz04", back, 4) != 0);
    CHECK(cs_unhex("010203", back, 4) != 0);
TEST_MAIN_END
