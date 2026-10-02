#include "cs_test.h"
#include "l9_obs.h"
#include <stdio.h>
#include <string.h>

static uint64_t fake_now;
static uint64_t fake_clock(void *ctx) { (void)ctx; return fake_now; }

TEST_MAIN_BEGIN("l9 obs")
    obs_ctx o;
    obs_init(&o, fake_clock, NULL);
    obs_metric m;

    /* counters, gauges, summaries */
    CHECK_EQ_STATUS(obs_counter_add(&o, "jobs", 1), CS_OK);
    CHECK_EQ_STATUS(obs_counter_add(&o, "jobs", 4), CS_OK);
    CHECK(obs_get(&o, "jobs", &m) && m.value == 5 && m.kind == OBS_COUNTER);
    CHECK_EQ_STATUS(obs_counter_add(&o, "jobs", UINT64_MAX), CS_ERR_RANGE);
    CHECK(obs_get(&o, "jobs", &m) && m.value == 5);
    CHECK_EQ_STATUS(obs_gauge_set(&o, "queue", -3), CS_OK);
    CHECK_EQ_STATUS(obs_gauge_set(&o, "queue", 7), CS_OK);
    CHECK(obs_get(&o, "queue", &m) && m.value == 7);
    CHECK_EQ_STATUS(obs_gauge_set(&o, "jobs", 1), CS_ERR_STATE);                 /* kind mismatch */
    CHECK_EQ_STATUS(obs_observe(&o, "steps", 10), CS_OK);
    CHECK_EQ_STATUS(obs_observe(&o, "steps", 30), CS_OK);
    CHECK_EQ_STATUS(obs_observe(&o, "steps", -5), CS_OK);
    CHECK(obs_get(&o, "steps", &m) && m.count == 3 && m.value == 35 && m.min == -5 && m.max == 30);
    CHECK(!obs_get(&o, "absent", &m));
    CHECK_EQ_STATUS(obs_counter_add(&o, "", 1), CS_ERR_ARG);
    CHECK_EQ_STATUS(obs_counter_add(NULL, "x", 1), CS_ERR_ARG);
    char longname[OBS_NAME_MAX + 1];
    memset(longname, 'n', sizeof longname - 1);
    longname[sizeof longname - 1] = '\0';
    CHECK_EQ_STATUS(obs_counter_add(&o, longname, 1), CS_ERR_ARG);

    char text[512];
    size_t need = obs_export_metrics(&o, text, sizeof text);
    CHECK(need == strlen(text));
    CHECK(strstr(text, "jobs 5\n") && strstr(text, "queue 7\n"));
    CHECK(strstr(text, "steps_count 3\nsteps_sum 35\nsteps_min -5\nsteps_max 30\n"));
    char tiny[16];
    CHECK(obs_export_metrics(&o, tiny, sizeof tiny) == need && strlen(tiny) == sizeof tiny - 1);
    CHECK(obs_export_metrics(&o, NULL, 0) == need);

    obs_ctx full;
    obs_init(&full, fake_clock, NULL);
    int ok = 1;
    for (int i = 0; i < OBS_MAX_METRICS; i++) {
        char n[16];
        snprintf(n, sizeof n, "m%d", i);
        if (obs_counter_add(&full, n, 1) != CS_OK) ok = 0;
    }
    CHECK(ok);
    CHECK_EQ_STATUS(obs_counter_add(&full, "one_more", 1), CS_ERR_NOMEM);

    /* audit chain */
    CHECK_EQ_STATUS(obs_audit_verify(&o), CS_OK);                                /* empty log verifies */
    fake_now = 1000;
    CHECK_EQ_STATUS(obs_audit(&o, 0, CS_OK, "boot ok"), CS_OK);
    fake_now = 2000;
    CHECK_EQ_STATUS(obs_audit(&o, 5, CS_ERR_DENIED, "guardian denied job 7"), CS_OK);
    CHECK_EQ_STATUS(obs_audit(&o, 10, CS_OK, "bad layer"), CS_ERR_ARG);
    CHECK_EQ_STATUS(obs_audit(&o, -1, CS_OK, "bad layer"), CS_ERR_ARG);
    CHECK(obs_audit_total(&o) == 2);
    CHECK(obs_audit_at(&o, 0)->seq == 1 && obs_audit_at(&o, 1)->ts_ns == 2000);
    CHECK(obs_audit_at(&o, 2) == NULL);
    CHECK_EQ_STATUS(obs_audit_verify(&o), CS_OK);

    char alog[512];
    size_t an = obs_export_audit(&o, alog, sizeof alog);
    CHECK(an == strlen(alog));
    CHECK(strstr(alog, "1 1000 L0 ok boot ok chain=") != NULL);
    CHECK(strstr(alog, "2 2000 L5 denied guardian denied job 7 chain=") != NULL);

    /* editing any retained event is detected */
    obs_ctx t = o;
    t.ring[0].status = CS_OK + 1;
    CHECK_EQ_STATUS(obs_audit_verify(&t), CS_ERR_TAMPER);
    t = o; t.ring[1].ts_ns++;
    CHECK_EQ_STATUS(obs_audit_verify(&t), CS_ERR_TAMPER);
    t = o; t.ring[0].msg[0] = 'B';
    CHECK_EQ_STATUS(obs_audit_verify(&t), CS_ERR_TAMPER);
    t = o; t.ring[1].layer = 6;
    CHECK_EQ_STATUS(obs_audit_verify(&t), CS_ERR_TAMPER);
    t = o; t.ring[1].chain[0] ^= 1;
    CHECK_EQ_STATUS(obs_audit_verify(&t), CS_ERR_TAMPER);
    t = o; t.ring[1].seq = 9;
    CHECK_EQ_STATUS(obs_audit_verify(&t), CS_ERR_TAMPER);
    t = o; memcpy(&t.ring[0], &o.ring[1], sizeof t.ring[0]);                      /* replaced / duplicated */
    CHECK_EQ_STATUS(obs_audit_verify(&t), CS_ERR_TAMPER);

    /* ring wrap-around: oldest events are dropped, the chain still verifies */
    obs_ctx w;
    obs_init(&w, fake_clock, NULL);
    for (int i = 0; i < OBS_AUDIT_CAP * 2 + 17; i++) {
        char msg[24];
        snprintf(msg, sizeof msg, "event %d", i);
        fake_now = (uint64_t)i * 10;
        CHECK_EQ_STATUS(obs_audit(&w, i % 10, CS_OK, msg), CS_OK);
    }
    CHECK(obs_audit_total(&w) == OBS_AUDIT_CAP * 2 + 17);
    CHECK(obs_audit_at(&w, 0)->seq == OBS_AUDIT_CAP + 18);
    CHECK(obs_audit_at(&w, OBS_AUDIT_CAP - 1)->seq == OBS_AUDIT_CAP * 2 + 17);
    CHECK(obs_audit_at(&w, OBS_AUDIT_CAP) == NULL);
    CHECK_EQ_STATUS(obs_audit_verify(&w), CS_OK);
    t = w; t.ring[40].msg[1] ^= 0x20;
    CHECK_EQ_STATUS(obs_audit_verify(&t), CS_ERR_TAMPER);
    char big[OBS_AUDIT_CAP * 200];
    CHECK(obs_export_audit(&w, big, sizeof big) == strlen(big));

    /* default clock works */
    obs_ctx d;
    obs_init(&d, NULL, NULL);
    CHECK_EQ_STATUS(obs_audit(&d, 9, CS_OK, "x"), CS_OK);
    CHECK(obs_audit_at(&d, 0)->ts_ns > 0);
TEST_MAIN_END
