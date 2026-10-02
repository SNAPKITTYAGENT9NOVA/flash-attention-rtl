#ifndef CS_TEST_H
#define CS_TEST_H

#include <stdio.h>
#include <stdlib.h>

static int cs_test_fail_count;
static int cs_test_check_count;

#define CHECK(cond)                                                              \
    do {                                                                         \
        cs_test_check_count++;                                                   \
        if (!(cond)) {                                                           \
            cs_test_fail_count++;                                                \
            fprintf(stderr, "  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);    \
        }                                                                        \
    } while (0)

#define CHECK_EQ_STATUS(expr, want) CHECK((expr) == (want))

#define TEST_MAIN_BEGIN(name) int main(void) { const char *cs_test_name = (name);
#define TEST_MAIN_END                                                            \
    printf("%-22s %d checks, %d failed\n", cs_test_name, cs_test_check_count,    \
           cs_test_fail_count);                                                  \
    return cs_test_fail_count ? 1 : 0; }

#endif
