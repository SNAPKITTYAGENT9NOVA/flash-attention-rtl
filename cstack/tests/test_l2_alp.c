#include "cs_test.h"
#include "l2_alp.h"
#include <stdio.h>
#include <string.h>

#define SCAN(s) alp_scan_sorries((s), strlen(s))

TEST_MAIN_BEGIN("l2 alp")
    /* sorry scanner */
    CHECK(SCAN("") == 0);
    CHECK(SCAN("theorem t : 1 = 1 := rfl") == 0);
    CHECK(SCAN("theorem t : 1 = 1 := by sorry") == 1);
    CHECK(SCAN("sorry sorry\nsorry") == 3);
    CHECK(SCAN("sorryAx mysorry sorry_2 sorry'") == 0);          /* different identifiers */
    CHECK(SCAN("-- sorry in a line comment\nby rfl") == 0);
    CHECK(SCAN("/- sorry -/ by sorry") == 1);
    CHECK(SCAN("/- outer /- inner sorry -/ still comment sorry -/ done") == 0);   /* nesting */
    CHECK(SCAN("/-- doc sorry -/ by rfl") == 0);
    CHECK(SCAN("\"sorry\" ++ x") == 0);                          /* string literal */
    CHECK(SCAN("\"a \\\" sorry\" by sorry") == 1);               /* escaped quote */
    CHECK(SCAN("(sorry)") == 1 && SCAN("by\n  sorry\n") == 1);
    CHECK(SCAN("/- unterminated sorry") == 0);

    alp_registry r;
    alp_init(&r);
    CHECK(alp_state_of(&r, "x") == ALP_MISSING);
    CHECK_EQ_STATUS(alp_require(&r, "x"), CS_ERR_UNPROVEN);
    CHECK_EQ_STATUS(alp_declare(&r, "gl_mul_correct"), CS_OK);
    CHECK(alp_state_of(&r, "gl_mul_correct") == ALP_MISSING);
    CHECK_EQ_STATUS(alp_require(&r, "gl_mul_correct"), CS_ERR_UNPROVEN);

    const char *good = "theorem gl_mul_correct : ∀ a b, a * b = b * a := by\n  intro a b; ring\n";
    const char *bad  = "theorem fa_bound : x ≤ y := by\n  sorry\n";
    CHECK_EQ_STATUS(alp_attach_proof(&r, "gl_mul_correct", good, strlen(good)), CS_OK);
    CHECK_EQ_STATUS(alp_attach_proof(&r, "fa_bound", bad, strlen(bad)), CS_OK);
    CHECK(alp_state_of(&r, "gl_mul_correct") == ALP_PROVEN);
    CHECK(alp_state_of(&r, "fa_bound") == ALP_SORRY);
    CHECK(alp_proof_available(&r, "gl_mul_correct") && !alp_proof_available(&r, "fa_bound"));
    CHECK_EQ_STATUS(alp_require(&r, "gl_mul_correct"), CS_OK);
    CHECK_EQ_STATUS(alp_require(&r, "fa_bound"), CS_ERR_UNPROVEN);
    CHECK(alp_total_sorries(&r) == 1);

    /* proof drift: the recorded hash binds the proof source */
    CHECK_EQ_STATUS(alp_verify_proof(&r, "gl_mul_correct", good, strlen(good)), CS_OK);
    const char *edited = "theorem gl_mul_correct : ∀ a b, a * b = b * a := by\n  intro a b; simp\n";
    CHECK_EQ_STATUS(alp_verify_proof(&r, "gl_mul_correct", edited, strlen(edited)), CS_ERR_TAMPER);
    CHECK_EQ_STATUS(alp_verify_proof(&r, "nope", good, strlen(good)), CS_ERR_UNPROVEN);

    /* a sorry proof can be replaced by a complete one */
    const char *fixed = "theorem fa_bound : x ≤ y := by\n  omega\n";
    CHECK_EQ_STATUS(alp_attach_proof(&r, "fa_bound", fixed, strlen(fixed)), CS_OK);
    CHECK(alp_state_of(&r, "fa_bound") == ALP_PROVEN && alp_total_sorries(&r) == 0);
    CHECK_EQ_STATUS(alp_attach_proof(&r, "fa_bound", bad, strlen(bad)), CS_OK);   /* regression */
    CHECK(alp_state_of(&r, "fa_bound") == ALP_SORRY);

    /* file attach */
    const char *path = "build/alp_test.lean";
    FILE *f = fopen(path, "wb");
    CHECK(f != NULL);
    if (f) { fputs("lemma l : True := by trivial\n", f); fclose(f); }
    CHECK_EQ_STATUS(alp_attach_file(&r, "from_file", path), CS_OK);
    CHECK(alp_state_of(&r, "from_file") == ALP_PROVEN);
    CHECK_EQ_STATUS(alp_attach_file(&r, "x2", "build/does_not_exist.lean"), CS_ERR_IO);
    remove(path);

    /* manifest: deterministic, snprintf-style sizing */
    alp_declare(&r, "pending");
    char big[1024], small[40];
    size_t need = alp_manifest(&r, big, sizeof big);
    CHECK(need == strlen(big));
    CHECK(strncmp(big, "alp-manifest v1\n", 16) == 0);
    CHECK(strstr(big, "fa_bound sorry sorries=1 sha256=") != NULL);
    CHECK(strstr(big, "pending missing sorries=0 sha256=-\n") != NULL);
    CHECK(strstr(big, "total_sorries=1\n") != NULL);
    char big2[1024];
    CHECK(alp_manifest(&r, big2, sizeof big2) == need && strcmp(big, big2) == 0);
    CHECK(alp_manifest(&r, small, sizeof small) == need);        /* truncated but sized correctly */
    CHECK(strlen(small) == sizeof small - 1 && strncmp(small, big, sizeof small - 1) == 0);
    CHECK(alp_manifest(&r, NULL, 0) == need);

    /* limits and name validation */
    CHECK_EQ_STATUS(alp_declare(&r, ""), CS_ERR_ARG);
    CHECK_EQ_STATUS(alp_declare(&r, "has space"), CS_ERR_ARG);
    char longname[ALP_NAME_MAX + 8];
    memset(longname, 'a', sizeof longname - 1);
    longname[sizeof longname - 1] = '\0';
    CHECK_EQ_STATUS(alp_declare(&r, longname), CS_ERR_ARG);
    alp_registry full;
    alp_init(&full);
    for (int i = 0; i < ALP_MAX_CLAIMS; i++) {
        char n[16];
        snprintf(n, sizeof n, "c%d", i);
        CHECK_EQ_STATUS(alp_declare(&full, n), CS_OK);
    }
    CHECK_EQ_STATUS(alp_declare(&full, "one_too_many"), CS_ERR_NOMEM);
TEST_MAIN_END
