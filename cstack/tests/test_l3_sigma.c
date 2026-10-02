#include "cs_test.h"
#include "l3_sigma.h"
#include "cs_sha256.h"
#include <string.h>

static uint64_t fake_now;
static uint64_t fake_clock(void *ctx) { (void)ctx; return fake_now; }

TEST_MAIN_BEGIN("l3 sigma")
    sigma_limits lim = {.max_mem_bytes = 1000, .max_steps = 50, .max_ns = 2000};
    sigma_ctx s;

    /* memory accounting */
    fake_now = 100;
    sigma_init(&s, &lim, fake_clock, NULL);
    CHECK_EQ_STATUS(sigma_charge_mem(&s, 600), CS_OK);
    CHECK_EQ_STATUS(sigma_charge_mem(&s, 400), CS_OK);                 /* exactly at the limit */
    CHECK(s.mem_used == 1000 && s.mem_peak == 1000);
    CHECK_EQ_STATUS(sigma_release_mem(&s, 300), CS_OK);
    CHECK(s.mem_used == 700 && s.mem_peak == 1000);
    CHECK_EQ_STATUS(sigma_release_mem(&s, 701), CS_ERR_RANGE);          /* over-release */
    CHECK_EQ_STATUS(sigma_charge_mem(&s, 301), CS_ERR_LIMIT);
    CHECK(s.mem_used == 700);                                           /* failed charge not applied */
    CHECK_EQ_STATUS(sigma_status(&s), CS_ERR_LIMIT);
    CHECK_EQ_STATUS(sigma_charge_mem(&s, 1), CS_ERR_LIMIT);             /* latched */
    CHECK_EQ_STATUS(sigma_charge_steps(&s, 1), CS_ERR_LIMIT);

    /* overflow safety */
    sigma_init(&s, &lim, fake_clock, NULL);
    CHECK_EQ_STATUS(sigma_charge_mem(&s, UINT64_MAX), CS_ERR_LIMIT);
    sigma_init(&s, &lim, fake_clock, NULL);
    CHECK_EQ_STATUS(sigma_charge_mem(&s, 10), CS_OK);
    CHECK_EQ_STATUS(sigma_charge_mem(&s, UINT64_MAX - 5), CS_ERR_LIMIT);

    /* steps */
    sigma_init(&s, &lim, fake_clock, NULL);
    CHECK_EQ_STATUS(sigma_charge_steps(&s, 50), CS_OK);
    CHECK_EQ_STATUS(sigma_charge_steps(&s, 1), CS_ERR_LIMIT);
    CHECK(s.steps == 50);

    /* zero limit means nothing allowed */
    sigma_limits zero = {0, 0, 0};
    sigma_init(&s, &zero, fake_clock, NULL);
    CHECK_EQ_STATUS(sigma_charge_steps(&s, 1), CS_ERR_LIMIT);
    sigma_init(&s, &zero, fake_clock, NULL);
    CHECK_EQ_STATUS(sigma_charge_mem(&s, 0), CS_OK);

    /* time */
    fake_now = 5000;
    sigma_init(&s, &lim, fake_clock, NULL);
    fake_now = 5000 + 2000;
    CHECK_EQ_STATUS(sigma_check_time(&s), CS_OK);                       /* at the limit */
    CHECK(sigma_elapsed_ns(&s) == 2000);
    fake_now = 5000 + 2001;
    CHECK_EQ_STATUS(sigma_check_time(&s), CS_ERR_LIMIT);
    CHECK_EQ_STATUS(sigma_check_time(&s), CS_ERR_LIMIT);
    /* clock going backwards never underflows */
    fake_now = 5000;
    sigma_init(&s, &lim, fake_clock, NULL);
    fake_now = 10;
    CHECK(sigma_elapsed_ns(&s) == 0);

    /* default clock is monotonic and works */
    sigma_limits generous = {1 << 20, 1000, 60ull * 1000000000ull};
    sigma_init(&s, &generous, NULL, NULL);
    CHECK_EQ_STATUS(sigma_check_time(&s), CS_OK);
    CHECK_EQ_STATUS(sigma_charge_mem(NULL, 1), CS_ERR_ARG);

    /* numeric drift */
    sigma_drift d;
    CHECK_EQ_STATUS(sigma_drift_init(&d, 100, -1, 3), CS_ERR_ARG);
    CHECK_EQ_STATUS(sigma_drift_init(&d, 100, 5, 0), CS_ERR_ARG);
    CHECK_EQ_STATUS(sigma_drift_init(&d, 100, 5, 17), CS_ERR_ARG);
    CHECK_EQ_STATUS(sigma_drift_init(&d, INT64_MAX, 5, 3), CS_ERR_ARG);
    CHECK_EQ_STATUS(sigma_drift_init(&d, 100, 5, 3), CS_OK);
    /* stable stream with bounded noise never drifts */
    int stable = 1;
    for (int i = 0; i < 1000; i++)
        if (sigma_drift_update(&d, 100 + (i % 7) - 3) != CS_OK) stable = 0;
    CHECK(stable);
    /* a step change to 200: EWMA crosses the tolerance after a deterministic number of samples */
    sigma_drift_init(&d, 100, 5, 3);
    int detected_at = 0;
    for (int i = 1; i <= 100 && !detected_at; i++)
        if (sigma_drift_update(&d, 200) == CS_ERR_DRIFT) detected_at = i;
    CHECK(detected_at > 0);
    sigma_drift d2;
    sigma_drift_init(&d2, 100, 5, 3);
    int detected_again = 0;
    for (int i = 1; i <= 100 && !detected_again; i++)
        if (sigma_drift_update(&d2, 200) == CS_ERR_DRIFT) detected_again = i;
    CHECK(detected_again == detected_at);                               /* deterministic */
    CHECK_EQ_STATUS(sigma_drift_update(&d, 100), CS_ERR_DRIFT);         /* latched */
    CHECK_EQ_STATUS(sigma_drift_update(&d2, INT64_MAX), CS_ERR_DRIFT);  /* latched check precedes range check */
    sigma_drift d3;
    sigma_drift_init(&d3, 0, 10, 2);
    CHECK_EQ_STATUS(sigma_drift_update(&d3, INT64_MAX), CS_ERR_ARG);
    /* downward drift is detected too */
    sigma_drift d4;
    sigma_drift_init(&d4, 100, 5, 1);
    CHECK_EQ_STATUS(sigma_drift_update(&d4, 0), CS_ERR_DRIFT);          /* ewma 50 */

    /* state drift */
    const char *state = "config v1";
    uint8_t digest[32];
    cs_sha256(state, strlen(state), digest);
    CHECK_EQ_STATUS(sigma_state_check(digest, state, strlen(state)), CS_OK);
    CHECK_EQ_STATUS(sigma_state_check(digest, "config v2", 9), CS_ERR_DRIFT);
    CHECK_EQ_STATUS(sigma_state_check(NULL, state, 1), CS_ERR_ARG);
TEST_MAIN_END
