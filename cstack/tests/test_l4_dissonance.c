#include "cs_test.h"
#include "l4_dissonance.h"
#include <stdio.h>
#include <string.h>

static int handler_calls;
static cs_status handler_last;
static void on_trap(const dis_violation *v, void *ctx)
{
    (void)ctx;
    handler_calls++;
    handler_last = v->code;
}

static int flag_value = 1;
static int flag_inv(void *ctx) { return *(int *)ctx != 0; }

TEST_MAIN_BEGIN("l4 dissonance")
    dis_engine e;
    dis_init(&e);
    dis_set_trap_handler(&e, on_trap, NULL);

    /* direct contradiction */
    CHECK(dis_value(&e, "p") == -1);
    CHECK_EQ_STATUS(dis_assert(&e, "p", 1), CS_OK);
    CHECK_EQ_STATUS(dis_assert(&e, "p", 1), CS_OK);                       /* idempotent */
    CHECK(dis_value(&e, "p") == 1);
    CHECK(!dis_is_trapped(&e));
    CHECK_EQ_STATUS(dis_assert(&e, "p", 0), CS_ERR_CONTRADICTION);
    CHECK(dis_is_trapped(&e) && handler_calls == 1 && handler_last == CS_ERR_CONTRADICTION);
    CHECK(dis_value(&e, "p") == 1);                                       /* state unchanged */
    CHECK(dis_violation_count(&e) == 1);
    CHECK(strstr(dis_violation_at(&e, 0)->msg, "'p'") != NULL);
    /* trapped: everything refused until reset */
    CHECK_EQ_STATUS(dis_assert(&e, "q", 1), CS_ERR_TRAPPED);
    CHECK_EQ_STATUS(dis_add_implication(&e, "a", "b"), CS_ERR_TRAPPED);
    CHECK_EQ_STATUS(dis_check_invariants(&e), CS_ERR_TRAPPED);
    CHECK(dis_value(&e, "q") == -1);
    CHECK_EQ_STATUS(dis_reset_trap(&e), CS_OK);
    CHECK(!dis_is_trapped(&e) && dis_violation_count(&e) == 1);           /* log is kept */
    CHECK_EQ_STATUS(dis_assert(&e, "q", 1), CS_OK);

    /* implication: modus ponens and modus tollens */
    dis_init(&e);
    CHECK_EQ_STATUS(dis_add_implication(&e, "a", "b"), CS_OK);
    CHECK_EQ_STATUS(dis_add_implication(&e, "b", "c"), CS_OK);
    CHECK_EQ_STATUS(dis_assert(&e, "a", 1), CS_OK);
    CHECK(dis_value(&e, "b") == 1 && dis_value(&e, "c") == 1);            /* transitive chain */
    CHECK_EQ_STATUS(dis_assert(&e, "c", 0), CS_ERR_CONTRADICTION);        /* derived contradiction */
    dis_reset_trap(&e);
    CHECK(dis_value(&e, "c") == 1);                                       /* nothing was committed */

    dis_init(&e);
    dis_add_implication(&e, "a", "b");
    dis_add_implication(&e, "b", "c");
    CHECK_EQ_STATUS(dis_assert(&e, "c", 0), CS_OK);                       /* modus tollens */
    CHECK(dis_value(&e, "b") == 0 && dis_value(&e, "a") == 0);
    CHECK_EQ_STATUS(dis_assert(&e, "a", 1), CS_ERR_CONTRADICTION);
    CHECK(dis_value(&e, "a") == 0);

    /* unknown stays unknown when the rule does not force it */
    dis_init(&e);
    dis_add_implication(&e, "a", "b");
    CHECK_EQ_STATUS(dis_assert(&e, "a", 0), CS_OK);
    CHECK(dis_value(&e, "b") == -1);
    CHECK_EQ_STATUS(dis_assert(&e, "b", 1), CS_OK);
    CHECK(dis_value(&e, "a") == 0);

    /* exclusion */
    dis_init(&e);
    dis_add_exclusion(&e, "sealed", "mutable");
    CHECK_EQ_STATUS(dis_assert(&e, "sealed", 1), CS_OK);
    CHECK(dis_value(&e, "mutable") == 0);
    CHECK_EQ_STATUS(dis_assert(&e, "mutable", 1), CS_ERR_CONTRADICTION);
    dis_init(&e);
    dis_add_exclusion(&e, "x", "y");
    CHECK_EQ_STATUS(dis_assert(&e, "y", 1), CS_OK);
    CHECK(dis_value(&e, "x") == 0);                                       /* symmetric */

    /* new rule conflicting with established facts is rejected and not installed */
    dis_init(&e);
    dis_assert(&e, "a", 1);
    dis_assert(&e, "b", 0);
    CHECK_EQ_STATUS(dis_add_implication(&e, "a", "b"), CS_ERR_CONTRADICTION);
    CHECK(e.nimpl == 0);
    dis_reset_trap(&e);
    CHECK_EQ_STATUS(dis_add_implication(&e, "b", "a"), CS_OK);            /* consistent: b false => a unknown ok */

    /* implication cycle behaves as equivalence */
    dis_init(&e);
    dis_add_implication(&e, "p", "q");
    dis_add_implication(&e, "q", "p");
    CHECK_EQ_STATUS(dis_assert(&e, "q", 0), CS_OK);
    CHECK(dis_value(&e, "p") == 0);

    /* invariants */
    dis_init(&e);
    dis_add_invariant(&e, "flag-set", flag_inv, &flag_value);
    CHECK_EQ_STATUS(dis_check_invariants(&e), CS_OK);
    flag_value = 0;
    CHECK_EQ_STATUS(dis_check_invariants(&e), CS_ERR_CONTRADICTION);
    CHECK(dis_is_trapped(&e) && strstr(dis_violation_at(&e, 0)->msg, "flag-set") != NULL);
    flag_value = 1;

    /* explicit trap from another layer */
    dis_init(&e);
    CHECK_EQ_STATUS(dis_trap(&e, CS_ERR_DRIFT, "sigma drift"), CS_ERR_DRIFT);
    CHECK(dis_is_trapped(&e));
    CHECK(dis_violation_at(&e, 0)->code == CS_ERR_DRIFT);

    /* violation ring keeps the newest DIS_MAX_VIOLATIONS in order */
    dis_init(&e);
    for (int i = 0; i < DIS_MAX_VIOLATIONS + 5; i++) {
        char m[16];
        snprintf(m, sizeof m, "v%d", i);
        dis_trap(&e, CS_ERR_STATE, m);
    }
    CHECK(dis_violation_count(&e) == DIS_MAX_VIOLATIONS + 5);
    CHECK(strcmp(dis_violation_at(&e, 0)->msg, "v5") == 0);
    CHECK(strcmp(dis_violation_at(&e, DIS_MAX_VIOLATIONS - 1)->msg, "v20") == 0);
    CHECK(dis_violation_at(&e, DIS_MAX_VIOLATIONS) == NULL);
    CHECK(dis_violation_at(&e, 0)->seq == 6);

    /* argument and capacity checks */
    dis_init(&e);
    CHECK_EQ_STATUS(dis_assert(&e, "", 1), CS_ERR_ARG);
    CHECK_EQ_STATUS(dis_assert(&e, "p", 2), CS_ERR_ARG);
    CHECK_EQ_STATUS(dis_assert(NULL, "p", 1), CS_ERR_ARG);
    for (int i = 0; i < DIS_MAX_FACTS; i++) {
        char n[16];
        snprintf(n, sizeof n, "f%d", i);
        CHECK_EQ_STATUS(dis_assert(&e, n, 1), CS_OK);
    }
    CHECK_EQ_STATUS(dis_assert(&e, "overflow", 1), CS_ERR_NOMEM);
    CHECK(dis_is_trapped(NULL));                                          /* NULL engine counts as trapped */
TEST_MAIN_END
